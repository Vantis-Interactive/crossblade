--!strict
--[[
	Match flow for every implemented mode (spec §5, §10, §17). The mode comes from Shared/PlaceConfig;
	its Kind selects the flow and all timings/limits come from Config.GameModes.

	Phases:
	  Lobby        hub: always; weapons usable on dummies; players can never damage each other
	  Waiting      not enough players to start (players can move; combat disabled)
	  Countdown    enough players; match starts when the countdown ends
	  Active       combat allowed for participants (in duels: only those alive this round)
	  RoundEnd     duel only: short pause between rounds
	  Intermission results + map vote; combat disabled; next match after the timer

	Decisions are delegated to pure, tested modules: Domain/MatchRules (scores, streaks, ranking),
	Domain/Teams (assignment, Team Deathmatch outcome), Domain/DuelRounds (rounds, forfeits,
	time limit), Domain/MapVote (options, tally, winner).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Logger = require(ReplicatedStorage.Shared.Util.Logger)
local PlaceConfig = require(ReplicatedStorage.Shared.PlaceConfig)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local DuelRounds = require(script.Parent.Parent.Domain.DuelRounds)
local MapVote = require(script.Parent.Parent.Domain.MapVote)
local MatchRules = require(script.Parent.Parent.Domain.MatchRules)
local Teams = require(script.Parent.Parent.Domain.Teams)

local log = Logger.new("Match")

type Phase = "Lobby" | "Waiting" | "Countdown" | "Active" | "RoundEnd" | "Intermission"

export type MatchResult = {
	ModeId: string,
	Kind: string,
	MatchId: number,
	Ranked: { MatchRules.Entry },
	WinnerTeam: string?,
	Teams: { [number]: string },
}

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
	ModeId = PlaceConfig.Mode,
	-- (event, killerStreak, matchId, deathSequence) after an elimination is scored in an active match.
	EliminationScored = Signal.new() :: Signal.Signal<any, number, number, number>,
	-- (result) when a match ends.
	MatchFinished = Signal.new() :: Signal.Signal<MatchResult>,
}

local mode = Config.GameModes[MatchService.ModeId]
local kind = mode and mode.Kind
local teamSize = PlaceConfig.TeamSize or (mode and mode.TeamSize) or 1
local teamMode = kind == "TeamDeathmatch" or kind == "Duel"

local phase: Phase = if kind == "Lobby" then "Lobby" else "Waiting"
local matchId = 0
local endsAt = 0
local roundEndsAt = 0
local entries: { [number]: MatchRules.Entry } = {}
local teams: { [number]: Teams.TeamId } = {}
local teamScores = { A = 0, B = 0 }
local duel: DuelRounds.State? = nil
local vote: MapVote.Vote? = nil
local voteDirty = false
local lastResults: { any } = {}
local lastWinnerTeam: string? = nil
local joinOrder: { [number]: number } = {}
local joinCounter = 0
local deathSequence = 0
local scoreboardDirty = false
local pendingRespawn: { [Player]: boolean } = {}

local net: any
local playerData: any
local damage: any
local spawns: any
local health: any
local mapService: any
local weapons: any

local function loadedPlayers(): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		if playerData:GetProfile(player) then
			table.insert(list, player)
		end
	end
	table.sort(list, function(a, b)
		return (joinOrder[a.UserId] or math.huge) < (joinOrder[b.UserId] or math.huge)
	end)
	return list
end

local function requiredPlayers(): number
	return if kind == "Duel" then teamSize * 2 else mode.MinPlayers
end

local function setTeam(player: Player, team: Teams.TeamId?)
	teams[player.UserId] = team
	player:SetAttribute("Team", team)
end

local function clearTeams()
	for _, player in Players:GetPlayers() do
		player:SetAttribute("Team", nil)
	end
	table.clear(teams)
end

local function isEnemy(a: Player, b: Player): boolean
	if a == b or kind == "Lobby" then
		return false
	end
	if not teamMode then
		return true
	end
	local ta, tb = teams[a.UserId], teams[b.UserId]
	return ta ~= nil and tb ~= nil and ta ~= tb
end

local function entryFor(player: Player): MatchRules.Entry
	local entry = entries[player.UserId]
	if entry == nil then
		entry = MatchRules.NewEntry(player.UserId, player.DisplayName, joinOrder[player.UserId] or 0)
		entries[player.UserId] = entry
		scoreboardDirty = true
	end
	return entry
end

local function spawnPlayer(player: Player)
	spawns:Spawn(player, mode.SpawnProtectionSeconds, {
		Team = teams[player.UserId],
		IsEnemy = function(other: Player)
			return isEnemy(player, other)
		end,
	})
end

local function spawnLater(player: Player, delaySeconds: number)
	pendingRespawn[player] = true
	local forMatch = matchId
	task.delay(delaySeconds, function()
		pendingRespawn[player] = nil
		if matchId == forMatch and player.Parent == Players then
			spawnPlayer(player)
		end
	end)
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
			Team = teams[entry.UserId],
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

local function voteState(): { [string]: any }?
	if vote == nil then
		return nil
	end
	local options = {}
	local tally = MapVote.Tally(vote)
	for _, id in vote.Options do
		local info = mapService:Info(id)
		table.insert(options, { Id = id, DisplayName = info and info.DisplayName or id, Votes = tally[id] })
	end
	return { Options = options, EndsAt = endsAt }
end

local function matchState(): { [string]: any }
	return {
		Mode = mode.Id,
		ModeName = mode.DisplayName,
		Kind = kind,
		Phase = phase,
		MatchId = matchId,
		EndsAt = if phase == "Active" and kind == "Duel" then roundEndsAt else endsAt,
		MapName = mapService:GetDisplayName(),
		MapId = mapService:CurrentId(),
		TeamScores = if teamMode then teamScores else nil,
		ScoreLimit = mode.ScoreLimit,
		Duel = if duel then { Round = duel.Round, Wins = duel.Wins, RoundsToWin = duel.RoundsToWin } else nil,
		TeamSize = if kind == "Duel" then teamSize else nil,
		RespawnEnabled = mode.RespawnDelaySeconds ~= nil,
		PlayersNeeded = requiredPlayers(),
		PlayerCount = #loadedPlayers(),
		Results = if phase == "Intermission" then lastResults else nil,
		WinnerTeam = if phase == "Intermission" then lastWinnerTeam else nil,
		Vote = voteState(),
	}
end

local function broadcast()
	net.FireAll("MatchState", matchState())
end

local function announce(payload: { [string]: any })
	net.FireAll("Announcement", payload)
end

local function addStats(player: Player, mutate: (stats: { [string]: number }) -> ())
	if mode.AwardsProgression then
		playerData:Update(player, function(data)
			mutate(data.Stats)
		end)
	end
end

local function finishMatch(winnerTeam: Teams.TeamId?)
	if phase == "Intermission" then
		return
	end
	phase = "Intermission"
	lastWinnerTeam = winnerTeam
	local list = {}
	for _, entry in entries do
		table.insert(list, entry)
	end
	local ranked = MatchRules.Rank(list)
	lastResults = {}
	for rank, entry in ranked do
		if rank <= 16 then
			table.insert(lastResults, {
				Rank = rank,
				Name = entry.Name,
				Team = teams[entry.UserId],
				Eliminations = entry.Eliminations,
				Deaths = entry.Deaths,
				Assists = entry.Assists,
			})
		end
		local player = Players:GetPlayerByUserId(entry.UserId)
		if player then
			local won = if teamMode
				then winnerTeam ~= nil and teams[entry.UserId] == winnerTeam
				else rank == 1 and entry.Eliminations > 0
			local drew = teamMode and winnerTeam == nil
			addStats(player, function(stats)
				stats.MatchesPlayed += 1
				if won then
					stats.Wins += 1
				elseif not drew then
					stats.Losses += 1
				end
			end)
		end
	end
	if mode.MapVote then
		local eligible = mapService:MapsForMode(mode.Id)
		vote = MapVote.new(MapVote.Options(eligible, mapService:CurrentId(), 3, math.random))
	end
	endsAt = net.Now() + mode.IntermissionSeconds
	MatchService.MatchFinished:Fire({
		ModeId = mode.Id,
		Kind = kind,
		MatchId = matchId,
		Ranked = ranked,
		WinnerTeam = winnerTeam,
		Teams = table.clone(teams),
	})
	if winnerTeam then
		announce({ Kind = "MatchWinner", Team = winnerTeam, TeamName = Teams.Names[winnerTeam] })
	end
	log:Info("match finished", { match = matchId, mode = mode.Id, winner = winnerTeam })
	broadcast()
end

local function startRound()
	local state = duel :: DuelRounds.State
	DuelRounds.StartRound(state)
	phase = "Active"
	roundEndsAt = net.Now() + (mode.RoundSeconds or 120)
	for userId in state.Roster do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			task.spawn(spawnPlayer, player)
		end
	end
	announce({ Kind = "Round", Round = state.Round, Wins = state.Wins })
	broadcast()
end

local function handleRound(outcome: DuelRounds.Outcome)
	if outcome.MatchWinner then
		finishMatch(outcome.MatchWinner)
	elseif outcome.RoundWinner or outcome.Draw then
		phase = "RoundEnd"
		endsAt = net.Now() + (mode.RoundIntermissionSeconds or 4)
		announce({
			Kind = "RoundResult",
			Team = outcome.RoundWinner,
			TeamName = outcome.RoundWinner and Teams.Names[outcome.RoundWinner],
			Draw = outcome.Draw,
			Wins = (duel :: DuelRounds.State).Wins,
		})
		broadcast()
	end
end

local function startMatch()
	matchId += 1
	table.clear(entries)
	teamScores = { A = 0, B = 0 }
	duel = nil
	lastResults = {}
	lastWinnerTeam = nil
	scoreboardDirty = true
	local players = loadedPlayers()
	local ids = {}
	for _, player in players do
		table.insert(ids, player.UserId)
	end
	if teamMode then
		clearTeams()
		local assignment, overflow = Teams.Balance(ids, if kind == "Duel" then teamSize else nil)
		for userId, team in assignment do
			local player = Players:GetPlayerByUserId(userId)
			if player then
				setTeam(player, team)
				entryFor(player)
			end
		end
		for _, userId in overflow do
			local player = Players:GetPlayerByUserId(userId)
			if player then
				spawns:Despawn(player) -- duel spectators until a slot opens next match
			end
		end
		if kind == "Duel" then
			duel = DuelRounds.new(mode.RoundsToWin :: number, assignment)
			log:Info("duel started", { match = matchId, size = teamSize })
			startRound()
			return
		end
	else
		for _, player in players do
			entryFor(player)
		end
	end
	phase = "Active"
	endsAt = net.Now() + (mode.DurationSeconds :: number)
	for _, player in players do
		task.spawn(spawnPlayer, player)
	end
	log:Info("match started", { match = matchId, mode = mode.Id, players = #players })
	broadcast()
end

local function endIntermission()
	if vote then
		local winner = MapVote.Winner(vote, math.random)
		vote = nil
		if winner and winner ~= mapService:CurrentId() then
			mapService:Load(winner)
			-- The old map is gone: put everyone on the new one rather than letting them fall.
			for _, player in loadedPlayers() do
				if player.Character then
					task.spawn(spawnPlayer, player)
				end
			end
		end
	end
	clearTeams()
	table.clear(entries)
	scoreboardDirty = true
	phase = "Waiting"
	broadcast()
end

local function tick()
	local now = net.Now()
	if phase == "Lobby" then
		return
	elseif phase == "Waiting" then
		if #loadedPlayers() >= requiredPlayers() then
			if mode.CountdownSeconds > 0 then
				phase = "Countdown"
				endsAt = now + mode.CountdownSeconds
				broadcast()
			else
				startMatch()
			end
		end
	elseif phase == "Countdown" then
		if #loadedPlayers() < requiredPlayers() then
			phase = "Waiting"
			broadcast()
		elseif now >= endsAt then
			startMatch()
		end
	elseif phase == "Active" then
		if kind == "FreeForAll" then
			if now >= endsAt then
				finishMatch(nil)
			end
		elseif kind == "TeamDeathmatch" then
			local winner, over = Teams.DeathmatchWinner(teamScores, mode.ScoreLimit, now >= endsAt)
			if over then
				finishMatch(winner)
			end
		elseif kind == "Duel" and duel and now >= roundEndsAt then
			handleRound(DuelRounds.TimeUp(duel, function(userId)
				local player = Players:GetPlayerByUserId(userId)
				return if player then health:GetHealth(player) else 0
			end))
		end
	elseif phase == "RoundEnd" then
		if now >= endsAt then
			startRound()
		end
	elseif phase == "Intermission" then
		if now >= endsAt then
			endIntermission()
		end
	end
end

local function onEliminated(event: any)
	local victim: Player = event.Victim
	local killer: Player? = event.Killer
	if kind == "Lobby" then
		spawnLater(victim, mode.RespawnDelaySeconds or 2)
		return
	end
	local victimEntry = entries[victim.UserId]
	local scoring = phase == "Active" and victimEntry ~= nil
	if not scoring then
		-- Warm-up, intermission or a non-participant: just give them a body again (not in duels).
		if mode.RespawnDelaySeconds or phase ~= "Active" then
			spawnLater(victim, mode.RespawnDelaySeconds or 3)
		end
		return
	end
	if killer and not isEnemy(killer, victim) then
		killer = nil -- defensive: friendly damage is impossible, but never credit it
	end
	local killerEntry = killer and entries[killer.UserId]
	local assistEntries, assistIds = {}, {}
	for _, assister in event.Assists do
		local entry = entries[assister.UserId]
		if entry and isEnemy(assister, victim) then
			table.insert(assistEntries, entry)
			table.insert(assistIds, assister.UserId)
		end
	end
	local streak = MatchRules.RecordElimination(
		killerEntry,
		victimEntry :: MatchRules.Entry,
		assistEntries,
		Config.Combat.Killstreaks.AnnounceAt
	)
	scoreboardDirty = true
	if kind == "TeamDeathmatch" and killer and teams[killer.UserId] then
		local team = teams[killer.UserId]
		teamScores[team] += 1
	end
	if event.Position then
		spawns:RecordDeath(event.Position)
	end

	local isKnife = event.Kind == "Knife" or event.Kind == "ThrownKnife"
	net.FireAll("KillFeed", {
		KillerUserId = killer and killer.UserId,
		KillerName = killer and killer.DisplayName,
		KillerTeam = killer and teams[killer.UserId],
		VictimUserId = victim.UserId,
		VictimName = victim.DisplayName,
		VictimTeam = teams[victim.UserId],
		WeaponId = event.WeaponId,
		Kind = if killer then event.Kind else "Environment",
		Headshot = event.Headshot,
		AssistUserIds = assistIds,
	})
	net.Fire("Eliminated", victim, {
		KillerUserId = killer and killer.UserId,
		KillerName = killer and killer.DisplayName,
		WeaponId = event.WeaponId,
		KillerHealth = if killer then math.ceil(health:GetHealth(killer)) else nil,
		KillerLevel = killer and killer:GetAttribute("Level") or nil,
		RespawnAt = if mode.RespawnDelaySeconds then net.Now() + mode.RespawnDelaySeconds else nil,
		Spectating = mode.RespawnDelaySeconds == nil,
	})
	if streak and killer then
		announce({ Kind = "Killstreak", UserId = killer.UserId, Name = killer.DisplayName, Streak = streak })
	end
	deathSequence += 1
	local rewardEvent = table.clone(event)
	rewardEvent.Killer = killer
	MatchService.EliminationScored:Fire(
		rewardEvent,
		if killerEntry then killerEntry.Streak else 0,
		matchId,
		deathSequence
	)

	addStats(victim, function(stats)
		stats.Deaths += 1
	end)
	for _, assistId in assistIds do
		local assister = Players:GetPlayerByUserId(assistId)
		if assister then
			addStats(assister, function(stats)
				stats.Assists += 1
			end)
		end
	end
	if killer and killerEntry then
		addStats(killer, function(stats)
			stats.Eliminations += 1
			if isKnife then
				stats.KnifeEliminations += 1
			end
			stats.HighestKillstreak = math.max(stats.HighestKillstreak, killerEntry.Streak)
		end)
	end

	if mode.RespawnDelaySeconds then
		spawnLater(victim, mode.RespawnDelaySeconds)
	elseif duel then
		handleRound(DuelRounds.Eliminate(duel, victim.UserId))
	end
	if kind == "TeamDeathmatch" then
		broadcast() -- team score changed
	end
end

function MatchService.Mode(_self: typeof(MatchService))
	return mode
end

function MatchService.TeamOf(_self: typeof(MatchService), player: Player): string?
	return teams[player.UserId]
end

function MatchService.TracksStats(_self: typeof(MatchService)): boolean
	return mode.AwardsProgression
end

-- May this player use weapons right now?
function MatchService.IsCombatAllowed(_self: typeof(MatchService), player: Player): boolean
	if kind == "Lobby" then
		return true -- weapons work on training dummies; player damage is refused by CanDamage
	end
	if phase ~= "Active" or entries[player.UserId] == nil then
		return false
	end
	if kind == "Duel" then
		return duel ~= nil and DuelRounds.IsAlive(duel, player.UserId)
	end
	return true
end

-- May `attacker` damage `victim` right now? (lobby: never; team modes: opponents only)
function MatchService.CanDamage(self: typeof(MatchService), attacker: Player, victim: Player): boolean
	if kind == "Lobby" then
		return false
	end
	return health:IsAlive(victim)
		and self:IsCombatAllowed(attacker)
		and self:IsCombatAllowed(victim)
		and isEnemy(attacker, victim)
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

	net.OnEvent("VoteMap", function(player: Player, payload: any)
		if vote and phase == "Intermission" and playerData:GetProfile(player) then
			if MapVote.Cast(vote, player.UserId, payload.MapId) then
				voteDirty = true
			end
		end
	end)

	-- Connected in Init (not Start) so no profile load or elimination can fire before we listen.
	damage.Eliminated:Connect(onEliminated)

	playerData.ProfileLoaded:Connect(function(player: Player)
		joinCounter += 1
		joinOrder[player.UserId] = joinCounter
		net.Fire("MatchState", player, matchState())
		if kind == "Duel" and (phase == "Active" or phase == "RoundEnd") then
			return -- spectate until the next match
		end
		if phase == "Active" then
			if kind == "TeamDeathmatch" then
				local team = Teams.Pick(teams, nil)
				if team then
					setTeam(player, team)
				end
			end
			entryFor(player)
		end
		task.spawn(spawnPlayer, player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		pendingRespawn[player] = nil
		joinOrder[player.UserId] = nil
		if vote then
			MapVote.Remove(vote, player.UserId)
			voteDirty = true
		end
		if entries[player.UserId] then
			entries[player.UserId] = nil
			scoreboardDirty = true
		end
		teams[player.UserId] = nil
		if duel and phase ~= "Intermission" then
			handleRound(DuelRounds.RemovePlayer(duel, player.UserId))
		end
		if phase == "Waiting" or phase == "Countdown" then
			broadcast()
		end
	end)
end

function MatchService.Start(_self: typeof(MatchService))
	-- Batched broadcasts (at most twice per second) bound network traffic.
	task.spawn(function()
		while true do
			task.wait(0.5)
			if scoreboardDirty then
				scoreboardDirty = false
				net.FireAll("Scoreboard", { Rows = scoreboardRows() })
			end
			if voteDirty then
				voteDirty = false
				local state = voteState()
				if state then
					net.FireAll("MapVote", state)
				end
			end
		end
	end)

	-- Watchdog: a loaded player with no character and no scheduled respawn is respawned, except duel
	-- spectators, who wait for the next match.
	task.spawn(function()
		while true do
			task.wait(2)
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local stranded = character == nil
					or character.Parent == nil
					or character:FindFirstChildOfClass("Humanoid") == nil
				local spectator = kind == "Duel" and (phase == "Active" or phase == "RoundEnd")
				if
					stranded
					and not spectator
					and not pendingRespawn[player]
					and playerData:GetProfile(player)
				then
					log:Warn("respawning stranded player", { player = player.UserId })
					task.spawn(spawnPlayer, player)
				end
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.25)
			local ok, err = pcall(tick)
			if not ok then
				log:Error("match tick failed", { error = err })
			end
		end
	end)
	log:Info("match service ready", { mode = mode.Id, kind = kind })
end

return MatchService
