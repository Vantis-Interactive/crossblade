--!strict
--[[
	Training dummies (spec §18 shooting range, §27 tutorial). Built at every Crossblade.DummySpot on
	the current map. A dummy uses the standardized hitbox (its root sits where a character root
	would), has Config.Player.MaxHealth health, never fights back, and resets shortly after being
	knocked down. Dummies grant no coins, XP or statistics.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local HealthRules = require(ReplicatedStorage.Shared.Combat.HealthRules)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local DUMMY_TAG = "Crossblade.Dummy"
local RESET_SECONDS = 2
local ROOT_HEIGHT = 3

export type Dummy = { Id: number, Model: Model, Root: BasePart, Health: number, Alive: boolean }

local TrainingService = {
	Name = "TrainingService",
	Dependencies = { "MapService" },
	DummyTag = DUMMY_TAG,
	-- (player, kind: "Firearm" | "Knife" | "ThrownKnife", knockedDown)
	DummyHit = Signal.new() :: Signal.Signal<Player, string, boolean>,
}

local dummies: { [number]: Dummy } = {}
local folder: Folder
local mapService: any
local nextId = 0

local function part(
	name: string,
	size: Vector3,
	offset: Vector3,
	parent: Model,
	root: BasePart,
	color: Color3
): Part
	local piece = Instance.new("Part")
	piece.Name = name
	piece.Size = size
	piece.Anchored = true
	piece.CanQuery = false -- like characters: never blocks line of sight; hits use the standard hitbox
	piece.Color = color
	piece.Material = Enum.Material.SmoothPlastic
	piece.CFrame = root.CFrame * CFrame.new(offset)
	piece.Parent = parent
	return piece
end

local function updateVisual(dummy: Dummy)
	dummy.Model:SetAttribute("Health", dummy.Health)
	dummy.Model:SetAttribute("Alive", dummy.Alive)
	for _, child in dummy.Model:GetChildren() do
		if child:IsA("BasePart") and child ~= dummy.Root then
			child.Transparency = if dummy.Alive then 0 else 0.7
		end
	end
	local label = dummy.Model:FindFirstChild("HealthLabel", true) :: TextLabel?
	if label then
		label.Text = if dummy.Alive then `{math.ceil(dummy.Health)} HP` else "DOWN"
	end
end

local function build(spot: BasePart): Dummy
	nextId += 1
	local model = Instance.new("Model")
	model.Name = `TrainingDummy{nextId}`
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CFrame = spot.CFrame + Vector3.new(0, ROOT_HEIGHT, 0)
	root.Parent = model
	model.PrimaryPart = root
	local body = Color3.fromRGB(150, 128, 92)
	part("Torso", Vector3.new(2, 2, 1), Vector3.new(0, 0, 0), model, root, body)
	part(
		"Head",
		Vector3.new(1.2, 1.2, 1.2),
		Vector3.new(0, Config.Player.Hitbox.HeadOffset, 0),
		model,
		root,
		body
	)
	part("LeftLeg", Vector3.new(0.9, 2, 1), Vector3.new(-0.5, -2, 0), model, root, body)
	part("RightLeg", Vector3.new(0.9, 2, 1), Vector3.new(0.5, -2, 0), model, root, body)
	part(
		"Stand",
		Vector3.new(0.4, 3, 0.4),
		Vector3.new(0, -1.5, -0.8),
		model,
		root,
		Color3.fromRGB(80, 80, 80)
	)

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(90, 24)
	billboard.StudsOffset = Vector3.new(0, 3.2, 0)
	billboard.Adornee = root
	billboard.Parent = model
	local label = Instance.new("TextLabel")
	label.Name = "HealthLabel"
	label.BackgroundTransparency = 0.4
	label.BackgroundColor3 = Config.Theme.Colors.Background
	label.TextColor3 = Config.Theme.Colors.Text
	label.Font = Config.Theme.Fonts.Heading
	label.TextSize = 14
	label.Size = UDim2.fromScale(1, 1)
	label.Parent = billboard

	local dummy: Dummy =
		{ Id = nextId, Model = model, Root = root, Health = Config.Player.MaxHealth, Alive = true }
	model:SetAttribute("DummyId", nextId)
	CollectionService:AddTag(model, DUMMY_TAG)
	model.Parent = folder
	updateVisual(dummy)
	return dummy
end

local function rebuild()
	for _, dummy in dummies do
		dummy.Model:Destroy()
	end
	table.clear(dummies)
	for _, spot in mapService:GetTagged("DummySpot") do
		local dummy = build(spot)
		dummies[dummy.Id] = dummy
	end
end

function TrainingService.GetDummy(_self: typeof(TrainingService), id: number): Dummy?
	local dummy = dummies[id]
	return if dummy and dummy.Alive then dummy else nil
end

function TrainingService.AliveDummies(_self: typeof(TrainingService)): { Dummy }
	local list = {}
	for _, dummy in dummies do
		if dummy.Alive then
			table.insert(list, dummy)
		end
	end
	return list
end

-- Returns (damage dealt, knocked down).
function TrainingService.ApplyHit(
	_self: typeof(TrainingService),
	player: Player,
	id: number,
	amount: number,
	kind: string
): (number, boolean)
	local dummy = dummies[id]
	if dummy == nil or not dummy.Alive then
		return 0, false
	end
	local result = HealthRules.ApplyDamage(dummy.Health, amount)
	dummy.Health = result.Health
	if result.Died then
		dummy.Alive = false
		task.delay(RESET_SECONDS, function()
			if dummies[id] == dummy then
				dummy.Health = Config.Player.MaxHealth
				dummy.Alive = true
				updateVisual(dummy)
			end
		end)
	end
	updateVisual(dummy)
	TrainingService.DummyHit:Fire(player, kind, result.Died)
	return result.Dealt, result.Died
end

function TrainingService.Init(_self: typeof(TrainingService), registry: { [string]: any })
	mapService = registry.MapService
	folder = Instance.new("Folder")
	folder.Name = "CrossbladeTraining"
	folder.Parent = Workspace
	rebuild()
	mapService.MapChanged:Connect(rebuild)
end

return TrainingService
