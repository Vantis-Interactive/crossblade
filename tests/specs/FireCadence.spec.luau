--!nocheck
local FireCadence = Runtime:Get("ReplicatedStorage/Shared/Combat/FireCadence")

describe("FireCadence", function()
	local interval = FireCadence.IntervalForRpm(600) -- 0.1s

	it("accepts shots at the weapon's fire rate", function()
		local cadence = FireCadence.new(interval, 3)
		for i = 0, 50 do
			expect((FireCadence.TryFire(cadence, i * interval))).toBe(true)
		end
	end)

	it("rejects shots that are impossibly close together", function()
		local cadence = FireCadence.new(interval, 3)
		expect((FireCadence.TryFire(cadence, 0))).toBe(true)
		local ok, reason = FireCadence.TryFire(cadence, 0.02)
		expect(ok).toBe(false)
		expect(reason).toBe("TooSoon")
	end)

	it("tolerates network jitter in packet spacing", function()
		local cadence = FireCadence.new(interval, 3)
		expect((FireCadence.TryFire(cadence, 0))).toBe(true)
		expect((FireCadence.TryFire(cadence, 0.08))).toBe(true) -- 20% early
	end)

	it("bounds the sustained rate even when every shot exploits the jitter tolerance", function()
		local cadence = FireCadence.new(interval, 3)
		local accepted = 0
		local t = 0
		for _ = 1, 200 do
			if FireCadence.TryFire(cadence, t) then
				accepted += 1
			end
			t += interval * 0.76 -- just over the minimum spacing
		end
		local duration = t
		local maxLegit = duration / interval + 3 -- true rate plus burst
		expect(accepted).toBeAtMost(math.ceil(maxLegit))
	end)
end)

describe("PositionHistory", function()
	local PositionHistory = Runtime:Get("ReplicatedStorage/Shared/Combat/PositionHistory")

	it("interpolates between samples", function()
		local history = PositionHistory.new(4)
		PositionHistory.Push(history, 0, CFrame.new(0, 0, 0))
		PositionHistory.Push(history, 1, CFrame.new(10, 0, 0))
		expect(PositionHistory.At(history, 0.5).Position.X).toBeNear(5, 1e-2) -- Vector3 is float32
	end)

	it("clamps to the newest and oldest samples", function()
		local history = PositionHistory.new(3)
		for i = 1, 5 do
			PositionHistory.Push(history, i, CFrame.new(i, 0, 0))
		end
		expect(PositionHistory.At(history, 99).Position.X).toBe(5)
		expect(PositionHistory.At(history, -99).Position.X).toBe(3) -- capacity 3 keeps 3..5
		expect(PositionHistory.Latest(history).Time).toBe(5)
	end)

	it("returns nil when empty", function()
		expect(PositionHistory.At(PositionHistory.new(2), 1)).toBeNil()
	end)
end)
