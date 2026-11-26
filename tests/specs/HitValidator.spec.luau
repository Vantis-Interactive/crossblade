--!nocheck
local HitValidator = Runtime:Get("ServerScriptService/Server/Domain/HitValidator")
local Config = Runtime:Get("ReplicatedStorage/Shared/Config")
local PositionHistory = Runtime:Get("ReplicatedStorage/Shared/Combat/PositionHistory")

local V = Config.Combat.Validation
local H = Config.Player.Hitbox
local TOLERANCE = {
	MaxOriginDeviation = V.MaxOriginDeviation,
	HitboxTolerance = V.HitboxTolerance,
	HeadshotTolerance = V.HeadshotTolerance,
	DirectionToleranceDegrees = V.DirectionToleranceDegrees,
	LineOfSightEndPadding = V.LineOfSightEndPadding,
}

local function clear()
	return true
end

local function shot(overrides)
	local input = {
		ShooterHead = Vector3.new(0, 5, 0),
		Origin = Vector3.new(0, 5, 0),
		Direction = Vector3.new(0, 0, -1),
		HitPosition = Vector3.new(0, 5, -50 + H.BodyRadius),
		ClaimedZone = "Body",
		TargetRoot = CFrame.new(0, 5, -50),
		Range = 300,
		SpreadDegrees = 2,
		LineOfSight = clear,
		Tolerance = TOLERANCE,
	}
	for key, value in overrides or {} do
		input[key] = value
	end
	return input
end

describe("HitValidator.ValidateShot", function()
	it("accepts a legitimate body shot", function()
		local result = HitValidator.ValidateShot(shot())
		expect(result.Valid).toBe(true)
		expect(result.Zone).toBe("Body")
	end)

	it("rejects shots whose origin is far from the shooter's head", function()
		local result = HitValidator.ValidateShot(shot({ Origin = Vector3.new(0, 5, -30) }))
		expect(result.Reason).toBe("OriginMismatch")
	end)

	it("rejects out-of-range hits", function()
		local result = HitValidator.ValidateShot(shot({ Range = 20 }))
		expect(result.Reason).toBe("OutOfRange")
	end)

	it("rejects a reported direction that does not point at the hit", function()
		local result = HitValidator.ValidateShot(shot({ Direction = Vector3.new(1, 0, 0) }))
		expect(result.Reason).toBe("DirectionMismatch")
	end)

	it("rejects non-unit directions", function()
		local result = HitValidator.ValidateShot(shot({ Direction = Vector3.new(0, 0, -0.5) }))
		expect(result.Reason).toBe("DirectionNotUnit")
	end)

	it("rejects hits through walls", function()
		local result = HitValidator.ValidateShot(shot({
			LineOfSight = function()
				return false
			end,
		}))
		expect(result.Reason).toBe("NoLineOfSight")
	end)

	it("rejects hits on a target that was not there at the rewound time", function()
		local result = HitValidator.ValidateShot(shot({ TargetRoot = CFrame.new(15, 5, -50) }))
		expect(result.Reason).toBe("MissedRewoundHitbox")
	end)

	it("downgrades an unjustified headshot claim to a body hit", function()
		local result = HitValidator.ValidateShot(shot({ ClaimedZone = "Head" }))
		expect(result.Valid).toBe(true)
		expect(result.Zone).toBe("Body")
	end)

	it("confirms a genuine headshot", function()
		local target = CFrame.new(0, 5 - H.HeadOffset, -50)
		local result = HitValidator.ValidateShot(shot({
			TargetRoot = target,
			ClaimedZone = "Head",
			HitPosition = Vector3.new(0, 5, -50 + H.HeadRadius),
		}))
		expect(result.Valid).toBe(true)
		expect(result.Zone).toBe("Head")
	end)

	it("never upgrades a body claim to a headshot", function()
		local target = CFrame.new(0, 5 - H.HeadOffset, -50)
		local result = HitValidator.ValidateShot(shot({
			TargetRoot = target,
			ClaimedZone = "Body",
			HitPosition = Vector3.new(0, 5, -50 + H.HeadRadius),
		}))
		expect(result.Zone).toBe("Body")
	end)
end)

describe("HitValidator.RewindTime", function()
	local L = Config.Combat.LagCompensation
	it("clamps rewind to the configured maximum", function()
		expect(HitValidator.RewindTime(100, 99, L.MaxRewindSeconds, L.MaxFutureSeconds)).toBe(
			100 - L.MaxRewindSeconds
		)
		expect(HitValidator.RewindTime(100, 99.9, L.MaxRewindSeconds, L.MaxFutureSeconds)).toBeNear(
			99.9,
			1e-9
		)
	end)
	it("rejects timestamps from the future", function()
		expect(HitValidator.RewindTime(100, 100.5, L.MaxRewindSeconds, L.MaxFutureSeconds)).toBeNil()
		expect(HitValidator.RewindTime(100, 100.01, L.MaxRewindSeconds, L.MaxFutureSeconds)).toBe(100)
	end)
end)

describe("Lag compensation with PositionHistory", function()
	it("validates a hit against where the target was, not where it is now", function()
		local history = PositionHistory.new(20)
		for i = 0, 10 do
			-- target strafes at 20 studs/s along +X
			PositionHistory.Push(history, 100 + i * 0.05, CFrame.new(i * 0.05 * 20, 5, -50))
		end
		local now = 100.5
		local rewound = PositionHistory.At(history, now - 0.2)
		local hitX = rewound.Position.X
		local input = shot({
			TargetRoot = rewound,
			HitPosition = Vector3.new(hitX, 5, -50 + H.BodyRadius),
			Direction = (Vector3.new(hitX, 5, -50) - Vector3.new(0, 5, 0)).Unit,
		})
		expect(HitValidator.ValidateShot(input).Valid).toBe(true)
		-- The same claim checked against the current position (6 studs later) fails.
		input.TargetRoot = PositionHistory.At(history, now)
		expect(HitValidator.ValidateShot(input).Valid).toBe(false)
	end)
end)

describe("HitValidator.ValidateMelee", function()
	local knife = Config.Archetypes.CombatKnife.Knife.Slash
	local function melee(overrides)
		local input = {
			Origin = Vector3.new(0, 5, 0),
			Direction = Vector3.new(0, 0, -1),
			ShooterHead = Vector3.new(0, 5, 0),
			TargetRoot = CFrame.new(0, 3.5, -4),
			Range = knife.Range,
			ConeDegrees = knife.ConeDegrees,
			RangeTolerance = Config.Combat.Melee.RangeTolerance,
			ConeToleranceDegrees = Config.Combat.Melee.ConeToleranceDegrees,
			MaxOriginDeviation = V.MaxOriginDeviation,
			LineOfSight = clear,
		}
		for key, value in overrides or {} do
			input[key] = value
		end
		return input
	end

	it("accepts a target in front and in reach", function()
		expect(HitValidator.ValidateMelee(melee()).Valid).toBe(true)
	end)
	it("rejects targets out of reach", function()
		expect(HitValidator.ValidateMelee(melee({ TargetRoot = CFrame.new(0, 3.5, -20) })).Reason).toBe(
			"OutOfRange"
		)
	end)
	it("rejects targets behind the attacker", function()
		expect(HitValidator.ValidateMelee(melee({ TargetRoot = CFrame.new(0, 3.5, 5) })).Reason).toBe(
			"OutsideCone"
		)
	end)
	it("rejects attacks through walls", function()
		local blocked = melee({
			LineOfSight = function()
				return false
			end,
		})
		expect(HitValidator.ValidateMelee(blocked).Reason).toBe("NoLineOfSight")
	end)
end)
