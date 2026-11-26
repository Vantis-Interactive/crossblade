--!strict
-- Map vote panel during intermission (spec §5, §17). One vote per player; votes can be changed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Parent.Core.Net)
local Build = require(script.Parent.Parent.UI.Build)

local Theme = Config.Theme

local VoteController = {
	Name = "VoteController",
	Dependencies = { "SnapshotController" },
}

local panel: Frame
local list: Frame
local myChoice: string? = nil
local currentKey = ""

local function render(vote: { [string]: any }?)
	if panel == nil then
		return
	end
	if vote == nil or #vote.Options == 0 then
		panel.Visible = false
		myChoice = nil
		currentKey = ""
		return
	end
	local key = ""
	for _, option in vote.Options do
		key ..= option.Id .. ","
	end
	if key ~= currentKey then
		currentKey = key
		myChoice = nil
	end
	panel.Visible = true
	for _, child in list:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	for order, option in vote.Options do
		local chosen = myChoice == option.Id
		Build.Button({
			Text = `{option.DisplayName}   ({option.Votes})` .. (if chosen then "   ✓" else ""),
			Size = UDim2.new(1, 0, 0, 34),
			LayoutOrder = order,
			BackgroundColor3 = if chosen then Theme.Colors.Accent else Theme.Colors.PanelRaised,
			Parent = list,
		}, function()
			myChoice = option.Id
			Net.Fire("VoteMap", { MapId = option.Id })
			render(vote)
		end)
	end
end

function VoteController.Init(_self: typeof(VoteController), registry: { [string]: any })
	registry.SnapshotController.Loaded:Connect(function(snapshot)
		render(snapshot.Match and snapshot.Match.Vote)
	end)
end

function VoteController.Start(_self: typeof(VoteController))
	local gui = Build.New("ScreenGui", {
		Name = "CrossbladeVote",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 14,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	panel = Build.Panel({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -116),
		Size = UDim2.fromOffset(300, 170),
		Visible = false,
		Parent = gui,
	}, { Build.Padding(8) })
	Build.Label({
		Text = "VOTE FOR THE NEXT MAP",
		Font = Theme.Fonts.Heading,
		Size = UDim2.new(1, 0, 0, 20),
		Parent = panel,
	})
	list = Build.New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 1, -26),
		Parent = panel,
	}, {
		Build.New("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	Net.On("MatchState", function(state)
		render(if state.Phase == "Intermission" then state.Vote else nil)
	end)
	Net.On("MapVote", function(vote)
		render(vote)
	end)
end

return VoteController
