--!strict
--[[
	TEMPORARY DEVELOPMENT MAP (docs/ASSET_MANIFEST.md: DEV-MAP-002).
	"Outpost Yard" greybox: a compact 120x120 arena mirrored across X for duels and Team Deathmatch.
	Alpha spawns west, Bravo east. A raised centre with ramps, mid cover, flank walls and crates give
	short and medium sightlines; the long axis gives one exposed long lane.
]]

local CONCRETE = Color3.fromRGB(150, 140, 118)
local STEEL = Color3.fromRGB(90, 96, 92)
local SAND = Color3.fromRGB(186, 164, 120)
local OLIVE = Color3.fromRGB(96, 108, 70)

local blocks = {}
local function add(
	size: Vector3,
	position: Vector3,
	color: Color3?,
	material: Enum.Material?,
	wedge: boolean?,
	rotation: number?
)
	table.insert(blocks, {
		Size = size,
		Position = position,
		Color = color,
		Material = material,
		Wedge = wedge,
		Rotation = rotation,
	})
end
-- Mirror across X so both teams get identical cover.
local function mirror(size: Vector3, position: Vector3, color: Color3?, material: Enum.Material?)
	add(size, position, color, material)
	add(size, Vector3.new(-position.X, position.Y, position.Z), color, material)
end

add(Vector3.new(120, 2, 120), Vector3.new(0, -1, 0), SAND, Enum.Material.Sand)
for _, side in { 1, -1 } do
	add(Vector3.new(124, 14, 2), Vector3.new(0, 7, 61 * side), STEEL, Enum.Material.Metal)
	add(Vector3.new(2, 14, 124), Vector3.new(61 * side, 7, 0), STEEL, Enum.Material.Metal)
end

-- Raised centre (6 studs: reached by the ramps, not by jumping).
add(Vector3.new(12, 6, 12), Vector3.new(0, 3, 0), CONCRETE, Enum.Material.Concrete)
add(Vector3.new(8, 6, 10), Vector3.new(0, 3, 11), CONCRETE, Enum.Material.Concrete, true, 180)
add(Vector3.new(8, 6, 10), Vector3.new(0, 3, -11), CONCRETE, Enum.Material.Concrete, true, 0)

mirror(Vector3.new(2, 6, 14), Vector3.new(20, 3, 0), STEEL, Enum.Material.Metal) -- mid cover
mirror(Vector3.new(5, 4, 5), Vector3.new(30, 2, 20), OLIVE, Enum.Material.WoodPlanks)
mirror(Vector3.new(5, 4, 5), Vector3.new(30, 2, -20), OLIVE, Enum.Material.WoodPlanks)
mirror(Vector3.new(16, 8, 2), Vector3.new(38, 4, 32), STEEL, Enum.Material.Metal) -- flank walls
mirror(Vector3.new(16, 8, 2), Vector3.new(38, 4, -32), STEEL, Enum.Material.Metal)
mirror(Vector3.new(2, 3, 8), Vector3.new(42, 1.5, 0), CONCRETE, Enum.Material.Concrete) -- spawn shield

local spawns = {}
for _, team in { "A", "B" } do
	local x = if team == "A" then -50 else 50
	for _, z in { -15, -5, 5, 15 } do
		table.insert(
			spawns,
			{ Position = Vector3.new(x, 0.5, z), Facing = if team == "A" then -90 else 90, Team = team }
		)
	end
end

return table.freeze({
	Id = "dev_outpost_yard",
	DisplayName = "Outpost Yard (Greybox)",
	Modes = { "CasualDuel1v1", "CasualDuelTeam", "TeamDeathmatch" },
	KillHeight = -40,
	Lighting = {
		ClockTime = 16.5,
		Brightness = 2.2,
		Ambient = Color3.fromRGB(100, 92, 80),
		OutdoorAmbient = Color3.fromRGB(130, 120, 104),
	},
	Blocks = blocks,
	Spawns = spawns,
	Health = {
		{ Position = Vector3.new(28, 1.5, 0), Kind = "Small" },
		{ Position = Vector3.new(-28, 1.5, 0), Kind = "Small" },
		{ Position = Vector3.new(0, 7.5, 0), Kind = "Medium" },
	},
	Ammo = {
		{ Position = Vector3.new(14, 1.5, 24) },
		{ Position = Vector3.new(-14, 1.5, 24) },
		{ Position = Vector3.new(14, 1.5, -24) },
		{ Position = Vector3.new(-14, 1.5, -24) },
	},
	KnifeStations = {
		{ Position = Vector3.new(50, 1.5, 28) },
		{ Position = Vector3.new(-50, 1.5, 28) },
	},
	Portals = {},
	Stations = {},
	DummySpots = {},
})
