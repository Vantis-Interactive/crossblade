--!strict
--[[
	Crate shop and reveal (spec §14).
	  - Every possible reward and its exact individual probability is shown BEFORE purchase; the OPEN
	    button lives inside that odds view. Odds come from Shared/Economy/CrateOdds, the same function
	    the server uses to select rewards.
	  - The reveal only displays the result the server already determined. There is no spinning reel
	    and no near-miss presentation. Reduced-motion shows the result instantly.
	  - Duplicates show the exact coins they converted into.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local CrateOdds = require(ReplicatedStorage.Shared.Economy.CrateOdds)
local Wallet = require(ReplicatedStorage.Shared.Economy.Wallet)
local WeaponCatalog = require(ReplicatedStorage.Shared.Weapons.WeaponCatalog)
local Build = require(script.Parent.Parent.UI.Build)

local Theme = Config.Theme
local C = Theme.Colors

local CrateController = {
	Name = "CrateController",
	Dependencies = { "InventoryController", "SettingsController" },
}

local inventory: any
local settings: any
local list: ScrollingFrame
local detail: Frame
local titleLabel: TextLabel
local priceLabel: TextLabel
local noteLabel: TextLabel
local oddsList: ScrollingFrame
local openButton: TextButton
local reveal: Frame
local revealCard: Frame
local revealName: TextLabel
local revealRarity: TextLabel
local revealNote: TextLabel
local selected: string? = nil
local busy = false

local REASONS = {
	InsufficientFunds = "Not enough coins.",
	InsufficientEarnedFunds = "Purchased coins can't be used for crates on your account. Earn more coins in matches.",
	UnknownCrate = "This crate is not available.",
	NotLoaded = "Your data is still loading.",
	NoResponse = "No response from the server. If you were charged, the result will appear in your collection.",
}

local function percent(probability: number): string
	return string.format("%.4g%%", probability * 100)
end

local function spendable(state: { [string]: any }): number
	return Wallet.Spendable(
		{ Earned = state.Earned, Purchased = state.Purchased },
		state.PurchasedUsableForCrates
	)
end

local function renderDetail()
	local state = inventory.State
	local crate = selected and Config.Crates.Crates[selected]
	detail.Visible = crate ~= nil
	if crate == nil or state == nil then
		return
	end
	titleLabel.Text = string.upper(crate.DisplayName)
	priceLabel.Text = `PRICE ◈ {crate.Price}    •    YOU CAN SPEND ◈ {spendable(state)}`
	noteLabel.Text = if state.PurchasedUsableForCrates
		then "Odds below are exact and are the same values the server uses."
		else "Odds below are exact. Only coins earned in matches can be used for crates on your account."
	for _, child in oddsList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local distribution = CrateOdds.Build(crate)
	for order, item in distribution.Entries do
		local entry = WeaponCatalog.Get(item.WeaponId)
		local tier = Config.Rarity.Tiers[item.Rarity]
		local row = Build.New("Frame", {
			BackgroundTransparency = if order % 2 == 0 then 1 else 0.85,
			BackgroundColor3 = C.PanelRaised,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -8, 0, 22),
			LayoutOrder = order,
			Parent = oddsList,
		})
		Build.Label({
			Text = `{tier.Symbol} {string.upper(item.Rarity)}`,
			TextColor3 = tier.Color,
			TextSize = 12,
			Size = UDim2.fromScale(0.26, 1),
			Parent = row,
		})
		Build.Label({
			Text = entry.DisplayName,
			TextSize = 14,
			Position = UDim2.fromScale(0.26, 0),
			Size = UDim2.fromScale(0.44, 1),
			Parent = row,
		})
		Build.Label({
			Text = if inventory:Owns(item.WeaponId)
				then `OWNED → +{Config.Economy.DuplicateCompensation[item.Rarity]}`
				else "",
			TextColor3 = C.TextMuted,
			TextSize = 12,
			Position = UDim2.fromScale(0.7, 0),
			Size = UDim2.fromScale(0.16, 1),
			Parent = row,
		})
		Build.Label({
			Text = percent(item.Probability),
			Font = Theme.Fonts.Mono,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.fromScale(0.86, 0),
			Size = UDim2.fromScale(0.14, 1),
			Parent = row,
		})
	end
	oddsList.CanvasSize = UDim2.fromOffset(0, #distribution.Entries * 24)
	local short = crate.Price - spendable(state)
	if busy then
		openButton.Text = "OPENING..."
	elseif short > 0 then
		openButton.Text = `NEED ◈ {short} MORE`
	else
		openButton.Text = `OPEN FOR ◈ {crate.Price}`
	end
	openButton.AutoButtonColor = short <= 0 and not busy
	openButton.BackgroundColor3 = if short <= 0 and not busy then C.Accent else C.PanelRaised
end

local function showReveal(response: { [string]: any })
	reveal.Visible = true
	if not response.Ok then
		revealName.Text = "NOT OPENED"
		revealRarity.Text = ""
		revealNote.Text = REASONS[response.Reason] or `Could not open the crate ({response.Reason}).`
		return
	end
	local result = response.Result
	local entry = WeaponCatalog.Get(result.WeaponId)
	local tier = Config.Rarity.Tiers[result.Rarity]
	revealName.Text = if entry then entry.DisplayName else result.WeaponId
	revealRarity.Text = `{tier.Symbol} {string.upper(result.Rarity)}`
	revealRarity.TextColor3 = tier.Color
	revealCard.BackgroundColor3 = tier.Color
	revealNote.Text = if result.Duplicate
		then `DUPLICATE: converted to +{result.Compensation} coins`
		else "NEW WEAPON ADDED TO YOUR COLLECTION"
	if not settings.Current.ReducedMotion then
		local scale = revealCard:FindFirstChildOfClass("UIScale") :: UIScale
		scale.Scale = 0.7
		revealCard.BackgroundTransparency = 1
		TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		TweenService:Create(revealCard, TweenInfo.new(0.45), { BackgroundTransparency = 0.6 }):Play()
	else
		revealCard.BackgroundTransparency = 0.6
	end
end

local function openSelected()
	local state = inventory.State
	local crate = selected and Config.Crates.Crates[selected]
	if busy or crate == nil or state == nil or spendable(state) < crate.Price then
		return
	end
	busy = true
	renderDetail()
	local response = inventory:OpenCrate(crate.Id)
	busy = false
	showReveal(response)
	renderDetail()
end

function CrateController.Refresh(_self: typeof(CrateController))
	local state = inventory.State
	if list == nil or state == nil then
		return
	end
	for _, child in list:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	for order, crateId in state.ActiveCrates do
		local crate = Config.Crates.Crates[crateId]
		if crate then
			local button = Build.Button({
				Text = "",
				Size = UDim2.new(1, -8, 0, 44),
				LayoutOrder = order,
				BackgroundColor3 = if selected == crateId then C.Accent else C.PanelRaised,
				Parent = list,
			}, function()
				selected = crateId
				CrateController:Refresh()
			end)
			Build.Label({
				Text = crate.DisplayName,
				Font = Theme.Fonts.Heading,
				Position = UDim2.fromOffset(8, 4),
				Size = UDim2.new(1, -16, 0, 18),
				Parent = button,
			})
			Build.Label({
				Text = `◈ {crate.Price}  •  {string.upper(crate.Category)}`,
				TextSize = 12,
				TextColor3 = C.TextMuted,
				Position = UDim2.fromOffset(8, 23),
				Size = UDim2.new(1, -16, 0, 16),
				Parent = button,
			})
		end
	end
	list.CanvasSize = UDim2.fromOffset(0, #state.ActiveCrates * 48)
	if selected == nil then
		selected = state.ActiveCrates[1]
	end
	renderDetail()
end

function CrateController.Mount(_self: typeof(CrateController), parent: Frame, gui: ScreenGui)
	list = Build.New("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		Size = UDim2.new(0.3, -8, 1, 0),
		CanvasSize = UDim2.new(),
		Parent = parent,
	}, { Build.New("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }) })
	detail = Build.New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.3, 0),
		Size = UDim2.fromScale(0.7, 1),
		Visible = false,
		Parent = parent,
	})
	titleLabel = Build.Label({
		Text = "",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Large,
		Size = UDim2.new(1, 0, 0, 26),
		Parent = detail,
	})
	priceLabel = Build.Label({
		Text = "",
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = detail,
	})
	noteLabel = Build.Label({
		Text = "",
		TextColor3 = C.TextMuted,
		TextSize = 12,
		TextWrapped = true,
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 0, 28),
		Parent = detail,
	})
	oddsList = Build.New("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		Position = UDim2.fromOffset(0, 80),
		Size = UDim2.new(1, 0, 1, -130),
		CanvasSize = UDim2.new(),
		Parent = detail,
	}, { Build.New("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }) })
	openButton = Build.Button({
		Text = "OPEN",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(240, 40),
		Parent = detail,
	}, function()
		task.spawn(openSelected)
	end)

	reveal = Build.New("Frame", {
		BackgroundColor3 = C.Background,
		BackgroundTransparency = 0.25,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 5,
		Parent = gui,
	})
	revealCard = Build.Panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(420, 220),
		ZIndex = 6,
		Parent = reveal,
	}, {
		Build.New("UIScale", {}),
		Build.Padding(16),
	})
	revealRarity = Build.Label({
		Text = "",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Large,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 30),
		ZIndex = 7,
		Parent = revealCard,
	})
	revealName = Build.Label({
		Text = "",
		Font = Theme.Fonts.Heading,
		TextSize = Theme.TextSize.Huge,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 44),
		ZIndex = 7,
		Parent = revealCard,
	})
	revealNote = Build.Label({
		Text = "",
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 96),
		Size = UDim2.new(1, 0, 0, 44),
		ZIndex = 7,
		Parent = revealCard,
	})
	Build.Button({
		Text = "CONTINUE",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(180, 36),
		ZIndex = 7,
		Parent = revealCard,
	}, function()
		reveal.Visible = false
	end)
end

function CrateController.Init(_self: typeof(CrateController), registry: { [string]: any })
	inventory = registry.InventoryController
	settings = registry.SettingsController
end

return CrateController
