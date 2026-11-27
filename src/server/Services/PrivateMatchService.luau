--!strict
--[[
	Private matches (spec §5, §19), hub only. A party leader (or solo player) hosts a reserved match
	with chosen base mode, map, duration and score limit. Private matches never award coins, XP,
	statistics or challenge progress: the reserved server builds a Private mode with
	AwardsProgression = false (Core/MatchContext.ModeConfig).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Shared.Config)
local Teams = require(script.Parent.Parent.Domain.Teams)
local MemoryStoreAdapter = require(script.Parent.Parent.Matchmaking.MemoryStoreAdapter)

local P = Config.Matchmaking.Private

local PrivateMatchService = {
	Name = "PrivateMatchService",
	Roles = { "Hub" },
	Dependencies = {
		"Net",
		"PlayerDataService",
		"PartyService",
		"PortalService",
		"MapService",
		"AuditService",
	},
}

local net: any
local playerData: any
local party: any
local portal: any
local mapService: any
local audit: any

local function options(): { [string]: any }
	local modes = {}
	for _, modeId in P.Modes do
		local maps = {}
		for _, mapId in mapService:MapsForMode(modeId) do
			local info = mapService:Info(mapId)
			table.insert(maps, { Id = mapId, DisplayName = info and info.DisplayName or mapId })
		end
		modes[modeId] = { DisplayName = Config.GameModes[modeId].DisplayName, Maps = maps }
	end
	return { Modes = modes, Order = P.Modes, DurationMinutes = P.DurationMinutes, ScoreLimit = P.ScoreLimit }
end

local function fail(player: Player, reason: string)
	net.Fire("TeleportStatus", player, { Ok = false, Reason = reason })
end

local function host(player: Player, payload: any)
	if not party:IsLeaderOrSolo(player) then
		return fail(player, "NotLeader")
	end
	if not table.find(P.Modes, payload.Mode) then
		return fail(player, "UnknownDestination")
	end
	local group = party:Group(player)
	for _, member in group do
		local profile = playerData:GetProfile(member)
		if profile == nil or not profile.Data.Tutorial.Completed then
			return fail(player, "TutorialRequired")
		end
	end
	local destination = Config.Places.Destinations[payload.Mode]
	if RunService:IsStudio() then
		return fail(player, "Studio")
	end
	if destination == nil or destination.PlaceId == 0 then
		return fail(player, "NotConfigured")
	end
	local maps = mapService:MapsForMode(payload.Mode)
	local settings = {
		MapId = if table.find(maps, payload.MapId) then payload.MapId else maps[1],
		DurationMinutes = math.clamp(payload.DurationMinutes, P.DurationMinutes.Min, P.DurationMinutes.Max),
		ScoreLimit = math.clamp(payload.ScoreLimit, P.ScoreLimit.Min, P.ScoreLimit.Max),
	}
	local ids = {}
	for _, member in group do
		table.insert(ids, member.UserId)
	end
	local teams: { [string]: { number } }
	if Config.GameModes[payload.Mode].Kind == "TeamDeathmatch" then
		local assignment = Teams.Balance(ids, nil)
		teams = { A = {}, B = {} }
		for userId, team in assignment do
			table.insert(teams[team], userId)
		end
	else
		teams = { A = ids }
	end
	local ok, accessCode, privateServerId = pcall(function()
		return TeleportService:ReserveServer(destination.PlaceId)
	end)
	if not ok then
		return fail(player, "Failed")
	end
	local saved = pcall(function()
		MemoryStoreAdapter.Map(Config.Matchmaking.StoreNames.Matches):SetAsync(privateServerId, {
			Destination = payload.Mode,
			Mode = "Private",
			BaseMode = payload.Mode,
			Private = true,
			Settings = settings,
			Teams = teams,
			AccessCode = accessCode,
			PlaceId = destination.PlaceId,
			CreatedAt = os.time(),
		}, Config.Matchmaking.Reserved.MatchRecordSeconds)
	end)
	if not saved then
		return fail(player, "Failed")
	end
	audit:Record(
		"Data",
		"PrivateMatchHosted",
		player.UserId,
		{ mode = payload.Mode, map = settings.MapId, players = #group }
	)
	local teleported, reason = portal:TeleportReserved(group, destination.PlaceId, accessCode)
	if not teleported then
		fail(player, reason or "Failed")
	end
end

function PrivateMatchService.Init(_self: typeof(PrivateMatchService), registry: { [string]: any })
	net = registry.Net
	playerData = registry.PlayerDataService
	party = registry.PartyService
	portal = registry.PortalService
	mapService = registry.MapService
	audit = registry.AuditService
	net.OnInvoke("GetPrivateOptions", function()
		return options()
	end)
	net.OnEvent("HostPrivate", function(player: Player, payload: any)
		task.spawn(host, player, payload)
	end)
end

return PrivateMatchService
