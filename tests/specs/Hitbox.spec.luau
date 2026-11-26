--!nocheck
local Hitbox = Runtime:Get("ReplicatedStorage/Shared/Combat/Hitbox")
local Config = Runtime:Get("ReplicatedStorage/Shared/Config")

local root = CFrame.new(0, 3, 0)
local shape = Hitbox.Shape(root)
local H = Config.Player.Hitbox

describe("Hitbox", function()
	it("hits the body from the front", function()
		local hit = Hitbox.Raycast(shape, Vector3.new(0, 3, -20), Vector3.new(0, 0, 1), 100)
		expect(hit.Zone).toBe("Body")
		expect(hit.Distance).toBeNear(20 - H.BodyRadius, 1e-2) -- Vector3 is float32
	end)

	it("hits the head when aimed at head height", function()
		local hit = Hitbox.Raycast(shape, Vector3.new(0, 3 + H.HeadOffset, -20), Vector3.new(0, 0, 1), 100)
		expect(hit.Zone).toBe("Head")
		expect(hit.Distance).toBeNear(20 - H.HeadRadius, 1e-2) -- Vector3 is float32
	end)

	it("misses beside the target and beyond max distance", function()
		expect(Hitbox.Raycast(shape, Vector3.new(5, 3, -20), Vector3.new(0, 0, 1), 100)).toBeNil()
		expect(Hitbox.Raycast(shape, Vector3.new(0, 3, -20), Vector3.new(0, 0, 1), 10)).toBeNil()
		expect(Hitbox.Raycast(shape, Vector3.new(0, 3, -20), Vector3.new(0, 0, -1), 100)).toBeNil()
	end)

	it("handles rays parallel to the capsule axis and origins inside", function()
		local fromAbove = Hitbox.Raycast(shape, Vector3.new(0, 30, 0), Vector3.new(0, -1, 0), 100)
		expect(fromAbove.Zone).toBe("Head")
		local fromBelow = Hitbox.Raycast(shape, Vector3.new(0, -30, 0), Vector3.new(0, 1, 0), 100)
		expect(fromBelow.Zone).toBe("Body")
		local inside = Hitbox.Raycast(shape, Vector3.new(0, 3, 0), Vector3.new(1, 0, 0), 100)
		expect(inside.Distance).toBe(0)
	end)

	it("inflation by tolerance widens the hitbox", function()
		local origin = Vector3.new(H.BodyRadius + 0.5, 3, -20)
		expect(Hitbox.Raycast(shape, origin, Vector3.new(0, 0, 1), 100)).toBeNil()
		local inflated = Hitbox.Shape(root, 0.9)
		expect(Hitbox.Raycast(inflated, origin, Vector3.new(0, 0, 1), 100)).never.toBeNil()
	end)

	it("follows the root orientation (rotated character)", function()
		local tilted = Hitbox.Shape(CFrame.new(0, 3, 0) * CFrame.Angles(0, 0, math.rad(90)))
		-- Lying on its side: the head is now along -X.
		local hit = Hitbox.Raycast(tilted, Vector3.new(-H.HeadOffset, 3, -20), Vector3.new(0, 0, 1), 100)
		expect(hit.Zone).toBe("Head")
	end)

	it("measures distance to a point", function()
		local distance, zone = Hitbox.DistanceToPoint(shape, Vector3.new(5, 3, 0))
		expect(zone).toBe("Body")
		expect(distance).toBeNear(5 - H.BodyRadius, 1e-2) -- Vector3 is float32
	end)
end)
