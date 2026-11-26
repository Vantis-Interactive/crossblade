--!nocheck
local MAPS = {
	Runtime:Get("ServerScriptService/Server/Maps/DevArena"),
	Runtime:Get("ServerScriptService/Server/Maps/DevOutpost"),
	Runtime:Get("ServerScriptService/Server/Maps/DevHub"),
}
local DevArena = MAPS[1]
local Config = Runtime:Get("ReplicatedStorage/Shared/Config")

-- Axis-aligned bounds of a block (all greybox blocks rotate only about Y in 90/180 degree steps).
local function bounds(block)
	local size = block.Size
	local rotation = (block.Rotation or 0) % 180
	if rotation == 90 then
		size = Vector3.new(size.Z, size.Y, size.X)
	end
	return block.Position - size / 2, block.Position + size / 2
end

local function inside(map, point, margin)
	for index, block in map.Blocks do
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

describe("Foundry Yard layout", function()
	it("has 16 spawns and the planned pickup counts", function()
		expect(#DevArena.Spawns).toBe(16)
		expect(#DevArena.Health).toBe(7)
		expect(#DevArena.Ammo).toBe(4)
		expect(#DevArena.KnifeStations).toBe(2)
	end)
end)

for _, map in MAPS do
	describe(`Map layout {map.Id}`, function()
		it("declares implemented modes and a display name", function()
			expect(#map.Modes).toBeGreaterThan(0)
			for _, mode in map.Modes do
				expect(Config.GameModes[mode].Implemented).toBe(true)
			end
			expect(type(map.DisplayName)).toBe("string")
		end)

		it("places no pickup, station or portal inside geometry", function()
			local problems = {}
			for _, list in { map.Health, map.Ammo, map.KnifeStations, map.Stations, map.DummySpots } do
				for _, marker in list do
					local hit = inside(map, marker.Position + Vector3.new(0, 0.5, 0), 0.5)
					if hit then
						table.insert(problems, `{tostring(marker.Position)} inside block {hit}`)
					end
				end
			end
			expect(#problems).toBe(0)
		end)

		it("places no spawn inside or within 2 studs of geometry", function()
			local problems = {}
			for _, spawn in map.Spawns do
				local hit = inside(map, spawn.Position + Vector3.new(0, 1, 0), 2)
				if hit then
					table.insert(problems, `{tostring(spawn.Position)} near block {hit}`)
				end
			end
			expect(#problems).toBe(0)
		end)

		it("keeps every marker inside the perimeter and above the kill height", function()
			local half = map.Blocks[1].Size.X / 2 - 1
			for _, list in
				{
					map.Spawns,
					map.Health,
					map.Ammo,
					map.KnifeStations,
					map.Portals,
					map.Stations,
					map.DummySpots,
				}
			do
				for _, marker in list do
					expect(math.abs(marker.Position.X)).toBeLessThan(half)
					expect(math.abs(marker.Position.Z)).toBeLessThan(half)
					expect(marker.Position.Y).toBeGreaterThan(map.KillHeight)
				end
			end
		end)

		it("gives team modes balanced team spawns", function()
			local teamMode = table.find(map.Modes, "TeamDeathmatch") or table.find(map.Modes, "CasualDuel1v1")
			if teamMode then
				local counts = { A = 0, B = 0 }
				for _, spawn in map.Spawns do
					if spawn.Team then
						counts[spawn.Team] += 1
					end
				end
				expect(counts.A).toBe(counts.B)
				expect(counts.A).toBeGreaterThan(3)
			end
		end)
	end)
end
