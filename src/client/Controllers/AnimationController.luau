--!strict
--[[
	TEMPORARY procedural weapon poses (docs/ASSET_MANIFEST.md DEV-ANIM-001).
	Until original animation assets are authored and uploaded, every client poses every R15 character's
	arms each frame from replicated attributes (AnimationProfile, AimPitch). Motor6D.Transform is not
	replicated, so this is purely visual and has no gameplay effect. Poses are applied in
	PreSimulation, after the Animator has written its own transforms for the frame.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Net = require(script.Parent.Parent.Core.Net)

local AnimationController = {
	Name = "AnimationController",
	Dependencies = { "CameraController" },
}

local camera: any
local swings: { [Model]: number } = {}
local localPlayer = Players.LocalPlayer
local RAISE = math.rad(90)

local function motor(character: Model, partName: string, motorName: string): Motor6D?
	local part = character:FindFirstChild(partName)
	local found = part and part:FindFirstChild(motorName)
	return if found and found:IsA("Motor6D") then found else nil
end

local function pose(character: Model, pitch: number, profile: string, swing: number)
	local right = motor(character, "RightUpperArm", "RightShoulder")
	local left = motor(character, "LeftUpperArm", "LeftShoulder")
	local rightElbow = motor(character, "RightLowerArm", "RightElbow")
	local leftElbow = motor(character, "LeftLowerArm", "LeftElbow")
	local waist = motor(character, "UpperTorso", "Waist")
	if right == nil then
		return -- R6 or custom rig: no procedural pose
	end
	local aimPitch = math.clamp(pitch, -1.2, 1.2)
	if waist then
		waist.Transform = CFrame.Angles(aimPitch * 0.35, 0, 0)
	end
	local armPitch = aimPitch * 0.65
	if profile == "Knife" then
		right.Transform = CFrame.Angles(math.rad(55) + armPitch * 0.5 + swing * 1.2, swing * 0.8, 0)
	else
		right.Transform = CFrame.Angles(RAISE + armPitch, 0, 0)
		if rightElbow then
			rightElbow.Transform = CFrame.new()
		end
	end
	if profile == "TwoHanded" and left then
		left.Transform = CFrame.Angles(RAISE + armPitch, math.rad(-35), 0)
		if leftElbow then
			leftElbow.Transform = CFrame.Angles(math.rad(25), 0, 0)
		end
	end
end

function AnimationController.Init(_self: typeof(AnimationController), registry: { [string]: any })
	camera = registry.CameraController
end

function AnimationController.Start(_self: typeof(AnimationController))
	Net.On("MeleeSwing", function(payload)
		local attacker = Players:GetPlayerByUserId(payload.AttackerUserId)
		if attacker and attacker.Character then
			swings[attacker.Character] = os.clock() + 0.25
		end
	end)
	RunService.PreSimulation:Connect(function()
		local now = os.clock()
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if character and humanoid and humanoid.Health > 0 then
				local profile = character:GetAttribute("AnimationProfile")
				if type(profile) == "string" then
					local pitch = if player == localPlayer
						then camera.Pitch
						else (character:GetAttribute("AimPitch") or 0)
					local swingUntil = swings[character]
					local swing = if swingUntil and swingUntil > now then (swingUntil - now) / 0.25 else 0
					pose(character, pitch :: number, profile, swing)
				end
			end
		end
		for character, untilTime in swings do
			if untilTime < now or character.Parent == nil then
				swings[character] = nil
			end
		end
	end)
end

return AnimationController
