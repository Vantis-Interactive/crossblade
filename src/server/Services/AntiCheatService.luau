--!strict
--[[
	Defence-in-depth anti-cheat (spec §25). Collects signals from the network layer, combat
	validation and server-side movement sampling into a decaying per-player suspicion score.

	Policy: signals are evidence, not verdicts. Crossing ReviewThreshold raises an audited security
	alert for moderators. Removal from the server (never a ban) requires the KickOnSuspicion flag.
	Movement correction only triggers for grossly impossible movement (teleport-scale).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Logger = require(ReplicatedStorage.Shared.Util.Logger)
local MovementValidator = require(script.Parent.Parent.Domain.MovementValidator)
local SuspicionScore = require(script.Parent.Parent.Domain.SuspicionScore)

local log = Logger.new("AntiCheat")
local S = Config.AntiCheat.Suspicion
local M = Config.AntiCheat.Movement

local AntiCheatService = {
	Name = "AntiCheatService",
	Dependencies = { "Net", "AuditService" },
}

local suspicion: { [Player]: SuspicionScore.State } = {}
local movement: { [Player]: MovementValidator.State } = {}
local alerted: { [Player]: boolean } = {}
local audit: any

local limits: MovementValidator.Limits = {
	RunSpeed = Config.Player.Movement.RunSpeed,
	SpeedToleranceMultiplier = M.SpeedToleranceMultiplier,
	SpeedToleranceFlat = M.SpeedToleranceFlat,
	CorrectionMultiplier = M.CorrectionMultiplier,
	MaxRiseSpeed = M.MaxRiseSpeed,
	FlagsBeforeSuspicion = M.FlagsBeforeSuspicion,
	FlagWindowSeconds = M.FlagWindowSeconds,
}

function AntiCheatService.Report(
	_self: typeof(AntiCheatService),
	player: Player,
	kind: string,
	detail: { [string]: any }?
)
	local weight = (S.Weights :: any)[kind] or 1
	local state = suspicion[player]
	if state == nil then
		state = SuspicionScore.new(os.clock())
		suspicion[player] = state
	end
	local score = SuspicionScore.Add(state, kind, weight, os.clock(), S.DecayPerMinute)
	log:Debug("signal", { player = player.UserId, kind = kind, score = score })
	if score >= S.ReviewThreshold and not alerted[player] then
		alerted[player] = true
		audit:Record("Security", "SuspicionReviewThreshold", player.UserId, {
			score = math.floor(score),
			lastSignal = kind,
			detail = detail and detail.reason,
		})
	elseif score < S.ReviewThreshold * 0.5 then
		alerted[player] = nil
	end
	if score >= S.KickThreshold and Config.FeatureFlags.KickOnSuspicion then
		audit:Record("Security", "RemovedForSuspicion", player.UserId, { score = math.floor(score) })
		player:Kick("Removed from this server due to unusual activity.")
	end
end

-- Must be called by any server code that moves a character (spawning, corrections).
function AntiCheatService.NotifyTeleport(_self: typeof(AntiCheatService), player: Player, position: Vector3)
	local state = movement[player]
	if state == nil then
		state = MovementValidator.new()
		movement[player] = state
	end
	MovementValidator.Teleported(state, position, os.clock(), M.TeleportGraceSeconds)
end

local function sampleMovement(self: typeof(AntiCheatService))
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root == nil or humanoid == nil or humanoid.Health <= 0 then
			-- Dead or between lives: forget the previous position so a respawn is never a "teleport".
			movement[player] = nil
		else
			local state = movement[player]
			if state == nil then
				state = MovementValidator.new()
				movement[player] = state
			end
			local verdict, speed, reached = MovementValidator.Sample(state, root.Position, now, limits)
			if verdict == "Correct" then
				self:Report(player, "SpeedViolation", { reason = "Impossible", speed = speed })
				if Config.FeatureFlags.MovementAntiCheatCorrection and state.LastValid then
					character:PivotTo(CFrame.new(state.LastValid) * root.CFrame.Rotation)
					MovementValidator.Teleported(state, state.LastValid, now, M.TeleportGraceSeconds)
				end
			elseif reached then
				self:Report(player, "SpeedViolation", { reason = "Repeated", speed = speed })
			end
		end
	end
end

function AntiCheatService.Init(self: typeof(AntiCheatService), registry: { [string]: any })
	audit = registry.AuditService
	registry.Net.Violation:Connect(function(player: Player, kind: string, remoteName: string, detail: string?)
		self:Report(player, kind, { reason = detail, remote = remoteName })
	end)
end

function AntiCheatService.Start(self: typeof(AntiCheatService))
	Players.PlayerRemoving:Connect(function(player)
		suspicion[player] = nil
		movement[player] = nil
		alerted[player] = nil
	end)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= M.SampleIntervalSeconds then
			accumulator = 0
			sampleMovement(self)
		end
	end)
end

return AntiCheatService
