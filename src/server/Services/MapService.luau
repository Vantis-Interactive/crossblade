--!strict
--[[
	Arena loading (spec §17). Maps are discovered by CollectionService tags so core combat code never
	changes for new maps:
	  Crossblade.Spawn         - BasePart; spawn position/orientation
	  Crossblade.HealthPickup  - BasePart; attribute Size = "Small" | "Medium" | "Large"
	  Crossblade.AmmoPickup    - BasePart
	  Crossblade.KnifeStation  - BasePart
	A map Model may carry attributes MapId, DisplayName, KillHeight.

	Source priority: a Model in ServerStorage.Maps (Studio-authored) > the generated dev greybox.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Logger = require(ReplicatedStorage.Shared.Util.Logger)
local DevArena = require(script.Parent.Parent.Maps.DevArena)

local log = Logger.new("Map")

export type Spawn = { Id: string, CFrame: CFrame, Position: Vector3 }

local MapService = {
	Name = "MapService",
	Tags = table.freeze({
		Spawn = "Crossblade.Spawn",
		Health = "Crossblade.HealthPickup",
		Ammo = "Crossblade.AmmoPickup",
		KnifeStation = "Crossblade.KnifeStation",
	}),
}

local currentMap: Model? = nil

local function marker(
	name: string,
	position: Vector3,
	size: Vector3,
	color: Color3,
	tag: string,
	parent: Instance
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = Enum.Material.Neon
	part.CastShadow = false
	CollectionService:AddTag(part, tag)
	part.Parent = parent
	return part
end

local function buildGreybox(): Model
	local model = Instance.new("Model")
	model.Name = "Arena"
	model:SetAttribute("MapId", DevArena.Id)
	model:SetAttribute("DisplayName", DevArena.DisplayName)
	model:SetAttribute("KillHeight", DevArena.KillHeight)

	local geometry = Instance.new("Folder")
	geometry.Name = "Geometry"
	geometry.Parent = model
	for index, block in DevArena.Blocks do
		local part: BasePart = if block.Wedge then Instance.new("WedgePart") else Instance.new("Part")
		part.Name = `Block{index}`
		part.Anchored = true
		part.Size = block.Size
		part.CFrame = CFrame.new(block.Position) * CFrame.Angles(0, math.rad(block.Rotation or 0), 0)
		part.Color = block.Color or Color3.fromRGB(120, 120, 120)
		part.Material = block.Material or Enum.Material.Concrete
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = geometry
	end

	local markers = Instance.new("Folder")
	markers.Name = "Markers"
	markers.Parent = model
	for index, spawn in DevArena.Spawns do
		local part = Instance.new("Part")
		part.Name = `Spawn{index}`
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(4, 1, 4)
		part.CFrame = CFrame.new(spawn.Position) * CFrame.Angles(0, math.rad(spawn.Facing or 0), 0)
		CollectionService:AddTag(part, MapService.Tags.Spawn)
		part.Parent = markers
	end
	local healthColor = Color3.fromRGB(110, 220, 120)
	for index, entry in DevArena.Health do
		local size = if entry.Kind == "Large" then 2.4 elseif entry.Kind == "Medium" then 1.9 else 1.4
		local part = marker(
			`Health{index}`,
			entry.Position,
			Vector3.one * size,
			healthColor,
			MapService.Tags.Health,
			markers
		)
		part.Shape = Enum.PartType.Ball
		part:SetAttribute("Size", entry.Kind)
	end
	for index, entry in DevArena.Ammo do
		marker(
			`Ammo{index}`,
			entry.Position,
			Vector3.new(2, 1.2, 1.4),
			Color3.fromRGB(230, 190, 70),
			MapService.Tags.Ammo,
			markers
		)
	end
	for index, entry in DevArena.KnifeStations do
		marker(
			`KnifeStation{index}`,
			entry.Position,
			Vector3.new(2.5, 3, 0.6),
			Color3.fromRGB(180, 200, 215),
			MapService.Tags.KnifeStation,
			markers
		)
	end

	local lighting = DevArena.Lighting
	Lighting.ClockTime = lighting.ClockTime
	Lighting.Brightness = lighting.Brightness
	Lighting.Ambient = lighting.Ambient
	Lighting.OutdoorAmbient = lighting.OutdoorAmbient
	return model
end

function MapService.Start(_self: typeof(MapService))
	-- Map is loaded during Init so dependents can query it from their own Start.
end

function MapService.Init(_self: typeof(MapService), _registry: { [string]: any })
	local authored = ServerStorage:FindFirstChild("Maps")
	local source = authored and authored:FindFirstChildWhichIsA("Model")
	if source then
		currentMap = source:Clone()
		log:Info("loading authored map", { map = source.Name })
	else
		currentMap = buildGreybox()
		log:Info("loading development greybox map", { map = DevArena.Id })
	end
	(currentMap :: Model).Parent = Workspace
	if #MapService:GetSpawns() == 0 then
		error("map has no spawn points tagged " .. MapService.Tags.Spawn)
	end
end

local function tagged(tag: string): { BasePart }
	local result = {}
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsA("BasePart") and currentMap and instance:IsDescendantOf(currentMap) then
			table.insert(result, instance)
		end
	end
	return result
end

function MapService.GetSpawns(_self: typeof(MapService)): { Spawn }
	local result = {}
	for _, part in tagged(MapService.Tags.Spawn) do
		table.insert(result, { Id = part:GetFullName(), CFrame = part.CFrame, Position = part.Position })
	end
	return result
end

function MapService.GetTagged(
	_self: typeof(MapService),
	kind: "Health" | "Ammo" | "KnifeStation"
): { BasePart }
	return tagged((MapService.Tags :: any)[kind])
end

function MapService.GetKillHeight(_self: typeof(MapService)): number
	local height = currentMap and currentMap:GetAttribute("KillHeight")
	return if type(height) == "number" then height else -50
end

function MapService.GetDisplayName(_self: typeof(MapService)): string
	local name = currentMap and currentMap:GetAttribute("DisplayName")
	return if type(name) == "string" then name else "Arena"
end

return MapService
