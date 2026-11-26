--!strict
--[[
	Combat HUD (spec §9, §10, §20). Built in code from Config.Theme; responsive via UIScale.
	Rarity is shown with a symbol and name as well as colour. Every interactive element works with
	mouse, touch and gamepad (slot buttons, scoreboard toggle, settings toggle).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Settings = require(ReplicatedStorage.Shared.Settings)
local WeaponCatalog = require(ReplicatedStorage.Shared.Weapons.WeaponCatalog)
local Net = require(script.Parent.Parent.Core.Net)
local Build = require(script.Parent.Parent.UI.Build)

local Theme = Config.Theme
local C = Theme.Colors

local HUDController = {
	Name = "HUDController",
	Dependencies = {
		"InputController",
		"SettingsController",
		"WeaponController",
		"CameraController",
		"SnapshotController",
		"EffectsController",
	},
}

local player = Players.LocalPlayer
local settings: any
local weapons: any
local camera: any
local effects: any

local gui: ScreenGui
local ui: { [string]: any } = {}
local match: { [string]: any } = { Phase = "Intermission", EndsAt = 0 }
local scoreboardRows: { any } = {}
local respawnAt: number? = nil
local hitMarkerUntil = 0
local bloom = 0
local built = false
local pendingSnapshot: { [string]: any }? = nil

local function weaponName(weaponId: string?): string
	local entry = weaponId and WeaponCatalog.Get(weaponId)
	return if entry then entry.DisplayName else "Environment"
end

local function rarityTag(weaponId: string?): (string, Color3)
	local entry = weaponId and WeaponCatalog.Get(weaponId)
	local tier = entry and Config.Rarity.Tiers[entry.Rarity]
	if entry and tier then
		return `{tier.Symbol} {string.upper(entry.Rarity)}`, tier.Color
	end
	return "", C.TextMuted
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function disableCoreGui()
	for _, kind in { Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health, Enum.CoreGuiType.PlayerList } do
		pcall(function()
			StarterGui:SetCoreGuiEnabled(kind, false)
		end)
	end
end

local function buildCrosshair()
	local root = Build.New("Frame", {
		Name = "Crosshair",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(80, 80),
		Parent = gui,
	})
	ui.CrosshairBars = {}
	for index = 1, 4 do
		ui.CrosshairBars[index] =
			Build.New("Frame", { BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Parent = root })
	end
	ui.CrosshairDot = Build.New("Frame", {
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(4, 4),
		Parent = root,
	}, { Build.Corner(UDim.new(1, 0)) })
	ui.CrosshairRing = Build.New("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Parent = root,
	}, { Build.Corner(UDim.new(1, 0)), Build.New("UIStroke", { Thickness = 2 }) })
	ui.HitMarker = {}
	for index = 1, 4 do
		local angle = 45 + (index - 1) * 90
		local rad = math.rad(angle)
		ui.HitMarker[index] = Build.New("Frame", {
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.cos(rad) * 14, 0.5, math.sin(rad) * 14),
			Size = UDim2.fromOffset(12, 2),
			Rotation = angle,
			Visible = false,
			Parent = root,
		})
	end
	ui.Crosshair = root
end

local function updateCrosshair(dt: number)
	local current = settings.Current
	local color = Settings.CrosshairColors[current.CrosshairColor] or Color3.new(1, 1, 1)
	local size = current.CrosshairSize
	bloom = math.max(0, bloom - dt * 30)
	local gap = 4 + bloom + (if camera.Aiming then 0 else 2)
	local style = current.CrosshairStyle
	local state = weapons.State
	local showGun = state ~= nil and state.Equipped ~= "Knife"
	for index, bar in ui.CrosshairBars do
		local horizontal = index <= 2
		local sign = if index % 2 == 1 then -1 else 1
		bar.Visible = style == "Cross"
		bar.BackgroundColor3 = color
		bar.Size = if horizontal then UDim2.fromOffset(size, 2) else UDim2.fromOffset(2, size)
		local distance = gap + size / 2
		bar.Position = if horizontal
			then UDim2.new(0.5, sign * distance, 0.5, 0)
			else UDim2.new(0.5, 0, 0.5, sign * distance)
	end
	ui.CrosshairDot.Visible = style == "Dot" or not showGun
	ui.CrosshairDot.BackgroundColor3 = color
	ui.CrosshairRing.Visible = style == "Circle" and showGun
	ui.CrosshairRing.Size = UDim2.fromOffset(size + gap * 2, size + gap * 2)
	ui.CrosshairRing.UIStroke.Color = color
	local showMarker = os.clock() < hitMarkerUntil
	for _, bar in ui.HitMarker do
		bar.Visible = showMarker
	end
