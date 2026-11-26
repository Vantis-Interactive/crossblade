--!strict
--[[
	Server-simulated thrown knives (spec §8). The server integrates each knife's flight, tests the
	segment against world geometry and standardized hitboxes, applies damage, and drops the knife into
	the world where only its owner can recover it (by walking within RecoverRadius).
	A knife that is superseded (station replacement, respawn) or expires is removed.

	Known limitation (docs/DECISIONS.md D-011): projectiles are simulated against current target
	positions, without rewind, because they start on the server at receive time.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Archetypes = require(ReplicatedStorage.Shared.Config.Weapons.Archetypes)
local DamageCalculator = require(ReplicatedStorage.Shared.Combat.DamageCalculator)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local WeaponCatalog = require(ReplicatedStorage.Shared.Weapons.WeaponCatalog)
local WeaponModels = require(ReplicatedStorage.Shared.Weapons.WeaponModels)
local CombatQuery = require(script.Parent.Parent.Core.CombatQuery)

local DROPPED_TAG = "Crossblade.DroppedKnife"

type Knife = {
	Owner: Player,
	ThrowId: number,
	WeaponId: string,
	Stats: Archetypes.ThrowStats,
	Model: Model,
	Position: Vector3,
	Velocity: Vector3,
	Age: number,
	Landed: boolean,
	ExpiresAt: number,
}

local ProjectileService = {
	Name = "ProjectileService",
	Dependencies = {
		"Net",
		"WeaponService",
		"DamageService",
		"HealthService",
		"MatchService",
		"PlayerDataService",
		"TrainingService",
		"MapService",
	},
	DroppedTag = DROPPED_TAG,
}

local knives: { Knife } = {}
local folder: Folder
local net: any
local weapons: any
local damage: any
local health: any
local match: any
local playerData: any
local training: any

local function remove(knife: Knife)
	local index = table.find(knives, knife)
	if index then
		table.remove(knives, index)
	end
	knife.Model:Destroy()
end

local function land(knife: Knife, position: Vector3)
	knife.Landed = true
	knife.Position = position
	knife.ExpiresAt = os.clock() + knife.Stats.GroundLifetimeSeconds
	knife.Model:PivotTo(CFrame.new(position + Vector3.new(0, 0.6, 0)) * CFrame.Angles(math.rad(90), 0, 0))
	CollectionService:AddTag(knife.Model, DROPPED_TAG)
end

-- Drops the knife straight down onto the nearest floor, or removes it if there is none.
local function drop(knife: Knife, from: Vector3)
	local hit = CombatQuery.Raycast(from, Vector3.new(0, -200, 0))
	if hit then
		land(knife, hit.Position)
	else
		remove(knife)
	end
end

function ProjectileService.LaunchKnife(
	_self: typeof(ProjectileService),
	owner: Player,
	throwId: number,
	origin: Vector3,
	direction: Vector3,
	stats: Archetypes.ThrowStats,
	weaponId: string
)
	local entry = WeaponCatalog.Get(weaponId)
	local model = WeaponModels.Build(entry and entry.ModelProfile or "Knife", weaponId)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	model.Name = `ThrownKnife_{owner.UserId}_{throwId}`
	model:SetAttribute("OwnerUserId", owner.UserId)
	model:SetAttribute("ThrowId", throwId)
	model:PivotTo(CFrame.lookAt(origin, origin + direction))
	model.Parent = folder
	table.insert(knives, {
		Owner = owner,
		ThrowId = throwId,
		WeaponId = weaponId,
		Stats = stats,
		Model = model,
		Position = origin,
		Velocity = direction * stats.Speed,
		Age = 0,
		Landed = false,
		ExpiresAt = math.huge,
	})
end

local function step(dt: number)
	for index = #knives, 1, -1 do
		local knife = knives[index]
		if knife and not knife.Landed then
			local gravity = Vector3.new(0, -knife.Stats.Gravity, 0)
			local nextPosition = knife.Position + knife.Velocity * dt + gravity * (0.5 * dt * dt)
			local segment = nextPosition - knife.Position
			local length = segment.Magnitude
			knife.Velocity += gravity * dt
			knife.Age += dt
			if length > 1e-4 then
				local direction = segment / length
				local worldHit = CombatQuery.Raycast(knife.Position, segment)
				local limit = if worldHit then (worldHit.Position - knife.Position).Magnitude else length

				local victim: Player? = nil
				local victimDummy: any = nil
				local victimHit: Hitbox.Hit? = nil
				for _, player in Players:GetPlayers() do
					local root = player ~= knife.Owner
						and player.Character
						and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
					if root and match:CanDamage(knife.Owner, player) then
						local hit =
							Hitbox.Raycast(Hitbox.Shape(root.CFrame), knife.Position, direction, limit)
						if hit and (victimHit == nil or hit.Distance < victimHit.Distance) then
							victim, victimDummy, victimHit = player, nil, hit
						end
					end
				end
				for _, dummy in training:AliveDummies() do
					local hit =
						Hitbox.Raycast(Hitbox.Shape(dummy.Root.CFrame), knife.Position, direction, limit)
					if hit and (victimHit == nil or hit.Distance < victimHit.Distance) then
						victim, victimDummy, victimHit = nil, dummy, hit
					end
				end

				if victimHit and (victim or victimDummy) then
					local impact = knife.Position + direction * victimHit.Distance
					local amount = DamageCalculator.ThrownKnife(knife.Stats, victimHit.Zone)
					if victimDummy and knife.Owner.Parent == Players then
						local dealt, down =
							training:ApplyHit(knife.Owner, victimDummy.Id, amount, "ThrownKnife")
						net.Fire("HitConfirmed", knife.Owner, {
							Hits = {
								{
									TargetDummyId = victimDummy.Id,
									Damage = dealt,
									Zone = victimHit.Zone,
									Eliminated = down,
								},
							},
						})
					elseif
						victim
						and knife.Owner.Parent == Players
						and match:CanDamage(knife.Owner, victim)
					then
						local dealt, eliminated = damage:Apply(knife.Owner, victim, amount, {
							WeaponId = knife.WeaponId,
							Kind = "ThrownKnife",
							Zone = victimHit.Zone,
						})
						if dealt > 0 then
							if match:TracksStats() then
								playerData:Update(knife.Owner, function(data)
									data.Stats.KnivesHit += 1
									data.Stats.DamageDealt += dealt
								end)
							end
							net.Fire("HitConfirmed", knife.Owner, {
								Hits = {
									{
										TargetUserId = victim.UserId,
										Damage = dealt,
										Zone = victimHit.Zone,
										Eliminated = eliminated,
									},
								},
							})
						end
					end
					drop(knife, impact)
				elseif worldHit then
					land(knife, worldHit.Position + worldHit.Normal * 0.1)
				elseif knife.Age >= knife.Stats.MaxFlightSeconds then
					drop(knife, nextPosition)
				else
					knife.Position = nextPosition
					knife.Model:PivotTo(
						CFrame.lookAt(nextPosition, nextPosition + direction)
							* CFrame.Angles(-knife.Age * 25, 0, 0)
					)
				end
			end
		end
	end
end

local function recoverLoop()
	while true do
		task.wait(0.1)
		local now = os.clock()
		for index = #knives, 1, -1 do
			local knife = knives[index]
			if knife and knife.Landed then
				local root = knife.Owner.Character
					and knife.Owner.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if now >= knife.ExpiresAt or knife.Owner.Parent ~= Players then
					remove(knife)
				elseif
					root
					and health:IsAlive(knife.Owner)
					and (root.Position - knife.Position).Magnitude <= knife.Stats.RecoverRadius
				then
					if weapons:RecoverKnife(knife.Owner, knife.ThrowId) then
						remove(knife)
					end
				end
			end
		end
	end
end

function ProjectileService.Init(_self: typeof(ProjectileService), registry: { [string]: any })
	net = registry.Net
	weapons = registry.WeaponService
	damage = registry.DamageService
	health = registry.HealthService
	match = registry.MatchService
	playerData = registry.PlayerDataService
	training = registry.TrainingService
	registry.MapService.MapChanged:Connect(function()
		for index = #knives, 1, -1 do
			remove(knives[index])
		end
	end)

	folder = Instance.new("Folder")
	folder.Name = "CrossbladeProjectiles"
	folder.Parent = Workspace

	weapons.KnifeReplaced:Connect(function(player: Player, supersededId: number)
		for index = #knives, 1, -1 do
			local knife = knives[index]
			if knife.Owner == player and knife.ThrowId == supersededId then
				remove(knife)
			end
		end
	end)
end

function ProjectileService.Start(_self: typeof(ProjectileService))
	RunService.Heartbeat:Connect(step)
	task.spawn(recoverLoop)
end

return ProjectileService
