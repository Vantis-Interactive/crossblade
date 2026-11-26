--!strict
-- Health arithmetic (spec §7). Health is always within [0, MaxHealth]; there is no regeneration.

local HealthRules = {}

export type DamageResult = { Health: number, Dealt: number, Died: boolean }

function HealthRules.Heal(current: number, amount: number, maxHealth: number): number
	if current <= 0 or amount <= 0 then
		return math.clamp(current, 0, maxHealth) -- the dead cannot be healed
	end
	return math.clamp(current + amount, 0, maxHealth)
end

function HealthRules.ApplyDamage(current: number, amount: number): DamageResult
	if current <= 0 then
		return { Health = 0, Dealt = 0, Died = false } -- already dead: no double elimination
	end
	local dealt = math.clamp(amount, 0, current)
	local health = current - dealt
	return { Health = health, Dealt = dealt, Died = health <= 0 }
end

function HealthRules.NeedsHealing(current: number, maxHealth: number): boolean
	return current > 0 and current < maxHealth
end

return HealthRules
