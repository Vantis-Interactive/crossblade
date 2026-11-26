--!strict
--[[
	Collectible weapon catalog (spec §11). Phase 2 ships the three starter weapons. The full
	150-weapon catalog is Phase 9 content work; every entry follows this exact shape and is
	validated by tests/specs/WeaponCatalog.spec.luau.

	Entries carry NO combat statistics. Combat stats come from the referenced archetype.
]]

local Rarity = require(script.Parent.Parent.Rarity)

export type CatalogEntry = {
	Id: string,
	DisplayName: string,
	Archetype: string,
	Rarity: Rarity.RarityId,
	Collection: string,
	ModelProfile: string,
	AnimationProfile: string,
	AudioProfile: string,
	Starter: boolean,
}

local Catalog: { [string]: CatalogEntry } = {
	classic_ar_vanguard = {
		Id = "classic_ar_vanguard",
		DisplayName = "Vanguard AR",
		Archetype = "AssaultRifle",
		Rarity = "Common",
		Collection = "Classic",
		ModelProfile = "Rifle",
		AnimationProfile = "TwoHanded",
		AudioProfile = "Rifle",
		Starter = true,
	},
	classic_pistol_warden = {
		Id = "classic_pistol_warden",
		DisplayName = "Warden P9",
		Archetype = "Pistol",
		Rarity = "Common",
		Collection = "Classic",
		ModelProfile = "Pistol",
		AnimationProfile = "OneHanded",
		AudioProfile = "Pistol",
		Starter = true,
	},
	classic_knife_ranger = {
		Id = "classic_knife_ranger",
		DisplayName = "Ranger Combat Knife",
		Archetype = "CombatKnife",
		Rarity = "Common",
		Collection = "Classic",
		ModelProfile = "Knife",
		AnimationProfile = "Knife",
		AudioProfile = "Knife",
		Starter = true,
	},
}

for _, entry in Catalog do
	table.freeze(entry)
end

local StarterLoadout = table.freeze({
	Primary = "classic_ar_vanguard",
	Secondary = "classic_pistol_warden",
	Knife = "classic_knife_ranger",
})

return table.freeze({
	Entries = table.freeze(Catalog),
	StarterLoadout = StarterLoadout,
})
