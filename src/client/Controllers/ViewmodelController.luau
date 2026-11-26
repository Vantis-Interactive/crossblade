--!strict
--[[
	First-person viewmodel (spec §6, §12). Purely cosmetic and local: it never affects timing or
	hit detection. Inspect/swing/reload motions are procedural until original animation assets exist
	(docs/ASSET_MANIFEST.md DEV-ANIM-001). Reduced-motion disables sway.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local WeaponCatalog = require(ReplicatedStorage.Shared.Weapons.WeaponCatalog)
local WeaponModels = require(ReplicatedStorage.Shared.Weapons.WeaponModels)

local ViewmodelController = {
	Name = "ViewmodelController",
	Dependencies = { "CameraController", "SettingsController" },
}

local player = Players.LocalPlayer
local camera: any
local settings: any
local model: Model? = nil
local slot = "Primary"
local kick = 0
local swing = 0
local swingKind = "Slash"
local inspect = 0
local reloadUntil = 0
local reloadDuration = 1
local lastYaw = 0
local sway = Vector2.zero

local HIP = CFrame.new(0.9, -0.85, -1.7)
local AIM = CFrame.new(0, -0.5, -1.35)
local KNIFE = CFrame.new(0.8, -0.9, -1.4) * CFrame.Angles(math.rad(10), math.rad(-15), 0)

function ViewmodelController.SetWeapon(
	_self: typeof(ViewmodelController),
	weaponId: string?,
	newSlot: string,
	inHand: boolean
)
	if model then
		model:Destroy()
		model = nil
	end
	slot = newSlot
	inspect = 0
	reloadUntil = 0
	local entry = weaponId and WeaponCatalog.Get(weaponId)
	if entry == nil or (newSlot == "Knife" and not inHand) then
		return
	end
	local built = WeaponModels.Build(entry.ModelProfile, entry.Id)
	for _, part in built:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	built.Name = "Viewmodel"
	built.Parent = Workspace.CurrentCamera
	model = built
end

function ViewmodelController.Kick(_self: typeof(ViewmodelController))
	kick = 1
end

function ViewmodelController.Swing(_self: typeof(ViewmodelController), kind: string)
	swing = 1
	swingKind = kind
end

function ViewmodelController.Inspect(_self: typeof(ViewmodelController))
	inspect = 1.6
end

function ViewmodelController.PlayReload(_self: typeof(ViewmodelController), seconds: number)
	reloadDuration = math.max(0.1, seconds)
	reloadUntil = os.clock() + seconds
end

-- World position bullets visually leave from (first-person viewmodel, else the held world model).
function ViewmodelController.GetMuzzlePosition(_self: typeof(ViewmodelController)): Vector3?
	if camera.Perspective == "FirstPerson" and model and model.PrimaryPart then
		local muzzle = model.PrimaryPart:FindFirstChild("Muzzle") :: Attachment?
		if muzzle then
			return muzzle.WorldPosition
		end
	end
	local held = player.Character and player.Character:FindFirstChild("EquippedWeapon") :: Model?
	local handle = held and held.PrimaryPart
	local muzzle = handle and handle:FindFirstChild("Muzzle") :: Attachment?
	return muzzle and muzzle.WorldPosition
end

function ViewmodelController.Init(_self: typeof(ViewmodelController), registry: { [string]: any })
	camera = registry.CameraController
	settings = registry.SettingsController
end

function ViewmodelController.Start(_self: typeof(ViewmodelController))
	RunService:BindToRenderStep("CrossbladeViewmodel", Enum.RenderPriority.Camera.Value + 2, function(dt)
		if model == nil then
			return
		end
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local visible = camera.Perspective == "FirstPerson" and humanoid ~= nil and humanoid.Health > 0
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part.Name ~= "Handle" then
				part.LocalTransparencyModifier = if visible then 0 else 1
			end
		end
		if not visible then
			return
		end
		local reduced = settings.Current.ReducedMotion
		local yawDelta = camera.Yaw - lastYaw
		lastYaw = camera.Yaw
		if reduced then
			sway = Vector2.zero
		else
			sway = sway:Lerp(
				Vector2.new(math.clamp(yawDelta * 2, -0.15, 0.15), math.sin(os.clock() * 1.6) * 0.01),
				math.min(1, dt * 8)
			)
		end
		kick = math.max(0, kick - dt * 9)
		swing = math.max(0, swing - dt * 4)
		inspect = math.max(0, inspect - dt)

		local base = if slot == "Knife" then KNIFE elseif camera.Aiming then AIM else HIP
		local offset = base * CFrame.new(sway.X, sway.Y, kick * 0.18) * CFrame.Angles(kick * 0.06, 0, 0)
		if inspect > 0 then
			local t = 1 - inspect / 1.6
			offset *= CFrame.Angles(
				0,
				math.sin(t * math.pi) * math.rad(70),
				math.sin(t * math.pi * 2) * math.rad(25)
			)
		end
		local reloadLeft = reloadUntil - os.clock()
		if reloadLeft > 0 then
			local t = 1 - reloadLeft / reloadDuration
			offset *= CFrame.new(0, -math.sin(t * math.pi) * 0.35, 0) * CFrame.Angles(
				math.sin(t * math.pi) * math.rad(-30),
				0,
				0
			)
		end
		if swing > 0 then
			if swingKind == "Stab" then
				offset *= CFrame.new(0, 0, -math.sin(swing * math.pi) * 0.8)
			elseif swingKind == "Throw" then
				offset *= CFrame.new(0, swing * 0.5, -swing * 0.4) * CFrame.Angles(swing * 1.2, 0, 0)
			else
				offset *= CFrame.Angles(0, math.sin(swing * math.pi) * 1.1, -math.sin(swing * math.pi) * 0.6)
			end
		end
		model:PivotTo((Workspace.CurrentCamera :: Camera).CFrame * offset)
	end)
end

return ViewmodelController
