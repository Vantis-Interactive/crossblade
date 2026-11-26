--!strict
--[[
	Player settings (spec §6, §20): applies settings locally, persists them via the server (which
	sanitizes), and provides the settings panel. Every control in the panel is functional.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Settings = require(ReplicatedStorage.Shared.Settings)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Net = require(script.Parent.Parent.Core.Net)
local UIState = require(script.Parent.Parent.Core.UIState)
local Build = require(script.Parent.Parent.UI.Build)

local Theme = Config.Theme

local SettingsController = {
	Name = "SettingsController",
	Dependencies = { "SnapshotController", "InputController" },
	Current = Settings.Defaults(),
	Changed = Signal.new() :: Signal.Signal<Settings.Settings>,
}

local panel: Frame
local rows: { [string]: TextLabel } = {}
local draft: Settings.Settings = Settings.Defaults()

local function cycle<T>(list: { T }, current: T): T
	local index = table.find(list, current) or 0
	return list[index % #list + 1]
end

local function describe(value: any): string
	if type(value) == "boolean" then
		return if value then "ON" else "OFF"
	elseif type(value) == "number" then
		return if value % 1 == 0 then tostring(value) else string.format("%.2f", value)
	end
	return tostring(value)
end

local function refresh()
	for key, label in rows do
		label.Text = describe((draft :: any)[key])
	end
end

function SettingsController.Apply(self: typeof(SettingsController), settings: any)
	self.Current = Settings.Sanitize(settings)
	draft = table.clone(self.Current)
	refresh()
	self.Changed:Fire(self.Current)
end

function SettingsController.SetOpen(_self: typeof(SettingsController), open: boolean)
	if panel == nil then
		return
	end
	panel.Visible = open
	UIState.SetMenuOpen("Settings", open)
	if open then
		draft = table.clone(SettingsController.Current)
		refresh()
		local first = panel:FindFirstChild("FirstSelectable", true)
		if first and first:IsA("GuiObject") then
			GuiService.SelectedObject = first
		end
	elseif GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(panel) then
		GuiService.SelectedObject = nil
	end
end

local function buildPanel(gui: ScreenGui)
	local camera = Config.Camera
	panel = Build.Panel({
		Name = "Settings",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(460, 520),
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = gui,
	}, { Build.Padding(16) })
	Build.Label({
		Text = "SETTINGS",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Large,
		Size = UDim2.new(1, 0, 0, 30),
		Parent = panel,
	})
	local list = Build.New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 1, -100),
		Parent = panel,
	}, {
		Build.New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	local order = 0
	local firstAssigned = false
	local function row(key: string, title: string, onLeft: () -> (), onRight: () -> ())
		order += 1
		local frame = Build.New(
			"Frame",
			{ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = order, Parent = list }
		)
		Build.Label({
			Text = title,
			Size = UDim2.new(0.5, 0, 1, 0),
			TextColor3 = Theme.Colors.TextMuted,
			Parent = frame,
		})
		local left = Build.Button({
			Text = "<",
			Size = UDim2.fromOffset(34, 30),
			Position = UDim2.new(0.5, 0, 0, 2),
			Parent = frame,
		}, function()
			onLeft()
			refresh()
		end)
		if not firstAssigned then
			left.Name = "FirstSelectable"
			firstAssigned = true
		end
		rows[key] = Build.Label({
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Theme.Fonts.Mono,
			Size = UDim2.new(0.5, -76, 1, 0),
			Position = UDim2.new(0.5, 38, 0, 0),
			Parent = frame,
		})
		Build.Button({
			Text = ">",
			Size = UDim2.fromOffset(34, 30),
			Position = UDim2.new(1, -34, 0, 2),
			Parent = frame,
		}, function()
			onRight()
			refresh()
		end)
	end
	local function numeric(key: string, title: string, step: number, min: number, max: number)
		row(key, title, function()
			(draft :: any)[key] = math.clamp((draft :: any)[key] - step, min, max)
		end, function()
			(draft :: any)[key] = math.clamp((draft :: any)[key] + step, min, max)
		end)
	end
	local function choice(key: string, title: string, options: { any })
		local function step()
			(draft :: any)[key] = cycle(options, (draft :: any)[key])
		end
		row(key, title, step, step)
	end

	numeric("FieldOfView", "Field of view", 1, camera.FieldOfView.Min, camera.FieldOfView.Max)
	numeric("Sensitivity", "Sensitivity", 0.05, camera.Sensitivity.Min, camera.Sensitivity.Max)
	numeric(
		"AimSensitivity",
		"Aim sensitivity",
		0.05,
		camera.AimSensitivityMultiplier.Min,
		camera.AimSensitivityMultiplier.Max
	)
	choice("Perspective", "Default camera", { "ThirdPerson", "FirstPerson" })
	choice("CrosshairStyle", "Crosshair style", { "Cross", "Dot", "Circle" })
	choice("CrosshairColor", "Crosshair colour", { "White", "Green", "Yellow", "Cyan", "Magenta" })
	numeric("CrosshairSize", "Crosshair size", 1, 4, 40)
	choice("ReducedMotion", "Reduced motion", { false, true })
	choice("DamageNumbers", "Damage numbers", { true, false })

	local footer = Build.New("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 44),
		Parent = panel,
	})
	Build.Button({ Text = "DEFAULTS", Size = UDim2.new(0.3, -6, 1, 0), Parent = footer }, function()
		draft = Settings.Defaults()
		refresh()
	end)
	Build.Button({
		Text = "CANCEL",
		Size = UDim2.new(0.3, -6, 1, 0),
		Position = UDim2.fromScale(0.35, 0),
		Parent = footer,
	}, function()
		SettingsController:SetOpen(false)
	end)
	Build.Button({
		Text = "SAVE",
		BackgroundColor3 = Theme.Colors.Accent,
		Size = UDim2.new(0.3, 0, 1, 0),
		Position = UDim2.fromScale(0.7, 0),
		Parent = footer,
	}, function()
		SettingsController:Apply(draft)
		Net.Fire("SaveSettings", SettingsController.Current)
		SettingsController:SetOpen(false)
	end)
end

function SettingsController.Init(self: typeof(SettingsController), registry: { [string]: any })
	registry.SnapshotController.Loaded:Connect(function(snapshot)
		self:Apply(snapshot.Settings)
	end)
	registry.InputController.Began:Connect(function(action: string)
		if action == "Settings" then
			self:SetOpen(not (panel and panel.Visible))
		end
	end)
end

function SettingsController.Start(self: typeof(SettingsController))
	local gui = Build.New("ScreenGui", {
		Name = "CrossbladeSettings",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 20,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	buildPanel(gui)
	Net.On("SettingsApplied", function(sanitized)
		self:Apply(sanitized)
	end)
end

return SettingsController
