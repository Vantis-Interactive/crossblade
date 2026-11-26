--!strict
-- Short toast notifications (pickups, warnings, system messages).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Parent.Core.Net)
local Build = require(script.Parent.Parent.UI.Build)

local Theme = Config.Theme

local NotificationController = {
	Name = "NotificationController",
	Dependencies = { "SettingsController" },
}

local container: Frame
local settings: any

function NotificationController.Show(_self: typeof(NotificationController), text: string, kind: string?)
	if container == nil then
		return
	end
	local color = if kind == "Warning"
		then Theme.Colors.Warning
		elseif kind == "Pickup" then Theme.Colors.Health
		else Theme.Colors.Text
	local toast = Build.Panel(
		{ Size = UDim2.fromOffset(320, 30), BackgroundColor3 = Theme.Colors.Background, Parent = container },
		{}
	)
	Build.Label({
		Text = text,
		TextColor3 = color,
		Font = Theme.Fonts.Heading,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		Size = UDim2.fromScale(1, 1),
		Parent = toast,
	})
	local duration = if kind == "Warning" then 6 else 2.2
	task.delay(duration, function()
		local fadeTime = if settings.Current.ReducedMotion then 0 else Theme.Motion.Normal
		TweenService:Create(toast, TweenInfo.new(fadeTime), { BackgroundTransparency = 1 }):Play()
		task.wait(fadeTime)
		toast:Destroy()
	end)
end

function NotificationController.Init(_self: typeof(NotificationController), registry: { [string]: any })
	settings = registry.SettingsController
end

function NotificationController.Start(self: typeof(NotificationController))
	local gui = Build.New("ScreenGui", {
		Name = "CrossbladeNotifications",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 15,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	container = Build.New("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 96),
		Size = UDim2.fromOffset(320, 200),
		Parent = gui,
	}, {
		Build.New(
			"UIListLayout",
			{ Padding = UDim.new(0, 4), HorizontalAlignment = Enum.HorizontalAlignment.Center }
		),
	})
	Net.On("Notification", function(payload)
		self:Show(payload.Text, payload.Kind)
	end)
end

return NotificationController
