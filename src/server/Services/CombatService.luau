--!strict
--[[
	Combat request handling (spec §9). Clients propose; the server validates and applies.

	FireWeapon validation order (any failure drops the request):
	  combat allowed (alive, in active match) -> slot equals server-equipped slot -> equip delay elapsed
	  -> fire cadence (min spacing + sustained rate) -> ammunition (not reloading, magazine > 0)
	  -> timestamp within bounded rewind window -> per pellet: unique pellet index, valid target,
	     HitValidator against rewound standardized hitboxes with line of sight.
	Damage is computed here from server-side archetype stats; the client never sends damage.

	Lag compensation: every character's root CFrame is sampled into a PositionHistory at
	Combat.LagCompensation.SampleRate; hits are validated against the target's position at the
	client's (clamped) fire time.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local DamageCalculator = require(ReplicatedStorage.Shared.Combat.DamageCalculator)
local FireCadence = require(ReplicatedStorage.Shared.Combat.FireCadence)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local KnifeState = require(ReplicatedStorage.Shared.Combat.KnifeState)
local PositionHistory = require(ReplicatedStorage.Shared.Combat.PositionHistory)
local WeaponCatalog = require(ReplicatedStorage.Shared.Weapons.WeaponCatalog)
local CombatQuery = require(script.Parent.Parent.Core.CombatQuery)
local HitValidator = require(script.Parent.Parent.Domain.HitValidator)

local L = Config.Combat.LagCompensation
local V = Config.Combat.Validation
local TOLERANCE = table.freeze({
	MaxOriginDeviation = V.MaxOriginDeviation,
	HitboxTolerance = V.HitboxTolerance,
	HeadshotTolerance = V.HeadshotTolerance,
	DirectionToleranceDegrees = V.DirectionToleranceDegrees,
	LineOfSightEndPadding = V.LineOfSightEndPadding,
})
-- Small allowance for equip/melee timers so legitimate inputs at the boundary are not dropped.
local TIMER_TOLERANCE = 0.08

local CombatService = {
	Name = "CombatService",
	Dependencies = {
		"Net",
		"WeaponService",
		"AmmunitionService",
		"DamageService",
		"HealthService",
		"SpawnService",
		"AntiCheatService",
		"MatchService",
		"PlayerDataService",
		"ProjectileService",
	},
}

local histories: { [Player]: PositionHistory.PositionHistory } = {}
local net: any
local weapons: any
local ammunition: any
local damage: any
local health: any
local spawns: any
local antiCheat: any
local match: any
local playerData: any
local projectiles: any

local function root(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function rewoundRoot(player: Player, time: number): CFrame?
	local history = histories[player]
	local cframe = history and PositionHistory.At(history, time)
	if cframe then
		return cframe
	end
	local part = root(player)
	return part and part.CFrame
end

-- The shooter's head at the fire time, or now if that is closer to the reported origin.
local function shooterHead(player: Player, time: number, origin: Vector3): Vector3?
	local rewound = rewoundRoot(player, time)
	local current = root(player)
	if rewound == nil and current == nil then
		return nil
	end
	local candidates = {}
	if rewound then
		table.insert(candidates, Hitbox.Shape(rewound).HeadCenter)
	end
	if current then
		table.insert(candidates, Hitbox.Shape(current.CFrame).HeadCenter)
	end
	table.sort(candidates, function(a, b)
		return (a - origin).Magnitude < (b - origin).Magnitude
	end)
	return candidates[1]
end

local function canFight(player: Player): boolean
	return health:IsAlive(player) and match:IsCombatAllowed(player)
end

local function addStats(player: Player, changes: { [string]: number })
	playerData:Update(player, function(data)
		for key, amount in changes do
			data.Stats[key] += amount
		end
	end)
end

local function onFire(player: Player, payload: any)
	if not canFight(player) then
		return
	end
	local state = weapons:GetState(player)
	if state == nil or state.Equipped ~= payload.Slot then
		weapons:PushState(player) -- resync a stale client
		return
	end
	local now = net.Now()
	if now < state.EquipReadyAt - TIMER_TOLERANCE then
		return
	end
	local weaponId = state.Loadout[payload.Slot]
	local stats = WeaponCatalog.GetFirearmStats(weaponId)
	if stats == nil then
		antiCheat:Report(player, "UnownedWeapon", { reason = "NoFirearmInSlot", slot = payload.Slot })
		return
	end
	local cadenceOk, cadenceReason = FireCadence.TryFire(state.Cadence[payload.Slot], now)
	if not cadenceOk then
		if cadenceReason == "RateExceeded" then
			antiCheat:Report(player, "ImpossibleFireRate", { reason = cadenceReason, weapon = weaponId })
		end
		return
	end
	local fired = ammunition:Consume(player, payload.Slot, now)
	if not fired then
		weapons:PushState(player)
		return
	end
	spawns:EndProtection(player)

	net.FireAllExcept("ShotFired", player, {
		ShooterUserId = player.UserId,
		Origin = payload.Origin,
		Direction = payload.Direction,
		Pellets = stats.Pellets,
		Range = stats.Range,
	})

	local stat = { ShotsFired = 1 }
	local rewind = HitValidator.RewindTime(now, payload.ClientTime, L.MaxRewindSeconds, L.MaxFutureSeconds)
	if rewind == nil then
		antiCheat:Report(player, "InvalidShot", { reason = "FutureTimestamp" })
		addStats(player, stat)
		return
	end
	if #payload.Hits > stats.Pellets then
		antiCheat:Report(player, "InvalidShot", { reason = "TooManyPellets" })
		addStats(player, stat)
		return
	end
	local head = shooterHead(player, rewind, payload.Origin)
	if head == nil then
		return
	end

	local seenPellets = {}
	local confirmations = {}
	local anyHit, anyHead = false, false
	local dealtTotal = 0
	for _, hit in payload.Hits do
		local target = Players:GetPlayerByUserId(hit.TargetUserId)
		if seenPellets[hit.Pellet] or hit.Pellet > stats.Pellets then
			antiCheat:Report(player, "InvalidShot", { reason = "DuplicatePellet" })
		elseif target and target ~= player and canFight(target) then
			seenPellets[hit.Pellet] = true
			local targetRoot = rewoundRoot(target, rewind)
			if targetRoot then
				local result = HitValidator.ValidateShot({
					ShooterHead = head,
					Origin = payload.Origin,
					Direction = payload.Direction,
					HitPosition = hit.Position,
					ClaimedZone = hit.Zone,
					TargetRoot = targetRoot,
					Range = stats.Range,
					SpreadDegrees = math.max(stats.HipSpreadDegrees, stats.AimSpreadDegrees),
					LineOfSight = CombatQuery.LineOfSight,
					Tolerance = TOLERANCE,
				})
				if result.Valid then
					local zone = result.Zone :: Hitbox.Zone
					local amount = DamageCalculator.Firearm(stats, result.Distance :: number, zone)
					local dealt, eliminated = damage:Apply(
						player,
						target,
						amount,
						{ WeaponId = weaponId, Kind = "Firearm", Zone = zone }
					)
					anyHit = true
					anyHead = anyHead or zone == "Head"
					dealtTotal += dealt
					if dealt > 0 then
						table.insert(confirmations, {
							TargetUserId = target.UserId,
							Damage = dealt,
							Zone = zone,
							Eliminated = eliminated,
						})
					end
				else
					antiCheat:Report(player, "InvalidShot", { reason = result.Reason })
				end
			end
		end
	end
	if anyHit then
		stat.ShotsHit = 1
		stat.DamageDealt = dealtTotal
		if anyHead then
			stat.Headshots = 1
		end
	end
	addStats(player, stat)
	if #confirmations > 0 then
		net.Fire("HitConfirmed", player, { Hits = confirmations })
	end
end

local function onMelee(player: Player, payload: any)
	if not canFight(player) then
		return
	end
	local state = weapons:GetState(player)
	if state == nil or state.Equipped ~= "Knife" or not KnifeState.CanAttack(state.Knife) then
		return
	end
	local now = net.Now()
	if now < state.EquipReadyAt - TIMER_TOLERANCE or now < state.MeleeReadyAt - TIMER_TOLERANCE then
		return
	end
	local weaponId = state.Loadout.Knife
	local knife = WeaponCatalog.GetKnifeStats(weaponId)
	if knife == nil then
		return
	end
	local attack = if payload.Attack == "Stab" then knife.Stab else knife.Slash
	state.MeleeReadyAt = now + attack.CooldownSeconds
	spawns:EndProtection(player)
	net.FireAllExcept("MeleeSwing", player, { AttackerUserId = player.UserId, Attack = payload.Attack })

	local target = payload.TargetUserId and Players:GetPlayerByUserId(payload.TargetUserId)
	if target == nil or target == player or not canFight(target) then
		return
	end
	local rewind = HitValidator.RewindTime(now, payload.ClientTime, L.MaxRewindSeconds, L.MaxFutureSeconds)
	if rewind == nil then
		antiCheat:Report(player, "InvalidShot", { reason = "FutureTimestamp" })
		return
	end
	local head = shooterHead(player, rewind, payload.Origin)
	local targetRoot = rewoundRoot(target, rewind)
	if head == nil or targetRoot == nil then
		return
	end
	local result = HitValidator.ValidateMelee({
		Origin = payload.Origin,
		Direction = payload.Direction,
		ShooterHead = head,
		TargetRoot = targetRoot,
		Range = attack.Range,
		ConeDegrees = attack.ConeDegrees,
		RangeTolerance = Config.Combat.Melee.RangeTolerance,
		ConeToleranceDegrees = Config.Combat.Melee.ConeToleranceDegrees,
		MaxOriginDeviation = V.MaxOriginDeviation,
		LineOfSight = CombatQuery.LineOfSight,
	})
	if not result.Valid then
		antiCheat:Report(player, "InvalidShot", { reason = `Melee{result.Reason}` })
		return
	end
	local dealt, eliminated =
		damage:Apply(player, target, attack.Damage, { WeaponId = weaponId, Kind = "Knife", Zone = "Body" })
	if dealt > 0 then
		addStats(player, { DamageDealt = dealt })
		net.Fire("HitConfirmed", player, {
			Hits = {
				{ TargetUserId = target.UserId, Damage = dealt, Zone = "Body", Eliminated = eliminated },
			},
		})
	end
end

local function onThrow(player: Player, payload: any)
	if not Config.FeatureFlags.ThrownKnives or not canFight(player) then
		return
	end
	local state = weapons:GetState(player)
	if state == nil or state.Equipped ~= "Knife" or not KnifeState.CanAttack(state.Knife) then
		return
	end
	local now = net.Now()
	if now < state.EquipReadyAt - TIMER_TOLERANCE or now < state.ThrowReadyAt - TIMER_TOLERANCE then
		return
	end
	local current = root(player)
	if current == nil then
		return
	end
	if (Hitbox.Shape(current.CFrame).HeadCenter - payload.Origin).Magnitude > V.MaxOriginDeviation then
		antiCheat:Report(player, "InvalidShot", { reason = "ThrowOriginMismatch" })
		return
	end
	local weaponId = state.Loadout.Knife
	local knife = WeaponCatalog.GetKnifeStats(weaponId)
	if knife == nil then
		return
	end
	local throwId = weapons:ThrowKnife(player)
	if throwId == nil then
		return
	end
	state.ThrowReadyAt = now + knife.Throw.CooldownSeconds
	state.MeleeReadyAt = now + knife.Throw.CooldownSeconds
	spawns:EndProtection(player)
	projectiles:LaunchKnife(player, throwId, payload.Origin, payload.Direction.Unit, knife.Throw, weaponId)
	addStats(player, { KnivesThrown = 1 })
end

function CombatService.Init(_self: typeof(CombatService), registry: { [string]: any })
	net = registry.Net
	weapons = registry.WeaponService
	ammunition = registry.AmmunitionService
	damage = registry.DamageService
	health = registry.HealthService
	spawns = registry.SpawnService
	antiCheat = registry.AntiCheatService
	match = registry.MatchService
	playerData = registry.PlayerDataService
	projectiles = registry.ProjectileService

	net.OnEvent("FireWeapon", onFire)
	net.OnEvent("MeleeAttack", onMelee)
	net.OnEvent("ThrowKnife", onThrow)
end

function CombatService.Start(_self: typeof(CombatService))
	local capacity = math.ceil(L.SampleRate * L.HistorySeconds) + 2
	local function track(player: Player)
		player.CharacterAdded:Connect(function()
			histories[player] = PositionHistory.new(capacity)
		end)
		histories[player] = PositionHistory.new(capacity)
	end
	Players.PlayerAdded:Connect(track)
	for _, player in Players:GetPlayers() do
		track(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		histories[player] = nil
	end)

	local interval = 1 / L.SampleRate
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < interval then
			return
		end
		accumulator = 0
		local now = net.Now()
		for player, history in histories do
			local part = root(player)
			if part then
				PositionHistory.Push(history, now, part.CFrame)
			end
		end
	end)
end

return CombatService
