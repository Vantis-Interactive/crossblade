--!strict
--[[
	Client weapon handling (spec §8, §9). Responsive prediction with server authority:
	  - mirrors the server's LoadoutState; predicts ammo/reload/equip locally and is corrected by
	    every LoadoutState the server sends
	  - shots: aim point from the screen-centre ray; bullets travel from the standardized HEAD
	    position toward it, so third-person camera angles cannot shoot around cover
	  - hit detection uses the same Shared/Combat/Hitbox geometry the server validates against
	  - hit markers are shown only on server confirmation (HitConfirmed), never on prediction
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local WeaponCatalog = require(ReplicatedStorage.Shared.Weapons.WeaponCatalog)
local Net = require(script.Parent.Parent.Core.Net)
local UIState = require(script.Parent.Parent.Core.UIState)

local SLOTS = { "Primary", "Secondary", "Knife" }
local DUMMY_TAG = "Crossblade.Dummy" -- Server/Services/TrainingService

local WeaponController = {
	Name = "WeaponController",
	Dependencies = {
		"InputController",
		"CameraController",
		"SnapshotController",
		"EffectsController",
		"ViewmodelController",
	},
	State = nil :: { [string]: any }?,
	Changed = Signal.new() :: Signal.Signal<{ [string]: any }>,
	HitConfirmed = Signal.new() :: Signal.Signal<{ [string]: any }>,
	Fired = Signal.new() :: Signal.Signal<number>, -- spread degrees, for crosshair bloom
	MatchActive = false,
}

local player = Players.LocalPlayer
local input: any
local camera: any
local effects: any
local viewmodel: any
local shotId = 0
local lastShot = -math.huge
local meleeReadyAt = 0
local throwReadyAt = 0
local triggerReleased = true
local lastAimSent = { Pitch = 0, Aiming = false, Time = 0 }

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = true

local function refreshFilter()
	local exclude: { Instance } = { Workspace.CurrentCamera }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(exclude, other.Character)
		end
	end
	params.FilterDescendantsInstances = exclude
end

local function localRoot(): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return nil
	end
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function equippedId(): string?
	local state = WeaponController.State
	return state and state.Loadout[state.Equipped]
end

function WeaponController.FirearmStats(_self: typeof(WeaponController))
	local id = equippedId()
	return id and WeaponCatalog.GetFirearmStats(id)
end

local function canAct(): boolean
	return WeaponController.State ~= nil
		and WeaponController.MatchActive
		and not UIState.MenuOpen
		and localRoot() ~= nil
end

-- Nearest standardized-hitbox hit along a ray among other living players.
export type Target = { Player: Player?, DummyId: number?, Root: CFrame }

-- Everything this client may hit right now: living opponents (teammates excluded) and training dummies.
local function targets(): { Target }
	local list: { Target } = {}
	local myTeam = player:GetAttribute("Team")
	for _, other in Players:GetPlayers() do
		local character = other ~= player and other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local teammate = myTeam ~= nil and other:GetAttribute("Team") == myTeam
		if root and humanoid and humanoid.Health > 0 and not teammate then
			table.insert(list, { Player = other, Root = root.CFrame })
		end
	end
	for _, model in CollectionService:GetTagged(DUMMY_TAG) do
		local root = model:IsA("Model") and model.PrimaryPart
		local id = model:GetAttribute("DummyId")
		if root and type(id) == "number" and model:GetAttribute("Alive") then
			table.insert(list, { DummyId = id, Root = root.CFrame })
		end
	end
	return list
end

-- Nearest standardized-hitbox hit along a ray among current targets.
local function castCharacters(
	origin: Vector3,
	direction: Vector3,
	maxDistance: number
): (Target?, Hitbox.Hit?)
	local best: Target? = nil
	local bestHit: Hitbox.Hit? = nil
	for _, target in targets() do
		local hit = Hitbox.Raycast(Hitbox.Shape(target.Root), origin, direction, maxDistance)
		if hit and (bestHit == nil or hit.Distance < bestHit.Distance) then
			best, bestHit = target, hit
		end
	end
	return best, bestHit
end

local function aimPoint(range: number): Vector3
	local origin, direction = camera:GetAimRay()
	refreshFilter()
	local world = Workspace:Raycast(origin, direction * range, params)
	local distance = if world then (world.Position - origin).Magnitude else range
	local _, hit = castCharacters(origin, direction, distance)
	if hit then
		distance = hit.Distance
	end
	return origin + direction * distance
end

local function spreadDirection(direction: Vector3, degrees: number): Vector3
	if degrees <= 0 then
		return direction
	end
	local angle = math.rad(degrees) * math.sqrt(math.random())
	local roll = math.random() * math.pi * 2
	local basis = CFrame.lookAt(Vector3.zero, direction)
	return (basis * CFrame.Angles(0, 0, roll) * CFrame.Angles(angle, 0, 0)).LookVector
end

local function headPosition(root: BasePart): Vector3
	return Hitbox.Shape(root.CFrame).HeadCenter
end

local shownWeapon = ""

local function showWeapon(state: { [string]: any })
	local key = `{state.Equipped}:{state.Loadout[state.Equipped]}:{tostring(state.KnifeInHand)}`
	if key ~= shownWeapon then
		shownWeapon = key
		viewmodel:SetWeapon(state.Loadout[state.Equipped], state.Equipped, state.KnifeInHand)
	end
end

function WeaponController.Reload(self: typeof(WeaponController))
	local state = self.State
	if state == nil or state.Equipped == "Knife" then
		return
	end
	local ammo = state.Ammo[state.Equipped]
	local stats = self:FirearmStats()
	local now = Net.Now()
	if ammo == nil or stats == nil or (ammo.ReloadEndsAt and now < ammo.ReloadEndsAt) then
		return
	end
	if ammo.Magazine >= stats.MagazineSize or ammo.Reserve <= 0 then
		return
	end
	ammo.ReloadEndsAt = now + stats.ReloadSeconds -- prediction; corrected by LoadoutState
	Net.Fire("Reload", { Slot = state.Equipped })
	viewmodel:PlayReload(stats.ReloadSeconds)
	self.Changed:Fire(state)
end

function WeaponController.Equip(self: typeof(WeaponController), slot: string)
	local state = self.State
	if state == nil or state.Equipped == slot or localRoot() == nil then
		return
	end
	local id = state.Loadout[slot]
	local archetype = id and WeaponCatalog.GetArchetype(id)
	local equipSeconds = archetype
			and ((archetype.Firearm and archetype.Firearm.EquipSeconds) or (archetype.Knife and archetype.Knife.EquipSeconds))
		or 0.5
	for _, ammo in state.Ammo do
		ammo.ReloadEndsAt = nil -- switching cancels reload (mirrors server)
	end
	state.Equipped = slot
	state.EquipReadyAt = Net.Now() + equipSeconds
	camera:SetAiming(false)
	Net.Fire("EquipSlot", { Slot = slot })
	showWeapon(state)
	self.Changed:Fire(state)
end

local function fire(self: typeof(WeaponController))
	local state = self.State
	local stats = self:FirearmStats()
	local root = localRoot()
	if state == nil or stats == nil or root == nil or not canAct() then
		return
	end
	local now = Net.Now()
	if now < state.EquipReadyAt then
		return
	end
	local ammo = state.Ammo[state.Equipped]
	if ammo == nil or (ammo.ReloadEndsAt and now < ammo.ReloadEndsAt) then
		return
	end
	if ammo.Magazine <= 0 then
		self:Reload()
		return
	end
	if now - lastShot < 60 / stats.RoundsPerMinute then
		return
	end
	lastShot = now
	ammo.Magazine -= 1
	shotId = (shotId + 1) % 2 ^ 31

	local origin = headPosition(root)
	local base = (aimPoint(stats.Range) - origin)
	if base.Magnitude < 1e-3 then
		base = select(2, camera:GetAimRay())
	end
	local direction = base.Unit
	local spread = if camera.Aiming then stats.AimSpreadDegrees else stats.HipSpreadDegrees
	local hits = {}
	local muzzle = viewmodel:GetMuzzlePosition() or origin
	refreshFilter()
	for pellet = 1, stats.Pellets do
		local pelletDirection = spreadDirection(direction, spread)
		local world = Workspace:Raycast(origin, pelletDirection * stats.Range, params)
		local limit = if world then (world.Position - origin).Magnitude else stats.Range
		local target, hit = castCharacters(origin, pelletDirection, limit)
		local endPoint: Vector3
		if target and hit then
			endPoint = origin + pelletDirection * hit.Distance
			table.insert(hits, {
				TargetUserId = target.Player and target.Player.UserId,
				DummyId = target.DummyId,
				Position = endPoint,
				Zone = hit.Zone,
				Pellet = pellet,
			})
		else
			endPoint = origin + pelletDirection * limit
			if world then
				effects:Impact(world.Position, world.Normal)
			end
		end
		effects:Tracer(muzzle, endPoint)
	end
	Net.Fire("FireWeapon", {
		Slot = state.Equipped,
		ShotId = shotId,
		ClientTime = now,
		Origin = origin,
		Direction = direction,
		Hits = hits,
	})
	effects:MuzzleFlash(muzzle)
	viewmodel:Kick()
	camera:AddRecoil(stats.RecoilPitchDegrees, stats.RecoilYawDegrees)
	self.Fired:Fire(spread)
	self.Changed:Fire(state)
	if ammo.Magazine <= 0 then
		self:Reload()
	end
end

local function melee(self: typeof(WeaponController), attack: "Slash" | "Stab")
	local state = self.State
	local root = localRoot()
	if state == nil or root == nil or state.Equipped ~= "Knife" or not state.KnifeInHand or not canAct() then
		return
	end
	local knife = WeaponCatalog.GetKnifeStats(state.Loadout.Knife)
	local now = Net.Now()
	if knife == nil or now < state.EquipReadyAt or now < meleeReadyAt then
		return
	end
	local stats = if attack == "Stab" then knife.Stab else knife.Slash
	meleeReadyAt = now + stats.CooldownSeconds
	local origin = headPosition(root)
	local _, look = camera:GetAimRay()
	local flatLook = Vector3.new(look.X, 0, look.Z)
	local target: Target? = nil
	local best = math.huge
	for _, candidate in targets() do
		local distance = Hitbox.DistanceToPoint(Hitbox.Shape(candidate.Root), origin)
		local toTarget = candidate.Root.Position - origin
		local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
		local inCone = flat.Magnitude < 0.5
			or flatLook.Magnitude < 0.01
			or math.deg(math.acos(math.clamp(flat.Unit:Dot(flatLook.Unit), -1, 1)))
				<= stats.ConeDegrees / 2
		if distance <= stats.Range and inCone and distance < best then
			best, target = distance, candidate
		end
	end
	Net.Fire("MeleeAttack", {
		Attack = attack,
		ClientTime = now,
		Origin = origin,
		Direction = look,
		TargetUserId = target and target.Player and target.Player.UserId,
		TargetDummyId = target and target.DummyId,
	})
	viewmodel:Swing(attack)
end

local function throw(self: typeof(WeaponController))
	local state = self.State
	local root = localRoot()
	if state == nil or root == nil or state.Equipped ~= "Knife" or not state.KnifeInHand or not canAct() then
		return
	end
	if not Config.FeatureFlags.ThrownKnives then
		return
	end
	local knife = WeaponCatalog.GetKnifeStats(state.Loadout.Knife)
	local now = Net.Now()
	if knife == nil or now < state.EquipReadyAt or now < throwReadyAt then
		return
	end
	throwReadyAt = now + knife.Throw.CooldownSeconds
	meleeReadyAt = throwReadyAt
	local origin = headPosition(root)
	local direction = (aimPoint(200) - origin)
	if direction.Magnitude < 1e-3 then
		return
	end
	Net.Fire("ThrowKnife", { ClientTime = now, Origin = origin, Direction = direction.Unit })
	state.KnifeInHand = false -- prediction; LoadoutState confirms
	viewmodel:Swing("Throw")
	task.delay(0.2, function()
		if self.State == state and not state.KnifeInHand then
			showWeapon(state)
		end
	end)
	self.Changed:Fire(state)
end

local function nextSlot(current: string): string
	local index = table.find(SLOTS, current) or 1
	return SLOTS[index % #SLOTS + 1]
end

function WeaponController.Init(self: typeof(WeaponController), registry: { [string]: any })
	input = registry.InputController
	camera = registry.CameraController
	effects = registry.EffectsController
	viewmodel = registry.ViewmodelController

	registry.SnapshotController.Loaded:Connect(function(snapshot)
		if snapshot.Loadout then
			self:ApplyState(snapshot.Loadout)
		end
		self.MatchActive = snapshot.Match
			and (snapshot.Match.Phase == "Active" or snapshot.Match.Phase == "Lobby")
	end)

	input.Began:Connect(function(action: string)
		if UIState.MenuOpen then
			return
		end
		local state = self.State
		if state == nil then
			return
		end
		if action == "Fire" then
			triggerReleased = false
			if state.Equipped == "Knife" then
				melee(self, "Slash")
			else
				fire(self)
			end
		elseif action == "Aim" then
			if state.Equipped == "Knife" then
				melee(self, "Stab")
			else
				local stats = self:FirearmStats()
				camera:SetAiming(true, stats and stats.AimFieldOfView)
			end
		elseif action == "Reload" then
			self:Reload()
		elseif action == "NextWeapon" then
			self:Equip(nextSlot(state.Equipped))
		elseif action == "SlotPrimary" then
			self:Equip("Primary")
		elseif action == "SlotSecondary" then
			self:Equip("Secondary")
		elseif action == "SlotKnife" then
			self:Equip("Knife")
		elseif action == "ThrowKnife" then
			throw(self)
		elseif action == "Inspect" then
			viewmodel:Inspect()
		elseif action == "Sprint" then
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and not camera.Aiming then
				humanoid.WalkSpeed = Config.Player.Movement.RunSpeed
			end
		end
	end)
	input.Ended:Connect(function(action: string)
		if action == "Fire" then
			triggerReleased = true
		elseif action == "Aim" then
			camera:SetAiming(false)
		elseif action == "Sprint" then
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.WalkSpeed = Config.Player.Movement.WalkSpeed
			end
		end
	end)
end

-- Server state is authoritative. Timestamps share the synchronized GetServerTimeNow clock.
function WeaponController.ApplyState(self: typeof(WeaponController), snapshot: { [string]: any })
	self.State = snapshot
	showWeapon(snapshot)
	self.Changed:Fire(snapshot)
end

function WeaponController.Start(self: typeof(WeaponController))
	Net.On("LoadoutState", function(snapshot)
		self:ApplyState(snapshot)
	end)
	Net.On("HitConfirmed", function(payload)
		self.HitConfirmed:Fire(payload)
	end)
	Net.On("MatchState", function(state)
		self.MatchActive = state.Phase == "Active" or state.Phase == "Lobby"
	end)
	player.CharacterAdded:Connect(function()
		shownWeapon = ""
		camera:SetAiming(false)
		lastShot = -math.huge
		meleeReadyAt = 0
		throwReadyAt = 0
	end)

	RunService.RenderStepped:Connect(function()
		local state = self.State
		if state and not triggerReleased and input:IsDown("Fire") and state.Equipped ~= "Knife" then
			local stats = self:FirearmStats()
			if stats and stats.FireMode == "Automatic" then
				fire(self)
			end
		end
		local now = os.clock()
		if now - lastAimSent.Time >= 0.1 and localRoot() then
			local pitch = math.clamp(camera.Pitch, -1.5, 1.5)
			if math.abs(pitch - lastAimSent.Pitch) > 0.02 or camera.Aiming ~= lastAimSent.Aiming then
				lastAimSent = { Pitch = pitch, Aiming = camera.Aiming, Time = now }
				Net.Fire("AimUpdate", { Pitch = pitch, Aiming = camera.Aiming })
			end
		end
	end)
end

return WeaponController
