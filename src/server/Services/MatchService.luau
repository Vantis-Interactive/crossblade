--!strict
--[[
	Free-for-All match flow (spec §5, §10). Phase 2 implements FreeForAll only; MatchService refuses to
	run any mode whose config has Implemented = false.

	Round: Active for DurationSeconds -> Intermission (results, combat disabled) -> new round.
	Eliminations: update scoreboard, kill feed, victim's elimination screen (killer, weapon, killer HP,
	killer level), killstreak announcements, persistent statistics, then respawn after the mode's delay.

	Rewards (coins/XP) are Phase 3 (EconomyService/ProgressionService) and intentionally absent here.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Logger = require(ReplicatedStorage.Shared.Util.Logger)
local MatchRules = require(script.Parent.Parent.Domain.MatchRules)

local log = Logger.new("Match")

type Phase = "Active" | "Intermission"

local MatchService = {
	Name = "MatchService",
	Dependencies = {
		"Net",
		"PlayerDataService",
		"DamageService",
		"SpawnService",
		"HealthService",
		"MapService",
		"WeaponService",
	},
	ModeId = "FreeForAll",
}

local mode = Config.GameModes[MatchService.ModeId]
local phase: Phase = "Intermission"
local roundId = 0
local endsAt = 0
local entries: { [number]: MatchRules.Entry } = {}
local joinCounter = 0
local scoreboardDirty = false
local lastResults: { any } = {}

local net: any
local playerData: any
local damage: any
local spawns: any
local health: any
local mapService: any
local weapons: any

local function entryFor(player: Player): MatchRules.Entry
	local entry = entries[player.UserId]
	if entry == nil then
		joinCounter += 1
		entry = MatchRules.NewEntry(player.UserId, player.DisplayName, joinCounter)
		entries[player.UserId] = entry
		scoreboardDirty = true
	end
	return entry
end

local function matchState(): { [string]: any }
	return {
		Mode = mode.Id,
		ModeName = mode.DisplayName,
		Phase = phase,
		RoundId = roundId,
		EndsAt = endsAt,
		MapName = mapService:GetDisplayName(),
		Results = if phase == "Intermission" then lastResults else nil,
	}
end

local function scoreboardRows(): { any }
	local list = {}
	for _, entry in entries do
		table.insert(list, entry)
	end
	local rows = {}
	for rank, entry in MatchRules.Rank(list) do
		local player = Players:GetPlayerByUserId(entry.UserId)
		table.insert(rows, {
			Rank = rank,
			UserId = entry.UserId,
			Name = entry.Name,
			Eliminations = entry.Eliminations,
			Deaths = entry.Deaths,
			Assists = entry.Assists,
			Streak = entry.Streak,
			Level = player and player:GetAttribute("Level") or 1,
			Ping = player and math.floor(player:GetNetworkPing() * 1000) or 0,
		})
	end
	return rows
end

local pendingRespawn: { [Player]: boolean } = {}

local function spawnLater(player: Player, delaySeconds: number, forRound: number)
	pendingRespawn[player] = true
	task.delay(delaySeconds, function()
		pendingRespawn[player] = nil
		-- Combat is gated separately (IsCombatAllowed), so respawning during intermission is safe.
		if roundId == forRound and player.Parent == Players then
			spawns:Spawn(player, mode.SpawnProtectionSeconds)
		end
	end)
end

local function onEliminated(event: any)
	local victim: Player = event.Victim
	local killer: Player? = event.Killer
	local victimEntry = entries[victim.UserId]
	if victimEntry == nil then
		-- Not in the scoring round (joined during intermission): just give them a body again.
		spawnLater(victim, mode.RespawnDelaySeconds or 0, roundId)
		return
	end
	local killerEntry = killer and entries[killer.UserId]
	local assistEntries = {}
	local assistIds = {}
	for _, assister in event.Assists do
		local entry = entries[assister.UserId]
		if entry then
			table.insert(assistEntries, entry)
			table.insert(assistIds, assister.UserId)
		end
	end
	local streak = MatchRules.RecordElimination(
		killerEntry,
		victimEntry,
		assistEntries,
		Config.Combat.Killstreaks.AnnounceAt
	)
	scoreboardDirty = true

	if event.Position then
		spawns:RecordDeath(event.Position)
	end

	local isKnife = event.Kind == "Knife" or event.Kind == "ThrownKnife"
	net.FireAll("KillFeed", {
		KillerUserId = killer and killer.UserId,
		KillerName = killer and killer.DisplayName,
		VictimUserId = victim.UserId,
		VictimName = victim.DisplayName,
		WeaponId = event.WeaponId,
		Kind = event.Kind,
		Headshot = event.Headshot,
		AssistUserIds = assistIds,
	})
	net.Fire("Eliminated", victim, {
		KillerUserId = killer and killer.UserId,
		KillerName = killer and killer.DisplayName,
		WeaponId = event.WeaponId,
		KillerHealth = if killer then math.ceil(health:GetHealth(killer)) else nil,
		KillerLevel = killer and killer:GetAttribute("Level") or nil,
		RespawnAt = net.Now() + (mode.RespawnDelaySeconds or 0),
	})
	if streak and killer then
		net.FireAll(
			"Announcement",
			{ Kind = "Killstreak", UserId = killer.UserId, Name = killer.DisplayName, Streak = streak }
		)
	end

	playerData:Update(victim, function(data)
		data.Stats.Deaths += 1
	end)
	for _, assister in event.Assists do
		playerData:Update(assister, function(data)
			data.Stats.Assists += 1
		end)
	end
	if killer and killerEntry then
		playerData:Update(killer, function(data)
			data.Stats.Eliminations += 1
			if isKnife then
				data.Stats.KnifeEliminations += 1
			end
			data.Stats.HighestKillstreak = math.max(data.Stats.HighestKillstreak, killerEntry.Streak)
		end)
	end

	spawnLater(victim, mode.RespawnDelaySeconds or 0, roundId)
end

local function finishRound()
	phase = "Intermission"
	local list = {}
	for _, entry in entries do
		table.insert(list, entry)
	end
	local ranked = MatchRules.Rank(list)
	lastResults = {}
	for rank, entry in ranked do
		if rank <= 10 then
			table.insert(lastResults, {
				Rank = rank,
				Name = entry.Name,
				Eliminations = entry.Eliminations,
				Deaths = entry.Deaths,
				Assists = entry.Assists,
			})
		end
		local player = Players:GetPlayerByUserId(entry.UserId)
		if player then
			playerData:Update(player, function(data)
				data.Stats.MatchesPlayed += 1
				if rank == 1 and entry.Eliminations > 0 then
					data.Stats.Wins += 1
				else
					data.Stats.Losses += 1
				end
			end)
		end
	end
	endsAt = net.Now() + mode.IntermissionSeconds
	log:Info("round finished", { round = roundId, players = #ranked })
	net.FireAll("MatchState", matchState())
end

local function beginRound()
	roundId += 1
	table.clear(entries)
	joinCounter = 0
	phase = "Active"
	endsAt = net.Now() + (mode.DurationSeconds :: number)
	for _, player in Players:GetPlayers() do
		if playerData:GetProfile(player) then
			entryFor(player)
			task.spawn(function()
				spawns:Spawn(player, mode.SpawnProtectionSeconds)
			end)
		end
	end
	log:Info("round started", { round = roundId, mode = mode.Id })
	net.FireAll("MatchState", matchState())
end

function MatchService.IsCombatAllowed(_self: typeof(MatchService), player: Player): boolean
	return phase == "Active" and entries[player.UserId] ~= nil
end

function MatchService.Init(_self: typeof(MatchService), registry: { [string]: any })
	assert(mode and mode.Implemented, `mode {MatchService.ModeId} is not implemented`)
	net = registry.Net
	playerData = registry.PlayerDataService
	damage = registry.DamageService
	spawns = registry.SpawnService
	health = registry.HealthService
	mapService = registry.MapService
	weapons = registry.WeaponService

	net.OnInvoke("GetSnapshot", function(player: Player)
		local profile = playerData:GetProfile(player)
		if profile == nil then
			return nil -- not loaded yet; client retries
		end
		return {
			Settings = profile.Data.Settings,
			Level = profile.Data.Progression.Level,
			Loadout = weapons:Snapshot(player, net.Now()),
			Match = matchState(),
			Scoreboard = scoreboardRows(),
		}
	end)

	-- Connected in Init (not Start) so no profile load or elimination can fire before we listen.
	damage.Eliminated:Connect(onEliminated)

	playerData.ProfileLoaded:Connect(function(player: Player)
		net.Fire("MatchState", player, matchState())
		if phase == "Active" then
			entryFor(player)
		end
		task.spawn(function()
			spawns:Spawn(player, mode.SpawnProtectionSeconds)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		pendingRespawn[player] = nil
		if entries[player.UserId] then
			entries[player.UserId] = nil
			scoreboardDirty = true
		end
	end)
end

function MatchService.Start(_self: typeof(MatchService))
	-- Scoreboard broadcasts are batched (at most twice per second) to bound network traffic.
	task.spawn(function()
		while true do
			task.wait(0.5)
			if scoreboardDirty then
				scoreboardDirty = false
				net.FireAll("Scoreboard", { Rows = scoreboardRows() })
			end
		end
	end)

	-- Watchdog: a loaded player with no living character and no scheduled respawn (for example a
	-- character removed by the engine without a counted death) is respawned rather than stranded.
	task.spawn(function()
		while true do
			task.wait(2)
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local stranded = character == nil or character.Parent == nil or humanoid == nil
				if stranded and not pendingRespawn[player] and playerData:GetProfile(player) then
					log:Warn("respawning stranded player", { player = player.UserId })
					task.spawn(function()
						spawns:Spawn(player, mode.SpawnProtectionSeconds)
					end)
				end
			end
		end
	end)

	task.spawn(function()
		beginRound()
		while true do
			task.wait(0.25)
			if net.Now() >= endsAt then
				if phase == "Active" then
					finishRound()
				else
					beginRound()
				end
			end
		end
	end)
end

return MatchService
