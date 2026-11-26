--!strict
--[[
	Rarity tiers (spec §11). Rarity is cosmetic/collection metadata only: it is never read by any
	combat calculation (enforced by tests/specs/WeaponCatalog.spec.luau).
	Each tier has a colour AND a distinct symbol so rarity is never communicated by colour alone.
]]
export type RarityId = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythical" | "Celestial"

local Rarity = {
	Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythical", "Celestial" } :: { RarityId },
	Tiers = {
		Common = { Rank = 1, Color = Color3.fromRGB(170, 174, 168), Symbol = "●" },
		Uncommon = { Rank = 2, Color = Color3.fromRGB(110, 190, 90), Symbol = "◆" },
		Rare = { Rank = 3, Color = Color3.fromRGB(70, 140, 230), Symbol = "▲" },
		Epic = { Rank = 4, Color = Color3.fromRGB(160, 90, 220), Symbol = "★" },
		Legendary = { Rank = 5, Color = Color3.fromRGB(235, 165, 40), Symbol = "✦" },
		Mythical = { Rank = 6, Color = Color3.fromRGB(225, 70, 90), Symbol = "✸" },
		Celestial = { Rank = 7, Color = Color3.fromRGB(120, 235, 235), Symbol = "❂" },
	},
}

return table.freeze(Rarity)
