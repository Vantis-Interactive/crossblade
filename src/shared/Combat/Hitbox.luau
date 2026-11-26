--!strict
--[[
	Standardized combat hitboxes (spec §6). Every character, regardless of avatar, is represented by:
	  - Body: a vertical capsule in HumanoidRootPart space
	  - Head: a sphere in HumanoidRootPart space
	Hit detection on both client (prediction) and server (validation) uses ONLY this geometry.
	Pure math; no Instances.
]]

local Config = require(script.Parent.Parent.Config)

export type Zone = "Head" | "Body"
export type Hit = { Zone: Zone, Distance: number }

local Hitbox = {}

local EPSILON = 1e-6

export type Shape = {
	CapsuleA: Vector3,
	CapsuleB: Vector3,
	BodyRadius: number,
	HeadCenter: Vector3,
	HeadRadius: number,
}

-- World-space hitbox shape for a root CFrame, optionally inflated by `tolerance` studs.
function Hitbox.Shape(rootCFrame: CFrame, tolerance: number?, headTolerance: number?): Shape
	local h = Config.Player.Hitbox
	local inflate = tolerance or 0
	local bodyRadius = h.BodyRadius + inflate
	local up = rootCFrame.UpVector
	local root = rootCFrame.Position
	-- Capsule segment endpoints sit one (un-inflated) radius inside the capsule extremes.
	local a = root + up * (h.BodyBottom + h.BodyRadius)
	local b = root + up * (h.BodyTop - h.BodyRadius)
	return {
		CapsuleA = a,
		CapsuleB = b,
		BodyRadius = bodyRadius,
		HeadCenter = root + up * h.HeadOffset,
		HeadRadius = h.HeadRadius + (headTolerance or inflate),
	}
end

function Hitbox.ClosestPointOnSegment(a: Vector3, b: Vector3, point: Vector3): Vector3
	local ab = b - a
	local lengthSquared = ab:Dot(ab)
	if lengthSquared < EPSILON then
		return a
	end
	local t = math.clamp((point - a):Dot(ab) / lengthSquared, 0, 1)
	return a + ab * t
end

-- Distance along a unit ray to a sphere, or nil. Origin inside the sphere returns 0.
function Hitbox.RaySphere(origin: Vector3, direction: Vector3, center: Vector3, radius: number): number?
	local oc = origin - center
	local c = oc:Dot(oc) - radius * radius
	if c <= 0 then
		return 0
	end
	local b = oc:Dot(direction)
	if b > 0 then
		return nil -- outside and pointing away
	end
	local h = b * b - c
	if h < 0 then
		return nil
	end
	return -b - math.sqrt(h)
end

-- Distance along a unit ray to a capsule (segment a-b, radius r), or nil. Origin inside returns 0.
function Hitbox.RayCapsule(
	origin: Vector3,
	direction: Vector3,
	a: Vector3,
	b: Vector3,
	radius: number
): number?
	if (Hitbox.ClosestPointOnSegment(a, b, origin) - origin).Magnitude <= radius then
		return 0
	end
	local ba = b - a
	local oa = origin - a
	local baba = ba:Dot(ba)
	local bard = ba:Dot(direction)
	local baoa = ba:Dot(oa)
	local rdoa = direction:Dot(oa)
	local oaoa = oa:Dot(oa)
	local qa = baba - bard * bard
	local best: number? = nil
	if qa > EPSILON then
		local qb = baba * rdoa - baoa * bard
		local qc = baba * oaoa - baoa * baoa - radius * radius * baba
		local h = qb * qb - qa * qc
		if h >= 0 then
			local t = (-qb - math.sqrt(h)) / qa
			local y = baoa + t * bard
			if t >= 0 and y > 0 and y < baba then
				best = t
			end
		end
	end
	if best == nil then
		-- Hemispherical caps (also handles rays parallel to the axis).
		local ta = Hitbox.RaySphere(origin, direction, a, radius)
		local tb = Hitbox.RaySphere(origin, direction, b, radius)
		if ta and (best == nil or ta < best) then
			best = ta
		end
		if tb and (best == nil or tb < best) then
			best = tb
		end
	end
	return best
end

-- Nearest hit of a unit ray against a hitbox within maxDistance.
function Hitbox.Raycast(shape: Shape, origin: Vector3, direction: Vector3, maxDistance: number): Hit?
	local headT = Hitbox.RaySphere(origin, direction, shape.HeadCenter, shape.HeadRadius)
	local bodyT = Hitbox.RayCapsule(origin, direction, shape.CapsuleA, shape.CapsuleB, shape.BodyRadius)
	local result: Hit? = nil
	if bodyT and bodyT <= maxDistance then
		result = { Zone = "Body", Distance = bodyT }
	end
	-- Head wins ties and near-ties: the head sphere overlaps the top of the capsule.
	if headT and headT <= maxDistance and (result == nil or headT <= result.Distance + 0.25) then
		result = { Zone = "Head", Distance = headT }
	end
	return result
end

-- Shortest distance from a point to the hitbox surface (0 if inside), and the zone that is closest.
function Hitbox.DistanceToPoint(shape: Shape, point: Vector3): (number, Zone)
	local bodyDistance = (Hitbox.ClosestPointOnSegment(shape.CapsuleA, shape.CapsuleB, point) - point).Magnitude
		- shape.BodyRadius
	local headDistance = (shape.HeadCenter - point).Magnitude - shape.HeadRadius
	if headDistance < bodyDistance then
		return math.max(0, headDistance), "Head"
	end
	return math.max(0, bodyDistance), "Body"
end

-- Centre of mass used for aim cones and spawn scoring.
function Hitbox.Center(rootCFrame: CFrame): Vector3
	return rootCFrame.Position
end

return Hitbox
