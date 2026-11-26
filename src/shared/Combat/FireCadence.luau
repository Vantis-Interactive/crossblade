--!strict
--[[
	Server fire-rate enforcement (spec §9 "attack cooldown", §25 "impossible attack rates").
	Two checks, both must pass:
	  1. Minimum spacing: shots closer together than Interval * (1 - JitterTolerance) are rejected.
	     The tolerance absorbs network jitter that bunches legitimately-spaced packets.
	  2. Average rate: a token bucket (Burst capacity, refilled at 1 token per Interval) bounds the
	     sustained rate to the weapon's true fire rate, so jitter tolerance cannot be exploited.
]]

export type FireCadence = {
	Interval: number,
	JitterTolerance: number,
	Burst: number,
	Tokens: number,
	LastShot: number?,
	LastRefill: number?,
}

local FireCadence = {}

function FireCadence.new(interval: number, burst: number, jitterTolerance: number?): FireCadence
	return {
		Interval = interval,
		JitterTolerance = jitterTolerance or 0.25,
		Burst = burst,
		Tokens = burst,
		LastShot = nil,
		LastRefill = nil,
	}
end

function FireCadence.IntervalForRpm(rpm: number): number
	return 60 / rpm
end

function FireCadence.TryFire(cadence: FireCadence, now: number): (boolean, string?)
	local lastRefill = cadence.LastRefill
	if lastRefill ~= nil then
		cadence.Tokens = math.min(cadence.Burst, cadence.Tokens + (now - lastRefill) / cadence.Interval)
	end
	cadence.LastRefill = now

	local lastShot = cadence.LastShot
	if lastShot ~= nil and now - lastShot < cadence.Interval * (1 - cadence.JitterTolerance) then
		return false, "TooSoon"
	end
	if cadence.Tokens < 1 then
		return false, "RateExceeded"
	end
	cadence.Tokens -= 1
	cadence.LastShot = now
	return true, nil
end

-- Pure cooldown check used for melee/throws where no burst is permitted.
function FireCadence.Reset(cadence: FireCadence)
	cadence.Tokens = cadence.Burst
	cadence.LastShot = nil
	cadence.LastRefill = nil
end

return FireCadence
