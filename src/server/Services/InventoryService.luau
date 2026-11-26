--!strict
--[[
	Weapon inventory and loadout presets (spec §8, §11, §12). Ownership is the persisted
	Inventory.Weapons map. Loadout changes are validated against ownership and slot on the server and
	apply from the player's next life (WeaponService resolves the loadout at spawn).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local WeaponCatalog = require(ReplicatedStorage.Shared.Weapons.WeaponCatalog)

local InventoryService = {
	Name = "InventoryService",
	Dependencies = { "Net", "PlayerDataService", "AuditService" },
	Changed = Signal.new() :: Signal.Signal<Player>,
}

local net: any
local playerData: any
local audit: any

function InventoryService.Owns(_self: typeof(InventoryService), player: Player, weaponId: string): boolean
	local profile = playerData:GetProfile(player)
	return profile ~= nil and profile.Data.Inventory.Weapons[weaponId] ~= nil
end

function InventoryService.Snapshot(_self: typeof(InventoryService), player: Player): { [string]: any }?
	local profile = playerData:GetProfile(player)
	if profile == nil then
		return nil
	end
	local owned = {}
	for weaponId in profile.Data.Inventory.Weapons do
		if WeaponCatalog.Get(weaponId) then
			table.insert(owned, weaponId)
		end
	end
	table.sort(owned)
	local loadouts = profile.Data.Loadouts
	return { Owned = owned, Loadout = table.clone(loadouts.Presets[loadouts.ActivePreset]) }
end

function InventoryService.Init(self: typeof(InventoryService), registry: { [string]: any })
	net = registry.Net
	playerData = registry.PlayerDataService
	audit = registry.AuditService

	net.OnEvent("SetLoadout", function(player: Player, payload: any)
		local profile = playerData:GetProfile(player)
		if profile == nil then
			return
		end
		for _, slot in WeaponCatalog.Slots do
			local weaponId = payload[slot]
			if WeaponCatalog.SlotFor(weaponId) ~= slot or not self:Owns(player, weaponId) then
				audit:Record(
					"Security",
					"LoadoutChangeRejected",
					player.UserId,
					{ slot = slot, weapon = weaponId }
				)
				net.Fire(
					"Notification",
					player,
					{ Kind = "Warning", Text = "That loadout is not available." }
				)
				return
			end
		end
		playerData:Update(player, function(data)
			local loadouts = data.Loadouts
			loadouts.Presets[loadouts.ActivePreset] =
				{ Primary = payload.Primary, Secondary = payload.Secondary, Knife = payload.Knife }
		end)
		playerData:RequestSave(player)
		net.Fire(
			"Notification",
			player,
			{ Kind = "Info", Text = "Loadout saved. It applies on your next spawn." }
		)
		self.Changed:Fire(player)
	end)
end

return InventoryService
