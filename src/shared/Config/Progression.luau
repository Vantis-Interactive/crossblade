--!strict
-- Player level progression (spec §15). Curve and level rewards are PROPOSED (D-022).
local Progression = {
	MaxLevel = 100, -- prestige threshold (prestige itself is Phase 7)
	-- XP required to go from level L to L+1 = BaseXP + GrowthPerLevel * (L - 1).
	BaseXP = 1000,
	GrowthPerLevel = 100,
	LevelRewards = {
		CoinsPerLevel = 100,
		MilestoneEvery = 10,
		MilestoneBonusCoins = 400,
	},
}

return table.freeze(Progression)
