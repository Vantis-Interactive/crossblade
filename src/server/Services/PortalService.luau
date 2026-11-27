--!strict
--[[
	Place-to-place travel (spec §18, §19): hub portals, the Play menu and "return to hub".
	  - Destinations and PlaceIds come only from Config.Places; the client sends a destination id,
	    never a PlaceId, and teleport data is informational only (never trusted on arrival: each
	    place knows its own mode from PlaceConfig).
	  - First-time players must finish the tutorial before leaving the hub (spec §27).
	  - Refusals are explicit (Studio, unconfigured PlaceId, tutorial, already travelling); failures
	    are retried with backoff and reported, and the player stays fully playable here.
	Also creates the ProximityPrompts on tagged portals and stations; the client decides what a
	triggered prompt does (open a menu or request a teleport).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Shared.Config)
local Logger = require(ReplicatedStorage.Shared.Util.Logger)
local PlaceConfig = require(ReplicatedStorage.Shared.PlaceConfig)
local Retry = require(ReplicatedStorage.Shared.Util.Retry)

local log = Logger.new("Portal")

local STATION_TEXT = {
	Armory = { "Armory", "Open" },
	Crates = { "Crate Shop", "Open" },
	Tutorial = { "Training", "Start Tutorial" },
}

local PortalService = {
	Name = "PortalService",
	Dependencies = { "Net", "PlayerDataService", "MapService", "AuditService" },
}

local pending: { [Player]: boolean } = {}
local net: any
local playerData: any
local mapService: any
local audit: any

local function status(player: Player, payload: { [string]: any })
	net.Fire("TeleportStatus", player, payload)
end

local function addPrompts()
	for _, part in mapService:GetTagged("Portal") do
		local destination = Config.Places.Destinations[part:GetAttribute("Destination")]
		if destination and part:FindFirstChildOfClass("ProximityPrompt") == nil then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ObjectText = destination.DisplayName
			prompt.ActionText = "Join"
			prompt.MaxActivationDistance = 12
			prompt.RequiresLineOfSight = false
			prompt.Parent = part
		end
	end
	for _, part in mapService:GetTagged("Station") do
		local text = STATION_TEXT[part:GetAttribute("Station")]
		if text and part:FindFirstChildOfClass("ProximityPrompt") == nil then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ObjectText = text[1]
			prompt.ActionText = text[2]
			prompt.MaxActivationDistance = 10
			prompt.RequiresLineOfSight = false
			prompt.Parent = part
		end
	end
end

local function refusal(player: Player, destinationId: string): string?
	local destination = Config.Places.Destinations[destinationId]
	if destination == nil then
		return "UnknownDestination"
	end
	if destination.Mode == PlaceConfig.Mode or (destinationId == "Hub" and PlaceConfig.Role == "Hub") then
		return "AlreadyHere"
	end
	local profile = playerData:GetProfile(player)
	if profile == nil then
		return "NotLoaded"
	end
	if PlaceConfig.Role == "Hub" and destinationId ~= "Hub" and not profile.Data.Tutorial.Completed then
		return "TutorialRequired"
	end
	if pending[player] then
		return "InProgress"
	end
	if RunService:IsStudio() then
		return "Studio"
	end
	if destination.PlaceId == 0 then
		return "NotConfigured"
	end
	return nil
end

local function teleport(player: Player, destinationId: string)
	local reason = refusal(player, destinationId)
	if reason then
		status(player, { Ok = false, Destination = destinationId, Reason = reason })
		return
	end
	local destination = Config.Places.Destinations[destinationId]
	pending[player] = true
	status(player, { Ok = true, Destination = destinationId, Stage = "Starting" })
	local options = Instance.new("TeleportOptions")
	options:SetTeleportData({ Destination = destinationId, From = PlaceConfig.Mode })
	local ok, err = Retry.Call(Config.Places.Teleport, function()
		return TeleportService:TeleportAsync(destination.PlaceId, { player }, options)
	end)
	if not ok then
		pending[player] = nil
		log:Warn("teleport failed", { player = player.UserId, destination = destinationId, error = err })
		audit:Record(
			"Data",
			"TeleportFailed",
			player.UserId,
			{ destination = destinationId, error = tostring(err) }
		)
		status(player, { Ok = false, Destination = destinationId, Reason = "Failed" })
	end
end

-- Teleports a group to a reserved server (matchmaking, private matches, reconnects).
-- Returns true when TeleportAsync accepted the request; arrival failures surface via TeleportInitFailed.
function PortalService.TeleportReserved(
	_self: typeof(PortalService),
	players: { Player },
	placeId: number,
	accessCode: string
): (boolean, string?)
	if RunService:IsStudio() then
		return false, "Studio"
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = accessCode
	for _, player in players do
		pending[player] = true
	end
	local ok, err = Retry.Call(Config.Places.Teleport, function()
		return TeleportService:TeleportAsync(placeId, players, options)
	end)
	if not ok then
		for _, player in players do
			pending[player] = nil
		end
		audit:Record(
			"Data",
			"ReservedTeleportFailed",
			nil,
			{ place = placeId, players = #players, error = tostring(err) }
		)
		return false, "Failed"
	end
	return true, nil
end

-- Joins one specific public server (server browser).
function PortalService.JoinInstance(
	_self: typeof(PortalService),
	player: Player,
	destinationId: string,
	jobId: string
)
	local reason = refusal(player, destinationId)
	if reason then
		status(player, { Ok = false, Destination = destinationId, Reason = reason })
		return
	end
	local destination = Config.Places.Destinations[destinationId]
	pending[player] = true
	status(player, { Ok = true, Destination = destinationId, Stage = "Starting" })
	local options = Instance.new("TeleportOptions")
	options.ServerInstanceId = jobId
	local ok, err = Retry.Call(Config.Places.Teleport, function()
		return TeleportService:TeleportAsync(destination.PlaceId, { player }, options)
	end)
	if not ok then
		pending[player] = nil
		log:Warn("instance join failed", { player = player.UserId, error = err })
		status(player, { Ok = false, Destination = destinationId, Reason = "Failed" })
	end
end

-- Sends a player back to the hub. If that is impossible (Studio, hub unpublished) and `kickIfStuck`
-- is set, the player is removed with `message` instead of being left somewhere they cannot play.
function PortalService.SendToHub(
	_self: typeof(PortalService),
	player: Player,
	message: string,
	kickIfStuck: boolean?
)
	net.Fire("Notification", player, { Kind = "Warning", Text = message })
	local hub = Config.Places.Destinations.Hub
	if RunService:IsStudio() or hub.PlaceId == 0 or PlaceConfig.Role == "Hub" then
		if kickIfStuck then
			player:Kick(message)
		end
		return
	end
	local ok = Retry.Call(Config.Places.Teleport, function()
		return TeleportService:TeleportAsync(hub.PlaceId, { player })
	end)
	if not ok and kickIfStuck then
		player:Kick(message)
	end
end

function PortalService.Init(_self: typeof(PortalService), registry: { [string]: any })
	net = registry.Net
	playerData = registry.PlayerDataService
	mapService = registry.MapService
	audit = registry.AuditService
	net.OnEvent("RequestTeleport", function(player: Player, payload: any)
		task.spawn(teleport, player, payload.Destination)
	end)
	mapService.MapChanged:Connect(addPrompts)
	addPrompts()

	-- Arenas enforce the mandatory tutorial too (players can arrive by joining a friend, etc.).
	if PlaceConfig.Role == "Arena" then
		playerData.ProfileLoaded:Connect(function(player: Player, profile: any)
			if not profile.Data.Tutorial.Completed then
				task.spawn(function()
					if RunService:IsStudio() then
						net.Fire("Notification", player, {
							Kind = "Warning",
							Text = "Studio: tutorial not completed (a live server would send you to the hub).",
						})
					else
						PortalService:SendToHub(
							player,
							"Complete the tutorial in the hub before joining matches.",
							false
						)
					end
				end)
			end
		end)
	end
end

function PortalService.Start(_self: typeof(PortalService))
	-- Failures after TeleportAsync returned (e.g. the destination server was full) arrive here.
	TeleportService.TeleportInitFailed:Connect(
		function(player: Player, result: Enum.TeleportResult, message: string)
			pending[player] = nil
			log:Warn(
				"teleport init failed",
				{ player = player.UserId, result = result.Name, message = message }
			)
			status(player, { Ok = false, Reason = "Failed", Detail = result.Name })
		end
	)
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
	end)
end

return PortalService
