--!strict
--[[
	Authoritative magazine / reserve / reload state for one firearm (spec §8).
	Time is passed explicitly; reload completion is evaluated lazily from ReloadEndsAt so there is no
	timer race: a reload is complete exactly when `now >= ReloadEndsAt`, on whichever call observes it.
]]

export type AmmoState = {
	Magazine: number,
	Reserve: number,
	MagazineSize: number,
	MaxReserve: number,
	ReloadSeconds: number,
	ReloadEndsAt: number?,
}

local AmmoState = {}

function AmmoState.new(magazineSize: number, maxReserve: number, reloadSeconds: number): AmmoState
	return {
		Magazine = magazineSize,
		Reserve = maxReserve,
		MagazineSize = magazineSize,
		MaxReserve = maxReserve,
		ReloadSeconds = reloadSeconds,
		ReloadEndsAt = nil,
	}
end

-- Finishes a due reload. Returns true if a reload completed during this call.
function AmmoState.Update(state: AmmoState, now: number): boolean
	local endsAt = state.ReloadEndsAt
	if endsAt == nil or now < endsAt then
		return false
	end
	local needed = state.MagazineSize - state.Magazine
	local moved = math.min(needed, state.Reserve)
	state.Magazine += moved
	state.Reserve -= moved
	state.ReloadEndsAt = nil
	return true
end

function AmmoState.IsReloading(state: AmmoState, now: number): boolean
	AmmoState.Update(state, now)
	return state.ReloadEndsAt ~= nil
end

function AmmoState.CanFire(state: AmmoState, now: number): (boolean, string?)
	AmmoState.Update(state, now)
	if state.ReloadEndsAt ~= nil then
		return false, "Reloading"
	end
	if state.Magazine <= 0 then
		return false, "Empty"
	end
	return true, nil
end

-- Consumes one round. Callers must check CanFire first; this re-checks and refuses otherwise.
function AmmoState.Consume(state: AmmoState, now: number): boolean
	if not AmmoState.CanFire(state, now) then
		return false
	end
	state.Magazine -= 1
	return true
end

function AmmoState.StartReload(state: AmmoState, now: number): (boolean, string?)
	AmmoState.Update(state, now)
	if state.ReloadEndsAt ~= nil then
		return false, "AlreadyReloading"
	end
	if state.Magazine >= state.MagazineSize then
		return false, "MagazineFull"
	end
	if state.Reserve <= 0 then
		return false, "NoReserve"
	end
	state.ReloadEndsAt = now + state.ReloadSeconds
	return true, nil
end

-- Switching weapons cancels an in-progress reload without moving any rounds.
function AmmoState.CancelReload(state: AmmoState)
	state.ReloadEndsAt = nil
end

-- Adds rounds to reserve up to MaxReserve. Returns rounds actually added.
function AmmoState.AddReserve(state: AmmoState, amount: number): number
	local added = math.clamp(state.MaxReserve - state.Reserve, 0, math.max(0, amount))
	state.Reserve += added
	return added
end

function AmmoState.IsReserveFull(state: AmmoState): boolean
	return state.Reserve >= state.MaxReserve
end

return AmmoState
