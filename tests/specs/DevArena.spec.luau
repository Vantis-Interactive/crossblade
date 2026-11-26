--!nocheck
local DevArena = Runtime:Get("ServerScriptService/Server/Maps/DevArena")

-- Axis-aligned bounds of a block (all greybox blocks rotate only about Y in 90/180 degree steps).
local function bounds(block)
	local size = block.Size
	local rotation = (block.Rotation or 0) % 180
	if rotation == 90 then
		size = Vector3.new(size.Z, size.Y, size.X)
	end
	return block.Position - size / 2, block.Position + size / 2
end

local function inside(point, margin)
	for index, block in DevArena.Blocks do
		local low, high = bounds(block)
		-- The floor is excluded: markers sit on top of it.
		if
			index > 1
			and point.X > low.X - margin
			and point.X < high.X + margin
			and point.Z > low.Z - margin
			and point.Z < high.Z + margin
			and point.Y > low.Y
			and point.Y < high.Y + 0.5
		then
			return index
		end
	end
	return nil
end

describe("DevArena layout", function()
	it("has 16 spawns and the planned pickup counts", function()
		expect(#DevArena.Spawns).toBe(16)
		expect(#DevArena.Health).toBe(7)
		expect(#DevArena.Ammo).toBe(4)
		expect(#DevArena.KnifeStations).toBe(2)
	end)

	it("places no pickup or knife station inside geometry", function()
		local problems = {}
		for _, list in { DevArena.Health, DevArena.Ammo, DevArena.KnifeStations } do
			for _, marker in list do
				local hit = inside(marker.Position, 0.5)
				-- The Large pack intentionally sits ON the central platform (block 2); allow standing on top.
				if hit and not (marker.Kind == "Large") then
					table.insert(problems, `{tostring(marker.Position)} inside block {hit}`)
				end
			end
		end
		expect(#problems).toBe(0)
	end)

	it("places no spawn inside or within 2 studs of geometry", function()
		local problems = {}
		for _, spawn in DevArena.Spawns do
			local hit = inside(spawn.Position + Vector3.new(0, 1, 0), 2)
			if hit then
				table.insert(problems, `{tostring(spawn.Position)} near block {hit}`)
			end
		end
		expect(#problems).toBe(0)
	end)

	it("keeps every marker inside the perimeter and above the kill height", function()
		for _, list in { DevArena.Spawns, DevArena.Health, DevArena.Ammo, DevArena.KnifeStations } do
			for _, marker in list do
				expect(math.abs(marker.Position.X)).toBeLessThan(89)
				expect(math.abs(marker.Position.Z)).toBeLessThan(89)
				expect(marker.Position.Y).toBeGreaterThan(DevArena.KillHeight)
			end
		end
	end)
end)
