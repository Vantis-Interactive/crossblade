--!strict
--[[
	Collectible weapon catalog (spec §11). Entries carry NO combat statistics: combat stats come from
	the referenced archetype (D-008). Rarity and collection are cosmetic/collection metadata.

	Phase 3 content: 3 starter weapons + 37 collectibles spanning every archetype, rarity and themed
	collection so that every crate has a real, validated reward pool. Names are original. Models are
	temporary primitive dev models tinted by collection (docs/ASSET_MANIFEST.md DEV-MODEL-*). The
	full 150-weapon launch catalog is Phase 9 content work and follows this exact shape.
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

-- Archetype -> (model profile, animation profile). Audio profile is the archetype id.
local PRESENTATION: { [string]: { string } } = {
	AssaultRifle = { "Rifle", "TwoHanded" },
	SubmachineGun = { "SMG", "TwoHanded" },
	Shotgun = { "Shotgun", "TwoHanded" },
	SniperRifle = { "Sniper", "TwoHanded" },
	Pistol = { "Pistol", "OneHanded" },
	Revolver = { "Revolver", "OneHanded" },
	Dagger = { "Knife", "Knife" },
	Karambit = { "Knife", "Knife" },
	ButterflyKnife = { "Knife", "Knife" },
	CombatKnife = { "Knife", "Knife" },
}

local Catalog: { [string]: CatalogEntry } = {}

local function add(
	id: string,
	name: string,
	archetype: string,
	rarity: Rarity.RarityId,
	collection: string,
	starter: boolean?
)
	assert(Catalog[id] == nil, `duplicate weapon id {id}`)
	local presentation = PRESENTATION[archetype]
	assert(presentation, `no presentation for archetype {archetype}`)
	Catalog[id] = table.freeze({
		Id = id,
		DisplayName = name,
		Archetype = archetype,
		Rarity = rarity,
		Collection = collection,
		ModelProfile = presentation[1],
		AnimationProfile = presentation[2],
		AudioProfile = archetype,
		Starter = starter == true,
	})
end

-- Starter loadout (granted to every player, never in crate pools).
add("classic_ar_vanguard", "Vanguard AR", "AssaultRifle", "Common", "Classic", true)
add("classic_pistol_warden", "Warden P9", "Pistol", "Common", "Classic", true)
add("classic_knife_ranger", "Ranger Combat Knife", "CombatKnife", "Common", "Classic", true)

-- Knives
add("classic_dagger_field", "Field Dagger", "Dagger", "Common", "Classic")
add("tactical_karambit_trench", "Trench Karambit", "Karambit", "Uncommon", "Tactical")
add("inferno_butterfly_ember", "Ember Flicker", "ButterflyKnife", "Rare", "Inferno")
add("arctic_knife_glacier", "Glacier Bowie", "CombatKnife", "Epic", "Arctic")
add("cyber_karambit_talon", "Neon Talon", "Karambit", "Legendary", "Cyberpunk")
add("galaxy_dagger_nebula", "Nebula Stiletto", "Dagger", "Mythical", "Galaxy")
add("celestial_butterfly_starfall", "Starfall Butterfly", "ButterflyKnife", "Celestial", "Celestial")

-- Secondaries
add("classic_pistol_courier", "Courier P7", "Pistol", "Common", "Classic")
add("arctic_revolver_snowline", "Snowline Revolver", "Revolver", "Uncommon", "Arctic")
add("cyber_pistol_circuit", "Circuit Sidearm", "Pistol", "Rare", "Cyberpunk")
add("inferno_revolver_cinder", "Cinder .44", "Revolver", "Epic", "Inferno")
add("galaxy_pistol_quasar", "Quasar Sidearm", "Pistol", "Legendary", "Galaxy")
add("arctic_revolver_permafrost", "Permafrost Magnum", "Revolver", "Mythical", "Arctic")
add("celestial_pistol_halo", "Halo Sidearm", "Pistol", "Celestial", "Celestial")

-- Assault rifles
add("tactical_ar_sentinel", "Sentinel AR", "AssaultRifle", "Common", "Tactical")
add("inferno_ar_kindling", "Kindling Carbine", "AssaultRifle", "Uncommon", "Inferno")
add("arctic_ar_whiteout", "Whiteout AR", "AssaultRifle", "Rare", "Arctic")
add("cyber_ar_voltage", "Voltage AR", "AssaultRifle", "Epic", "Cyberpunk")
add("inferno_ar_wildfire", "Wildfire Rifle", "AssaultRifle", "Legendary", "Inferno")
add("galaxy_ar_eclipse", "Eclipse Rifle", "AssaultRifle", "Mythical", "Galaxy")
add("celestial_ar_aurora", "Aurora Rifle", "AssaultRifle", "Celestial", "Celestial")

-- Shotguns (no Celestial shotgun: launch target allows only 2 Celestial primaries)
add("classic_shotgun_breacher", "Breacher 12", "Shotgun", "Common", "Classic")
add("cyber_shotgun_static", "Static Scattergun", "Shotgun", "Uncommon", "Cyberpunk")
add("arctic_shotgun_icebreaker", "Icebreaker", "Shotgun", "Rare", "Arctic")
add("galaxy_shotgun_meteor", "Meteor Scatter", "Shotgun", "Epic", "Galaxy")
add("arctic_shotgun_avalanche", "Avalanche", "Shotgun", "Legendary", "Arctic")
add("cyber_shotgun_overclock", "Overclock", "Shotgun", "Mythical", "Cyberpunk")

-- Sniper rifles
add("tactical_sniper_longwatch", "Longwatch", "SniperRifle", "Common", "Tactical")
add("galaxy_sniper_orbit", "Orbit Marksman", "SniperRifle", "Uncommon", "Galaxy")
add("inferno_sniper_flare", "Flare Lance", "SniperRifle", "Rare", "Inferno")
add("arctic_sniper_polar", "Polar Lance", "SniperRifle", "Epic", "Arctic")
add("cyber_sniper_railspike", "Railspike", "SniperRifle", "Legendary", "Cyberpunk")
add("inferno_sniper_hellfire", "Hellfire Bolt", "SniperRifle", "Mythical", "Inferno")
add("celestial_sniper_seraph", "Seraph Long Rifle", "SniperRifle", "Celestial", "Celestial")

-- Submachine guns
add("classic_smg_pathfinder", "Pathfinder SMG", "SubmachineGun", "Common", "Classic")
add("galaxy_smg_pulsar", "Pulsar SMG", "SubmachineGun", "Rare", "Galaxy")
add("shadow_smg_spectre", "Spectre SMG", "SubmachineGun", "Epic", "Shadow")

local StarterLoadout = table.freeze({
	Primary = "classic_ar_vanguard",
	Secondary = "classic_pistol_warden",
	Knife = "classic_knife_ranger",
})

return table.freeze({
	Entries = table.freeze(Catalog),
	StarterLoadout = StarterLoadout,
})
