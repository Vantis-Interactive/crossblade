--!strict
--[[
	Duel spectating (spec §5, §10): eliminated players watch surviving participants until the next
	round. Teammates are preferred; FIRE / AIM cycle targets. Purely client-side camera behaviour.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Parent.Core.Net)
local Build = require(script.Parent.Parent.UI.Build)

local SpectatorController = {
	Name = "SpectatorController",
	Dependencies = { "CameraController", "InputController", "SnapshotController" },
}

local player = Players.LocalPlayer
local camera: any
local match: { [string]: any } = {}
local label: TextLabel
local cycleOffset = 0

local function alive(other: Player): boolean
	local humanoid = other.Character and other.Character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function candidates(): { Player }
	local myTeam = player:GetAttribute("Team")
	local list = {}
	for _, other in Players:GetPlayers() do
		if other ~= player and alive(other) and other:GetAttribute("Team") ~= nil then
			table.insert(list, other)
		end
	end
	table.sort(list, function(a, b)
		local aMine, bMine = a:GetAttribute("Team") == myTeam, b:GetAttribute("Team") == myTeam
		if aMine ~= bMine then
			return aMine
		end
		return a.UserId < b.UserId
	end)
	return list
end

local function update()
	local spectating = match.Kind == "Duel"
		and (match.Phase == "Active" or match.Phase == "RoundEnd")
		and not alive(player)
	local list = if spectating then candidates() else {}
	if #list == 0 then
		camera.SpectateTarget = nil
		label.Visible = false
		return
	end
	local index = (cycleOffset % #list) + 1
	local target = list[index]
	camera.SpectateTarget = target
	label.Visible = true
	label.Text = `SPECTATING {string.upper(target.DisplayName)}   •   FIRE / AIM to switch`
end

function SpectatorController.Init(_self: typeof(SpectatorController), registry: { [string]: any })
	camera = registry.CameraController
	registry.SnapshotController.Loaded:Connect(function(snapshot)
		match = snapshot.Match or {}
	end)
	registry.InputController.Began:Connect(function(action: string)
		if camera.SpectateTarget and (action == "Fire" or action == "Aim") then
			cycleOffset += if action == "Fire" then 1 else -1
		end
	end)
end

function SpectatorController.Start(_self: typeof(SpectatorController))
	local gui = Build.New("ScreenGui", {
		Name = "CrossbladeSpectator",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 12,
		Parent = player:WaitForChild("PlayerGui"),
	})
	label = Build.Label({
		Text = "",
		Font = Config.Theme.Fonts.Heading,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.5,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -90),
		Size = UDim2.fromOffset(600, 24),
		Visible = false,
		Parent = gui,
	})
	Net.On("MatchState", function(state)
		match = state
	end)
	RunService.RenderStepped:Connect(update)
end

return SpectatorController
