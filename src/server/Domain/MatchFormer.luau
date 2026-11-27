--!strict
--[[
	Forms team matches from queued tickets (spec §19). Pure.
	  - Tickets are considered oldest first; the oldest remaining ticket is always in the next match
	    (no starvation by smaller tickets).
	  - Parties are never split: a ticket goes entirely onto one team.
	  - A match forms when both teams are full, or (relaxed) when the oldest ticket has waited
	    RelaxAfterSeconds and at least RelaxedMinPlayers are placed on two non-empty teams.
	Greedy packing; it can miss a feasible packing in rare party-size combinations (documented).
]]

export type Ticket = { Id: string, Members: { number }, CreatedAt: number }
export type Spec = { TeamSize: number, RelaxedMinPlayers: number?, RelaxAfterSeconds: number? }
export type Match = { TicketIds: { string }, Teams: { A: { number }, B: { number } } }

local MatchFormer = {}

local function attempt(pool: { Ticket }, spec: Spec, now: number): (Match?, { [string]: boolean })
	local teams = { A = {} :: { number }, B = {} :: { number } }
	local used: { [string]: boolean } = {}
	local ids = {}
	for index, ticket in pool do
		local size = #ticket.Members
		local roomA, roomB = spec.TeamSize - #teams.A, spec.TeamSize - #teams.B
		local team: "A" | "B" | nil = nil
		if size <= roomA and (roomA >= roomB or size > roomB) then
			team = "A"
		elseif size <= roomB then
			team = "B"
		end
		if team then
			for _, member in ticket.Members do
				table.insert(teams[team], member)
			end
			used[ticket.Id] = true
			table.insert(ids, ticket.Id)
		elseif index == 1 then
			return nil, {} -- the oldest ticket cannot fit at all (oversized): caller rejects it
		end
		if #teams.A == spec.TeamSize and #teams.B == spec.TeamSize then
			return { TicketIds = ids, Teams = teams }, used
		end
	end
	local oldest = pool[1]
	if
		spec.RelaxedMinPlayers
		and spec.RelaxAfterSeconds
		and oldest
		and now - oldest.CreatedAt >= spec.RelaxAfterSeconds
	then
		if #teams.A > 0 and #teams.B > 0 and #teams.A + #teams.B >= spec.RelaxedMinPlayers then
			return { TicketIds = ids, Teams = teams }, used
		end
	end
	return nil, {}
end

-- Returns formed matches and the ids of tickets that can never be placed (oversized parties).
function MatchFormer.Form(tickets: { Ticket }, spec: Spec, now: number): ({ Match }, { string })
	local pool = table.clone(tickets)
	table.sort(pool, function(a, b)
		if a.CreatedAt ~= b.CreatedAt then
			return a.CreatedAt < b.CreatedAt
		end
		return a.Id < b.Id
	end)
	local rejected = {}
	local remaining = {}
	for _, ticket in pool do
		if #ticket.Members == 0 or #ticket.Members > spec.TeamSize then
			table.insert(rejected, ticket.Id)
		else
			table.insert(remaining, ticket)
		end
	end
	local matches = {}
	while #remaining > 0 do
		local match, used = attempt(remaining, spec, now)
		if match == nil then
			break
		end
		table.insert(matches, match)
		local nextPool = {}
		for _, ticket in remaining do
			if not used[ticket.Id] then
				table.insert(nextPool, ticket)
			end
		end
		remaining = nextPool
	end
	return matches, rejected
end

return MatchFormer
