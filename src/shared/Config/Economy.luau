--!strict
--[[
	Economy configuration (spec §13, §14). Values marked SPEC come from the master directive.
	Values marked PROPOSED were not specified and are recorded in docs/DECISIONS.md (D-021..D-024);
	they are configuration, not code, and can be changed without touching gameplay logic.
]]

local Economy = {
	-- Coin rewards (SPEC).
	Rewards = {
		GunElimination = 25,
		KnifeElimination = 35, -- melee and thrown knife
		HeadshotEliminationBonus = 10,
		Assist = 10,
		Streak = { Every = 5, Coins = 50 }, -- awarded at streak 5, 10, 15, ...
		DuelVictory = 100,
		TeamDeathmatchVictory = 150,
		-- PROPOSED: Free-for-All first place is not specified; no coin bonus.
		FreeForAllFirstPlace = 0,
		-- PROPOSED (D-013): an environmental "finished off" kill pays the assist rate, not a full kill.
		FinishedElimination = 10,
	},

	-- XP rewards (PROPOSED: the specification defines XP sources but not amounts).
	Experience = {
		Elimination = 100,
		HeadshotBonus = 20,
		Assist = 40,
		FinishedElimination = 40,
		MatchCompleted = 150,
		FirstPlace = 250,
	},

	-- Duplicate crate compensation in coins (SPEC).
	DuplicateCompensation = {
		Common = 50,
		Uncommon = 100,
		Rare = 250,
		Epic = 500,
		Legendary = 1000,
		Mythical = 2500,
		Celestial = 5000,
	},

	-- Anti-farming (spec §13; limits PROPOSED).
	AntiFarming = {
		-- The same killer->victim pair earns rewards at most this many times per window.
		RepeatVictim = { MaxRewarded = 3, WindowSeconds = 300 },
		-- Rolling-hour caps on match-earned coins and XP (persisted, so server hopping does not reset them).
		HourlyCoinCap = 2000,
		HourlyXPCap = 20000,
		-- Rewards require at least this many players with loaded profiles in the server.
		MinPlayersForRewards = 2,
		-- Player-owned private servers never award progression (spec §5, "private-server farming").
		DisableInOwnedPrivateServers = true,
	},

	-- Crate validation (spec §14 "must not permit sustainable unlimited currency generation").
	-- A crate is only activated if the expected duplicate compensation for a player who already owns
	-- every item in its pool is below Price * (1 - MinimumSinkMargin).
	MinimumSinkMargin = 0,

	CrateHistoryLimit = 50,
}

return table.freeze(Economy)
