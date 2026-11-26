--!strict
--[[
	Spawning and spawn protection (spec §10).
	  - Spawn point chosen by Domain/SpawnSelector (opponent distance, recent deaths, reuse, sightlines).
	  - Spawn protection for the mode's configured duration; it ends immediately when the protected
	    player attacks (CombatService calls EndProtection). Protected players take no damage.
	  - Every life restores the starting loadout (WeaponService:ResetForLife).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Logger = require(ReplicatedStorage.Shared.Util.Logger)
local CombatQuery = require(script.Parent.Parent.Core.CombatQuery)
local SpawnSelector = require(script.Parent.Parent.Domain.SpawnSelector)

local log = Logger.new("Spawn")

local SpawnService = {
	Name = "SpawnService",
	Dependencies = { "Net", "MapService", "AntiCheatService", "WeaponService", "HealthService" },
}

local protectedUntil: { [Player]: number } = {}
local forceFields: { [Player]: ForceField } = {}
local recentDeaths: { SpawnSelector.Death } = {}
local lastUsed: { [string]: number } = {}
local spawning: { [Player]: boolean } = {}
local net: any
local mapService: any
local antiCheat: any
local weaponService: any
local healthService: any

function SpawnService.Init(_self: typeof(SpawnService), registry: { [string]: any })
	net = registry.Net
	mapService = registry.MapService
	antiCheat = registry.AntiCheatService
	weaponService = registry.WeaponService
	healthService = registry.HealthService
end

function SpawnService.Start(_self: typeof(SpawnService))
	Players.PlayerRemoving:Connect(function(player)
		protectedUntil[player] = nil
		forceFields[player] = nil
		spawning[player] = nil
	end)
end

function SpawnService.RecordDeath(_self: typeof(SpawnService), position: Vector3)
	local now = net.Now()
	table.insert(recentDeaths, { Position = position, Time = now })
	local window = Config.Spawning.RecentDeath.WindowSeconds
	while #recentDeaths > 0 and now - recentDeaths[1].Time > window do
		table.remove(recentDeaths, 1)
	end
end

function SpawnService.IsProtected(_self: typeof(SpawnService), player: Player): boolean
	local untilTime = protectedUntil[player]
	return untilTime ~= nil and net.Now() < untilTime
end

function SpawnService.EndProtection(_self: typeof(SpawnService), player: Player)
	protectedUntil[player] = nil
	local field = forceFields[player]
	if field then
		field:Destroy()
		forceFields[player] = nil
	end
end

local function choose(player: Player)
	local enemies = {}
	for _, other in Players:GetPlayers() do
		local root = other ~= player
			and other.Character
			and other.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and healthService:IsAlive(other) then
			table.insert(enemies, root.Position)
		end
	end
	local spawns = {}
	for _, spawn in mapService:GetSpawns() do
		table.insert(spawns, { Id = spawn.Id, Position = spawn.Position, CFrame = spawn.CFrame })
	end
	local headOffset = Vector3.new(0, Config.Player.Hitbox.HeadOffset + 3, 0)
	return SpawnSelector.Select({
		Spawns = spawns,
		Enemies = enemies,
		RecentDeaths = recentDeaths,
		LastUsed = lastUsed,
		Now = net.Now(),
		Weights = Config.Spawning,
		LineOfSight = function(from, to)
			return CombatQuery.LineOfSight(from + headOffset * 0.5, to + headOffset)
		end,
	}) :: any
end

-- Spawns (or respawns) the player. Yields until the character exists. Safe to call repeatedly.
function SpawnService.Spawn(self: typeof(SpawnService), player: Player, protectionSeconds: number)
	if spawning[player] or player.Parent ~= Players then
		return
	end
	spawning[player] = true
	local spawn = choose(player)
	local ok, err = pcall(function()
		player:LoadCharacter()
	end)
	spawning[player] = nil
	if not ok then
		log:Warn("LoadCharacter failed", { player = player.UserId, error = err })
		return
	end
	local character = player.Character
	local root = character and character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if character == nil or root == nil then
		return
	end
	if spawn then
		lastUsed[spawn.Id] = net.Now()
		-- Root sits ~3 studs above the floor for standard rigs; the spawn marker is on the floor.
		local target = spawn.CFrame + Vector3.new(0, 3.5, 0)
		character:PivotTo(target)
		antiCheat:NotifyTeleport(player, target.Position)
	end

	if protectionSeconds > 0 then
		protectedUntil[player] = net.Now() + protectionSeconds
		local field = Instance.new("ForceField")
		field.Visible = true
		field.Parent = character
		forceFields[player] = field
		task.delay(protectionSeconds, function()
			if forceFields[player] == field then
				self:EndProtection(player)
			end
		end)
	end
	weaponService:ResetForLife(player)
end

return SpawnService
