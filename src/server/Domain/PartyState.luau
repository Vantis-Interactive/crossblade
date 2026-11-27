--!strict
--[[
	Parties within one hub server (spec §19: friend parties of up to eight players). Pure.
	Invites must be accepted, expire, and respect capacity. Leaving as leader promotes the next
	member; an empty party disbands. Every mutation returns (ok, reason).
]]

export type Party = { Id: number, Leader: number, Members: { number } }
export type State = {
	Parties: { [number]: Party },
	ByUser: { [number]: number },
	Invites: { [number]: { [number]: number } }, -- invitee -> partyId -> expiresAt
	NextId: number,
	MaxSize: number,
}

local PartyState = {}

function PartyState.new(maxSize: number): State
	return { Parties = {}, ByUser = {}, Invites = {}, NextId = 1, MaxSize = maxSize }
end

function PartyState.PartyOf(state: State, userId: number): Party?
	local id = state.ByUser[userId]
	return id and state.Parties[id]
end

-- Members who travel/queue together: the party, or just the player when solo.
function PartyState.Group(state: State, userId: number): { number }
	local party = PartyState.PartyOf(state, userId)
	return if party then table.clone(party.Members) else { userId }
end

function PartyState.IsLeaderOrSolo(state: State, userId: number): boolean
	local party = PartyState.PartyOf(state, userId)
	return party == nil or party.Leader == userId
end

local function create(state: State, leader: number): Party
	local party = { Id = state.NextId, Leader = leader, Members = { leader } }
	state.NextId += 1
	state.Parties[party.Id] = party
	state.ByUser[leader] = party.Id
	return party
end

function PartyState.Invite(
	state: State,
	from: number,
	to: number,
	now: number,
	ttl: number
): (boolean, string?)
	if from == to then
		return false, "Self"
	end
	if state.ByUser[to] then
		return false, "AlreadyInParty"
	end
	local party = PartyState.PartyOf(state, from)
	if party and party.Leader ~= from then
		return false, "NotLeader"
	end
	if party and #party.Members >= state.MaxSize then
		return false, "Full"
	end
	party = party or create(state, from)
	state.Invites[to] = state.Invites[to] or {}
	state.Invites[to][(party :: Party).Id] = now + ttl
	return true, nil
end

function PartyState.Accept(state: State, userId: number, partyId: number, now: number): (boolean, string?)
	local invites = state.Invites[userId]
	local expires = invites and invites[partyId]
	if expires == nil or now > expires then
		return false, "NoInvite"
	end
	invites[partyId] = nil
	if state.ByUser[userId] then
		return false, "AlreadyInParty"
	end
	local party = state.Parties[partyId]
	if party == nil then
		return false, "Disbanded"
	end
	if #party.Members >= state.MaxSize then
		return false, "Full"
	end
	table.insert(party.Members, userId)
	state.ByUser[userId] = partyId
	return true, nil
end

function PartyState.Decline(state: State, userId: number, partyId: number)
	local invites = state.Invites[userId]
	if invites then
		invites[partyId] = nil
	end
end

function PartyState.Leave(state: State, userId: number): (boolean, string?)
	local party = PartyState.PartyOf(state, userId)
	if party == nil then
		return false, "NotInParty"
	end
	local index = table.find(party.Members, userId)
	if index then
		table.remove(party.Members, index)
	end
	state.ByUser[userId] = nil
	if #party.Members <= 1 then
		for _, member in party.Members do
			state.ByUser[member] = nil
		end
		state.Parties[party.Id] = nil
	elseif party.Leader == userId then
		party.Leader = party.Members[1]
	end
	return true, nil
end

function PartyState.Kick(state: State, leader: number, target: number): (boolean, string?)
	local party = PartyState.PartyOf(state, leader)
	if party == nil or party.Leader ~= leader then
		return false, "NotLeader"
	end
	if target == leader or state.ByUser[target] ~= party.Id then
		return false, "NotMember"
	end
	return PartyState.Leave(state, target)
end

function PartyState.Promote(state: State, leader: number, target: number): (boolean, string?)
	local party = PartyState.PartyOf(state, leader)
	if party == nil or party.Leader ~= leader then
		return false, "NotLeader"
	end
	if state.ByUser[target] ~= party.Id then
		return false, "NotMember"
	end
	party.Leader = target
	return true, nil
end

-- Removes a departed player everywhere (party membership and pending invites).
function PartyState.Forget(state: State, userId: number)
	PartyState.Leave(state, userId)
	state.Invites[userId] = nil
end

return PartyState
