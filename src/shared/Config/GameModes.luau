--!strict
--[[
	Game mode configuration (spec §5, §10).
	Only modes with Implemented = true can be started by MatchService. The remaining entries are
	the authoritative balance values for later phases and are validated by tests now so that the
	numbers in the specification are captured in exactly one place.
]]

export type ModeConfig = {
	Id: string,
	DisplayName: string,
	Implemented: boolean,
	MinPlayers: number,
	MaxPlayers: number,
	DurationSeconds: number?,
	RespawnDelaySeconds: number?,
	SpawnProtectionSeconds: number,
	ScoreLimit: number?,
	RoundsToWin: number?,
	IntermissionSeconds: number,
	AwardsProgression: boolean,
}

local GameModes: { [string]: ModeConfig } = {
	FreeForAll = {
		Id = "FreeForAll",
		DisplayName = "Free-for-All",
		Implemented = true,
		MinPlayers = 1,
		MaxPlayers = 20,
		DurationSeconds = 15 * 60,
		RespawnDelaySeconds = 3,
		SpawnProtectionSeconds = 5,
		ScoreLimit = nil,
		IntermissionSeconds = 20,
		AwardsProgression = true,
	},
	TeamDeathmatch = {
		Id = "TeamDeathmatch",
		DisplayName = "Team Deathmatch",
		Implemented = false,
		MinPlayers = 10,
		MaxPlayers = 16,
		DurationSeconds = 10 * 60,
		RespawnDelaySeconds = 5,
		SpawnProtectionSeconds = 5,
		ScoreLimit = 50,
		IntermissionSeconds = 20,
		AwardsProgression = true,
	},
	CasualDuel1v1 = {
		Id = "CasualDuel1v1",
		DisplayName = "Casual Duel 1v1",
		Implemented = false,
		MinPlayers = 2,
		MaxPlayers = 2,
		SpawnProtectionSeconds = 5,
		RoundsToWin = 3, -- best of five
		IntermissionSeconds = 10,
		AwardsProgression = true,
	},
	CasualDuelTeam = {
		Id = "CasualDuelTeam",
		DisplayName = "Casual Team Duel",
		Implemented = false,
		MinPlayers = 4,
		MaxPlayers = 8,
		SpawnProtectionSeconds = 5,
		RoundsToWin = 4, -- best of seven
		IntermissionSeconds = 10,
		AwardsProgression = true,
	},
	RankedDuel = {
		Id = "RankedDuel",
		DisplayName = "Ranked Duel",
		Implemented = false,
		MinPlayers = 2,
		MaxPlayers = 4,
		SpawnProtectionSeconds = 0,
		RoundsToWin = 5, -- best of nine
		IntermissionSeconds = 10,
		AwardsProgression = true,
	},
	Private = {
		Id = "Private",
		DisplayName = "Private Match",
		Implemented = false,
		MinPlayers = 1,
		MaxPlayers = 16,
		SpawnProtectionSeconds = 5,
		IntermissionSeconds = 20,
		-- Private matches never award coins, XP, ratings or challenge progress (spec §5).
		AwardsProgression = false,
	},
}

return table.freeze(GameModes)
