--!strict
--[[
	Tutorial guide panel (spec §27), hub only. Shows the current step from the server's
	TutorialState and reports completion of client-checked steps (movement, camera, weapon switching,
	the informational coins step, and travel intent). Server-checked steps complete from gameplay.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Parent.Core.Net)
local Build = require(script.Parent.Parent.UI.Build)

local Theme = Config.Theme
local T = Config.Tutorial

local TutorialController = {
	Name = "TutorialController",
	Roles = { "Hub" },
	Dependencies = { "InputController", "CameraController", "WeaponController", "LobbyController" },
}

local player = Players.LocalPlayer
local state: { [string]: any } = { Active = false }
local panel: Frame
local titleLabel: TextLabel
local bodyLabel: TextLabel
local continueButton: TextButton
local exitButton: TextButton
local progress = { Moved = 0, Sprinted = false, Jumped = false, Secondary = false, Knife = false }
local reported: { [number]: boolean } = {}

local function current(): any
	return if state.Active and state.Index then T.Steps[state.Index] else nil
end

local function complete(stepId: string)
	local step = current()
	if step and step.Id == stepId and step.Check == "Client" and not reported[state.Index] then
		reported[state.Index] = true
		Net.Fire("TutorialAction", { Action = "Complete", Step = state.Index })
	end
end

local function render()
	if panel == nil then
		return
	end
	local step = current()
	panel.Visible = step ~= nil
	if step == nil then
		return
	end
	titleLabel.Text = `TUTORIAL {state.Index}/{state.Total or #T.Steps}   •   {string.upper(step.Title)}`
	bodyLabel.Text = step.Text
	continueButton.Visible = step.Id == "Coins"
	exitButton.Visible = state.Completed == true
end

function TutorialController.Init(_self: typeof(TutorialController), registry: { [string]: any })
	registry.InputController.Began:Connect(function(action: string)
		if action == "Sprint" then
			progress.Sprinted = true
		end
	end)
	registry.CameraController.PerspectiveChanged:Connect(function()
		complete("Camera")
	end)
	registry.WeaponController.Changed:Connect(function(weaponState)
		if weaponState.Equipped == "Secondary" then
			progress.Secondary = true
		elseif weaponState.Equipped == "Knife" then
			progress.Knife = true
		end
		if progress.Secondary and progress.Knife then
			complete("Weapons")
		end
	end)
	registry.LobbyController.TravelIntent:Connect(function()
		complete("Matchmaking")
	end)
end

function TutorialController.Start(_self: typeof(TutorialController))
	local gui = Build.New("ScreenGui", {
		Name = "CrossbladeTutorial",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 13,
		Parent = player:WaitForChild("PlayerGui"),
	})
	panel = Build.Panel({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 260),
		Size = UDim2.fromOffset(340, 150),
		Visible = false,
		Parent = gui,
	}, { Build.Padding(10) })
	titleLabel = Build.Label({
		Text = "",
		Font = Theme.Fonts.Heading,
		TextColor3 = Theme.Colors.AccentBright,
		Size = UDim2.new(1, 0, 0, 20),
		Parent = panel,
	})
	bodyLabel = Build.Label({
		Text = "",
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 1, -66),
		Parent = panel,
	})
	continueButton = Build.Button({
		Text = "CONTINUE",
		BackgroundColor3 = Theme.Colors.Accent,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(150, 32),
		Parent = panel,
	}, function()
		complete("Coins")
	end)
	exitButton = Build.Button({
		Text = "EXIT TUTORIAL",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(150, 32),
		Parent = panel,
	}, function()
		Net.Fire("TutorialAction", { Action = "Exit" })
	end)

	Net.On("TutorialState", function(payload)
		if payload.Index ~= state.Index then
			table.clear(reported)
		end
		state = payload
		render()
	end)

	local function watchCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if humanoid then
			humanoid.StateChanged:Connect(function(_, new)
				if new == Enum.HumanoidStateType.Jumping then
					progress.Jumped = true
				end
			end)
		end
	end
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end

	RunService.Heartbeat:Connect(function(dt)
		local step = current()
		if step == nil or step.Id ~= "Move" then
			return
		end
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.MoveDirection.Magnitude > 0.1 then
			progress.Moved += dt
		end
		if progress.Moved >= 1 and progress.Sprinted and progress.Jumped then
			complete("Move")
		end
	end)
end

return TutorialController
