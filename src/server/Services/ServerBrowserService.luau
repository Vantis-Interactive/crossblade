--!strict
--[[
	Public server discovery (spec §19).
	  Arena public servers advertise themselves (players, capacity, map, phase) with a short TTL.
	  The hub lists them per destination (GetServers) and joins a chosen one (JoinServer).
	Reserved and player-owned private servers are never listed.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local PlaceConfig = require(ReplicatedStorage.Shared.PlaceConfig)
local MatchContext = require(script.Parent.Parent.Core.MatchContext)
local MemoryStoreAdapter = require(script.Parent.Parent.Matchmaking.MemoryStoreAdapter)

local B = Config.Matchmaking.Browser

local ServerBrowserService = {
	Name = "ServerBrowserService",
	Dependencies = { "Net", "MapService", "MatchService", "PortalService" },
}

local maps: { [string]: any } = {}
local net: any
local mapService: any
local match: any
local portal: any

local function directory(destination: string): any
	local existing = maps[destination]
	if existing == nil then
		existing = MemoryStoreAdapter.Map(Config.Matchmaking.StoreNames.Servers .. destination)
		maps[destination] = existing
	end
	return existing
end

local function advertised(): boolean
	return PlaceConfig.Role == "Arena"
		and MatchContext.Kind == "Public"
		and Config.Places.Destinations[PlaceConfig.Mode] ~= nil
		and not RunService:IsStudio()
end

local function publish()
	local count = #Players:GetPlayers()
	directory(PlaceConfig.Mode):SetAsync(game.JobId, {
		JobId = game.JobId,
		Players = count,
		MaxPlayers = Players.MaxPlayers,
		Map = mapService:GetDisplayName(),
		Phase = match:Phase(),
		UpdatedAt = os.time(),
	}, B.TimeToLiveSeconds, -count) -- fullest first
end

function ServerBrowserService.Init(_self: typeof(ServerBrowserService), registry: { [string]: any })
	net = registry.Net
	mapService = registry.MapService
	match = registry.MatchService
	portal = registry.PortalService

	net.OnInvoke("GetServers", function(_player: Player, payload: any)
		if PlaceConfig.Role ~= "Hub" or RunService:IsStudio() then
			return { Servers = {}, Reason = if RunService:IsStudio() then "Studio" else "NotHub" }
		end
		local ok, items = pcall(function()
			return directory(payload.Destination):GetRangeAsync("Ascending", B.MaxListed)
		end)
		if not ok then
			return { Servers = {}, Reason = "Unavailable" }
		end
		local servers = {}
		for _, item in items do
			local info = item.value
			if type(info) == "table" and info.Players < info.MaxPlayers then
				table.insert(servers, info)
			end
		end
		return { Servers = servers }
	end)

	net.OnEvent("JoinServer", function(player: Player, payload: any)
		if PlaceConfig.Role == "Hub" and string.match(payload.JobId, "^[%w%-]+$") then
			task.spawn(function()
				portal:JoinInstance(player, payload.Destination, payload.JobId)
			end)
		end
	end)
end

function ServerBrowserService.Start(_self: typeof(ServerBrowserService))
	if not advertised() then
		return
	end
	task.spawn(function()
		while true do
			pcall(publish)
			task.wait(B.HeartbeatSeconds)
		end
	end)
	game:BindToClose(function()
		pcall(function()
			directory(PlaceConfig.Mode):RemoveAsync(game.JobId)
		end)
	end)
end

return ServerBrowserService
