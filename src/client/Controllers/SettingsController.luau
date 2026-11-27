--!strict
--[[
	Player settings (spec §6, §20): applies settings locally, persists them via the server (which
	sanitizes), and provides the settings panel. Every control in the panel is functional.
]]

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Settings = require(ReplicatedStorage.Shared.Settings)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Net = require(script.Parent.Parent.Core.Net)
local UIState = require(script.Parent.Parent.Core.UIState)
local Build = require(script.Parent.Parent.UI.Build)
local Bindings = require(ReplicatedStorage.Shared.Bindings)

local input: any
local refreshControls: () -> ()
local buildControls: (list: Frame) -> ()

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

local function cloneSettings(settings: Settings.Settings): Settings.Settings
	local copy = table.clone(settings)
	copy.Bindings = {}
	for action, override in settings.Bindings do
		copy.Bindings[action] = table.clone(override)
	end
	return copy
end

function SettingsController.Apply(self: typeof(SettingsController), settings: any)
	self.Current = Settings.Sanitize(settings)
	draft = cloneSettings(self.Current)
	refresh()
	if input then
		input:Rebind(self.Current.Bindings)
	end
	self.Changed:Fire(self.Current)
end

-- Network form: bindings travel as an array (see Net/Contracts SaveSettings).
local function toWire(settings: Settings.Settings): { [string]: any }
	local payload = table.clone(settings) :: any
	payload.Bindings = Bindings.ToWire(settings.Bindings)
	return payload
end

function SettingsController.SetOpen(_self: typeof(SettingsController), open: boolean)
	if panel == nil then
		return
	end
	panel.Visible = open
	UIState.SetMenuOpen("Settings", open)
	if open then
		draft = cloneSettings(SettingsController.Current)
		refresh()
		refreshControls()
		local first = panel:FindFirstChild("FirstSelectable", true)
		if first and first:IsA("GuiObject") then
			GuiService.SelectedObject = first
		end
	elseif GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(panel) then
		GuiService.SelectedObject = nil
	end
end

-- CONTROLS page: click a binding, then press the new key/button. Rules are Shared/Bindings.
local controlsFrame: ScrollingFrame
local controlButtons: { [string]: { Keyboard: TextButton, Gamepad: TextButton } } = {}
local controlStatus: TextLabel
local capturing: { Action: string, Family: "Keyboard" | "Gamepad", Since: number }? = nil

refreshControls = function()
	if controlsFrame == nil then
		return
	end
	for action, buttons in controlButtons do
		local keyboard, gamepad = Bindings.Effective(draft.Bindings, action)
		buttons.Keyboard.Text = if capturing
				and capturing.Action == action
				and capturing.Family == "Keyboard"
			then "PRESS A KEY"
			else (keyboard or "-")
		buttons.Gamepad.Text = if capturing
				and capturing.Action == action
				and capturing.Family == "Gamepad"
			then "PRESS A BUTTON"
			else (gamepad or "-")
	end
end

local function capture(inputObject: InputObject)
	local current = capturing
	if current == nil or os.clock() - current.Since < 0.25 then
		return
	end
	if inputObject.KeyCode == Enum.KeyCode.Escape then
		capturing = nil
		refreshControls()
		return
	end
	local name: string? = nil
	if current.Family == "Keyboard" then
		if inputObject.UserInputType == Enum.UserInputType.Keyboard then
			name = inputObject.KeyCode.Name
		elseif string.match(inputObject.UserInputType.Name, "^MouseButton%d$") then
			name = inputObject.UserInputType.Name
		end
	elseif string.find(inputObject.UserInputType.Name, "Gamepad") then
		name = inputObject.KeyCode.Name
	end
	if name == nil then
		return
	end
	capturing = nil
	local allowed = if current.Family == "Keyboard" then Bindings.KeyboardAllowed else Bindings.GamepadAllowed
	if not allowed[name] then
		controlStatus.Text = `{name} cannot be bound.`
	else
		local usedBy = Bindings.UsedBy(draft.Bindings, current.Family, name, current.Action)
		if usedBy then
			controlStatus.Text = `{name} is already used by {usedBy}.`
		else
			local override = table.clone(draft.Bindings[current.Action] or {})
			override[current.Family] = name
			draft.Bindings[current.Action] = override
			controlStatus.Text = `{current.Action} -> {name}`
		end
	end
	refreshControls()
end

buildControls = function(list: Frame)
	local page = Build.New(
		"Frame",
		{ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = list.Parent }
	)
	page.Position = list.Position
	page.Size = list.Size
	controlStatus = Build.Label({
		Text = "Click a binding, then press the new key. Esc cancels.",
		TextColor3 = Theme.Colors.TextMuted,
		TextSize = 12,
		Size = UDim2.new(1, 0, 0, 18),
		Parent = page,
	})
	controlsFrame = Build.New("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 1, -60),
		CanvasSize = UDim2.new(),
		Parent = page,
	}, {
		Build.New("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for order, action in Bindings.Actions() do
		local row = Build.New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -8, 0, 28),
			LayoutOrder = order,
			Parent = controlsFrame,
		})
		Build.Label({ Text = action, TextSize = 14, Size = UDim2.new(0.4, 0, 1, 0), Parent = row })
		local function begin(family: "Keyboard" | "Gamepad")
			capturing = { Action = action, Family = family, Since = os.clock() }
			refreshControls()
		end
		controlButtons[action] = {
			Keyboard = Build.Button({
				Text = "",
				TextSize = 13,
				Position = UDim2.fromScale(0.4, 0),
				Size = UDim2.new(0.3, -4, 1, 0),
				Parent = row,
			}, function()
				begin("Keyboard")
			end),
			Gamepad = Build.Button({
				Text = "",
				TextSize = 13,
				Position = UDim2.fromScale(0.7, 0),
				Size = UDim2.new(0.3, -4, 1, 0),
				Parent = row,
			}, function()
				begin("Gamepad")
			end),
		}
	end
	controlsFrame.CanvasSize = UDim2.fromOffset(0, #Bindings.Actions() * 31)
	Build.Button({
		Text = "RESET CONTROLS",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 32),
		Parent = page,
	}, function()
		draft.Bindings = {}
		refreshControls()
	end)
	local pageButton: TextButton
	pageButton = Build.Button({
		Text = "CONTROLS",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, -36),
		Size = UDim2.fromOffset(120, 30),
		Parent = list.Parent,
	}, function()
		page.Visible = not page.Visible
		list.Visible = not page.Visible
		pageButton.Text = if page.Visible then "GENERAL" else "CONTROLS"
		capturing = nil
		refreshControls()
	end)
	pageButton.Position = UDim2.new(1, 0, 0, 0)
	UserInputService.InputBegan:Connect(capture)
	refreshControls()
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
		refreshControls()
	end)
	buildControls(list)
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
		Net.Fire("SaveSettings", toWire(SettingsController.Current))
		SettingsController:SetOpen(false)
	end)
end

function SettingsController.Init(self: typeof(SettingsController), registry: { [string]: any })
	input = registry.InputController
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
