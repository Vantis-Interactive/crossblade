--!strict
--[[
	Local cosmetic effects (spec §9, §21): tracers, impacts, muzzle flashes, other players' shots,
	optional floating damage numbers, and the non-graphic elimination fade (no blood, no gore,
	no dismemberment). Everything here is client-local and has no gameplay effect.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Parent.Core.Net)

local EffectsController = {
	Name = "EffectsController",
	Dependencies = { "SettingsController" },
}

local settings: any
local folder: Folder
local player = Players.LocalPlayer

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = true

local function effectPart(size: Vector3, cframe: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = size
	part.CFrame = cframe
	part.Parent = folder
	return part
end

local function fade(part: BasePart, seconds: number)
	TweenService:Create(part, TweenInfo.new(seconds), { Transparency = 1 }):Play()
	Debris:AddItem(part, seconds + 0.05)
end

function EffectsController.Tracer(_self: typeof(EffectsController), from: Vector3, to: Vector3)
	local length = (to - from).Magnitude
	if length < 0.5 then
		return
	end
	local part = effectPart(
		Vector3.new(0.06, 0.06, length),
		CFrame.lookAt((from + to) / 2, to),
		Color3.fromRGB(255, 226, 150)
	)
	part.Transparency = 0.25
	fade(part, 0.09)
end

function EffectsController.Impact(_self: typeof(EffectsController), position: Vector3, normal: Vector3)
	local part =
		effectPart(Vector3.one * 0.35, CFrame.new(position + normal * 0.05), Color3.fromRGB(255, 240, 200))
	part.Shape = Enum.PartType.Ball
	fade(part, 0.2)
end

function EffectsController.MuzzleFlash(_self: typeof(EffectsController), position: Vector3)
	local part = effectPart(Vector3.one * 0.4, CFrame.new(position), Color3.fromRGB(255, 200, 110))
	part.Shape = Enum.PartType.Ball
	local light = Instance.new("PointLight")
	light.Range = 8
	light.Brightness = 2
	light.Color = part.Color
	light.Parent = part
	fade(part, 0.06)
end

-- `target` is a player or a world position (training dummies).
function EffectsController.DamageNumber(
	_self: typeof(EffectsController),
	target: Player | Vector3,
	amount: number,
	headshot: boolean
)
	if not settings.Current.DamageNumbers then
		return
	end
	local position: Vector3
	if typeof(target) == "Vector3" then
		position = target
	else
		local root = target.Character and target.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root == nil then
			return
		end
		position = root.Position
	end
	local anchor = effectPart(
		Vector3.one * 0.1,
		CFrame.new(position + Vector3.new(math.random() - 0.5, 3.2, 0)),
		Color3.new()
	)
	anchor.Transparency = 1
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(80, 30)
	billboard.AlwaysOnTop = true
	billboard.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Config.Theme.Fonts.Heading
	label.TextSize = 20
	label.TextColor3 = if headshot then Config.Theme.Colors.HeadshotMarker else Config.Theme.Colors.Text
	label.TextStrokeTransparency = 0.4
	label.Text = (if headshot then "◎ " else "") .. tostring(math.floor(amount + 0.5))
	label.Parent = billboard
	local rise = if settings.Current.ReducedMotion then 0 else 1.5
	TweenService:Create(anchor, TweenInfo.new(0.7), { CFrame = anchor.CFrame + Vector3.new(0, rise, 0) })
		:Play()
	TweenService:Create(label, TweenInfo.new(0.7), { TextTransparency = 1, TextStrokeTransparency = 1 })
		:Play()
	Debris:AddItem(anchor, 0.75)
end

-- Non-graphic elimination: the character fades out and is replaced by a brief light pulse.
local function fadeCharacter(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			TweenService:Create(descendant, TweenInfo.new(0.8), { Transparency = 1 }):Play()
		end
	end
	if root then
		local pulse = effectPart(Vector3.one * 2, CFrame.new(root.Position), Config.Theme.Colors.AccentBright)
		pulse.Shape = Enum.PartType.Ball
		pulse.Transparency = 0.4
		TweenService:Create(pulse, TweenInfo.new(0.6), { Size = Vector3.one * 6, Transparency = 1 }):Play()
		Debris:AddItem(pulse, 0.65)
	end
end

local function watchCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid then
		humanoid.Died:Connect(function()
			fadeCharacter(character)
		end)
	end
end

local function watchPlayer(other: Player)
	other.CharacterAdded:Connect(watchCharacter)
	if other.Character then
		task.spawn(watchCharacter, other.Character)
	end
end

function EffectsController.Init(_self: typeof(EffectsController), registry: { [string]: any })
	settings = registry.SettingsController
end

function EffectsController.Start(self: typeof(EffectsController))
	folder = Instance.new("Folder")
	folder.Name = "CrossbladeEffects"
	folder.Parent = Workspace

	Players.PlayerAdded:Connect(watchPlayer)
	for _, other in Players:GetPlayers() do
		watchPlayer(other)
	end

	Net.On("ShotFired", function(payload)
		local shooter = Players:GetPlayerByUserId(payload.ShooterUserId)
		if shooter == nil or shooter == player then
			return
		end
		local held = shooter.Character and shooter.Character:FindFirstChild("EquippedWeapon") :: Model?
		local muzzle = held and held.PrimaryPart and held.PrimaryPart:FindFirstChild("Muzzle") :: Attachment?
		local from = if muzzle then muzzle.WorldPosition else payload.Origin
		local exclude: { Instance } = { folder }
		for _, other in Players:GetPlayers() do
			if other.Character then
				table.insert(exclude, other.Character)
			end
		end
		params.FilterDescendantsInstances = exclude
		for _ = 1, math.min(payload.Pellets or 1, 16) do
			local direction = payload.Direction
			if (payload.Pellets or 1) > 1 then
				direction = (direction + Vector3.new(
					math.random() - 0.5,
					math.random() - 0.5,
					math.random() - 0.5
				) * 0.08).Unit
			end
			local hit = Workspace:Raycast(payload.Origin, direction * (payload.Range or 300), params)
			local to = if hit then hit.Position else payload.Origin + direction * (payload.Range or 300)
			self:Tracer(from, to)
			if hit then
				self:Impact(hit.Position, hit.Normal)
			end
		end
		self:MuzzleFlash(from)
	end)
end

return EffectsController
