--!strict
-- Small helpers for building themed UI in code. All colours and fonts come from Config.Theme.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Theme = Config.Theme
local Build = {}

function Build.New(className: string, props: { [string]: any }, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = props.Parent
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = instance
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function Build.Corner(radius: UDim?): UICorner
	return Build.New("UICorner", { CornerRadius = radius or Theme.CornerRadius })
end

function Build.Stroke(color: Color3?, thickness: number?): UIStroke
	return Build.New(
		"UIStroke",
		{ Color = color or Theme.Colors.Stroke, Thickness = thickness or 1, Transparency = 0.2 }
	)
end

function Build.Padding(pixels: number?): UIPadding
	local p = UDim.new(0, pixels or Theme.Padding)
	return Build.New("UIPadding", { PaddingLeft = p, PaddingRight = p, PaddingTop = p, PaddingBottom = p })
end

function Build.Panel(props: { [string]: any }, children: { Instance }?): Frame
	local merged = {
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
	}
	for key, value in props do
		merged[key] = value
	end
	local list = { Build.Corner(), Build.Stroke() }
	for _, child in children or {} do
		table.insert(list, child)
	end
	return Build.New("Frame", merged, list)
end

function Build.Label(props: { [string]: any }): TextLabel
	local merged = {
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		TextColor3 = Theme.Colors.Text,
		TextSize = Theme.TextSize.Body,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	}
	for key, value in props do
		merged[key] = value
	end
	return Build.New("TextLabel", merged)
end

function Build.Button(props: { [string]: any }, onActivated: () -> ()): TextButton
	local merged = {
		BackgroundColor3 = Theme.Colors.PanelRaised,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = Theme.Fonts.Heading,
		TextColor3 = Theme.Colors.Text,
		TextSize = Theme.TextSize.Body,
		Selectable = true,
	}
	for key, value in props do
		merged[key] = value
	end
	local button = Build.New("TextButton", merged, { Build.Corner(), Build.Stroke() })
	button.Activated:Connect(onActivated)
	return button
end

return Build
