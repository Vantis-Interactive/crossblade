--!nocheck
local Schema = Runtime:Get("ReplicatedStorage/Shared/Net/Schema")
local Contracts = Runtime:Get("ReplicatedStorage/Shared/Net/Contracts")

local function fire(overrides)
	local payload = {
		Slot = "Primary",
		ShotId = 1,
		ClientTime = 100,
		Origin = Vector3.new(0, 5, 0),
		Direction = Vector3.new(0, 0, -1),
		Hits = { { TargetUserId = 2, Position = Vector3.new(0, 5, -20), Zone = "Body", Pellet = 1 } },
	}
	for key, value in overrides or {} do
		payload[key] = value
	end
	return payload
end

local FIRE = Contracts.ClientToServer.FireWeapon.Payload

describe("Net schema validation", function()
	it("accepts a well-formed fire request", function()
		expect((Schema.Check(FIRE, fire()))).toBe(true)
	end)

	it("rejects non-table payloads and Instances-like values", function()
		for _, bad in { nil, 1, "x", true, Vector3.new() } do
			expect((Schema.Check(FIRE, bad))).toBe(false)
		end
	end)

	it("rejects NaN, infinity and non-integers", function()
		expect((Schema.Check(FIRE, fire({ ClientTime = 0 / 0 })))).toBe(false)
		expect((Schema.Check(FIRE, fire({ ClientTime = math.huge })))).toBe(false)
		expect((Schema.Check(FIRE, fire({ ShotId = 1.5 })))).toBe(false)
		expect((Schema.Check(FIRE, fire({ Origin = Vector3.new(0 / 0, 0, 0) })))).toBe(false)
		expect((Schema.Check(FIRE, fire({ Origin = Vector3.new(math.huge, 0, 0) })))).toBe(false)
	end)

	it("rejects out-of-range values and oversized vectors", function()
		expect((Schema.Check(FIRE, fire({ Direction = Vector3.new(0, 0, -50) })))).toBe(false)
		expect((Schema.Check(FIRE, fire({ Origin = Vector3.new(1e7, 0, 0) })))).toBe(false)
		expect((Schema.Check(FIRE, fire({ ShotId = -1 })))).toBe(false)
	end)

	it("rejects unknown enum values and wrong types", function()
		expect((Schema.Check(FIRE, fire({ Slot = "Knife" })))).toBe(false)
		expect((Schema.Check(FIRE, fire({ Slot = 1 })))).toBe(false)
		expect((Schema.Check(FIRE, fire({ Direction = { 0, 0, -1 } })))).toBe(false)
	end)

	it("rejects unexpected fields (no smuggled data)", function()
		local payload = fire()
		payload.Damage = 9999
		expect((Schema.Check(FIRE, payload))).toBe(false)
		local nested = fire()
		nested.Hits[1].Damage = 9999
		expect((Schema.Check(FIRE, nested))).toBe(false)
	end)

	it("rejects oversized, sparse and keyed arrays", function()
		local many = {}
		for i = 1, 17 do
			many[i] = { TargetUserId = 2, Position = Vector3.new(), Zone = "Body", Pellet = 1 }
		end
		expect((Schema.Check(FIRE, fire({ Hits = many })))).toBe(false)
		expect((Schema.Check(FIRE, fire({ Hits = { [1] = many[1], [3] = many[1] } })))).toBe(false)
		expect((Schema.Check(FIRE, fire({ Hits = { a = many[1] } })))).toBe(false)
	end)

	it("treats missing required fields as invalid but allows optional ones", function()
		local payload = fire()
		payload.Origin = nil
		expect((Schema.Check(FIRE, payload))).toBe(false)
		local melee = Contracts.ClientToServer.MeleeAttack.Payload
		local ok = Schema.Check(melee, {
			Attack = "Slash",
			ClientTime = 1,
			Origin = Vector3.new(),
			Direction = Vector3.new(0, 0, -1),
		})
		expect(ok).toBe(true)
	end)

	it("every client contract declares a payload schema and a rate limit", function()
		for _, contract in Contracts.ClientToServer do
			expect(type(contract.Payload)).toBe("table")
			expect(contract.RateCapacity).toBeGreaterThan(0)
			expect(contract.RatePerSecond).toBeGreaterThan(0)
			expect(
				contract.Kind == "Event" or contract.Kind == "UnreliableEvent" or contract.Kind == "Function"
			).toBe(true)
		end
	end)
end)