end

local function buildPanels()
	-- Health (bottom-left)
	local health = Build.Panel({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -16),
		Size = UDim2.fromOffset(280, 64),
		Parent = gui,
	}, { Build.Padding(8) })
	Build.Label({
		Text = "HEALTH",
		TextSize = Theme.TextSize.Small,
		TextColor3 = C.TextMuted,
		Size = UDim2.new(1, 0, 0, 14),
		Parent = health,
	})
	ui.HealthValue = Build.Label({
		Text = "150",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Large,
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(0, 70, 0, 26),
		Parent = health,
	})
	local track = Build.New("Frame", {
		BackgroundColor3 = C.Background,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(74, 22),
		Size = UDim2.new(1, -74, 0, 12),
		Parent = health,
	}, { Build.Corner() })
	ui.HealthFill = Build.New(
		"Frame",
		{ BackgroundColor3 = C.Health, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = track },
		{ Build.Corner() }
	)
	ui.Protection = Build.Label({
		Text = "SPAWN PROTECTION",
		TextColor3 = C.AccentBright,
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Small,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -86),
		Size = UDim2.fromOffset(280, 18),
		Visible = false,
		Parent = gui,
	})

	-- Ammo (bottom-right)
	local ammo = Build.Panel({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(280, 84),
		Parent = gui,
	}, { Build.Padding(8) })
	ui.WeaponName = Build.Label({
		Text = "",
		TextSize = Theme.TextSize.Small,
		TextColor3 = C.TextMuted,
		Size = UDim2.new(1, 0, 0, 14),
		Parent = ammo,
	})
	ui.AmmoValue = Build.Label({
		Text = "",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Huge,
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 36),
		Parent = ammo,
	})
	local reloadTrack = Build.New("Frame", {
		BackgroundColor3 = C.Background,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, -8),
		Size = UDim2.new(1, 0, 0, 6),
		Parent = ammo,
	}, { Build.Corner() })
	ui.ReloadFill = Build.New("Frame", {
		BackgroundColor3 = C.Accent,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = reloadTrack,
	}, { Build.Corner() })

	-- Weapon slots (bottom-centre), clickable / tappable / gamepad-selectable
	local slots = Build.New("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(510, 56),
		Parent = gui,
	}, {
		Build.New("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
	})
	ui.Slots = {}
	for index, slot in WeaponCatalog.Slots do
		local button = Build.Button({
			Text = "",
			Size = UDim2.fromOffset(166, 56),
			LayoutOrder = index,
			BackgroundTransparency = 0.15,
			Parent = slots,
		}, function()
			weapons:Equip(slot)
		end)
		local title = Build.Label({
			Text = `{index}  {string.upper(slot)}`,
			TextSize = Theme.TextSize.Small,
			TextColor3 = C.TextMuted,
			Position = UDim2.fromOffset(8, 4),
			Size = UDim2.new(1, -16, 0, 14),
			Parent = button,
		})
		local name = Build.Label({
			Text = "",
			Font = Theme.Fonts.Heading,
			Position = UDim2.fromOffset(8, 18),
			Size = UDim2.new(1, -16, 0, 18),
			Parent = button,
		})
		local rarity = Build.Label({
			Text = "",
			TextSize = 12,
			Position = UDim2.fromOffset(8, 36),
			Size = UDim2.new(1, -16, 0, 14),
			Parent = button,
		})
		ui.Slots[slot] = { Button = button, Title = title, Name = name, Rarity = rarity }
	end

	-- Match bar (top-centre)
	local bar = Build.Panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(420, 72),
		Parent = gui,
	}, { Build.Padding(6) })
	ui.MatchTitle = Build.Label({
		Text = "",
		TextSize = Theme.TextSize.Small,
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 14),
		Parent = bar,
	})
	ui.MatchTimer = Build.Label({
		Text = "",
		Font = Theme.Fonts.Mono,
		TextSize = Theme.TextSize.Large,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 26),
		Parent = bar,
	})
	ui.Leader = Build.Label({
		Text = "",
		TextSize = Theme.TextSize.Small,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 42),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = bar,
	})

	-- Top-left buttons (work on touch and gamepad)
	Build.Button(
		{ Text = "SCORE", Position = UDim2.fromOffset(16, 12), Size = UDim2.fromOffset(84, 32), Parent = gui },
		function()
			ui.Scoreboard.Visible = not ui.Scoreboard.Visible
		end
	)
	Build.Button({
		Text = "SETTINGS",
		Position = UDim2.fromOffset(106, 12),
		Size = UDim2.fromOffset(100, 32),
		Parent = gui,
	}, function()
		settings:SetOpen(true)
	end)

	-- Kill feed (top-right)
	ui.KillFeed = Build.New("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 12),
		Size = UDim2.fromOffset(380, 180),
		Parent = gui,
	}, {
		Build.New("UIListLayout", {
			Padding = UDim.new(0, 4),
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	-- Centre announcements and elimination screen
	ui.Announcement = Build.Label({
		Text = "",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Huge,
		TextColor3 = C.AccentBright,
		TextStrokeTransparency = 0.5,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(700, 44),
		Visible = false,
		Parent = gui,
	})
	ui.Toast = Build.Label({
		Text = "",
		Font = Theme.Fonts.Heading,
		TextColor3 = C.Text,
		TextStrokeTransparency = 0.5,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromOffset(500, 24),
		Visible = false,
		Parent = gui,
	})
	local eliminated = Build.Panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(520, 110),
		Visible = false,
		BackgroundColor3 = C.Background,
		Parent = gui,
	}, { Build.Padding(10) })
	ui.ElimTitle = Build.Label({
		Text = "",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Large,
		TextColor3 = C.Danger,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 28),
		Parent = eliminated,
	})
	ui.ElimDetail = Build.Label({
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = eliminated,
	})
	ui.ElimRespawn = Build.Label({
		Text = "",
		Font = Theme.Fonts.Mono,
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 60),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = eliminated,
	})
	ui.Eliminated = eliminated

	-- Directional damage indicators
	ui.DamageRing = Build.New("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(1, 1),
		Parent = gui,
	})

	-- Scoreboard / results
	local board = Build.Panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(620, 460),
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = gui,
	}, { Build.Padding(12) })
	ui.BoardTitle = Build.Label({
		Text = "SCOREBOARD",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Large,
		Size = UDim2.new(1, 0, 0, 28),
		Parent = board,
	})
	ui.BoardRows = Build.New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 1, -36),
		Parent = board,
	}, {
		Build.New("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	ui.Scoreboard = board

	Build.New("UIScale", { Parent = gui })
end

local function renderScoreboard(rows: { any }, title: string)
	ui.BoardTitle.Text = title
	for _, child in ui.BoardRows:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local function line(order: number, cells: { string }, color: Color3, font: Enum.Font)
		local frame = Build.New("Frame", {
			BackgroundTransparency = if order % 2 == 0 then 1 else 0.85,
			BackgroundColor3 = C.PanelRaised,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 24),
			LayoutOrder = order,
			Parent = ui.BoardRows,
		})
		local widths = { 0.08, 0.4, 0.1, 0.1, 0.1, 0.1, 0.12 }
		local x = 0
		for index, text in cells do
			Build.Label({
				Text = text,
				TextColor3 = color,
				Font = font,
				Position = UDim2.fromScale(x, 0),
				Size = UDim2.fromScale(widths[index] or 0.1, 1),
				Parent = frame,
			})
			x += widths[index] or 0.1
		end
	end
	line(0, { "#", "PLAYER", "ELIM", "DEATHS", "ASSISTS", "LEVEL", "PING" }, C.TextMuted, Theme.Fonts.Heading)
	for index, row in rows do
		if index > 16 then
			break
		end
		local color = if row.UserId == player.UserId then C.AccentBright else C.Text
		line(index, {
			tostring(row.Rank),
			row.Name,
			tostring(row.Eliminations),
			tostring(row.Deaths),
			tostring(row.Assists),
			tostring(row.Level or "-"),
			if row.Ping then `{row.Ping}ms` else "-",
		}, color, Theme.Fonts.Body)
	end
end

local function updateLoadout()
	local state = weapons.State
	if state == nil or not built then
		return
	end
	for _, slot in WeaponCatalog.Slots do
		local widgets = ui.Slots[slot]
		local weaponId = state.Loadout[slot]
		local active = state.Equipped == slot
		widgets.Name.Text = weaponName(weaponId)
		local tag, color = rarityTag(weaponId)
		widgets.Rarity.Text = tag
		widgets.Rarity.TextColor3 = color
		if slot == "Knife" and not state.KnifeInHand then
			widgets.Rarity.Text = "THROWN - RECOVER OR USE STATION"
			widgets.Rarity.TextColor3 = C.Warning
		end
		widgets.Button.BackgroundColor3 = if active then C.Accent else C.PanelRaised
		widgets.Title.TextColor3 = if active then C.Text else C.TextMuted
	end
	ui.WeaponName.Text = string.upper(weaponName(state.Loadout[state.Equipped]))
end

local function updateFrame(dt: number)
	local now = Net.Now()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local health = if humanoid then math.max(0, humanoid.Health) else 0
	local fraction = health / Config.Player.MaxHealth
	ui.HealthValue.Text = tostring(math.ceil(health))
	ui.HealthFill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	ui.HealthFill.BackgroundColor3 = if fraction <= 0.3 then C.HealthLow else C.Health
	ui.Protection.Visible = character ~= nil and character:FindFirstChildOfClass("ForceField") ~= nil

	local state = weapons.State
	if state then
		if state.Equipped == "Knife" then
			ui.AmmoValue.Text = if state.KnifeInHand then "KNIFE" else "THROWN"
			ui.ReloadFill.Size = UDim2.fromScale(0, 1)
		else
			local ammo = state.Ammo[state.Equipped]
			local stats = weapons:FirearmStats()
			if ammo and stats then
				ui.AmmoValue.Text = `{ammo.Magazine} / {ammo.Reserve}`
				ui.AmmoValue.TextColor3 = if ammo.Magazine == 0 then C.Danger else C.Text
				local reloadEnds = ammo.ReloadEndsAt
				if reloadEnds and now < reloadEnds then
					ui.ReloadFill.Size = UDim2.fromScale(1 - (reloadEnds - now) / stats.ReloadSeconds, 1)
				else
					ui.ReloadFill.Size = UDim2.fromScale(0, 1)
				end
			end
		end
	end

	ui.MatchTitle.Text = `{string.upper(match.ModeName or "Free-for-All")}  •  {match.MapName or ""}`
	if match.Phase == "Active" then
		ui.MatchTimer.Text = formatTime(match.EndsAt - now)
	else
		ui.MatchTimer.Text = `NEXT ROUND {formatTime(match.EndsAt - now)}`
	end

	if respawnAt then
		local left = respawnAt - now
		ui.ElimRespawn.Text = if left > 0 then string.format("Respawning in %.1f", left) else "Respawning..."
		if humanoid and humanoid.Health > 0 and left <= 0 then
			ui.Eliminated.Visible = false
			respawnAt = nil
		end
	end
	updateCrosshair(dt)
end

local function flash(label: TextLabel, text: string, seconds: number)
	label.Text = text
	label.Visible = true
	local token = {}
	label:SetAttribute("Token", tostring(token))
	task.delay(seconds, function()
		if label:GetAttribute("Token") == tostring(token) then
			label.Visible = false
		end
	end)
end

local function addKillFeed(payload: any)
	local killer = payload.KillerName or ""
	local verb = if payload.Kind == "Finished"
		then "[finished off]"
		elseif payload.Kind == "Environment" then "eliminated"
		else `[{weaponName(payload.WeaponId)}]`
	local marker = if payload.Headshot then " ◎" else ""
	local text = if payload.KillerName
		then `{killer}  {verb}{marker}  {payload.VictimName}`
		else `{payload.VictimName} was eliminated`
	local mine = payload.KillerUserId == player.UserId or payload.VictimUserId == player.UserId
	local entry = Build.Panel({
		Size = UDim2.fromOffset(380, 24),
		BackgroundColor3 = if mine then C.Accent else C.Background,
		LayoutOrder = -os.clock() * 1000,
		Parent = ui.KillFeed,
	}, {})
	Build.Label({
		Text = text,
		TextSize = Theme.TextSize.Small,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(1, -8, 1, 0),
		Parent = entry,
	})
	local entries = {}
	for _, child in ui.KillFeed:GetChildren() do
		if child:IsA("Frame") then
			table.insert(entries, child)
		end
	end
	table.sort(entries, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for index = 6, #entries do
		entries[index]:Destroy()
	end
	task.delay(6, function()
		if entry.Parent then
			entry:Destroy()
		end
	end)
end

local function damageIndicator(fromPosition: Vector3?)
	if fromPosition == nil then
		return
	end
	local cam = Workspace.CurrentCamera :: Camera
	local look = cam.CFrame.LookVector
	local toAttacker = fromPosition - cam.CFrame.Position
	local forward = Vector2.new(look.X, look.Z)
	local direction = Vector2.new(toAttacker.X, toAttacker.Z)
	if forward.Magnitude < 1e-3 or direction.Magnitude < 1e-3 then
		return
	end
	forward, direction = forward.Unit, direction.Unit
	local angle =
		math.deg(math.atan2(forward.X * direction.Y - forward.Y * direction.X, forward:Dot(direction)))
	local rad = math.rad(angle - 90)
	local radius = 110
	local arc = Build.New("Frame", {
		BackgroundColor3 = C.Danger,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(math.cos(rad) * radius, math.sin(rad) * radius),
		Size = UDim2.fromOffset(46, 6),
		Rotation = angle,
		Parent = ui.DamageRing,
	}, { Build.Corner() })
	TweenService:Create(arc, TweenInfo.new(1), { BackgroundTransparency = 1 }):Play()
	task.delay(1.05, function()
		arc:Destroy()
	end)
end

local function applyMatch(state: any)
	match = state
	if state.Phase == "Intermission" and state.Results then
		local rows = {}
		for _, result in state.Results do
			table.insert(rows, {
				Rank = result.Rank,
				Name = result.Name,
				Eliminations = result.Eliminations,
				Deaths = result.Deaths,
				Assists = result.Assists,
			})
		end
		renderScoreboard(rows, "ROUND RESULTS")
		ui.Scoreboard.Visible = true
	elseif state.Phase == "Active" then
		ui.Scoreboard.Visible = false
		renderScoreboard(scoreboardRows, "SCOREBOARD")
	end
end

local function applySnapshot(snapshot: { [string]: any })
	scoreboardRows = snapshot.Scoreboard or {}
	if snapshot.Match then
		applyMatch(snapshot.Match)
	end
	updateLoadout()
end

function HUDController.Init(_self: typeof(HUDController), registry: { [string]: any })
	settings = registry.SettingsController
	weapons = registry.WeaponController
	camera = registry.CameraController
	effects = registry.EffectsController

	registry.SnapshotController.Loaded:Connect(function(snapshot)
		-- Start functions run concurrently; the snapshot can arrive before the HUD is built.
		if built then
			applySnapshot(snapshot)
		else
			pendingSnapshot = snapshot
		end
	end)
	weapons.Changed:Connect(updateLoadout)
	weapons.Fired:Connect(function(spread: number)
		bloom = math.min(14, bloom + 2 + spread)
	end)
	weapons.HitConfirmed:Connect(function(payload)
		if not built then
			return
		end
		local headshot = false
		for _, hit in payload.Hits do
			headshot = headshot or hit.Zone == "Head"
			local target = Players:GetPlayerByUserId(hit.TargetUserId)
			if target then
				effects:DamageNumber(target, hit.Damage, hit.Zone == "Head")
			end
		end
		hitMarkerUntil = os.clock() + 0.15
		for _, bar in ui.HitMarker do
			bar.BackgroundColor3 = if headshot then C.HeadshotMarker else C.HitMarker
		end
	end)
	registry.InputController.Began:Connect(function(action: string)
		if built and action == "Scoreboard" and match.Phase == "Active" then
			renderScoreboard(scoreboardRows, "SCOREBOARD")
			ui.Scoreboard.Visible = true
		end
	end)
	registry.InputController.Ended:Connect(function(action: string)
		if built and action == "Scoreboard" and match.Phase == "Active" then
			ui.Scoreboard.Visible = false
		end
	end)
end

function HUDController.Start(_self: typeof(HUDController))
	disableCoreGui()
	gui = Build.New("ScreenGui", {
		Name = "CrossbladeHUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 10,
		Parent = player:WaitForChild("PlayerGui"),
	})
	buildCrosshair()
	buildPanels()
	built = true
	updateLoadout()
	if pendingSnapshot then
		applySnapshot(pendingSnapshot)
		pendingSnapshot = nil
	end

	local scale = gui:FindFirstChildOfClass("UIScale") :: UIScale
	local function rescale()
		local viewport = (Workspace.CurrentCamera :: Camera).ViewportSize
		scale.Scale = math.clamp(math.min(viewport.X / 1600, viewport.Y / 900), 0.6, 1.3)
	end
	(Workspace.CurrentCamera :: Camera):GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	rescale()

	Net.On("MatchState", applyMatch)
	Net.On("Scoreboard", function(payload)
		scoreboardRows = payload.Rows
		local leader = scoreboardRows[1]
		ui.Leader.Text = if leader then `LEADER  {leader.Name}  {leader.Eliminations}` else ""
		if ui.Scoreboard.Visible and match.Phase == "Active" then
			renderScoreboard(scoreboardRows, "SCOREBOARD")
		end
	end)
	Net.On("KillFeed", function(payload)
		addKillFeed(payload)
		if payload.KillerUserId == player.UserId and payload.VictimUserId ~= player.UserId then
			flash(
				ui.Toast,
				`ELIMINATED {string.upper(payload.VictimName)}{if payload.Headshot
					then "  ◎ HEADSHOT"
					else ""}`,
				2
			)
		end
	end)
	Net.On("Announcement", function(payload)
		if payload.Kind == "Killstreak" then
			local who = if payload.UserId == player.UserId
				then "YOU ARE"
				else `{string.upper(payload.Name)} IS`
			flash(ui.Announcement, `{who} ON A {payload.Streak}-ELIMINATION STREAK`, 2.5)
		end
	end)
	Net.On("Eliminated", function(payload)
		if payload.KillerName then
			ui.ElimTitle.Text = `ELIMINATED BY {string.upper(payload.KillerName)}`
			ui.ElimDetail.Text =
				`{weaponName(payload.WeaponId)}  •  {payload.KillerHealth or 0} HP left  •  Level {payload.KillerLevel or 1}`
		else
			ui.ElimTitle.Text = "ELIMINATED"
			ui.ElimDetail.Text = "Out of bounds"
		end
		respawnAt = payload.RespawnAt
		ui.Eliminated.Visible = true
	end)
	Net.On("DamageTaken", function(payload)
		damageIndicator(payload.FromPosition)
	end)

	RunService.RenderStepped:Connect(updateFrame)
end

return HUDController
