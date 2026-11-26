--!strict
-- Authoritative ammunition for every player's firearms (spec §8). Wraps Shared/Combat/AmmoState.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local AmmoState = require(ReplicatedStorage.Shared.Combat.AmmoState)
local WeaponCatalog = require(ReplicatedStorage.Shared.Weapons.WeaponCatalog)

type Slot = "Primary" | "Secondary"

local AmmunitionService = {
	Name = "AmmunitionService",
}

local states: { [Player]: { [Slot]: AmmoState.AmmoState } } = {}

function AmmunitionService.Start(_self: typeof(AmmunitionService))
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

-- Respawning restores the starting loadout: full magazines and full reserves.
function AmmunitionService.Reset(
	_self: typeof(AmmunitionService),
	player: Player,
	loadout: { [string]: string }
)
	local perSlot = {}
	for _, slot in { "Primary", "Secondary" } :: { Slot } do
		local stats = WeaponCatalog.GetFirearmStats(loadout[slot])
		if stats then
			perSlot[slot] = AmmoState.new(stats.MagazineSize, stats.MaxReserve, stats.ReloadSeconds)
		end
	end
	states[player] = perSlot
end

function AmmunitionService.Get(
	_self: typeof(AmmunitionService),
	player: Player,
	slot: Slot
): AmmoState.AmmoState?
	local perSlot = states[player]
	return perSlot and perSlot[slot]
end

function AmmunitionService.Consume(
	self: typeof(AmmunitionService),
	player: Player,
	slot: Slot,
	now: number
): (boolean, string?)
	local state = self:Get(player, slot)
	if state == nil then
		return false, "NoWeapon"
	end
	local ok, reason = AmmoState.CanFire(state, now)
	if not ok then
		return false, reason
	end
	AmmoState.Consume(state, now)
	return true, nil
end

function AmmunitionService.StartReload(
	self: typeof(AmmunitionService),
	player: Player,
	slot: Slot,
	now: number
): (boolean, string?)
	local state = self:Get(player, slot)
	if state == nil then
		return false, "NoWeapon"
	end
	return AmmoState.StartReload(state, now)
end

function AmmunitionService.CancelReloads(_self: typeof(AmmunitionService), player: Player)
	for _, state in states[player] or {} do
		AmmoState.CancelReload(state)
	end
end

-- Ammo pickup: adds `magazines` worth of rounds to each firearm reserve. True if anything was added.
function AmmunitionService.Refill(
	_self: typeof(AmmunitionService),
	player: Player,
	magazines: number
): boolean
	local added = 0
	for _, state in states[player] or {} do
		added += AmmoState.AddReserve(state, state.MagazineSize * magazines)
	end
	return added > 0
end

function AmmunitionService.Snapshot(
	_self: typeof(AmmunitionService),
	player: Player,
	now: number
): { [string]: any }
	local result = {}
	for slot, state in states[player] or {} do
		AmmoState.Update(state, now)
		result[slot] =
			{ Magazine = state.Magazine, Reserve = state.Reserve, ReloadEndsAt = state.ReloadEndsAt }
	end
	return result
end

return AmmunitionService
