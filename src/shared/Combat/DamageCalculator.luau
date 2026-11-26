--!strict
--[[
	Damage calculation (spec §8, §9). Inputs are archetype stats only; rarity is never an input.
	All modifiers (headshot multiplier, falloff curve) are configuration values on the archetype.
]]

local Archetypes = require(script.Parent.Parent.Config.Weapons.Archetypes)

type FirearmStats = Archetypes.FirearmStats

local DamageCalculator = {}

-- Linear falloff from 1.0 at FalloffStart to MinDamageMultiplier at FalloffEnd.
function DamageCalculator.FalloffMultiplier(stats: FirearmStats, distance: number): number
	if distance <= stats.FalloffStart or stats.FalloffEnd <= stats.FalloffStart then
		return 1
	end
	if distance >= stats.FalloffEnd then
		return stats.MinDamageMultiplier
	end
	local alpha = (distance - stats.FalloffStart) / (stats.FalloffEnd - stats.FalloffStart)
	return 1 + (stats.MinDamageMultiplier - 1) * alpha
end

-- Damage for one pellet/bullet. Returns 0 beyond the weapon's range.
function DamageCalculator.Firearm(stats: FirearmStats, distance: number, zone: "Head" | "Body"): number
	if distance > stats.Range then
		return 0
	end
	local damage = stats.Damage * DamageCalculator.FalloffMultiplier(stats, distance)
	if zone == "Head" then
		damage *= stats.HeadshotMultiplier
	end
	return DamageCalculator.Round(damage)
end

function DamageCalculator.ThrownKnife(stats: Archetypes.ThrowStats, zone: "Head" | "Body"): number
	local damage = stats.Damage
	if zone == "Head" then
		damage *= stats.HeadshotMultiplier
	end
	return DamageCalculator.Round(damage)
end

-- Damage values are kept to one decimal place so pellet damage (12.5) is exact.
function DamageCalculator.Round(value: number): number
	return math.floor(value * 10 + 0.5) / 10
end

return DamageCalculator
