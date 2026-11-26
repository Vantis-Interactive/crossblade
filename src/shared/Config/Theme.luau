--!strict
-- Tactical UI theme tokens (spec §20). UI code reads colours and sizes only from here.
local Theme = {
	Colors = {
		Background = Color3.fromRGB(28, 30, 29), -- charcoal
		Panel = Color3.fromRGB(38, 41, 39),
		PanelRaised = Color3.fromRGB(50, 54, 51),
		Stroke = Color3.fromRGB(92, 98, 90), -- gunmetal
		Accent = Color3.fromRGB(122, 140, 74), -- olive
		AccentBright = Color3.fromRGB(164, 186, 98),
		Text = Color3.fromRGB(232, 234, 226),
		TextMuted = Color3.fromRGB(160, 166, 152),
		Danger = Color3.fromRGB(214, 84, 66),
		Warning = Color3.fromRGB(226, 176, 64),
		Health = Color3.fromRGB(132, 196, 96),
		HealthLow = Color3.fromRGB(214, 84, 66),
		HitMarker = Color3.fromRGB(255, 255, 255),
		HeadshotMarker = Color3.fromRGB(255, 196, 64),
	},
	Fonts = {
		Heading = Enum.Font.GothamBold,
		Body = Enum.Font.Gotham,
		Mono = Enum.Font.RobotoMono,
	},
	TextSize = {
		Small = 14,
		Body = 16,
		Large = 22,
		Huge = 34,
	},
	CornerRadius = UDim.new(0, 4),
	Padding = 8,
	-- Durations used by restrained UI animation. Reduced-motion setting replaces these with 0.
	Motion = {
		Fast = 0.12,
		Normal = 0.25,
	},
}

return table.freeze(Theme)
