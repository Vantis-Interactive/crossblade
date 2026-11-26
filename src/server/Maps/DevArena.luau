--!strict
--[[
	TEMPORARY DEVELOPMENT MAP (docs/ASSET_MANIFEST.md: DEV-MAP-001).
	"Foundry Yard" greybox: a symmetric 180x180 arena used to make the Phase 2 vertical slice
	playable. It exercises every map contract (spawns, pickups, knife stations, cover, elevation,
	short and long sightlines, boundaries). Studio-authored maps replace it by providing a Model in
	ServerStorage.Maps using the same CollectionService tags (see docs/MAP_DESIGN.md).

	Coordinates: X/Z in studs, floor top at Y = 0.
]]

export type Block = {
	Size: Vector3,
	Position: Vector3,
	Color: Color3?,
	Material: Enum.Material?,
	Wedge: boolean?,
	Rotation: number?,
	Transparent: boolean?,
}
export type Marker = { Position: Vector3, Kind: string?, Facing: number? }

local CONCRETE = Color3.fromRGB(122, 124, 118)
local STEEL = Color3.fromRGB(84, 90, 92)
local RUST = Color3.fromRGB(140, 92, 60)
local OLIVE = Color3.fromRGB(96, 108, 70)

local blocks: { Block } = {}

local function add(size: Vector3, position: Vector3, color: Color3?, material: Enum.Material?)
	table.insert(blocks, { Size = size, Position = position, Color = color, Material = material })
end

-- Mirror a block into all four quadrants (symmetry keeps the arena fair).
local function quad(size: Vector3, position: Vector3, color: Color3?, material: Enum.Material?)
	for _, sx in { 1, -1 } do
		for _, sz in { 1, -1 } do
			local swap = sx * sz < 0
			local s = if swap then Vector3.new(size.Z, size.Y, size.X) else size
			local p = if swap
				then Vector3.new(position.Z * sx, position.Y, position.X * sz)
				else Vector3.new(position.X * sx, position.Y, position.Z * sz)
			add(s, p, color, material)
		end
	end
end

-- Floor and perimeter.
add(Vector3.new(180, 2, 180), Vector3.new(0, -1, 0), CONCRETE, Enum.Material.Concrete)
for _, side in { 1, -1 } do
	add(Vector3.new(184, 16, 2), Vector3.new(0, 8, 91 * side), STEEL, Enum.Material.Metal)
	add(Vector3.new(2, 16, 184), Vector3.new(91 * side, 8, 0), STEEL, Enum.Material.Metal)
end

-- Central raised platform with two ramps (contested Large health on top).
add(Vector3.new(28, 6, 28), Vector3.new(0, 3, 0), RUST, Enum.Material.CorrodedMetal)
table.insert(blocks, {
	Size = Vector3.new(10, 6, 14),
	Position = Vector3.new(0, 3, 21),
	Color = RUST,
	Material = Enum.Material.CorrodedMetal,
	Wedge = true,
	Rotation = 180,
})
table.insert(blocks, {
	Size = Vector3.new(10, 6, 14),
	Position = Vector3.new(0, 3, -21),
	Color = RUST,
	Material = Enum.Material.CorrodedMetal,
	Wedge = true,
	Rotation = 0,
})
-- Low parapets on the platform for partial cover.
add(Vector3.new(8, 2.5, 1), Vector3.new(9, 7.25, 13.5), STEEL, Enum.Material.Metal)
add(Vector3.new(8, 2.5, 1), Vector3.new(-9, 7.25, -13.5), STEEL, Enum.Material.Metal)

-- Mid-quadrant L-shaped cover walls.
quad(Vector3.new(18, 8, 2), Vector3.new(38, 4, 30), STEEL, Enum.Material.Metal)
quad(Vector3.new(2, 8, 12), Vector3.new(46, 4, 25), STEEL, Enum.Material.Metal)
-- Crate clusters (head-height and waist-height cover).
quad(Vector3.new(5, 5, 5), Vector3.new(20, 2.5, 52), OLIVE, Enum.Material.WoodPlanks)
quad(Vector3.new(5, 3, 5), Vector3.new(25, 1.5, 52), OLIVE, Enum.Material.WoodPlanks)
quad(Vector3.new(4, 4, 4), Vector3.new(62, 2, 8), OLIVE, Enum.Material.WoodPlanks)
-- Long-lane pillars (break up sniper lines along the outer lanes).
quad(Vector3.new(3, 12, 3), Vector3.new(70, 6, 45), CONCRETE, Enum.Material.Concrete)
quad(Vector3.new(3, 12, 3), Vector3.new(70, 6, 70), CONCRETE, Enum.Material.Concrete)
-- Corner towers: elevated, exposed long-range positions. Jump height with the configured
-- JumpPower (50) and gravity (196.2) is ~6.4 studs, so the 5-stud tower is reached via a 2.5-stud step.
quad(Vector3.new(12, 5, 12), Vector3.new(76, 2.5, 76), STEEL, Enum.Material.DiamondPlate)
quad(Vector3.new(4, 2.5, 4), Vector3.new(67, 1.25, 76), OLIVE, Enum.Material.WoodPlanks)

local spawns: { Marker } = {}
for i = 0, 15 do
	local angle = (i / 16) * math.pi * 2
	local radius = if i % 2 == 0 then 80 else 66
	local position = Vector3.new(math.cos(angle) * radius, 0.5, math.sin(angle) * radius)
	-- Face the arena centre.
	table.insert(spawns, { Position = position, Facing = math.deg(math.atan2(-position.X, -position.Z)) })
end

local function quadMarkers(position: Vector3, kind: string?): { Marker }
	local result = {}
	for _, sx in { 1, -1 } do
		for _, sz in { 1, -1 } do
			table.insert(
				result,
				{ Position = Vector3.new(position.X * sx, position.Y, position.Z * sz), Kind = kind }
			)
		end
	end
	return result
end

local health: { Marker } = quadMarkers(Vector3.new(30, 1.5, 40), "Small")
table.insert(health, { Position = Vector3.new(55, 1.5, 0), Kind = "Medium" })
table.insert(health, { Position = Vector3.new(-55, 1.5, 0), Kind = "Medium" })
table.insert(health, { Position = Vector3.new(0, 7.5, 0), Kind = "Large" })

local ammo: { Marker } = quadMarkers(Vector3.new(50, 1.5, 55))
local knifeStations: { Marker } = {
	{ Position = Vector3.new(0, 1.5, 45) },
	{ Position = Vector3.new(0, 1.5, -45) },
}

return table.freeze({
	Id = "dev_foundry_yard",
	DisplayName = "Foundry Yard (Greybox)",
	KillHeight = -40,
	Lighting = {
		ClockTime = 14.5,
		Brightness = 2,
		Ambient = Color3.fromRGB(90, 92, 88),
		OutdoorAmbient = Color3.fromRGB(120, 122, 116),
	},
	Blocks = blocks,
	Spawns = spawns,
	Health = health,
	Ammo = ammo,
	KnifeStations = knifeStations,
})
