--!strict
--[[
	Hybrid first/third-person camera (spec §6).
	A fully scripted camera gives deterministic control over aim, recoil and collision:
	  - yaw/pitch from mouse (locked centre), gamepad right stick, or touch drag
	  - third person: over-the-shoulder with collision (shoulder and boom are both ray-tested)
	  - first person: eye at the standardized head position, local character hidden
	  - FOV from settings (clamped to competitive limits) and weapon aim FOV while aiming
	  - recoil kicks pitch/yaw and recovers over time
	Shots never originate from the camera: WeaponController fires from the head, so a third-person
	camera looking past a corner cannot shoot through it (spec §6).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local UIState = require(script.Parent.Parent.Core.UIState)

local C = Config.Camera
local HEAD = Config.Player.Hitbox.HeadOffset
local MOUSE_RADIANS_PER_PIXEL = 0.0032
local GAMEPAD_RADIANS_PER_SECOND = 3.2
local TOUCH_RADIANS_PER_PIXEL = 0.006
local PITCH_LIMIT = math.rad(80)

local CameraController = {
	Name = "CameraController",
	Dependencies = { "InputController", "SettingsController" },
	Perspective = C.DefaultPerspective :: "FirstPerson" | "ThirdPerson",
	PerspectiveChanged = Signal.new() :: Signal.Signal<string>,
	Yaw = 0,
	Pitch = 0,
	Aiming = false,
	AimFieldOfView = nil :: number?,
}

local settings: any
local player = Players.LocalPlayer
local stick = Vector2.zero
local touchDelta = Vector2.zero
local recoilPitch = 0
local currentFov = C.FieldOfView.Default
local hiddenParts: { [BasePart]: boolean } = {}

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = true

local function refreshFilter()
	local exclude: { Instance } = { Workspace.CurrentCamera }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(exclude, other.Character)
		end
	end
	params.FilterDescendantsInstances = exclude
end

local function setCharacterHidden(hidden: boolean)
	local character = player.Character
	if character == nil then
		return
	end
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = if hidden then 1 else 0
			hiddenParts[descendant] = hidden or nil
		end
	end
end

function CameraController.SetPerspective(
	self: typeof(CameraController),
	perspective: "FirstPerson" | "ThirdPerson"
)
	if self.Perspective ~= perspective then
		self.Perspective = perspective
		self.PerspectiveChanged:Fire(perspective)
	end
end

function CameraController.SetAiming(self: typeof(CameraController), aiming: boolean, aimFov: number?)
	self.Aiming = aiming
	self.AimFieldOfView = aimFov
end

function CameraController.AddRecoil(self: typeof(CameraController), pitchDegrees: number, yawDegrees: number)
	local kick = math.rad(pitchDegrees)
	self.Pitch = math.clamp(self.Pitch + kick, -PITCH_LIMIT, PITCH_LIMIT)
	recoilPitch += kick
	self.Yaw += math.rad(yawDegrees) * (if math.random() < 0.5 then -1 else 1)
end

-- Ray through the screen centre: (origin, unit direction).
function CameraController.GetAimRay(_self: typeof(CameraController)): (Vector3, Vector3)
	local cframe = (Workspace.CurrentCamera :: Camera).CFrame
	return cframe.Position, cframe.LookVector
end

function CameraController.Init(self: typeof(CameraController), registry: { [string]: any })
	settings = registry.SettingsController
	settings.Changed:Connect(function(current)
		self:SetPerspective(current.Perspective)
	end)
	registry.InputController.Began:Connect(function(action: string)
		if action == "TogglePerspective" and not UIState.MenuOpen then
			self:SetPerspective(if self.Perspective == "FirstPerson" then "ThirdPerson" else "FirstPerson")
		end
	end)
end

local function sensitivity(self: typeof(CameraController)): number
	local current = settings.Current
	local value = current.Sensitivity
	if self.Aiming then
		value *= current.AimSensitivity
	end
	-- Scale with zoom so aiming feels consistent across FOVs.
	return value * (currentFov / current.FieldOfView)
end

local function update(self: typeof(CameraController), dt: number)
	local camera = Workspace.CurrentCamera :: Camera
	camera.CameraType = Enum.CameraType.Scriptable

	local menuOpen = UIState.MenuOpen
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	else
		UserInputService.MouseBehavior = if menuOpen
			then Enum.MouseBehavior.Default
			else Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = menuOpen
	end

	if not menuOpen then
		local sens = sensitivity(self)
		local mouse = UserInputService:GetMouseDelta()
		local delta = mouse * MOUSE_RADIANS_PER_PIXEL * sens + touchDelta * TOUCH_RADIANS_PER_PIXEL * sens
		if stick.Magnitude > 0.15 then
			delta += Vector2.new(stick.X, -stick.Y) * GAMEPAD_RADIANS_PER_SECOND * sens * dt
		end
		self.Yaw -= delta.X
		self.Pitch = math.clamp(self.Pitch - delta.Y, -PITCH_LIMIT, PITCH_LIMIT)
	end
	touchDelta = Vector2.zero

	-- Recoil recovery.
	if recoilPitch > 0 then
		local recover = math.min(recoilPitch, math.rad(C.Recoil.RecoveryPerSecond) * dt)
		recoilPitch -= recover
		self.Pitch = math.clamp(self.Pitch - recover, -PITCH_LIMIT, PITCH_LIMIT)
	end

	local targetFov = settings.Current.FieldOfView
	if self.Aiming and self.AimFieldOfView then
		targetFov = math.min(targetFov, self.AimFieldOfView)
	end
	local blend = if settings.Current.ReducedMotion then 1 else math.min(1, dt * 14)
	currentFov += (targetFov - currentFov) * blend
	camera.FieldOfView = currentFov

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root == nil or humanoid == nil then
		return
	end
	local alive = humanoid.Health > 0
	local rotation = CFrame.Angles(0, self.Yaw, 0) * CFrame.Angles(self.Pitch, 0, 0)
	local head = root.Position + Vector3.new(0, HEAD, 0)

	if alive then
		humanoid.AutoRotate = false
		root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, self.Yaw, 0)
	end

	local firstPerson = self.Perspective == "FirstPerson" and alive
	setCharacterHidden(firstPerson)
	if firstPerson then
		camera.CFrame = CFrame.new(head) * rotation
		return
	end

	refreshFilter()
	local tp = C.ThirdPerson
	local distance = if self.Aiming then tp.Distance * 0.55 else tp.Distance
	local shoulderOffset =
		rotation:VectorToWorldSpace(Vector3.new(tp.ShoulderOffset.X, tp.ShoulderOffset.Y, 0))
	local shoulderHit = Workspace:Raycast(head, shoulderOffset, params)
	local shoulder = if shoulderHit
		then shoulderHit.Position - shoulderOffset.Unit * tp.CollisionPadding
		else head + shoulderOffset
	local back = rotation.LookVector * -distance
	local boomHit = Workspace:Raycast(shoulder, back, params)
	local position = if boomHit then boomHit.Position - back.Unit * tp.CollisionPadding else shoulder + back
	camera.CFrame = CFrame.new(position) * rotation
end

function CameraController.Start(self: typeof(CameraController))
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then
			stick = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	UserInputService.TouchMoved:Connect(function(touch: InputObject, processed: boolean)
		if not processed then
			touchDelta += Vector2.new(touch.Delta.X, touch.Delta.Y)
		end
	end)
	player.CharacterAdded:Connect(function(character)
		table.clear(hiddenParts)
		local root = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
		if root then
			local _, yaw = root.CFrame:ToOrientation()
			self.Yaw = yaw
			self.Pitch = 0
			recoilPitch = 0
		end
	end)
	RunService:BindToRenderStep("CrossbladeCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		update(self, dt)
	end)
end

return CameraController
