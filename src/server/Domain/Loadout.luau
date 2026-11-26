--!strict
--[[
	Server-side loadout resolution (spec §8, §25 "unauthorized weapons").
	Clients never send weapon ids for combat; they send slot names only. The weapon in each slot is
	resolved here from the player's persisted preset AND verified against their owned inventory.
	An unowned, unknown or wrong-slot weapon is replaced with the starter weapon for that slot.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponCatalog = require(ReplicatedStorage.Shared.Weapons.WeaponCatalog)

export type Loadout = { Primary: string, Secondary: string, Knife: string }
export type Problem = { Slot: string, WeaponId: any, Reason: "Unknown" | "WrongSlot" | "NotOwned" }

local Loadout = {}

function Loadout.Resolve(inventory: { [string]: any }?, preset: { [string]: any }?): (Loadout, { Problem })
	local starter = WeaponCatalog.StarterLoadout()
	local owned = inventory or {}
	local chosen = preset or {}
	local problems: { Problem } = {}
	local result = {} :: { [string]: string }
	for _, slot in WeaponCatalog.Slots do
		local weaponId = chosen[slot]
		local reason: ("Unknown" | "WrongSlot" | "NotOwned")? = nil
		if type(weaponId) ~= "string" or WeaponCatalog.Get(weaponId) == nil then
			reason = "Unknown"
		elseif WeaponCatalog.SlotFor(weaponId) ~= slot then
			reason = "WrongSlot"
		elseif owned[weaponId] == nil then
			reason = "NotOwned"
		end
		if reason then
			table.insert(problems, { Slot = slot, WeaponId = weaponId, Reason = reason })
			result[slot] = starter[slot]
		else
			result[slot] = weaponId
		end
	end
	return (result :: any) :: Loadout, problems
end

return Loadout
