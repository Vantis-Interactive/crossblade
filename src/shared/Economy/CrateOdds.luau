--!strict
--[[
	Crate reward distributions (spec §14). The SAME distribution object is used for:
	  - the odds disclosed to players before purchase (client), and
	  - the server's reward selection (Select).
	Each item's probability is exact: its rarity's odds divided by the number of pool items of that
	rarity. Selection walks the cumulative distribution with a single uniform roll in [0, 1).
]]

local Config = require(script.Parent.Parent.Config)

export type Entry = { WeaponId: string, Rarity: string, Probability: number }
export type Distribution = { CrateId: string, Entries: { Entry } }

local CrateOdds = {}

local function matches(entry: any, filter: any): boolean
	if entry.Starter then
		return false
	end
	local archetype = Config.Archetypes[entry.Archetype]
	if archetype == nil then
		return false
	end
	if filter.Slot and archetype.Category ~= filter.Slot then
		return false
	end
	if filter.Archetypes and not table.find(filter.Archetypes, entry.Archetype) then
		return false
	end
	if filter.Collection and entry.Collection ~= filter.Collection then
		return false
	end
	return true
end

-- Builds the distribution for a crate. Items are ordered by rarity rank then id (stable, so the
-- disclosed list and the server's cumulative walk are identical).
function CrateOdds.Build(crate: any, catalog: { [string]: any }?): Distribution
	local entries = catalog or Config.Catalog.Entries
	local byRarity: { [string]: { string } } = {}
	for id, entry in entries do
		if (crate.Odds[entry.Rarity] or 0) > 0 and matches(entry, crate.Filter) then
			byRarity[entry.Rarity] = byRarity[entry.Rarity] or {}
			table.insert(byRarity[entry.Rarity], id)
		end
	end
	local result: { Entry } = {}
	for _, rarity in Config.Rarity.Order do
		local ids = byRarity[rarity]
		if ids then
			table.sort(ids)
			local share = crate.Odds[rarity] / 100 / #ids
			for _, id in ids do
				table.insert(result, { WeaponId = id, Rarity = rarity, Probability = share })
			end
		end
	end
	return { CrateId = crate.Id, Entries = result }
end

-- roll must be in [0, 1). Returns the selected entry.
function CrateOdds.Select(distribution: Distribution, roll: number): Entry
	assert(roll >= 0 and roll < 1, "roll out of range")
	local cumulative = 0
	for _, entry in distribution.Entries do
		cumulative += entry.Probability
		if roll < cumulative then
			return entry
		end
	end
	-- Floating-point remainder at the very top of the range: last entry.
	return distribution.Entries[#distribution.Entries]
end

function CrateOdds.RarityTotal(distribution: Distribution, rarity: string): number
	local total = 0
	for _, entry in distribution.Entries do
		if entry.Rarity == rarity then
			total += entry.Probability
		end
	end
	return total
end

-- Expected duplicate compensation for a player who already owns every item in the pool.
function CrateOdds.ExpectedCompensation(
	distribution: Distribution,
	compensation: { [string]: number }
): number
	local expected = 0
	for _, entry in distribution.Entries do
		expected += entry.Probability * (compensation[entry.Rarity] or 0)
	end
	return expected
end

-- Returns a list of problems; an empty list means the crate may be activated.
function CrateOdds.Validate(crate: any, distribution: Distribution): { string }
	local problems = {}
	if type(crate.Price) ~= "number" or crate.Price <= 0 or crate.Price % 1 ~= 0 then
		table.insert(problems, "price must be a positive integer")
	end
	local oddsTotal = 0
	for rarity, percent in crate.Odds do
		if Config.Rarity.Tiers[rarity] == nil then
			table.insert(problems, `unknown rarity {rarity}`)
		elseif percent < 0 then
			table.insert(problems, `negative odds for {rarity}`)
		end
		oddsTotal += percent
		if percent > 0 and CrateOdds.RarityTotal(distribution, rarity) <= 0 then
			table.insert(problems, `{rarity} has odds but no items in the pool`)
		end
		if Config.Economy.DuplicateCompensation[rarity] == nil then
			table.insert(problems, `no duplicate compensation configured for {rarity}`)
		end
	end
	if math.abs(oddsTotal - 100) > 1e-9 then
		table.insert(problems, `odds sum to {oddsTotal}, not 100`)
	end
	local probabilityTotal = 0
	for _, entry in distribution.Entries do
		probabilityTotal += entry.Probability
	end
	if #distribution.Entries == 0 or math.abs(probabilityTotal - 1) > 1e-9 then
		table.insert(problems, `item probabilities sum to {probabilityTotal}`)
	end
	local expected = CrateOdds.ExpectedCompensation(distribution, Config.Economy.DuplicateCompensation)
	local ceiling = crate.Price * (1 - Config.Economy.MinimumSinkMargin)
	if expected >= ceiling then
		table.insert(
			problems,
			`expected duplicate compensation {expected} >= {ceiling}: crate would generate coins`
		)
	end
	return problems
end

return CrateOdds
