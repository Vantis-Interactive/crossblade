--!strict
--[[
	Damage application and elimination attribution (spec §9, §10).
	  - Applies validated damage through HealthService; spawn-protected and dead players take none.
	  - Records damage for assists; sends directional damage feedback to the victim.
	  - Converts every death (from HealthService.Died) into exactly one Eliminated event. Deaths with no
	    direct killer (void, reset) credit the top recent attacker so resetting cannot deny a kill.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local DamageLedger = require(script.Parent.Parent.Domain.DamageLedger)

export type DamageInfo = { WeaponId: string, Kind: "Firearm" | "Knife" | "ThrownKnife", Zone: string }

export type Elimination = {
	Victim: Player,
	Killer: Player?,
	WeaponId: string?,
	Kind: string,
	Headshot: boolean,
	Assists: { Player },
	Position: Vector3?,
}

local DamageService = {
	Name = "DamageService",
	Dependencies = { "Net", "HealthService", "SpawnService" },
	Damaged = Signal.new() :: Signal.Signal<Player, Player, number, DamageInfo>,
	Eliminated = Signal.new() :: Signal.Signal<Elimination>,
}

local ledger = DamageLedger.new()
local net: any
local healthService: any
local spawnService: any

local function rootPosition(player: Player): Vector3?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and root.Position
end

-- Returns (damage dealt, eliminated).
function DamageService.Apply(
	_self: typeof(DamageService),
	attacker: Player,
	victim: Player,
	amount: number,
	info: DamageInfo
): (number, boolean)
	if attacker == victim or amount <= 0 then
		return 0, false
	end
	if spawnService:IsProtected(victim) or not healthService:IsAlive(victim) then
		return 0, false
	end
	local result = healthService:ApplyDamage(victim, amount, {
		AttackerUserId = attacker.UserId,
		WeaponId = info.WeaponId,
		Kind = info.Kind,
		Zone = info.Zone,
	})
	if result.Dealt > 0 then
		DamageLedger.Record(ledger, victim.UserId, attacker.UserId, result.Dealt, net.Now())
		DamageService.Damaged:Fire(attacker, victim, result.Dealt, info)
		net.Fire("DamageTaken", victim, {
			FromUserId = attacker.UserId,
			FromPosition = rootPosition(attacker),
			Amount = result.Dealt,
			Health = result.Health,
		})
	end
	return result.Dealt, result.Died
end

function DamageService.Init(_self: typeof(DamageService), registry: { [string]: any })
	net = registry.Net
	healthService = registry.HealthService
	spawnService = registry.SpawnService

	healthService.Died:Connect(function(victim: Player, cause: any, position: Vector3?)
		local now = net.Now()
		local assistCfg = Config.Combat.Assists
		local killer: Player? = cause and Players:GetPlayerByUserId(cause.AttackerUserId)
		local kind = if cause then cause.Kind else "Environment"
		if killer == nil then
			local recent = DamageLedger.Assists(ledger, victim.UserId, nil, now, 1, assistCfg.WindowSeconds)
			if recent[1] then
				killer = Players:GetPlayerByUserId(recent[1])
				kind = "Finished"
			end
		end
		local assistIds = DamageLedger.Assists(
			ledger,
			victim.UserId,
			killer and killer.UserId,
			now,
			assistCfg.MinimumDamage,
			assistCfg.WindowSeconds
		)
		local assists = {}
		for _, userId in assistIds do
			local assister = Players:GetPlayerByUserId(userId)
			if assister then
				table.insert(assists, assister)
			end
		end
		DamageLedger.ClearVictim(ledger, victim.UserId)
		DamageService.Eliminated:Fire({
			Victim = victim,
			Killer = killer,
			WeaponId = cause and cause.WeaponId,
			Kind = kind,
			Headshot = cause ~= nil and cause.Zone == "Head",
			Assists = assists,
			Position = position,
		})
	end)
end

function DamageService.Start(_self: typeof(DamageService))
	Players.PlayerRemoving:Connect(function(player)
		DamageLedger.ForgetPlayer(ledger, player.UserId)
	end)
end

return DamageService
