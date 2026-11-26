--!strict
--[[
	Fixed-size ring buffer of timestamped root CFrames used for bounded lag compensation (spec §9).
	At(time) returns the interpolated CFrame at `time`, clamped to the stored window.
]]

export type Sample = { Time: number, CFrame: CFrame }

export type PositionHistory = {
	Capacity: number,
	Samples: { Sample },
	Head: number, -- index of the most recent sample
	Count: number,
}

local PositionHistory = {}

function PositionHistory.new(capacity: number): PositionHistory
	assert(capacity >= 2, "history needs at least two samples")
	return { Capacity = capacity, Samples = table.create(capacity), Head = 0, Count = 0 }
end

function PositionHistory.Push(history: PositionHistory, time: number, cframe: CFrame)
	local index = history.Head % history.Capacity + 1
	history.Samples[index] = { Time = time, CFrame = cframe }
	history.Head = index
	history.Count = math.min(history.Count + 1, history.Capacity)
end

function PositionHistory.Clear(history: PositionHistory)
	table.clear(history.Samples)
	history.Head = 0
	history.Count = 0
end

-- i = 0 is newest, i = Count - 1 is oldest.
local function sampleAt(history: PositionHistory, i: number): Sample
	local index = (history.Head - 1 - i) % history.Capacity + 1
	return history.Samples[index]
end

function PositionHistory.Latest(history: PositionHistory): Sample?
	if history.Count == 0 then
		return nil
	end
	return sampleAt(history, 0)
end

function PositionHistory.At(history: PositionHistory, time: number): CFrame?
	if history.Count == 0 then
		return nil
	end
	local newest = sampleAt(history, 0)
	if time >= newest.Time then
		return newest.CFrame
	end
	for i = 1, history.Count - 1 do
		local older = sampleAt(history, i)
		local newer = sampleAt(history, i - 1)
		if time >= older.Time then
			local span = newer.Time - older.Time
			if span <= 0 then
				return newer.CFrame
			end
			return older.CFrame:Lerp(newer.CFrame, (time - older.Time) / span)
		end
	end
	return sampleAt(history, history.Count - 1).CFrame -- older than the window: clamp to oldest
end

return PositionHistory
