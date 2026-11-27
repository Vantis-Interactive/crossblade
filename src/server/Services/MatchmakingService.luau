--!strict
--[[
	Cross-server matchmaking (spec §19), hub only.
	  - JoinQueue: the party leader (or a solo player) queues the whole group for a queued destination.
	    The group must be within the destination's party limit, have finished the tutorial, and not
	    already be queued anywhere (Matchmaking/Queue user index).
	  - Leader: one hub per destination (lease) forms matches, reserves servers and assigns tickets
	    (Matchmaking/Matchmaker).
	  - Owner hub: heartbeats its tickets, polls assignments and teleports the group with the reserved
	    access code; a failed teleport requeues at the front of the line (bounded retries).
	  - Any party change or departure cancels the group's ticket.
	  - Reconnect: players with an unfinished reserved match are offered a rejoin.
	Studio cannot reserve servers or teleport, so queueing is refused there with a clear reason.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Shared.Config)
local Logger = require(ReplicatedStorage.Shared.Util.Logger)
local Matchmaker = require(script.Parent.Parent.Matchmaking.Matchmaker)
local MemoryStoreAdapter = require(script.Parent.Parent.Matchmaking.MemoryStoreAdapter)
local Queue = require(script.Parent.Parent.Matchmaking.Queue)

local log = Logger.new("Matchmaking")
local M = Config.Matchmaking
local N = M.StoreNames

local MatchmakingService = {
	Name = "MatchmakingService",
	Roles = { "Hub" },
	Dependencies = { "Net", "PlayerDataService", "PartyService", "PortalService", "AuditService" },
}

type Local = { Ticket: Queue.Ticket, Since: number, Delivering: boolean? }

local tickets: { [string]: Local } = {}
local byUser: { [number]: string } = {}
local offers: { [Player]: { [string]: any } } = {}
local storesByDestination: { [string]: Queue.Stores } = {}
local shared: { [string]: any } = {}
local net: any
local playerData: any
local party: any
local portal: any
local audit: any

local function stores(destination: string): Queue.Stores
	local existing = storesByDestination[destination]
	if existing then
		return existing
	end
	local created = {
		Tickets = MemoryStoreAdapter.Map(N.Tickets .. destination),
		Users = shared.Users,
		Assignments = shared.Assignments,
	}
	storesByDestination[destination] = created
	return created
end

local function status(userIds: { number }, payload: { [string]: any })
	for _, userId in userIds do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			net.Fire("QueueStatus", player, payload)
		end
	end
end

local function forget(ticketId: string)
	local entry = tickets[ticketId]
	if entry then
		for _, userId in entry.Ticket.Members do
			if byUser[userId] == ticketId then
				byUser[userId] = nil
			end
		end
		tickets[ticketId] = nil
	end
end

local function cancel(ticketId: string, reason: string)
	local entry = tickets[ticketId]
	if entry == nil then
		return
	end
	pcall(Queue.Cancel, stores(entry.Ticket.Destination), entry.Ticket)
	status(
		entry.Ticket.Members,
		{ State = "Cancelled", Destination = entry.Ticket.Destination, Reason = reason }
	)
	forget(ticketId)
end

local function refusal(player: Player, destination: string, group: { Player }): string?
	local spec = M.Queues[destination]
	local place = Config.Places.Destinations[destination]
	if spec == nil or place == nil then
		return "UnknownDestination"
	end
	if not party:IsLeaderOrSolo(player) then
		return "NotLeader"
	end
	if #group > spec.MaxPartySize then
		return "PartyTooLarge"
	end
	for _, member in group do
		local profile = playerData:GetProfile(member)
		if profile == nil then
			return "NotLoaded"
		end
		if not profile.Data.Tutorial.Completed then
			return "TutorialRequired"
		end
		if byUser[member.UserId] then
			return "AlreadyQueued"
		end
	end
	if RunService:IsStudio() then
		return "Studio"
	end
	if place.PlaceId == 0 then
		return "NotConfigured"
	end
	return nil
end

local function join(player: Player, destination: string)
	local group = party:Group(player)
	local reason = refusal(player, destination, group)
	local members = {}
	for _, member in group do
		table.insert(members, member.UserId)
	end
	if reason then
		status({ player.UserId }, { State = "Refused", Destination = destination, Reason = reason })
		return
	end
	local ticket: Queue.Ticket = {
		Id = HttpService:GenerateGUID(false),
		Destination = destination,
		Members = members,
		CreatedAt = os.time(),
		HubJobId = game.JobId,
		Retries = 0,
	}
	local ok, enqueued, why =
		pcall(Queue.Enqueue, stores(destination), ticket, os.time(), M.Ticket.TimeToLiveSeconds)
	if not ok or not enqueued then
		status(
			members,
			{ State = "Refused", Destination = destination, Reason = if ok then why else "QueueUnavailable" }
		)
		return
	end
	tickets[ticket.Id] = { Ticket = ticket, Since = os.time() }
	for _, userId in members do
		byUser[userId] = ticket.Id
	end
	status(members, { State = "Queued", Destination = destination, Since = ticket.CreatedAt })
end

local function deliver(entry: Local, assignment: { [string]: any })
	local ticket = entry.Ticket
	if assignment.Rejected then
		status(
			ticket.Members,
			{ State = "Cancelled", Destination = ticket.Destination, Reason = assignment.Reason }
		)
		forget(ticket.Id)
		return
	end
	local players = {}
	for _, userId in ticket.Members do
		local member = Players:GetPlayerByUserId(userId)
		if member then
			table.insert(players, member)
		end
	end
	status(ticket.Members, { State = "Matched", Destination = ticket.Destination })
	local ok = portal:TeleportReserved(players, assignment.PlaceId, assignment.AccessCode)
	if ok then
		status(ticket.Members, { State = "Joining", Destination = ticket.Destination })
		pcall(Queue.Cancel, stores(ticket.Destination), ticket) -- releases the user index entries
		forget(ticket.Id)
	else
		audit:Record(
			"Data",
			"MatchTeleportFailed",
			players[1] and players[1].UserId,
			{ destination = ticket.Destination, retries = ticket.Retries }
		)
		local ok2, requeued = pcall(
			Queue.Requeue,
			stores(ticket.Destination),
			ticket,
			os.time(),
			M.Ticket.TimeToLiveSeconds,
			M.Ticket.MaxTeleportRetries
		)
		if ok2 and requeued then
			status(ticket.Members, { State = "Requeued", Destination = ticket.Destination })
		else
			status(
				ticket.Members,
				{ State = "Cancelled", Destination = ticket.Destination, Reason = "TeleportFailed" }
			)
			forget(ticket.Id)
		end
	end
end

local function leaderTick(destination: string, spec: any)
	local place = Config.Places.Destinations[destination]
	if place == nil or place.PlaceId == 0 then
		return
	end
	local acquired =
		Queue.AcquireLease(shared.Leases, `lead:{destination}`, game.JobId, os.time(), M.Leader.LeaseSeconds)
	if not acquired then
		return
	end
	local result = Matchmaker.Tick({
		Stores = stores(destination),
		Matches = shared.Matches,
		Reserve = function()
			return TeleportService:ReserveServer(place.PlaceId)
		end,
		PlaceId = place.PlaceId,
		Destination = destination,
		Mode = place.Mode or destination,
		Spec = spec,
		Now = os.time(),
		MaxTickets = M.Leader.MaxTicketsPerTick,
		AssignmentSeconds = M.Assignment.TimeToLiveSeconds,
		MatchRecordSeconds = M.Reserved.MatchRecordSeconds,
		Token = `{game.JobId}:{os.clock()}`,
		TicketSeconds = M.Ticket.TimeToLiveSeconds,
	})
	if result.Formed > 0 or result.Failed > 0 then
		log:Info(
			"matchmaking tick",
			{ destination = destination, formed = result.Formed, failed = result.Failed }
		)
	end
end

function MatchmakingService.Init(_self: typeof(MatchmakingService), registry: { [string]: any })
	net = registry.Net
	playerData = registry.PlayerDataService
	party = registry.PartyService
	portal = registry.PortalService
	audit = registry.AuditService
	shared.Users = MemoryStoreAdapter.Map(N.UserIndex)
	shared.Assignments = MemoryStoreAdapter.Map(N.Assignments)
	shared.Leases = MemoryStoreAdapter.Map(N.Leases)
	shared.Matches = MemoryStoreAdapter.Map(N.Matches)
	shared.Active = MemoryStoreAdapter.Map(N.Active)

	net.OnEvent("JoinQueue", function(player: Player, payload: any)
		task.spawn(join, player, payload.Destination)
	end)
	net.OnEvent("LeaveQueue", function(player: Player)
		local ticketId = byUser[player.UserId]
		if ticketId then
			cancel(ticketId, "Left")
		end
	end)
	party.Changed:Connect(function(userIds: { number })
		for _, userId in userIds do
			local ticketId = byUser[userId]
			if ticketId then
				cancel(ticketId, "PartyChanged")
			end
		end
	end)

	playerData.ProfileLoaded:Connect(function(player: Player)
		task.spawn(function()
			local ok, record = pcall(function()
				return shared.Active:GetAsync(`u{player.UserId}`)
			end)
			if
				ok
				and type(record) == "table"
				and (record.ExpiresAt or 0) > os.time()
				and record.PlaceId
				and record.PlaceId > 0
			then
				offers[player] = record
				net.Fire(
					"ReconnectOffer",
					player,
					{ Destination = record.Destination, ExpiresAt = record.ExpiresAt }
				)
			end
		end)
	end)
	net.OnEvent("RequestReconnect", function(player: Player)
		local record = offers[player]
		if record == nil then
			return
		end
		offers[player] = nil
		task.spawn(function()
			local ok, reason = portal:TeleportReserved({ player }, record.PlaceId, record.AccessCode)
			if not ok then
				net.Fire("TeleportStatus", player, { Ok = false, Reason = reason or "Failed" })
			end
		end)
	end)
end

function MatchmakingService.Start(_self: typeof(MatchmakingService))
	Players.PlayerRemoving:Connect(function(player)
		offers[player] = nil
		local ticketId = byUser[player.UserId]
		if ticketId then
			cancel(ticketId, "MemberLeft")
		end
	end)

	task.spawn(function() -- heartbeats keep live tickets from expiring
		while true do
			task.wait(M.Ticket.HeartbeatSeconds)
			for ticketId, entry in tickets do
				local ok, alive = pcall(
					Queue.Heartbeat,
					stores(entry.Ticket.Destination),
					entry.Ticket,
					os.time(),
					M.Ticket.TimeToLiveSeconds
				)
				if ok and not alive then
					local readOk, assignment =
						pcall(Queue.Assignment, stores(entry.Ticket.Destination), ticketId)
					if readOk and assignment == nil then
						status(entry.Ticket.Members, {
							State = "Cancelled",
							Destination = entry.Ticket.Destination,
							Reason = "Expired",
						})
						forget(ticketId)
					end
				end
			end
		end
	end)

	task.spawn(function() -- deliver assignments for tickets owned by this hub
		while true do
			task.wait(M.Assignment.PollSeconds)
			for ticketId, entry in tickets do
				-- In-flight guard: delivery can yield for seconds while teleport retries run.
				if not entry.Delivering then
					local ok, assignment = pcall(Queue.Assignment, stores(entry.Ticket.Destination), ticketId)
					if ok and assignment then
						entry.Delivering = true
						task.spawn(function()
							deliver(entry, assignment)
							entry.Delivering = false
						end)
					end
				end
			end
		end
	end)

	if RunService:IsStudio() then
		log:Info("Studio: matchmaking leader disabled (cannot reserve servers)")
		return
	end
	task.spawn(function() -- leader election and match forming
		while true do
			task.wait(M.Leader.TickSeconds)
			for destination, spec in M.Queues do
				local ok, err = pcall(leaderTick, destination, spec)
				if not ok then
					log:Warn("leader tick failed", { destination = destination, error = err })
				end
			end
		end
	end)
end

return MatchmakingService
