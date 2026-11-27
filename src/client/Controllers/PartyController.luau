--!strict
-- Party panel (spec §19), active in the hub: members, leader actions, invites in both directions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PlaceConfig = require(ReplicatedStorage.Shared.PlaceConfig)
local Net = require(script.Parent.Parent.Core.Net)
local UIState = require(script.Parent.Parent.Core.UIState)
local Build = require(script.Parent.Parent.UI.Build)

local Theme = Config.Theme
local C = Theme.Colors

local PartyController = {
	Name = "PartyController",
	Dependencies = { "NotificationController" },
	State = { Members = {}, Invites = {} } :: { [string]: any },
}

local player = Players.LocalPlayer
local notifications: any
local panel: Frame
local list: ScrollingFrame
local seenInvites: { [number]: boolean } = {}

local function action(name: string, target: number?, partyId: number?)
	Net.Fire("PartyAction", { Action = name, TargetUserId = target, PartyId = partyId })
end

local function row(
	order: number,
	text: string,
	color: Color3?,
	buttons: { { string } }?,
	handlers: { () -> () }?
)
	local frame = Build.New(
		"Frame",
		{ BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 32), LayoutOrder = order, Parent = list }
	)
	Build.Label({ Text = text, TextColor3 = color or C.Text, Size = UDim2.new(1, -200, 1, 0), Parent = frame })
	for index, button in buttons or {} do
		Build.Button({
			Text = button[1],
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -(index - 1) * 98, 0, 0),
			Size = UDim2.fromOffset(92, 30),
			Parent = frame,
		}, (handlers :: { () -> () })[index])
	end
end

local function render()
	if panel == nil then
		return
	end
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local state = PartyController.State
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	local isLeader = state.Leader == nil or state.Leader == player.UserId
	row(
		nextOrder(),
		if state.PartyId then `PARTY  {#state.Members}/{state.MaxSize or 8}` else "You are not in a party.",
		C.AccentBright
	)
	for _, member in state.Members do
		local you = member.UserId == player.UserId
		local label = `{member.Name}{if member.UserId == state.Leader then "  (leader)" else ""}{if you
			then "  (you)"
			else ""}`
		if isLeader and not you then
			row(nextOrder(), label, nil, { { "KICK" }, { "LEADER" } }, {
				function()
					action("Kick", member.UserId)
				end,
				function()
					action("Promote", member.UserId)
				end,
			})
		else
			row(nextOrder(), label)
		end
	end
	if state.PartyId then
		row(nextOrder(), "", nil, { { "LEAVE" } }, {
			function()
				action("Leave")
			end,
		})
	end
	for _, invite in state.Invites do
		row(nextOrder(), `Invite from {invite.From}`, C.Warning, { { "ACCEPT" }, { "DECLINE" } }, {
			function()
				action("Accept", nil, invite.PartyId)
			end,
			function()
				action("Decline", nil, invite.PartyId)
			end,
		})
	end
	if isLeader then
		row(nextOrder(), "INVITE PLAYERS IN THIS SERVER", C.TextMuted)
		local inParty = {}
		for _, member in state.Members do
			inParty[member.UserId] = true
		end
		for _, other in Players:GetPlayers() do
			if other ~= player and not inParty[other.UserId] then
				row(nextOrder(), other.DisplayName, nil, { { "INVITE" } }, {
					function()
						action("Invite", other.UserId)
						notifications:Show(`Invited {other.DisplayName}.`, "Info")
					end,
				})
			end
		end
	end
	list.CanvasSize = UDim2.fromOffset(0, order * 36)
end

function PartyController.SetOpen(_self: typeof(PartyController), open: boolean)
	if panel then
		panel.Visible = open
		UIState.SetMenuOpen("Party", open)
		if open then
			render()
		end
	end
end

function PartyController.Init(_self: typeof(PartyController), registry: { [string]: any })
	notifications = registry.NotificationController
end

function PartyController.Start(self: typeof(PartyController))
	if PlaceConfig.Role ~= "Hub" then
		return
	end
	local gui = Build.New("ScreenGui", {
		Name = "CrossbladeParty",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 17,
		Parent = player:WaitForChild("PlayerGui"),
	})
	panel = Build.Panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(500, 460),
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = gui,
	}, { Build.Padding(12) })
	Build.Label({
		Text = "PARTY",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Large,
		Size = UDim2.new(1, 0, 0, 26),
		Parent = panel,
	})
	list = Build.New("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 1, -80),
		CanvasSize = UDim2.new(),
		Parent = panel,
	}, {
		Build.New("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	Build.Button({
		Text = "CLOSE",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(150, 36),
		Parent = panel,
	}, function()
		self:SetOpen(false)
	end)
	Net.On("PartyState", function(state)
		self.State = state
		for _, invite in state.Invites do
			if not seenInvites[invite.PartyId] then
				seenInvites[invite.PartyId] = true
				notifications:Show(`{invite.From} invited you to a party (open PLAY > PARTY).`, "Info")
			end
		end
		if panel.Visible then
			render()
		end
	end)
	Players.PlayerAdded:Connect(function()
		if panel.Visible then
			render()
		end
	end)
end

return PartyController
