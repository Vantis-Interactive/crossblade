--!strict
--[[
	Server-side validation of client-proposed hits (spec §9).

	Model: "client proposes, server verifies". The client performs predictive hit detection against
	standardized hitboxes and reports (origin, direction, hit position, zone). The server:
	  1. checks the origin is near the shooter's rewound head (no shooting from the camera/elsewhere),
	  2. checks range,
	  3. checks the reported direction agrees with origin->hit within spread + tolerance,
	  4. re-runs the ray against the TARGET'S REWOUND standardized hitbox (bounded lag compensation),
	  5. determines the zone itself (headshots need the tighter head tolerance),
	  6. checks line of sight from origin to the hit against world geometry (injected function).
	Pure: world queries are injected so the logic is unit-testable.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)

export type LineOfSight = (from: Vector3, to: Vector3) -> boolean

export type ShotInput = {
	ShooterHead: Vector3, -- rewound head position of the shooter
	Origin: Vector3,
	Direction: Vector3, -- reported (should be unit)
	HitPosition: Vector3,
	ClaimedZone: Hitbox.Zone,
	TargetRoot: CFrame, -- rewound target root
	Range: number,
	SpreadDegrees: number,
	LineOfSight: LineOfSight,
	Tolerance: {
		MaxOriginDeviation: number,
		HitboxTolerance: number,
		HeadshotTolerance: number,
		DirectionToleranceDegrees: number,
		LineOfSightEndPadding: number,
	},
}

export type ShotResult = { Valid: boolean, Reason: string?, Zone: Hitbox.Zone?, Distance: number? }

export type MeleeInput = {
	Origin: Vector3,
	Direction: Vector3,
	ShooterHead: Vector3,
	TargetRoot: CFrame,
	Range: number,
	ConeDegrees: number,
	RangeTolerance: number,
	ConeToleranceDegrees: number,
	MaxOriginDeviation: number,
	LineOfSight: LineOfSight,
}

local HitValidator = {}

local function angleBetween(a: Vector3, b: Vector3): number
	local dot = math.clamp(a.Unit:Dot(b.Unit), -1, 1)
	return math.deg(math.acos(dot))
end

local function invalid(reason: string): ShotResult
	return { Valid = false, Reason = reason }
end

function HitValidator.ValidateShot(input: ShotInput): ShotResult
	local tol = input.Tolerance
	if input.Direction.Magnitude < 0.98 or input.Direction.Magnitude > 1.02 then
		return invalid("DirectionNotUnit")
	end
	if (input.Origin - input.ShooterHead).Magnitude > tol.MaxOriginDeviation then
		return invalid("OriginMismatch")
	end
	local toHit = input.HitPosition - input.Origin
	local distance = toHit.Magnitude
	if distance < 1e-3 then
		return invalid("DegenerateShot")
	end
	if distance > input.Range + tol.HitboxTolerance then
		return invalid("OutOfRange")
	end
	if angleBetween(input.Direction, toHit) > input.SpreadDegrees + tol.DirectionToleranceDegrees then
		return invalid("DirectionMismatch")
	end

	local rayDirection = toHit.Unit
	local maxDistance = distance + tol.HitboxTolerance * 2
	local generous = Hitbox.Shape(input.TargetRoot, tol.HitboxTolerance, tol.HeadshotTolerance)
	local hit = Hitbox.Raycast(generous, input.Origin, rayDirection, maxDistance)
	if hit == nil then
		return invalid("MissedRewoundHitbox")
	end

	-- Zone is decided by the server. A body claim is never upgraded; a head claim is confirmed only
	-- if the ray crosses the (tightly inflated) head sphere.
	local zone: Hitbox.Zone = "Body"
	if input.ClaimedZone == "Head" then
		local headT = Hitbox.RaySphere(input.Origin, rayDirection, generous.HeadCenter, generous.HeadRadius)
		if headT ~= nil and headT <= maxDistance then
			zone = "Head"
		end
	end

	local losEnd = input.Origin + rayDirection * math.max(0, hit.Distance - tol.LineOfSightEndPadding)
	if not input.LineOfSight(input.Origin, losEnd) then
		return invalid("NoLineOfSight")
	end

	return { Valid = true, Zone = zone, Distance = hit.Distance }
end

function HitValidator.ValidateMelee(input: MeleeInput): ShotResult
	if (input.Origin - input.ShooterHead).Magnitude > input.MaxOriginDeviation then
		return invalid("OriginMismatch")
	end
	local shape = Hitbox.Shape(input.TargetRoot)
	local distance = Hitbox.DistanceToPoint(shape, input.Origin)
	if distance > input.Range + input.RangeTolerance then
		return invalid("OutOfRange")
	end
	local toTarget = Hitbox.Center(input.TargetRoot) - input.Origin
	local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
	local facing = Vector3.new(input.Direction.X, 0, input.Direction.Z)
	-- Directly above/below or overlapping: cone check is meaningless, distance check suffices.
	if flat.Magnitude > 0.5 and facing.Magnitude > 0.01 then
		if angleBetween(facing, flat) > input.ConeDegrees / 2 + input.ConeToleranceDegrees then
			return invalid("OutsideCone")
		end
	end
	if not input.LineOfSight(input.Origin, Hitbox.Center(input.TargetRoot)) then
		return invalid("NoLineOfSight")
	end
	return { Valid = true, Zone = "Body", Distance = distance }
end

-- Clamps a client-reported timestamp into the permitted rewind window.
function HitValidator.RewindTime(
	serverNow: number,
	clientTime: number,
	maxRewind: number,
	maxFuture: number
): number?
	if clientTime > serverNow + maxFuture then
		return nil -- claims to be from the future: reject
	end
	return math.clamp(clientTime, serverNow - maxRewind, serverNow)
end

return HitValidator
