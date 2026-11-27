--!strict
--[[
	Parties (spec §19), hub only: up to Config.Matchmaking.MaxPartySize players in the same hub server
	queue, travel and host private matches together. Invites must be accepted and expire. Rules live
	in Domain/PartyState; this service wires remotes, membership updates and departures.
	Cross-server invites (inviting a friend on another server) are not implemented (D-044).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local PartyState = require(script.Parent.Parent.Domain.PartyState)

local M = Config.Matchmaking

local PartyService = {
	Name = "PartyService",
	Roles = { "Hub" },
	Dependencies = { "Net", "PlayerDataService" },
	-- (userIds whose party membership changed)
	Changed = Signal.new() :: Signal.Signal<{ number }>,
}

local state = PartyState.new(M.MaxPartySize)
local net: any

local function displayName(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	return if player then player.DisplayName else tostring(userId)
end

local function push(userId: number)
	local player = Players:GetPlayerByUserId(userId)
	if player == nil then
		return
	end
	local party = PartyState.PartyOf(state, userId)
	local members = {}
	if party then
		for _, member in party.Members do
			table.insert(members, { UserId = member, Name = displayName(member) })
		end
	end
	local invites = {}
	local now = os.time()
	for partyId, expires in state.Invites[userId] or {} do
		local inviting = state.Parties[partyId]
		if inviting and expires > now then
			table.insert(
				invites,
				{ PartyId = partyId, From = displayName(inviting.Leader), ExpiresAt = expires }
			)
		end
	end
	net.Fire("PartyState", player, {
		PartyId = party and party.Id,
		Leader = party and party.Leader,
		Members = members,
		Invites = invites,
		MaxSize = M.MaxPartySize,
	})
end

local function pushAll(userIds: { number })
	for _, userId in userIds do
		push(userId)
	end
end

-- Players who travel with `player` (the party, or just the player).
function PartyService.Group(_self: typeof(PartyService), player: Player): { Player }
	local list = {}
	for _, userId in PartyState.Group(state, player.UserId) do
		local member = Players:GetPlayerByUserId(userId)
		if member then
			table.insert(list, member)
		end
	end
	return list
end

function PartyService.IsLeaderOrSolo(_self: typeof(PartyService), player: Player): boolean
	return PartyState.IsLeaderOrSolo(state, player.UserId)
end

function PartyService.Init(self: typeof(PartyService), registry: { [string]: any })
	net = registry.Net
	net.OnEvent("PartyAction", function(player: Player, payload: any)
		local before = PartyState.Group(state, player.UserId)
		local target = payload.TargetUserId
		local ok, reason
		local now = os.time()
		if payload.Action == "Invite" then
			if target == nil or Players:GetPlayerByUserId(target) == nil then
				ok, reason = false, "NotInServer"
			else
				ok, reason = PartyState.Invite(state, player.UserId, target, now, M.InviteSeconds)
				if ok then
					push(target)
				end
			end
		elseif payload.Action == "Accept" and payload.PartyId then
			ok, reason = PartyState.Accept(state, player.UserId, payload.PartyId, now)
		elseif payload.Action == "Decline" and payload.PartyId then
			PartyState.Decline(state, player.UserId, payload.PartyId)
			ok = true
		elseif payload.Action == "Leave" then
			ok, reason = PartyState.Leave(state, player.UserId)
		elseif payload.Action == "Kick" and target then
			ok, reason = PartyState.Kick(state, player.UserId, target)
		elseif payload.Action == "Promote" and target then
			ok, reason = PartyState.Promote(state, player.UserId, target)
		else
			ok, reason = false, "BadRequest"
		end
		if not ok then
			net.Fire("Notification", player, { Kind = "Warning", Text = `Party: {reason}` })
		end
		local affected = PartyState.Group(state, player.UserId)
		for _, userId in before do
			if not table.find(affected, userId) then
				table.insert(affected, userId)
			end
		end
		if target and not table.find(affected, target) then
			table.insert(affected, target)
		end
		pushAll(affected)
		if ok and payload.Action ~= "Invite" and payload.Action ~= "Decline" then
			self.Changed:Fire(affected)
		end
	end)
end

function PartyService.Start(self: typeof(PartyService))
	Players.PlayerRemoving:Connect(function(player)
		local affected = PartyState.Group(state, player.UserId)
		PartyState.Forget(state, player.UserId)
		local index = table.find(affected, player.UserId)
		if index then
			table.remove(affected, index)
		end
		pushAll(affected)
		table.insert(affected, player.UserId)
		self.Changed:Fire(affected)
	end)
end

return PartyService
