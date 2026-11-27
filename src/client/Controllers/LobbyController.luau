--!strict
--[[
	Hub interactions and travel (spec §18, §19): portal and station ProximityPrompts, the PLAY menu
	(every lobby destination is also reachable from the interface), "return to hub" from arenas, and
	teleport status messages. The server decides everything; this only sends destination ids.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PlaceConfig = require(ReplicatedStorage.Shared.PlaceConfig)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Net = require(script.Parent.Parent.Core.Net)
local UIState = require(script.Parent.Parent.Core.UIState)
local Build = require(script.Parent.Parent.UI.Build)

local Theme = Config.Theme

local LobbyController = {
	Name = "LobbyController",
	Dependencies = {
		"ArmoryController",
		"NotificationController",
		"MatchmakingController",
		"PartyController",
	},
	-- Fired when the player asks to travel or reaches a portal (tutorial "Matchmaking" step).
	TravelIntent = Signal.new() :: Signal.Signal<string>,
}

local armory: any
local notifications: any
local matchmaking: any
local party: any
local menu: Frame

local REASONS = {
	Studio = "Teleports only work in a published game. Use Studio's multi-place testing or publish the places.",
	NotConfigured = "That destination has not been published yet (Config.Places).",
	TutorialRequired = "Finish the tutorial before joining matches.",
	InProgress = "Already joining a match.",
	AlreadyHere = "You're already here.",
	NotLoaded = "Your data is still loading.",
	Failed = "The teleport failed. Please try again.",
	UnknownDestination = "Unknown destination.",
}

-- Queued destinations go through matchmaking (reserved servers); others join public servers.
function LobbyController.Travel(self: typeof(LobbyController), destination: string)
	self.TravelIntent:Fire(destination)
	if PlaceConfig.Role == "Hub" and Config.Matchmaking.Queues[destination] then
		Net.Fire("JoinQueue", { Destination = destination })
	else
		Net.Fire("RequestTeleport", { Destination = destination })
	end
end

function LobbyController.SetMenuOpen(_self: typeof(LobbyController), open: boolean)
	if menu then
		menu.Visible = open
		UIState.SetMenuOpen("Play", open)
	end
end

local BROWSABLE = { FreeForAll = true, TeamDeathmatch = true }

local function buildMenu(gui: ScreenGui)
	local hub = PlaceConfig.Role == "Hub"
	local destinations = if hub then Config.Places.PlayOrder else { "Hub" }
	local extraRows = if hub then 2 else 0
	menu = Build.Panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(420, 84 + (#destinations + extraRows) * 44),
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = gui,
	}, { Build.Padding(12) })
	Build.Label({
		Text = if hub then "PLAY" else "LEAVE MATCH",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Large,
		Size = UDim2.new(1, 0, 0, 28),
		Parent = menu,
	})
	local y = 34
	for _, id in destinations do
		local destination = Config.Places.Destinations[id]
		local queued = hub and Config.Matchmaking.Queues[id] ~= nil
		local label = if id == "Hub"
			then "Return to hub"
			else destination.DisplayName .. (if queued then "  (matchmaking)" else "")
		local browsable = hub and BROWSABLE[id]
		Build.Button({
			Text = string.upper(label),
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.new(1, if browsable then -110 else 0, 0, 38),
			Parent = menu,
		}, function()
			LobbyController:SetMenuOpen(false)
			LobbyController:Travel(id)
		end)
		if browsable then
			Build.Button({
				Text = "SERVERS",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, y),
				Size = UDim2.fromOffset(104, 38),
				Parent = menu,
			}, function()
				LobbyController:SetMenuOpen(false)
				matchmaking:OpenBrowser(id)
			end)
		end
		y += 44
	end
	if hub then
		Build.Button({
			Text = "HOST PRIVATE MATCH",
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.new(1, 0, 0, 38),
			Parent = menu,
		}, function()
			LobbyController:SetMenuOpen(false)
			matchmaking:OpenPrivate()
		end)
		y += 44
		Build.Button({
			Text = "PARTY",
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.new(1, 0, 0, 38),
			Parent = menu,
		}, function()
			LobbyController:SetMenuOpen(false)
			party:SetOpen(true)
		end)
	end
	Build.Button({
		Text = "CLOSE",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 30),
		Parent = menu,
	}, function()
		LobbyController:SetMenuOpen(false)
	end)
	Build.Button({
		Text = if hub then "PLAY" else "HUB",
		BackgroundColor3 = Theme.Colors.Accent,
		Position = UDim2.fromOffset(338, 64),
		Size = UDim2.fromOffset(90, 32),
		Parent = gui,
	}, function()
		LobbyController:SetMenuOpen(not menu.Visible)
	end)
end

function LobbyController.Init(_self: typeof(LobbyController), registry: { [string]: any })
	armory = registry.ArmoryController
	notifications = registry.NotificationController
	matchmaking = registry.MatchmakingController
	party = registry.PartyController
end

function LobbyController.Start(self: typeof(LobbyController))
	local gui = Build.New("ScreenGui", {
		Name = "CrossbladeLobby",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 16,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	buildMenu(gui)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local part = prompt.Parent
		if part == nil then
			return
		end
		local destination = part:GetAttribute("Destination")
		local station = part:GetAttribute("Station")
		if type(destination) == "string" then
			self:Travel(destination)
		elseif station == "Armory" or station == "Crates" then
			armory:SetOpen(true)
			armory:SelectTab(if station == "Armory" then "Armory" else "Crates")
		elseif station == "Tutorial" then
			Net.Fire("TutorialAction", { Action = "Start" })
		end
	end)
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		local part = prompt.Parent
		local destination = part and part:GetAttribute("Destination")
		if type(destination) == "string" then
			self.TravelIntent:Fire(destination)
		end
	end)

	Net.On("TeleportStatus", function(payload)
		if payload.Ok then
			local destination = Config.Places.Destinations[payload.Destination]
			notifications:Show(
				`Joining {destination and destination.DisplayName or payload.Destination}...`,
				"Info"
			)
		else
			notifications:Show(REASONS[payload.Reason] or "Could not travel right now.", "Warning")
		end
	end)
end

return LobbyController
