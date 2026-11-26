--!strict
-- Decaying per-player suspicion score (spec §25). Scores inform review; they never ban on their own.

export type State = {
	Score: number,
	Updated: number,
	Events: { { Kind: string, Time: number, Weight: number } },
}

local SuspicionScore = {}

local MAX_EVENTS = 50

function SuspicionScore.new(now: number): State
	return { Score = 0, Updated = now, Events = {} }
end

function SuspicionScore.Current(state: State, now: number, decayPerMinute: number): number
	local elapsedMinutes = math.max(0, now - state.Updated) / 60
	state.Score = math.max(0, state.Score - elapsedMinutes * decayPerMinute)
	state.Updated = now
	return state.Score
end

function SuspicionScore.Add(
	state: State,
	kind: string,
	weight: number,
	now: number,
	decayPerMinute: number
): number
	SuspicionScore.Current(state, now, decayPerMinute)
	state.Score += weight
	table.insert(state.Events, { Kind = kind, Time = now, Weight = weight })
	if #state.Events > MAX_EVENTS then
		table.remove(state.Events, 1)
	end
	return state.Score
end

return SuspicionScore
