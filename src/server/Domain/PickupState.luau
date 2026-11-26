--!strict
--[[
	Map pickup availability and consumption (spec §7, §8). The server is the only writer.
	Health pickups are not consumed by players at full health; ammo pickups are not consumed when
	every firearm reserve is already full (the pickup stays for someone who needs it).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HealthRules = require(ReplicatedStorage.Shared.Combat.HealthRules)

export type Kind = "Health" | "Ammo"
export type Pickup = { Id: string, Kind: Kind, Amount: number, RespawnSeconds: number, AvailableAt: number }

local PickupState = {}

function PickupState.new(id: string, kind: Kind, amount: number, respawnSeconds: number): Pickup
	return { Id = id, Kind = kind, Amount = amount, RespawnSeconds = respawnSeconds, AvailableAt = 0 }
end

function PickupState.IsAvailable(pickup: Pickup, now: number): boolean
	return now >= pickup.AvailableAt
end

function PickupState.Consume(pickup: Pickup, now: number)
	pickup.AvailableAt = now + pickup.RespawnSeconds
end

-- Returns (consumed, newHealth).
function PickupState.TryHeal(
	pickup: Pickup,
	health: number,
	maxHealth: number,
	now: number
): (boolean, number)
	if pickup.Kind ~= "Health" or not PickupState.IsAvailable(pickup, now) then
		return false, health
	end
	if not HealthRules.NeedsHealing(health, maxHealth) then
		return false, health
	end
	PickupState.Consume(pickup, now)
	return true, HealthRules.Heal(health, pickup.Amount, maxHealth)
end

-- `refill` performs the ammo grant and returns true if it added any rounds.
function PickupState.TryAmmo(pickup: Pickup, now: number, refill: () -> boolean): boolean
	if pickup.Kind ~= "Ammo" or not PickupState.IsAvailable(pickup, now) then
		return false
	end
	if not refill() then
		return false
	end
	PickupState.Consume(pickup, now)
	return true
end

return PickupState
