--!strict
--[[
	Read API over the weapon catalog and archetypes. Combat code asks this module for stats by
	weapon id; the returned stats are the archetype's and never depend on rarity or collection.
]]

local Config = require(script.Parent.Parent.Config)
local Archetypes = require(script.Parent.Parent.Config.Weapons.Archetypes)

export type Slot = "Primary" | "Secondary" | "Knife"

local WeaponCatalog = {}

WeaponCatalog.Slots = table.freeze({ "Primary", "Secondary", "Knife" }) :: { Slot }

function WeaponCatalog.Get(weaponId: string)
	return Config.Catalog.Entries[weaponId]
end

function WeaponCatalog.GetArchetype(weaponId: string): Archetypes.Archetype?
	local entry = Config.Catalog.Entries[weaponId]
	if entry == nil then
		return nil
	end
	return Config.Archetypes[entry.Archetype]
end

function WeaponCatalog.GetFirearmStats(weaponId: string): Archetypes.FirearmStats?
	local archetype = WeaponCatalog.GetArchetype(weaponId)
	return archetype and archetype.Firearm
end

function WeaponCatalog.GetKnifeStats(weaponId: string): Archetypes.KnifeStats?
	local archetype = WeaponCatalog.GetArchetype(weaponId)
	return archetype and archetype.Knife
end

function WeaponCatalog.SlotFor(weaponId: string): Slot?
	local archetype = WeaponCatalog.GetArchetype(weaponId)
	return archetype and archetype.Category
end

function WeaponCatalog.StarterLoadout(): { [Slot]: string }
	return table.clone(Config.Catalog.StarterLoadout) :: any
end

-- Full structural validation of the catalog. Returns a list of problems (empty when valid).
function WeaponCatalog.Validate(): { string }
	local problems = {}
	local rarityTiers = Config.Rarity.Tiers
	local requiredStrings = {
		"Id",
		"DisplayName",
		"Archetype",
		"Rarity",
		"Collection",
		"ModelProfile",
		"AnimationProfile",
		"AudioProfile",
	}
	for id, entry in Config.Catalog.Entries do
		for _, field in requiredStrings do
			local value = (entry :: any)[field]
			if type(value) ~= "string" or value == "" then
				table.insert(problems, `{id}: missing {field}`)
			end
		end
		if entry.Id ~= id then
			table.insert(problems, `{id}: Id field does not match key`)
		end
		if rarityTiers[entry.Rarity] == nil then
			table.insert(problems, `{id}: unknown rarity {entry.Rarity}`)
		end
		local archetype = Config.Archetypes[entry.Archetype]
		if archetype == nil then
			table.insert(problems, `{id}: unknown archetype {entry.Archetype}`)
		elseif (archetype.Category == "Knife") ~= (archetype.Knife ~= nil) then
			table.insert(problems, `{id}: archetype category/stat mismatch`)
		end
		-- Collectibles must not carry combat stats (rarity-independence).
		for _, forbidden in { "Damage", "Firearm", "Knife", "Stats", "RoundsPerMinute", "HeadshotMultiplier" } do
			if (entry :: any)[forbidden] ~= nil then
				table.insert(problems, `{id}: collectible defines combat field {forbidden}`)
			end
		end
	end
	for slot, weaponId in Config.Catalog.StarterLoadout do
		local entry = Config.Catalog.Entries[weaponId]
		if entry == nil then
			table.insert(problems, `starter {slot}: unknown weapon {weaponId}`)
		elseif WeaponCatalog.SlotFor(weaponId) ~= slot then
			table.insert(problems, `starter {slot}: {weaponId} is not a {slot} weapon`)
		elseif not entry.Starter then
			table.insert(problems, `starter {slot}: {weaponId} not flagged Starter`)
		end
	end
	return problems
end

return WeaponCatalog
