--!strict
--[[
	Server-side movement plausibility check (spec §25 "speed manipulation", "unauthorized teleportation").
	Clients own their character physics on Roblox, so the server samples root positions and compares
	horizontal speed with the configured run speed plus generous tolerances. Falling is unrestricted
	(gravity is legitimate); rising faster than jumps allow is flagged.

	Verdicts:
	  "Ok"      - plausible
	  "Flag"    - over the limit; counts toward suspicion only after repeated flags in a window
	  "Correct" - grossly impossible (e.g. teleport); the caller returns the player to LastValid
]]

export type State = {
	LastPosition: Vector3?,
	LastTime: number?,
	LastValid: Vector3?,
	GraceUntil: number,
	Flags: { number },
}

export type Limits = {
	RunSpeed: number,
	SpeedToleranceMultiplier: number,
	SpeedToleranceFlat: number,
	CorrectionMultiplier: number,
	MaxRiseSpeed: number,
	FlagsBeforeSuspicion: number,
	FlagWindowSeconds: number,
}

export type Verdict = "Ok" | "Flag" | "Correct"

local MovementValidator = {}

function MovementValidator.new(): State
	return { LastPosition = nil, LastTime = nil, LastValid = nil, GraceUntil = 0, Flags = {} }
end

-- Call after any server-initiated teleport so the jump is not treated as cheating.
function MovementValidator.Teleported(state: State, position: Vector3, now: number, grace: number)
	state.LastPosition = position
	state.LastValid = position
	state.LastTime = now
	state.GraceUntil = now + grace
	table.clear(state.Flags)
end

-- Returns verdict, measured horizontal speed, and whether the flag threshold was reached.
function MovementValidator.Sample(
	state: State,
	position: Vector3,
	now: number,
	limits: Limits
): (Verdict, number, boolean)
	local lastPosition, lastTime = state.LastPosition, state.LastTime
	state.LastPosition = position
	state.LastTime = now
	if lastPosition == nil or lastTime == nil or now <= lastTime then
		state.LastValid = position
		return "Ok", 0, false
	end
	if now < state.GraceUntil then
		state.LastValid = position
		return "Ok", 0, false
	end

	local dt = now - lastTime
	local delta = position - lastPosition
	local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude / dt
	local rise = delta.Y / dt
	local allowed = limits.RunSpeed * limits.SpeedToleranceMultiplier + limits.SpeedToleranceFlat

	if
		horizontal > allowed * limits.CorrectionMultiplier
		or rise > limits.MaxRiseSpeed * limits.CorrectionMultiplier
	then
		state.LastPosition = state.LastValid -- the next sample measures from the corrected position
		return "Correct", horizontal, true
	end

	if horizontal > allowed or rise > limits.MaxRiseSpeed then
		table.insert(state.Flags, now)
		local cutoff = now - limits.FlagWindowSeconds
		while #state.Flags > 0 and state.Flags[1] < cutoff do
			table.remove(state.Flags, 1)
		end
		local reached = #state.Flags >= limits.FlagsBeforeSuspicion
		if reached then
			table.clear(state.Flags)
		end
		return "Flag", horizontal, reached
	end

	state.LastValid = position
	return "Ok", horizontal, false
end

return MovementValidator
