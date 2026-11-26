--!strict
--[[
	Collection window (spec §12, §20): hosts the ARMORY tab (owned weapons per slot, stats, equip into
	the active loadout preset, collection completion) and the CRATES tab (CrateController).
	Rarity is always shown as symbol + name + colour, never colour alone.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local WeaponCatalog = require(ReplicatedStorage.Shared.Weapons.WeaponCatalog)
local UIState = require(script.Parent.Parent.Core.UIState)
local Build = require(script.Parent.Parent.UI.Build)

local Theme = Config.Theme
local C = Theme.Colors

local ArmoryController = {
	Name = "ArmoryController",
	Dependencies = { "InputController", "InventoryController", "CrateController" },
}

local inventory: any
local crates: any
local window: Frame
local tabs: { [string]: Frame } = {}
local tabButtons: { [string]: TextButton } = {}
local columns: { [string]: ScrollingFrame } = {}
local walletLabel: TextLabel
local completionLabel: TextLabel
local detailLabel: TextLabel

local function rarityText(rarity: string): string
	local tier = Config.Rarity.Tiers[rarity]
	return if tier then `{tier.Symbol} {string.upper(rarity)}` else rarity
end

local function statsLine(weaponId: string): string
	local entry = WeaponCatalog.Get(weaponId)
	local archetype = WeaponCatalog.GetArchetype(weaponId)
	if entry == nil or archetype == nil then
		return ""
	end
	local prefix = `{entry.DisplayName}  •  {archetype.DisplayName}  •  {entry.Collection}  •  `
	local f = archetype.Firearm
	if f then
		local damage = if f.Pellets > 1 then `{f.Damage} x{f.Pellets}` else tostring(f.Damage)
		return prefix
			.. `Damage {damage}  •  {f.RoundsPerMinute} RPM  •  Mag {f.MagazineSize}/{f.MaxReserve}  •  Reload {f.ReloadSeconds}s  •  Range {f.Range}`
	end
	local k = archetype.Knife
	if k then
		return prefix
			.. `Slash {k.Slash.Damage} / {k.Slash.CooldownSeconds}s  •  Stab {k.Stab.Damage} / {k.Stab.CooldownSeconds}s  •  Throw {k.Throw.Damage}`
	end
	return prefix
end

local function formatCoins(value: number): string
	local text = tostring(math.floor(value))
	local formatted = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	return (string.gsub(formatted, "^,", ""))
end

function ArmoryController.SelectTab(_self: typeof(ArmoryController), name: string)
	for tabName, frame in tabs do
		frame.Visible = tabName == name
		tabButtons[tabName].BackgroundColor3 = if tabName == name then C.Accent else C.PanelRaised
	end
end

function ArmoryController.SetOpen(self: typeof(ArmoryController), open: boolean)
	if window == nil then
		return
	end
	window.Visible = open
	UIState.SetMenuOpen("Collection", open)
	if open then
		self:Refresh()
		GuiService.SelectedObject = tabButtons.Armory
	elseif GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(window) then
		GuiService.SelectedObject = nil
	end
end

function ArmoryController.Refresh(_self: typeof(ArmoryController))
	local state = inventory.State
	if window == nil or state == nil then
		return
	end
	walletLabel.Text =
		`◈ {formatCoins(state.Coins)} COINS   (earned {formatCoins(state.Earned)} · purchased {formatCoins(
			state.Purchased
		)})   •   LEVEL {state.Level}`
	local total = 0
	for _ in Config.Catalog.Entries do
		total += 1
	end
	completionLabel.Text = `COLLECTION {#state.Owned} / {total}`

	for _, slot in WeaponCatalog.Slots do
		local column = columns[slot]
		for _, child in column:GetChildren() do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
		local owned = {}
		for _, weaponId in state.Owned do
			if WeaponCatalog.SlotFor(weaponId) == slot then
				table.insert(owned, weaponId)
			end
		end
		table.sort(owned, function(a, b)
			local ra = Config.Rarity.Tiers[WeaponCatalog.Get(a).Rarity].Rank
			local rb = Config.Rarity.Tiers[WeaponCatalog.Get(b).Rarity].Rank
			if ra ~= rb then
				return ra > rb
			end
			return a < b
		end)
		for order, weaponId in owned do
			local entry = WeaponCatalog.Get(weaponId)
			local tier = Config.Rarity.Tiers[entry.Rarity]
			local equipped = state.Loadout[slot] == weaponId
			local button = Build.Button({
				Text = "",
				Size = UDim2.new(1, -8, 0, 46),
				LayoutOrder = order,
				BackgroundColor3 = if equipped then C.Accent else C.PanelRaised,
				Parent = column,
			}, function()
				detailLabel.Text = statsLine(weaponId)
				if not equipped then
					inventory:SetLoadout(slot, weaponId)
				end
			end)
			Build.Label({
				Text = entry.DisplayName,
				Font = Theme.Fonts.Heading,
				Position = UDim2.fromOffset(8, 4),
				Size = UDim2.new(1, -16, 0, 18),
				Parent = button,
			})
			Build.Label({
				Text = rarityText(entry.Rarity) .. (if equipped then "   •   EQUIPPED" else ""),
				TextSize = 12,
				TextColor3 = tier.Color,
				Position = UDim2.fromOffset(8, 24),
				Size = UDim2.new(1, -16, 0, 16),
				Parent = button,
			})
			button.MouseEnter:Connect(function()
				detailLabel.Text = statsLine(weaponId)
			end)
			button.SelectionGained:Connect(function()
				detailLabel.Text = statsLine(weaponId)
			end)
		end
		column.CanvasSize = UDim2.fromOffset(0, #owned * 50)
	end
	crates:Refresh()
end

local function build(gui: ScreenGui)
	window = Build.Panel({
		Name = "Collection",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(820, 560),
		BackgroundTransparency = 0.03,
		Visible = false,
		Parent = gui,
	}, { Build.Padding(14) })
	Build.Label({
		Text = "COLLECTION",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Large,
		Size = UDim2.fromOffset(200, 30),
		Parent = window,
	})
	for index, name in { "Armory", "Crates" } do
		tabButtons[name] = Build.Button({
			Text = string.upper(name),
			Position = UDim2.fromOffset(200 + (index - 1) * 116, 0),
			Size = UDim2.fromOffset(110, 30),
			Parent = window,
		}, function()
			ArmoryController:SelectTab(name)
		end)
	end
	Build.Button({
		Text = "CLOSE",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(90, 30),
		Parent = window,
	}, function()
		ArmoryController:SetOpen(false)
	end)
	walletLabel = Build.Label({
		Text = "",
		TextColor3 = C.TextMuted,
		Position = UDim2.fromOffset(0, 38),
		Size = UDim2.new(1, -180, 0, 20),
		Parent = window,
	})
	completionLabel = Build.Label({
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.AccentBright,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 38),
		Size = UDim2.fromOffset(180, 20),
		Parent = window,
	})

	local body = UDim2.new(1, 0, 1, -70)
	local armory = Build.New(
		"Frame",
		{ BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 66), Size = body, Parent = window }
	)
	tabs.Armory = armory
	for index, slot in WeaponCatalog.Slots do
		local x = (index - 1) / 3
		Build.Label({
			Text = string.upper(slot),
			Font = Theme.Fonts.Heading,
			TextColor3 = C.TextMuted,
			Position = UDim2.new(x, 0, 0, 0),
			Size = UDim2.new(1 / 3, -8, 0, 20),
			Parent = armory,
		})
		local column = Build.New("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 6,
			Position = UDim2.new(x, 0, 0, 24),
			Size = UDim2.new(1 / 3, -8, 1, -64),
			CanvasSize = UDim2.new(),
			Parent = armory,
		}, {
			Build.New("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		columns[slot] = column
	end
	detailLabel = Build.Label({
		Text = "Select a weapon to equip it. Changes apply on your next spawn.",
		TextColor3 = C.TextMuted,
		TextWrapped = true,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 34),
		Parent = armory,
	})

	local crateTab = Build.New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 66),
		Size = body,
		Visible = false,
		Parent = window,
	})
	tabs.Crates = crateTab
	crates:Mount(crateTab, gui)
	ArmoryController:SelectTab("Armory")
end

function ArmoryController.Init(self: typeof(ArmoryController), registry: { [string]: any })
	inventory = registry.InventoryController
	crates = registry.CrateController
	inventory.Changed:Connect(function()
		if window and window.Visible then
			self:Refresh()
		end
	end)
	registry.InputController.Began:Connect(function(action: string)
		if action == "Collection" then
			self:SetOpen(not (window and window.Visible))
		end
	end)
end

function ArmoryController.Start(_self: typeof(ArmoryController))
	local gui = Build.New("ScreenGui", {
		Name = "CrossbladeCollection",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 18,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	build(gui)
end

return ArmoryController
