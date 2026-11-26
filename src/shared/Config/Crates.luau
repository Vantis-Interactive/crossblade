--!strict
--[[
	Crate catalog (spec §14). Prices are SPEC. Basic and the weapon-specific crates use the SPEC
	standard distribution. Premium, Legendary, Mythical, Shotgun and themed crate distributions are
	PROPOSED (D-023) because the specification gives only the standard distribution.

	Each crate's reward pool = every non-starter catalog weapon matching Filter whose rarity has
	non-zero odds. A rarity's odds are split equally among that rarity's items in the pool. The odds
	shown to players are computed by the SAME function the server uses to select rewards
	(Shared/Economy/CrateOdds), so disclosure always equals the real algorithm.

	Seasonal crates (Halloween, Winter, Anniversary) are added with seasonal content (Phase 12).
]]

export type RarityOdds = { [string]: number } -- percent, must sum to 100
export type Filter = { Slot: string?, Archetypes: { string }?, Collection: string? }
export type Crate = {
	Id: string,
	DisplayName: string,
	Category: "Rarity" | "Weapon" | "Themed",
	Price: number,
	Filter: Filter,
	Odds: RarityOdds,
	Order: number,
}

local STANDARD: RarityOdds = table.freeze({
	Common = 40,
	Uncommon = 25,
	Rare = 18,
	Epic = 10,
	Legendary = 5,
	Mythical = 1.8,
	Celestial = 0.2,
})

local THEMED: RarityOdds = table.freeze({ Rare = 60, Epic = 28, Legendary = 10, Mythical = 2 })

local Crates: { [string]: Crate } = {
	basic = {
		Id = "basic",
		DisplayName = "Basic Crate",
		Category = "Rarity",
		Price = 250,
		Filter = {},
		Odds = STANDARD,
		Order = 1,
	},
	premium = {
		Id = "premium",
		DisplayName = "Premium Crate",
		Category = "Rarity",
		Price = 750,
		Filter = {},
		Odds = { Uncommon = 40, Rare = 30, Epic = 18, Legendary = 8, Mythical = 3.5, Celestial = 0.5 },
		Order = 2,
	},
	legendary = {
		Id = "legendary",
		DisplayName = "Legendary Crate",
		Category = "Rarity",
		Price = 2500,
		Filter = {},
		Odds = { Legendary = 85, Mythical = 13, Celestial = 2 },
		Order = 3,
	},
	mythical = {
		Id = "mythical",
		DisplayName = "Mythical Crate",
		Category = "Rarity",
		Price = 5000,
		Filter = {},
		Odds = { Mythical = 92, Celestial = 8 },
		Order = 4,
	},
	knife = {
		Id = "knife",
		DisplayName = "Knife Crate",
		Category = "Weapon",
		Price = 500,
		Filter = { Slot = "Knife" },
		Odds = STANDARD,
		Order = 10,
	},
	pistol = {
		Id = "pistol",
		DisplayName = "Pistol Crate",
		Category = "Weapon",
		Price = 500,
		Filter = { Slot = "Secondary" },
		Odds = STANDARD,
		Order = 11,
	},
	rifle = {
		Id = "rifle",
		DisplayName = "Rifle Crate",
		Category = "Weapon",
		Price = 750,
		Filter = { Archetypes = { "AssaultRifle" } },
		Odds = STANDARD,
		Order = 12,
	},
	shotgun = {
		Id = "shotgun",
		DisplayName = "Shotgun Crate",
		Category = "Weapon",
		Price = 750,
		Filter = { Archetypes = { "Shotgun" } },
		-- No Celestial shotgun exists; its 0.2% moves to Mythical.
		Odds = { Common = 40, Uncommon = 25, Rare = 18, Epic = 10, Legendary = 5, Mythical = 2 },
		Order = 13,
	},
	sniper = {
		Id = "sniper",
		DisplayName = "Sniper Crate",
		Category = "Weapon",
		Price = 1000,
		Filter = { Archetypes = { "SniperRifle" } },
		Odds = STANDARD,
		Order = 14,
	},
	inferno = {
		Id = "inferno",
		DisplayName = "Inferno Crate",
		Category = "Themed",
		Price = 1500,
		Filter = { Collection = "Inferno" },
		Odds = THEMED,
		Order = 20,
	},
	arctic = {
		Id = "arctic",
		DisplayName = "Arctic Crate",
		Category = "Themed",
		Price = 1500,
		Filter = { Collection = "Arctic" },
		Odds = THEMED,
		Order = 21,
	},
	cyberpunk = {
		Id = "cyberpunk",
		DisplayName = "Cyberpunk Crate",
		Category = "Themed",
		Price = 2000,
		Filter = { Collection = "Cyberpunk" },
		Odds = THEMED,
		Order = 22,
	},
	galaxy = {
		Id = "galaxy",
		DisplayName = "Galaxy Crate",
		Category = "Themed",
		Price = 2500,
		Filter = { Collection = "Galaxy" },
		Odds = THEMED,
		Order = 23,
	},
}

for _, crate in Crates do
	table.freeze(crate.Filter)
	if not table.isfrozen(crate.Odds) then
		table.freeze(crate.Odds) -- STANDARD/THEMED are shared and already frozen
	end
	table.freeze(crate)
end

return table.freeze({ Crates = table.freeze(Crates), Standard = STANDARD })
