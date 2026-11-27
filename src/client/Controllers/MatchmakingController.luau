--!strict
--[[
	Matchmaking UI (spec §19), active in the hub: queue status banner with cancel, reconnect offer,
	public server browser and private match host panel. Every action is a request; the server
	validates party leadership, limits, tutorial completion and destinations.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local PlaceConfig = require(ReplicatedStorage.Shared.PlaceConfig)
local Net = require(script.Parent.Parent.Core.Net)
local UIState = require(script.Parent.Parent.Core.UIState)
local Build = require(script.Parent.Parent.UI.Build)

local Theme = Config.Theme
local C = Theme.Colors

local MatchmakingController = {
	Name = "MatchmakingController",
	Dependencies = { "NotificationController" },
}

local notifications: any
local banner: Frame
local bannerText: TextLabel
local bannerButton: TextButton
local browser: Frame
local browserList: ScrollingFrame
local browserTitle: TextLabel
local privatePanel: Frame
local privateLabels: { [string]: TextLabel } = {}
local queue: { [string]: any } = {}
local reconnect: { [string]: any }? = nil
local browserDestination = "FreeForAll"
local privateOptions: { [string]: any }? = nil
local privateDraft = { Mode = "FreeForAll", MapIndex = 1, DurationMinutes = 10, ScoreLimit = 50 }

local REASONS = {
	NotLeader = "Only the party leader can do that.",
	PartyTooLarge = "Your party is too large for that mode.",
	TutorialRequired = "Everyone in the party must finish the tutorial first.",
	AlreadyQueued = "Someone in your party is already queued.",
	Studio = "Matchmaking needs published places; it cannot run in Studio.",
	NotConfigured = "That destination has not been published yet.",
	QueueUnavailable = "Matchmaking is unavailable right now. Try again shortly.",
	PartyChanged = "Queue cancelled because your party changed.",
	MemberLeft = "Queue cancelled because a party member left.",
	Expired = "Your queue ticket expired.",
	TeleportFailed = "Could not join the match. Please queue again.",
	Left = "Left the queue.",
	NotLoaded = "Your data is still loading.",
	UnknownDestination = "That mode is not available.",
}

local function destinationName(id: string?): string
	local destination = id and Config.Places.Destinations[id]
	return if destination then destination.DisplayName else (id or "")
end

local function renderBanner()
	if banner == nil then
		return
	end
	local state = queue.State
	if state == "Queued" or state == "Requeued" or state == "Matched" or state == "Joining" then
		banner.Visible = true
		local elapsed = if queue.Since then math.max(0, os.time() - queue.Since) else 0
		bannerText.Text = if state == "Matched" or state == "Joining"
			then `MATCH FOUND: {string.upper(destinationName(queue.Destination))}. JOINING...`
			else string.format(
				"SEARCHING: %s   %d:%02d",
				string.upper(destinationName(queue.Destination)),
				elapsed // 60,
				elapsed % 60
			)
		bannerButton.Text = "CANCEL"
		bannerButton.Visible = state == "Queued" or state == "Requeued"
	elseif reconnect then
		banner.Visible = true
		bannerText.Text = `YOUR {string.upper(destinationName(reconnect.Destination))} MATCH IS STILL RUNNING`
		bannerButton.Text = "REJOIN"
		bannerButton.Visible = true
	else
		banner.Visible = false
	end
end

local function setPanel(panel: Frame, open: boolean, name: string)
	panel.Visible = open
	UIState.SetMenuOpen(name, open)
end

function MatchmakingController.OpenBrowser(_self: typeof(MatchmakingController), destination: string)
	if browser == nil then
		return
	end
	browserDestination = destination
	browserTitle.Text = `SERVERS: {string.upper(destinationName(destination))}`
	setPanel(browser, true, "Browser")
	for _, child in browserList:GetChildren() do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	task.spawn(function()
		local result = Net.Invoke("GetServers", { Destination = destination })
		local servers = result and result.Servers or {}
		if #servers == 0 then
			Build.Label({
				Text = if result and result.Reason == "Studio"
					then "Server browsing needs published places."
					else "No open servers right now. Use PLAY to start one.",
				TextColor3 = C.TextMuted,
				Size = UDim2.new(1, 0, 0, 30),
				Parent = browserList,
			})
		end
		for order, info in servers do
			local row = Build.New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -8, 0, 34),
				LayoutOrder = order,
				Parent = browserList,
			})
			Build.Label({
				Text = `{info.Map}   •   {info.Players}/{info.MaxPlayers}   •   {info.Phase}`,
				Size = UDim2.new(1, -100, 1, 0),
				Parent = row,
			})
			Build.Button({
				Text = "JOIN",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.fromOffset(90, 30),
				Parent = row,
			}, function()
				setPanel(browser, false, "Browser")
				Net.Fire("JoinServer", { Destination = browserDestination, JobId = info.JobId })
			end)
		end
		browserList.CanvasSize = UDim2.fromOffset(0, math.max(1, #servers) * 38)
	end)
end

local function renderPrivate()
	local opts = privateOptions
	if opts == nil then
		return
	end
	local mode = opts.Modes[privateDraft.Mode]
	local maps = mode and mode.Maps or {}
	privateDraft.MapIndex = math.clamp(privateDraft.MapIndex, 1, math.max(1, #maps))
	privateLabels.Mode.Text = mode and mode.DisplayName or privateDraft.Mode
	privateLabels.Map.Text = if maps[privateDraft.MapIndex]
		then maps[privateDraft.MapIndex].DisplayName
		else "-"
	privateLabels.Duration.Text = `{privateDraft.DurationMinutes} min`
	privateLabels.Score.Text = if privateDraft.Mode == "TeamDeathmatch"
		then tostring(privateDraft.ScoreLimit)
		else "n/a"
end

function MatchmakingController.OpenPrivate(_self: typeof(MatchmakingController))
	if privatePanel == nil then
		return
	end
	setPanel(privatePanel, true, "Private")
	task.spawn(function()
		privateOptions = privateOptions or Net.Invoke("GetPrivateOptions", {})
		if privateOptions then
			privateDraft.DurationMinutes = privateOptions.DurationMinutes.Default
			privateDraft.ScoreLimit = privateOptions.ScoreLimit.Default
		end
		renderPrivate()
	end)
end

local function buildPrivate(gui: ScreenGui)
	privatePanel = Build.Panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(420, 300),
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = gui,
	}, { Build.Padding(12) })
	Build.Label({
		Text = "HOST A PRIVATE MATCH",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Large,
		Size = UDim2.new(1, 0, 0, 26),
		Parent = privatePanel,
	})
	Build.Label({
		Text = "Your party joins together. Private matches never award coins, XP or stats.",
		TextColor3 = C.TextMuted,
		TextSize = 12,
		TextWrapped = true,
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 0, 28),
		Parent = privatePanel,
	})
	local rows =
		{ { "Mode", "MODE" }, { "Map", "MAP" }, { "Duration", "DURATION" }, { "Score", "SCORE LIMIT" } }
	for index, row in rows do
		local key = row[1]
		local y = 64 + (index - 1) * 40
		Build.Label({
			Text = row[2],
			TextColor3 = C.TextMuted,
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.fromOffset(130, 32),
			Parent = privatePanel,
		})
		local function step(delta: number)
			local opts = privateOptions
			if opts == nil then
				return
			end
			if key == "Mode" then
				local index2 = table.find(opts.Order, privateDraft.Mode) or 1
				privateDraft.Mode = opts.Order[(index2 - 1 + delta) % #opts.Order + 1]
				privateDraft.MapIndex = 1
			elseif key == "Map" then
				local maps = opts.Modes[privateDraft.Mode].Maps
				privateDraft.MapIndex = (privateDraft.MapIndex - 1 + delta) % math.max(1, #maps) + 1
			elseif key == "Duration" then
				privateDraft.DurationMinutes = math.clamp(
					privateDraft.DurationMinutes + delta,
					opts.DurationMinutes.Min,
					opts.DurationMinutes.Max
				)
			else
				privateDraft.ScoreLimit =
					math.clamp(privateDraft.ScoreLimit + delta * 5, opts.ScoreLimit.Min, opts.ScoreLimit.Max)
			end
			renderPrivate()
		end
		Build.Button({
			Text = "<",
			Position = UDim2.fromOffset(140, y),
			Size = UDim2.fromOffset(32, 32),
			Parent = privatePanel,
		}, function()
			step(-1)
		end)
		privateLabels[key] = Build.Label({
			Text = "-",
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(176, y),
			Size = UDim2.fromOffset(180, 32),
			Parent = privatePanel,
		})
		Build.Button({
			Text = ">",
			Position = UDim2.fromOffset(360, y),
			Size = UDim2.fromOffset(32, 32),
			Parent = privatePanel,
		}, function()
			step(1)
		end)
	end
	Build.Button({
		Text = "CANCEL",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(180, 36),
		Parent = privatePanel,
	}, function()
		setPanel(privatePanel, false, "Private")
	end)
	Build.Button({
		Text = "HOST",
		BackgroundColor3 = C.Accent,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(180, 36),
		Parent = privatePanel,
	}, function()
		local opts = privateOptions
		if opts == nil then
			return
		end
		local maps = opts.Modes[privateDraft.Mode].Maps
		local map = maps[privateDraft.MapIndex]
		setPanel(privatePanel, false, "Private")
		Net.Fire("HostPrivate", {
			Mode = privateDraft.Mode,
			MapId = if map then map.Id else "",
			DurationMinutes = privateDraft.DurationMinutes,
			ScoreLimit = privateDraft.ScoreLimit,
		})
		notifications:Show("Setting up your private match...", "Info")
	end)
end

function MatchmakingController.Init(_self: typeof(MatchmakingController), registry: { [string]: any })
	notifications = registry.NotificationController
end

function MatchmakingController.Start(_self: typeof(MatchmakingController))
	if PlaceConfig.Role ~= "Hub" then
		return
	end
	local gui = Build.New("ScreenGui", {
		Name = "CrossbladeMatchmaking",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 17,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	banner = Build.Panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 90),
		Size = UDim2.fromOffset(520, 40),
		BackgroundColor3 = C.Background,
		Visible = false,
		Parent = gui,
	}, { Build.Padding(4) })
	bannerText = Build.Label({
		Text = "",
		Font = Theme.Fonts.Heading,
		Size = UDim2.new(1, -110, 1, 0),
		Parent = banner,
	})
	bannerButton = Build.Button({
		Text = "CANCEL",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 100, 1, 0),
		Parent = banner,
	}, function()
		if queue.State == "Queued" or queue.State == "Requeued" then
			Net.Fire("LeaveQueue", {})
		elseif reconnect then
			Net.Fire("RequestReconnect", {})
			reconnect = nil
			renderBanner()
		end
	end)

	browser = Build.Panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(520, 420),
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = gui,
	}, { Build.Padding(12) })
	browserTitle = Build.Label({
		Text = "SERVERS",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Large,
		Size = UDim2.new(1, 0, 0, 26),
		Parent = browser,
	})
	browserList = Build.New("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 1, -80),
		CanvasSize = UDim2.new(),
		Parent = browser,
	}, {
		Build.New("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	Build.Button({
		Text = "REFRESH",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(150, 36),
		Parent = browser,
	}, function()
		MatchmakingController:OpenBrowser(browserDestination)
	end)
	Build.Button({
		Text = "CLOSE",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(150, 36),
		Parent = browser,
	}, function()
		setPanel(browser, false, "Browser")
	end)
	buildPrivate(gui)

	Net.On("QueueStatus", function(payload)
		queue = payload
		if payload.State == "Refused" or payload.State == "Cancelled" then
			notifications:Show(
				REASONS[payload.Reason] or `Queue: {payload.Reason}`,
				if payload.Reason == "Left" then "Info" else "Warning"
			)
			queue = {}
		elseif payload.State == "Requeued" then
			notifications:Show("Joining the match failed; you're back at the front of the queue.", "Warning")
		end
		renderBanner()
	end)
	Net.On("ReconnectOffer", function(payload)
		reconnect = payload
		renderBanner()
	end)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 1 then
			accumulator = 0
			renderBanner()
		end
	end)
end

return MatchmakingController
