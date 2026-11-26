--!strict
-- Level/XP arithmetic (spec §15). Pure; configuration comes from Config.Progression.

local Config = require(script.Parent.Parent.Config)

local Leveling = {}

export type LevelInfo = { Level: number, IntoLevel: number, ForNext: number, AtMax: boolean }
export type ApplyResult = { LevelsGained: number, RewardCoins: number, Granted: number }

function Leveling.XPForNext(level: number): number
	local p = Config.Progression
	return p.BaseXP + p.GrowthPerLevel * (level - 1)
end

function Leveling.Info(lifetimeXP: number): LevelInfo
	local p = Config.Progression
	local level = 1
	local remaining = math.max(0, lifetimeXP)
	while level < p.MaxLevel do
		local needed = Leveling.XPForNext(level)
		if remaining < needed then
			return { Level = level, IntoLevel = remaining, ForNext = needed, AtMax = false }
		end
		remaining -= needed
		level += 1
	end
	return { Level = p.MaxLevel, IntoLevel = 0, ForNext = 0, AtMax = true }
end

function Leveling.RewardFor(level: number): number
	local r = Config.Progression.LevelRewards
	local coins = r.CoinsPerLevel
	if level % r.MilestoneEvery == 0 then
		coins += r.MilestoneBonusCoins
	end
	return coins
end

--[[
	Adds XP to a progression table { LifetimeXP, Level, HighestRewardedLevel } and returns the level
	rewards owed. Level rewards are paid only for levels above HighestRewardedLevel, so they can never
	be paid twice (including after a future prestige reset of Level).
]]
function Leveling.ApplyXP(progression: { [string]: any }, amount: number): ApplyResult
	local granted = math.max(0, math.floor(amount))
	local before = progression.Level
	progression.LifetimeXP += granted
	local info = Leveling.Info(progression.LifetimeXP)
	progression.Level = info.Level
	local coins = 0
	local highest = progression.HighestRewardedLevel or before
	for level = highest + 1, info.Level do
		coins += Leveling.RewardFor(level)
	end
	progression.HighestRewardedLevel = math.max(highest, info.Level)
	return { LevelsGained = info.Level - before, RewardCoins = coins, Granted = granted }
end

return Leveling
