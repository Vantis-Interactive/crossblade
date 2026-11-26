--!strict
--[[
	Arena loading and map rotation (spec §17). Maps are discovered by CollectionService tags, so core
	combat code never changes for new maps:
	  Crossblade.Spawn         BasePart; optional attribute Team = "A" | "B"
	  Crossblade.HealthPickup  BasePart; attribute Size = "Small" | "Medium" | "Large"
	  Crossblade.AmmoPickup    BasePart
	  Crossblade.KnifeStation  BasePart
	  Crossblade.Portal        BasePart; attribute Destination (Config.Places id)   [hub]
	  Crossblade.Station       BasePart; attribute Station = "Armory" | "Crates" | "Tutorial"   [hub]
	  Crossblade.DummySpot     BasePart; training dummy position   [hub / ranges]
	A map Model carries attributes MapId, DisplayName, KillHeight and Modes (comma-separated ids).

	Sources: Models in ServerStorage.Maps (Studio-authored) plus the generated greybox layouts in
	Server/Maps. Load() swaps the current map and fires MapChanged.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Logger = require(ReplicatedStorage.Shared.Util.Logger)
local PlaceConfig = require(ReplicatedStorage.Shared.PlaceConfig)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local log = Logger.new("Map")

export type Spawn = { Id: string, CFrame: CFrame, Position: Vector3, Team: string? }
export type Kind = "Health" | "Ammo" | "KnifeStation" | "Portal" | "Station" | "DummySpot"

type Source = { Id: string, DisplayName: string, Modes: { string }, Layout: any?, Model: Model? }

local MapService = {
	Name = "MapService",
	Tags = table.freeze({
		Spawn = "Crossblade.Spawn",
		Health = "Crossblade.HealthPickup",
		Ammo = "Crossblade.AmmoPickup",
		KnifeStation = "Crossblade.KnifeStation",
		Portal = "Crossblade.Portal",
		Station = "Crossblade.Station",
		DummySpot = "Crossblade.DummySpot",
	}),
	MapChanged = Signal.new() :: Signal.Signal<string>,
}

local sources: { [string]: Source } = {}
local currentMap: Model? = nil
local currentId: string? = nil

local function marker(
	name: string,
	position: Vector3,
	size: Vector3,
	color: Color3,
	tag: string,
	parent: Instance,
	visible: boolean?
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
	part.Transparency = if visible == false then 1 else 0
	CollectionService:AddTag(part, tag)
	part.Parent = parent
	return part
end

local function buildLayout(layout: any): Model
	local model = Instance.new("Model")
	model.Name = "Arena"
	model:SetAttribute("MapId", layout.Id)
	model:SetAttribute("DisplayName", layout.DisplayName)
	model:SetAttribute("KillHeight", layout.KillHeight)

	local geometry = Instance.new("Folder")
	geometry.Name = "Geometry"
	geometry.Parent = model
	for index, block in layout.Blocks do
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
	for index, spawn in layout.Spawns do
		local part = marker(
			`Spawn{index}`,
			spawn.Position,
			Vector3.new(4, 1, 4),
			Color3.new(),
			MapService.Tags.Spawn,
			markers,
			false
		)
		part.CFrame = CFrame.new(spawn.Position) * CFrame.Angles(0, math.rad(spawn.Facing or 0), 0)
		if spawn.Team then
			part:SetAttribute("Team", spawn.Team)
		end
	end
	for index, entry in layout.Health do
		local size = if entry.Kind == "Large" then 2.4 elseif entry.Kind == "Medium" then 1.9 else 1.4
		local part = marker(
			`Health{index}`,
			entry.Position,
			Vector3.one * size,
			Color3.fromRGB(110, 220, 120),
			MapService.Tags.Health,
			markers
		)
		part.Shape = Enum.PartType.Ball
		part:SetAttribute("Size", entry.Kind)
	end
	for index, entry in layout.Ammo do
		marker(
			`Ammo{index}`,
			entry.Position,
			Vector3.new(2, 1.2, 1.4),
			Color3.fromRGB(230, 190, 70),
			MapService.Tags.Ammo,
			markers
		)
	end
	for index, entry in layout.KnifeStations do
		marker(
			`KnifeStation{index}`,
			entry.Position,
			Vector3.new(2.5, 3, 0.6),
			Color3.fromRGB(180, 200, 215),
			MapService.Tags.KnifeStation,
			markers
		)
	end
	for index, entry in layout.Portals or {} do
		local part = marker(
			`Portal{index}`,
			entry.Position,
			Vector3.new(10, 12, 0.5),
			Color3.fromRGB(90, 200, 230),
			MapService.Tags.Portal,
			markers
		)
		part.Transparency = 0.45
		part:SetAttribute("Destination", entry.Destination)
	end
	for index, entry in layout.Stations or {} do
		local part = marker(
			`Station{index}`,
			entry.Position,
			Vector3.new(3, 5, 0.6),
			Color3.fromRGB(164, 186, 98),
			MapService.Tags.Station,
			markers
		)
		part:SetAttribute("Station", entry.Station)
	end
	for index, entry in layout.DummySpots or {} do
		local part = marker(
			`DummySpot{index}`,
			entry.Position,
			Vector3.new(2, 0.2, 2),
			Color3.new(),
			MapService.Tags.DummySpot,
			markers,
			false
		)
		part.CFrame = CFrame.new(entry.Position) * CFrame.Angles(0, math.rad(entry.Facing or 0), 0)
	end
	return model
end

local function register()
	for _, module in script.Parent.Parent.Maps:GetChildren() do
		if module:IsA("ModuleScript") then
			local layout = (require :: any)(module)
			sources[layout.Id] =
				{ Id = layout.Id, DisplayName = layout.DisplayName, Modes = layout.Modes, Layout = layout }
		end
	end
	local authored = ServerStorage:FindFirstChild("Maps")
	for _, model in if authored then authored:GetChildren() else {} do
		if model:IsA("Model") then
			local id = model:GetAttribute("MapId")
			local modes = model:GetAttribute("Modes")
			if type(id) == "string" and type(modes) == "string" then
				local name = model:GetAttribute("DisplayName")
				sources[id] = {
					Id = id,
					DisplayName = if type(name) == "string" then name else id,
					Modes = string.split((string.gsub(modes, "%s", "")), ","),
					Model = model,
				}
			else
				log:Warn("authored map ignored: needs MapId and Modes attributes", { map = model.Name })
			end
		end
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

function MapService.MapsForMode(_self: typeof(MapService), modeId: string): { string }
	local ids = {}
	for id, source in sources do
		if table.find(source.Modes, modeId) then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

function MapService.Info(_self: typeof(MapService), mapId: string): { Id: string, DisplayName: string }?
	local source = sources[mapId]
	return source and { Id = source.Id, DisplayName = source.DisplayName }
end

function MapService.Load(self: typeof(MapService), mapId: string)
	local source = sources[mapId]
	assert(source, `unknown map {mapId}`)
	if currentMap then
		currentMap:Destroy()
	end
	local model = if source.Model then source.Model:Clone() else buildLayout(source.Layout)
	model:SetAttribute("MapId", source.Id)
	model:SetAttribute("DisplayName", source.DisplayName)
	currentMap = model
	currentId = mapId
	local lighting = source.Layout and source.Layout.Lighting
	if lighting then
		Lighting.ClockTime = lighting.ClockTime
		Lighting.Brightness = lighting.Brightness
		Lighting.Ambient = lighting.Ambient
		Lighting.OutdoorAmbient = lighting.OutdoorAmbient
	end
	model.Parent = Workspace
	if #self:GetSpawns() == 0 then
		error(`map {mapId} has no spawn points tagged {MapService.Tags.Spawn}`)
	end
	log:Info("map loaded", { map = mapId })
	MapService.MapChanged:Fire(mapId)
end

function MapService.Init(self: typeof(MapService), _registry: { [string]: any })
	register()
	local candidates = self:MapsForMode(PlaceConfig.Mode)
	local initial = if PlaceConfig.Map and sources[PlaceConfig.Map] then PlaceConfig.Map else candidates[1]
	if initial == nil then
		error(`no map supports mode {PlaceConfig.Mode}`)
	end
	-- Loaded during Init so dependents can query the map from their own Start.
	self:Load(initial)
end

function MapService.CurrentId(_self: typeof(MapService)): string?
	return currentId
end

function MapService.GetSpawns(_self: typeof(MapService)): { Spawn }
	local result = {}
	for _, part in tagged(MapService.Tags.Spawn) do
		local team = part:GetAttribute("Team")
		table.insert(result, {
			Id = part:GetFullName(),
			CFrame = part.CFrame,
			Position = part.Position,
			Team = if type(team) == "string" then team else nil,
		})
	end
	return result
end

function MapService.GetTagged(_self: typeof(MapService), kind: Kind): { BasePart }
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
