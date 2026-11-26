--!strict
--[[
	TEMPORARY DEVELOPMENT MAP (docs/ASSET_MANIFEST.md: DEV-MAP-003).
	Social hub greybox (spec §18): central plaza spawn, matchmaking portals (north), armory station
	(west), crate shop station (east), tutorial station and training zone with pickups (south-east),
	shooting range with training dummies (south), parkour course (north-east).
	Player-versus-player damage is disabled in the hub (Lobby mode); weapons work on dummies only.
]]

local STONE = Color3.fromRGB(128, 130, 124)
local STEEL = Color3.fromRGB(84, 90, 92)
local OLIVE = Color3.fromRGB(96, 108, 70)
local ACCENT = Color3.fromRGB(122, 140, 74)

local blocks = {}
local function add(size: Vector3, position: Vector3, color: Color3?, material: Enum.Material?)
	table.insert(blocks, { Size = size, Position = position, Color = color, Material = material })
end

add(Vector3.new(220, 2, 220), Vector3.new(0, -1, 0), STONE, Enum.Material.Slate)
for _, side in { 1, -1 } do
	add(Vector3.new(224, 12, 2), Vector3.new(0, 6, 111 * side), STEEL, Enum.Material.Metal)
	add(Vector3.new(2, 12, 224), Vector3.new(111 * side, 6, 0), STEEL, Enum.Material.Metal)
end

-- Portal arches (north).
local portals = {}
local destinations = { "FreeForAll", "TeamDeathmatch", "CasualDuel1v1", "CasualDuelTeam" }
for index, destination in destinations do
	local x = -45 + (index - 1) * 30
	add(Vector3.new(2, 14, 2), Vector3.new(x - 6, 7, -82), STEEL, Enum.Material.Metal)
	add(Vector3.new(2, 14, 2), Vector3.new(x + 6, 7, -82), STEEL, Enum.Material.Metal)
	add(Vector3.new(14, 2, 2), Vector3.new(x, 15, -82), ACCENT, Enum.Material.Metal)
	table.insert(portals, { Position = Vector3.new(x, 6.5, -80), Destination = destination })
end

-- Station kiosks: a solid backboard behind each interaction marker.
local stations = {
	{ Position = Vector3.new(-60, 2.5, 0), Station = "Armory" },
	{ Position = Vector3.new(60, 2.5, 0), Station = "Crates" },
	{ Position = Vector3.new(55, 2.5, 40), Station = "Tutorial" },
}
add(Vector3.new(2, 8, 10), Vector3.new(-64, 4, 0), OLIVE, Enum.Material.Metal)
add(Vector3.new(2, 8, 10), Vector3.new(64, 4, 0), OLIVE, Enum.Material.Metal)
add(Vector3.new(10, 8, 2), Vector3.new(55, 4, 44), OLIVE, Enum.Material.Metal)

-- Shooting range (south): backstop, side walls, firing-line rail.
add(Vector3.new(84, 12, 2), Vector3.new(0, 6, 104), STEEL, Enum.Material.Metal)
add(Vector3.new(2, 6, 44), Vector3.new(-42, 3, 82), STEEL, Enum.Material.Metal)
add(Vector3.new(2, 6, 44), Vector3.new(42, 3, 82), STEEL, Enum.Material.Metal)
add(Vector3.new(80, 1.2, 1), Vector3.new(0, 0.6, 60), ACCENT, Enum.Material.Metal)
local dummySpots = {}
for index, x in { -30, -18, -6, 6, 18, 30 } do
	table.insert(dummySpots, { Position = Vector3.new(x, 0, 88 + (index % 2) * 7), Facing = 180 })
end

-- Parkour course (north-east): each platform is 2 studs above the previous one.
for step = 0, 5 do
	add(
		Vector3.new(6, 1, 6),
		Vector3.new(60 + step * 8, 1.5 + step * 2, -40 - (step % 2) * 6),
		ACCENT,
		Enum.Material.Metal
	)
end

local spawns = {}
for i = 0, 7 do
	local angle = i / 8 * math.pi * 2
	local position = Vector3.new(math.cos(angle) * 12, 0.5, math.sin(angle) * 12)
	table.insert(spawns, { Position = position, Facing = math.deg(math.atan2(position.X, position.Z)) })
end

return table.freeze({
	Id = "dev_hub",
	DisplayName = "Crossblade Hub (Greybox)",
	Modes = { "Lobby" },
	KillHeight = -30,
	Lighting = {
		ClockTime = 13,
		Brightness = 2.2,
		Ambient = Color3.fromRGB(100, 104, 98),
		OutdoorAmbient = Color3.fromRGB(128, 130, 124),
	},
	Blocks = blocks,
	Spawns = spawns,
	-- Training zone pickups (used by the tutorial's Pickups step).
	Health = { { Position = Vector3.new(70, 1.5, 55), Kind = "Small" } },
	Ammo = { { Position = Vector3.new(80, 1.5, 55) } },
	KnifeStations = { { Position = Vector3.new(90, 1.5, 55) } },
	Portals = portals,
	Stations = stations,
	DummySpots = dummySpots,
})
