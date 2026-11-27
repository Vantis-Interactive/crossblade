--!strict
--[[
	Reserved match servers (spec §19), arena only. Active when MatchContext says this server was
	reserved by matchmaking or a private match.
	  - Admission: only rostered players (Domain/ReservedRoster); others are sent to the hub.
	  - Start: when the roster has arrived, or at the arrival deadline if the match is playable;
	    otherwise everyone is returned to the hub (cancelled).
	  - Reconnection: each admitted player gets a reconnect record (place + access code) the hub uses
	    to offer a rejoin; a player who does not return within the window is removed for good.
	  - After the single match ends, everyone returns to the hub and reconnect records are cleared.
	  - Fail closed: a reserved server without a readable match record returns every player.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Logger = require(ReplicatedStorage.Shared.Util.Logger)
local MatchContext = require(script.Parent.Parent.Core.MatchContext)
local ReservedRoster = require(script.Parent.Parent.Domain.ReservedRoster)
local MemoryStoreAdapter = require(script.Parent.Parent.Matchmaking.MemoryStoreAdapter)

local log = Logger.new("Reserved")
local R = Config.Matchmaking.Reserved

local ReservedMatchService = {
	Name = "ReservedMatchService",
	Roles = { "Arena" },
	Dependencies = { "PlayerDataService", "MatchService", "PortalService", "AuditService" },
}

local roster: ReservedRoster.State? = nil
local active: any = nil
local closed = false
local match: any
local portal: any
local audit: any

local function activeKey(userId: number): string
	return `u{userId}`
end

local function clearActive(userId: number)
	if active then
		pcall(function()
			active:RemoveAsync(activeKey(userId))
		end)
	end
end

local function returnEveryone(message: string)
	closed = true
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			portal:SendToHub(player, message, true)
		end)
	end
end

function ReservedMatchService.Init(_self: typeof(ReservedMatchService), registry: { [string]: any })
	match = registry.MatchService
	portal = registry.PortalService
	audit = registry.AuditService
	if not MatchContext.IsReserved() then
		return
	end
	local record = MatchContext.Record
	if record then
		roster = ReservedRoster.new({ Teams = record.Teams }, os.time(), R.ArrivalTimeoutSeconds)
		active = MemoryStoreAdapter.Map(Config.Matchmaking.StoreNames.Active)
	end

	registry.PlayerDataService.ProfileLoaded:Connect(function(player: Player)
		if MatchContext.Failed or record == nil or roster == nil then
			task.spawn(function()
				portal:SendToHub(player, "This match could not be found. Returning to the hub.", true)
			end)
			return
		end
		if closed then
			task.spawn(function()
				portal:SendToHub(player, "This match has ended.", true)
			end)
			return
		end
		local ok, reason = ReservedRoster.Admit(roster, player.UserId, os.time())
		if not ok then
			audit:Record("Security", "ReservedAdmissionRefused", player.UserId, { reason = reason })
			task.spawn(function()
				portal:SendToHub(player, "This is a private match.", true)
			end)
			return
		end
		task.spawn(function()
			pcall(function()
				active:SetAsync(activeKey(player.UserId), {
					PlaceId = game.PlaceId,
					AccessCode = record.AccessCode,
					Destination = record.Destination,
					ExpiresAt = os.time() + R.MatchRecordSeconds,
				}, R.MatchRecordSeconds)
			end)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		if roster then
			ReservedRoster.Disconnect(roster, player.UserId, os.time(), R.ReconnectSeconds)
		end
	end)

	match.MatchFinished:Connect(function()
		task.delay(R.ReturnToHubSeconds, function()
			if roster then
				for userId in roster.Members do
					clearActive(userId)
				end
			end
			returnEveryone("Match complete. Returning to the hub.")
		end)
	end)
end

function ReservedMatchService.Start(_self: typeof(ReservedMatchService))
	if not MatchContext.IsReserved() or roster == nil then
		return
	end
	local state = roster :: ReservedRoster.State
	task.spawn(function()
		while not closed do
			task.wait(1)
			local now = os.time()
			if not state.Started then
				local decision = ReservedRoster.Decide(state, now, match:Mode().Kind ~= "FreeForAll")
				if decision == "Start" then
					state.Started = true
					log:Info("reserved match starting")
					match:BeginReserved()
				elseif decision == "Cancel" then
					log:Warn("reserved match cancelled: players did not arrive")
					for userId in state.Members do
						clearActive(userId)
					end
					returnEveryone("Not enough players arrived. Returning to the hub.")
				end
			end
			for _, userId in ReservedRoster.Expired(state, now) do
				match:ForgetPlayer(userId)
				clearActive(userId)
			end
		end
	end)
end

return ReservedMatchService
