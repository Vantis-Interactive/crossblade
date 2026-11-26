--!strict
--[[
	Loadouts, equipping, knife ownership and visible weapon models (spec §8).

	Security: the weapon in every slot is resolved here from the persisted inventory (Domain/Loadout);
	clients only ever reference slots. Equip timing, melee/throw cooldowns and knife state are all
	server-side. Weapon models are cosmetic and excluded from queries (CanQuery = false).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FireCadence = require(ReplicatedStorage.Shared.Combat.FireCadence)
local KnifeState = require(ReplicatedStorage.Shared.Combat.KnifeState)
local Config = require(ReplicatedStorage.Shared.Config)
local Logger = require(ReplicatedStorage.Shared.Util.Logger)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local WeaponCatalog = require(ReplicatedStorage.Shared.Weapons.WeaponCatalog)
local WeaponModels = require(ReplicatedStorage.Shared.Weapons.WeaponModels)
local Loadout = require(script.Parent.Parent.Domain.Loadout)

local log = Logger.new("Weapon")

export type Slot = "Primary" | "Secondary" | "Knife"

export type WeaponState = {
	Loadout: Loadout.Loadout,
	Equipped: Slot,
	EquipReadyAt: number,
	Knife: KnifeState.KnifeState,
	Cadence: { [string]: FireCadence.FireCadence },
	MeleeReadyAt: number,
	ThrowReadyAt: number,
	Model: Model?,
}

local WeaponService = {
	Name = "WeaponService",
	Dependencies = { "Net", "PlayerDataService", "AmmunitionService", "AuditService" },
	-- (player, supersededThrowId) when a station/respawn replaces a knife that is still in the world.
	KnifeReplaced = Signal.new() :: Signal.Signal<Player, number>,
	KnifeRecovered = Signal.new() :: Signal.Signal<Player>,
	Reloaded = Signal.new() :: Signal.Signal<Player, string>, -- a reload was started
}

local states: { [Player]: WeaponState } = {}
local net: any
local playerData: any
local ammunition: any
local audit: any

local function equipSeconds(weaponId: string): number
	local archetype = WeaponCatalog.GetArchetype(weaponId)
	if archetype and archetype.Firearm then
		return archetype.Firearm.EquipSeconds
	elseif archetype and archetype.Knife then
		return archetype.Knife.EquipSeconds
	end
	return 0.5
end

local function attachModel(player: Player, state: WeaponState)
	if state.Model then
		state.Model:Destroy()
		state.Model = nil
	end
	local character = player.Character
	if character == nil then
		return
	end
	local weaponId = state.Loadout[state.Equipped]
	local entry = WeaponCatalog.Get(weaponId)
	character:SetAttribute("EquippedSlot", state.Equipped)
	character:SetAttribute("WeaponId", weaponId)
	character:SetAttribute("AnimationProfile", entry and entry.AnimationProfile or "OneHanded")
	-- A thrown knife leaves the hand empty.
	if state.Equipped == "Knife" and not state.Knife.InHand then
		return
	end
	local hand = (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")) :: BasePart?
	if hand == nil or entry == nil then
		return
	end
	local model = WeaponModels.Build(entry.ModelProfile, weaponId)
	local handle = model.PrimaryPart :: BasePart
	-- Hand -Y is "forward" when the arm is raised by the procedural pose (AnimationController).
	model:PivotTo(hand.CFrame * CFrame.new(0, -hand.Size.Y / 2, 0) * CFrame.Angles(math.rad(-90), 0, 0))
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = handle
	weld.Parent = handle
	model.Name = "EquippedWeapon"
	model.Parent = character
	state.Model = model
end

function WeaponService.Snapshot(_self: typeof(WeaponService), player: Player, now: number): { [string]: any }?
	local state = states[player]
	if state == nil then
		return nil
	end
	return {
		Loadout = table.clone(state.Loadout),
		Equipped = state.Equipped,
		EquipReadyAt = state.EquipReadyAt,
		KnifeInHand = state.Knife.InHand,
		Ammo = ammunition:Snapshot(player, now),
		ServerTime = now,
	}
end

function WeaponService.PushState(self: typeof(WeaponService), player: Player)
	local snapshot = self:Snapshot(player, net.Now())
	if snapshot then
		net.Fire("LoadoutState", player, snapshot)
	end
end

function WeaponService.GetState(_self: typeof(WeaponService), player: Player): WeaponState?
	return states[player]
end

-- Called by SpawnService on every new life.
function WeaponService.ResetForLife(self: typeof(WeaponService), player: Player)
	local profile = playerData:GetProfile(player)
	local data = profile and profile.Data
	local preset = data and data.Loadouts.Presets[data.Loadouts.ActivePreset]
	local loadout, problems = Loadout.Resolve(data and data.Inventory.Weapons, preset)
	for _, problem in problems do
		audit:Record("Security", "LoadoutRejected", player.UserId, {
			slot = problem.Slot,
			weapon = tostring(problem.WeaponId),
			reason = problem.Reason,
		})
	end

	local previous = states[player]
	if previous and previous.Knife.ThrowId then
		WeaponService.KnifeReplaced:Fire(player, previous.Knife.ThrowId)
	end
	if previous and previous.Model then
		previous.Model:Destroy()
	end

	local cadence = {}
	for _, slot in { "Primary", "Secondary" } do
		local stats = WeaponCatalog.GetFirearmStats(loadout[slot])
		if stats then
			cadence[slot] = FireCadence.new(
				FireCadence.IntervalForRpm(stats.RoundsPerMinute),
				Config.Combat.FireTokenBurst
			)
		end
	end
	ammunition:Reset(player, loadout)
	local state: WeaponState = {
		Loadout = loadout,
		Equipped = "Primary",
		EquipReadyAt = 0,
		Knife = KnifeState.new(),
		Cadence = cadence,
		MeleeReadyAt = 0,
		ThrowReadyAt = 0,
		Model = nil,
	}
	states[player] = state
	attachModel(player, state)
	self:PushState(player)
end

function WeaponService.Equip(self: typeof(WeaponService), player: Player, slot: Slot)
	local state = states[player]
	if state == nil or state.Equipped == slot then
		return
	end
	ammunition:CancelReloads(player) -- switching cancels an in-progress reload
	state.Equipped = slot
	state.EquipReadyAt = net.Now() + equipSeconds(state.Loadout[slot])
	attachModel(player, state)
	self:PushState(player)
end

function WeaponService.ThrowKnife(self: typeof(WeaponService), player: Player): number?
	local state = states[player]
	if state == nil then
		return nil
	end
	local id = KnifeState.Throw(state.Knife)
	if id then
		attachModel(player, state)
		self:PushState(player)
	end
	return id
end

function WeaponService.RecoverKnife(self: typeof(WeaponService), player: Player, throwId: number): boolean
	local state = states[player]
	if state == nil or not KnifeState.Recover(state.Knife, throwId) then
		return false
	end
	WeaponService.KnifeRecovered:Fire(player)
	attachModel(player, state)
	self:PushState(player)
	return true
end

-- Knife replacement station. Returns true if a knife was granted.
function WeaponService.ReplaceKnife(self: typeof(WeaponService), player: Player): boolean
	local state = states[player]
	if state == nil or state.Knife.InHand then
		return false
	end
	local superseded = KnifeState.Replace(state.Knife)
	if superseded then
		WeaponService.KnifeReplaced:Fire(player, superseded)
	end
	attachModel(player, state)
	self:PushState(player)
	return true
end

function WeaponService.Init(self: typeof(WeaponService), registry: { [string]: any })
	net = registry.Net
	playerData = registry.PlayerDataService
	ammunition = registry.AmmunitionService
	audit = registry.AuditService

	net.OnEvent("EquipSlot", function(player: Player, payload: any)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid == nil or humanoid.Health <= 0 then
			return
		end
		self:Equip(player, payload.Slot)
	end)

	net.OnEvent("Reload", function(player: Player, payload: any)
		local state = states[player]
		if state == nil or state.Equipped ~= payload.Slot then
			return
		end
		local now = net.Now()
		local ok, reason = ammunition:StartReload(player, payload.Slot, now)
		self:PushState(player)
		if ok then
			WeaponService.Reloaded:Fire(player, payload.Slot)
			local ammo = ammunition:Get(player, payload.Slot)
			local endsAt = ammo and ammo.ReloadEndsAt
			if endsAt then
				task.delay(math.max(0, endsAt - now) + 0.02, function()
					if states[player] == state then
						self:PushState(player)
					end
				end)
			end
		else
			log:Debug("reload refused", { player = player.UserId, reason = reason })
		end
	end)

	net.OnEvent("AimUpdate", function(player: Player, payload: any)
		local character = player.Character
		if character then
			character:SetAttribute("AimPitch", payload.Pitch)
			character:SetAttribute("Aiming", payload.Aiming)
		end
	end)
end

function WeaponService.Start(_self: typeof(WeaponService))
	Players.PlayerRemoving:Connect(function(player)
		local state = states[player]
		if state and state.Model then
			state.Model:Destroy()
		end
		states[player] = nil
	end)
end

return WeaponService
