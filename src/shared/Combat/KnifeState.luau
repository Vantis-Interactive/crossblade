--!strict
--[[
	Knife ownership state (spec §8). A player holds exactly one knife. Once thrown, the knife cannot
	slash, stab or be thrown again until the specific thrown instance is recovered, a knife station
	replaces it, or the player respawns.
]]

export type KnifeState = {
	InHand: boolean,
	ThrowId: number?, -- identifies the knife currently in the world
	NextThrowId: number,
}

local KnifeState = {}

function KnifeState.new(): KnifeState
	return { InHand = true, ThrowId = nil, NextThrowId = 1 }
end

function KnifeState.CanAttack(state: KnifeState): boolean
	return state.InHand
end

-- Marks the knife as thrown. Returns the throw id for the projectile, or nil if not in hand.
function KnifeState.Throw(state: KnifeState): number?
	if not state.InHand then
		return nil
	end
	local id = state.NextThrowId
	state.NextThrowId += 1
	state.InHand = false
	state.ThrowId = id
	return id
end

-- Recovers a specific thrown knife. Stale or foreign ids are rejected.
function KnifeState.Recover(state: KnifeState, throwId: number): boolean
	if state.InHand or state.ThrowId ~= throwId then
		return false
	end
	state.InHand = true
	state.ThrowId = nil
	return true
end

-- Station replacement or respawn: a fresh knife regardless of where the old one is.
-- Returns the id of the knife that was superseded (so the world copy can be removed), if any.
function KnifeState.Replace(state: KnifeState): number?
	local superseded = state.ThrowId
	state.InHand = true
	state.ThrowId = nil
	return superseded
end

return KnifeState
