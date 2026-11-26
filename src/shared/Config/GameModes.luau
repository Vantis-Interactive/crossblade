--!strict
--[[
	Game mode configuration (spec §5, §10).
	Kind selects the match flow in MatchService:
	  Lobby          - hub: weapons usable on training dummies, no player damage, no scoring
	  FreeForAll     - everyone vs everyone, timed, continuous respawn
	  TeamDeathmatch - two teams, timed or first to ScoreLimit team eliminations, continuous respawn
	  Duel           - two teams of TeamSize, rounds, no respawn within a round (eliminated players
	                   spectate), first team to RoundsToWin round wins takes the match
	MinPlayers is the START threshold; MaxPlayers is capacity (also set in each place's Roblox
	server-size setting). Implemented = false modes cannot be started (Ranked is Phase 6, Private
	matches Phase 5).
]]

export type Kind = "Lobby" | "FreeForAll" | "TeamDeathmatch" | "Duel"

export type ModeConfig = {
	Id: string,
	DisplayName: string,
	Kind: Kind,
	Implemented: boolean,
	MinPlayers: number,
	MaxPlayers: number,
	TeamSize: number?, -- Duel default; a place may override via PlaceConfig.TeamSize
	DurationSeconds: number?,
	RespawnDelaySeconds: number?, -- nil: no respawn within a round
	SpawnProtectionSeconds: number,
	ScoreLimit: number?,
	RoundsToWin: number?,
	RoundSeconds: number?,
	RoundIntermissionSeconds: number?,
	CountdownSeconds: number,
	IntermissionSeconds: number,
	MapVote: boolean,
	AwardsProgression: boolean,
	VictoryReward: string?, -- key into Config.Economy.Rewards
}

local GameModes: { [string]: ModeConfig } = {
	Lobby = {
		Id = "Lobby",
		DisplayName = "Social Hub",
		Kind = "Lobby",
		Implemented = true,
		MinPlayers = 1,
		MaxPlayers = 40,
		RespawnDelaySeconds = 2,
		SpawnProtectionSeconds = 0,
		CountdownSeconds = 0,
		IntermissionSeconds = 0,
		MapVote = false,
		AwardsProgression = false,
	},
	FreeForAll = {
		Id = "FreeForAll",
		DisplayName = "Free-for-All",
		Kind = "FreeForAll",
		Implemented = true,
		MinPlayers = 1,
		MaxPlayers = 20,
		DurationSeconds = 15 * 60,
		RespawnDelaySeconds = 3,
		SpawnProtectionSeconds = 5,
		CountdownSeconds = 0,
		IntermissionSeconds = 20,
		MapVote = true,
		AwardsProgression = true,
	},
	TeamDeathmatch = {
		Id = "TeamDeathmatch",
		DisplayName = "Team Deathmatch",
		Kind = "TeamDeathmatch",
		Implemented = true,
		MinPlayers = 2,
		MaxPlayers = 16, -- 5v5 and 8v8 places set their own server size (10 / 16)
		DurationSeconds = 10 * 60,
		RespawnDelaySeconds = 5,
		SpawnProtectionSeconds = 5,
		ScoreLimit = 50,
		CountdownSeconds = 10,
		IntermissionSeconds = 20,
		MapVote = true,
		AwardsProgression = true,
		VictoryReward = "TeamDeathmatchVictory",
	},
	CasualDuel1v1 = {
		Id = "CasualDuel1v1",
		DisplayName = "Casual Duel 1v1",
		Kind = "Duel",
		Implemented = true,
		MinPlayers = 2,
		MaxPlayers = 2,
		TeamSize = 1,
		SpawnProtectionSeconds = 5,
		RoundsToWin = 3, -- best of five
		RoundSeconds = 120,
		RoundIntermissionSeconds = 4,
		CountdownSeconds = 5,
		IntermissionSeconds = 15,
		MapVote = true,
		AwardsProgression = true,
		VictoryReward = "DuelVictory",
	},
	CasualDuelTeam = {
		Id = "CasualDuelTeam",
		DisplayName = "Casual Team Duel",
		Kind = "Duel",
		Implemented = true,
		MinPlayers = 4,
		MaxPlayers = 8,
		TeamSize = 2, -- 2v2 default; 3v3 / 4v4 places set PlaceConfig.TeamSize
		SpawnProtectionSeconds = 5,
		RoundsToWin = 4, -- best of seven
		RoundSeconds = 150,
		RoundIntermissionSeconds = 4,
		CountdownSeconds = 5,
		IntermissionSeconds = 15,
		MapVote = true,
		AwardsProgression = true,
		VictoryReward = "DuelVictory",
	},
	RankedDuel = {
		Id = "RankedDuel",
		DisplayName = "Ranked Duel",
		Kind = "Duel",
		Implemented = false, -- Phase 6
		MinPlayers = 2,
		MaxPlayers = 4,
		TeamSize = 1,
		SpawnProtectionSeconds = 0,
		RoundsToWin = 5, -- best of nine
		RoundSeconds = 120,
		RoundIntermissionSeconds = 4,
		CountdownSeconds = 5,
		IntermissionSeconds = 10,
		MapVote = false,
		AwardsProgression = true,
	},
	Private = {
		Id = "Private",
		DisplayName = "Private Match",
		Kind = "FreeForAll",
		Implemented = false, -- Phase 5
		MinPlayers = 1,
		MaxPlayers = 16,
		RespawnDelaySeconds = 3,
		SpawnProtectionSeconds = 5,
		CountdownSeconds = 0,
		IntermissionSeconds = 20,
		MapVote = true,
		-- Private matches never award coins, XP, ratings or challenge progress (spec §5).
		AwardsProgression = false,
	},
}

for _, mode in GameModes do
	table.freeze(mode)
end

return table.freeze(GameModes)
