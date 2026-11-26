--!strict
--[[
	Platform policy checks (spec §14 compliance). Looks up each player's PolicyService info and
	exposes a fail-closed decision for paid randomized items: purchased coins can be spent on crates
	only when the lookup succeeded and reported no restriction (Domain/PaidRandomPolicy).
]]

local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Util.Logger)
local Retry = require(ReplicatedStorage.Shared.Util.Retry)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local PaidRandomPolicy = require(script.Parent.Parent.Domain.PaidRandomPolicy)

local log = Logger.new("Policy")

local PolicyComplianceService = {
	Name = "PolicyComplianceService",
	Dependencies = { "AuditService" },
	StatusChanged = Signal.new() :: Signal.Signal<Player, PaidRandomPolicy.Status>,
}

local statuses: { [Player]: PaidRandomPolicy.Status } = {}
local audit: any

local function fetch(player: Player)
	local ok, info = Retry.Call({ MaxAttempts = 3, BaseBackoffSeconds = 1, MaxBackoffSeconds = 4 }, function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	if player.Parent ~= Players then
		return
	end
	local status = PaidRandomPolicy.Decide(ok, info)
	statuses[player] = status
	if status == "Unknown" then
		log:Warn(
			"policy lookup failed; paid random items blocked (fail closed)",
			{ player = player.UserId, error = if ok then nil else info }
		)
		audit:Record("Economy", "PolicyLookupFailed", player.UserId, nil)
	end
	PolicyComplianceService.StatusChanged:Fire(player, status)
end

function PolicyComplianceService.Init(_self: typeof(PolicyComplianceService), registry: { [string]: any })
	audit = registry.AuditService
end

function PolicyComplianceService.Start(_self: typeof(PolicyComplianceService))
	Players.PlayerAdded:Connect(function(player)
		task.spawn(fetch, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(fetch, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		statuses[player] = nil
	end)
end

function PolicyComplianceService.GetStatus(
	_self: typeof(PolicyComplianceService),
	player: Player
): PaidRandomPolicy.Status
	return statuses[player] or "Unknown"
end

function PolicyComplianceService.PurchasedCurrencyAllowedForCrates(
	self: typeof(PolicyComplianceService),
	player: Player
): boolean
	return PaidRandomPolicy.AllowsPurchasedCurrency(self:GetStatus(player))
end

return PolicyComplianceService
