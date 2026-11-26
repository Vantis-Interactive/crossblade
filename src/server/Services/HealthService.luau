--!strict
--[[
	Authoritative health (spec §7). The server keeps its own health value per life and mirrors it to
	the Humanoid. There is no regeneration: the default Roblox regen script is overridden by
	StarterCharacterScripts/Health, and any unexpected increase is reverted here as a second guard.

	Every death goes through one path: Humanoid.Died -> HealthService.Died(player, cause, position).
	`cause` is set when the death came from ApplyDamage; nil means environmental (void, reset).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local HealthRules = require(ReplicatedStorage.Shared.Combat.HealthRules)
local Logger = require(ReplicatedStorage.Shared.Util.Logger)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local log = Logger.new("Health")
local MAX = Config.Player.MaxHealth

export type Cause = {
	AttackerUserId: number,
	WeaponId: string,
	Kind: "Firearm" | "Knife" | "ThrownKnife",
	Zone: string,
}

type LifeState = {
	Humanoid: Humanoid,
	Health: number,
	Alive: boolean,
	PendingCause: Cause?,
	DiedFired: boolean,
}

local HealthService = {
	Name = "HealthService",
	Dependencies = { "MapService", "AuditService" },
	Died = Signal.new() :: Signal.Signal<Player, Cause?, Vector3?>,
}

local lives: { [Player]: LifeState } = {}
local mapService: any
local audit: any

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid == nil then
		log:Error("character has no Humanoid", { player = player.UserId })
		return
	end
	humanoid.BreakJointsOnDeath = false -- non-graphic eliminations: no dismemberment
	humanoid.MaxHealth = MAX
	humanoid.Health = MAX
	humanoid.WalkSpeed = Config.Player.Movement.WalkSpeed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = Config.Player.Movement.JumpPower

	local life: LifeState =
		{ Humanoid = humanoid, Health = MAX, Alive = true, PendingCause = nil, DiedFired = false }
	lives[player] = life

	humanoid.HealthChanged:Connect(function(value: number)
		if lives[player] ~= life or not life.Alive then
			return
		end
		if value > life.Health + 1e-3 then
			-- Something other than HealthService raised health: revert (no regeneration exists).
			audit:Record(
				"Security",
				"UnexpectedHealthIncrease",
				player.UserId,
				{ from = life.Health, to = value }
			)
			humanoid.Health = life.Health
		elseif value < life.Health - 1e-3 then
			-- Environmental damage outside HealthService (e.g. engine kill): accept it.
			life.Health = math.max(0, value)
		end
	end)

	humanoid.Died:Connect(function()
		-- Ignore deaths of characters that were replaced (respawn) or removed from the world.
		if life.DiedFired or lives[player] ~= life or character.Parent == nil then
			return
		end
		life.DiedFired = true
		life.Alive = false
		life.Health = 0
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		HealthService.Died:Fire(player, life.PendingCause, root and root.Position)
	end)
end

function HealthService.Init(_self: typeof(HealthService), registry: { [string]: any })
	mapService = registry.MapService
	audit = registry.AuditService
end

function HealthService.Start(self: typeof(HealthService))
	local function watch(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lives[player] = nil
	end)

	-- Map boundary: anything below the kill height is eliminated (environmental).
	task.spawn(function()
		while true do
			task.wait(0.25)
			local killHeight = mapService:GetKillHeight()
			for player, life in lives do
				local root = player.Character
					and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if life.Alive and root and root.Position.Y < killHeight then
					self:Kill(player)
				end
			end
		end
	end)
end

function HealthService.IsAlive(_self: typeof(HealthService), player: Player): boolean
	local life = lives[player]
	return life ~= nil and life.Alive
end

function HealthService.GetHealth(_self: typeof(HealthService), player: Player): number
	local life = lives[player]
	return if life and life.Alive then life.Health else 0
end

function HealthService.ApplyDamage(
	_self: typeof(HealthService),
	player: Player,
	amount: number,
	cause: Cause
): HealthRules.DamageResult
	local life = lives[player]
	if life == nil or not life.Alive then
		return { Health = 0, Dealt = 0, Died = false }
	end
	local result = HealthRules.ApplyDamage(life.Health, amount)
	life.Health = result.Health
	if result.Died then
		life.PendingCause = cause
		life.Alive = false
	end
	life.Humanoid.Health = result.Health
	return result
end

function HealthService.Heal(_self: typeof(HealthService), player: Player, amount: number): number
	local life = lives[player]
	if life == nil or not life.Alive then
		return 0
	end
	life.Health = HealthRules.Heal(life.Health, amount, MAX)
	life.Humanoid.Health = life.Health
	return life.Health
end

function HealthService.Kill(_self: typeof(HealthService), player: Player)
	local life = lives[player]
	if life == nil or not life.Alive then
		return
	end
	life.Alive = false
	life.Health = 0
	life.Humanoid.Health = 0
end

return HealthService
