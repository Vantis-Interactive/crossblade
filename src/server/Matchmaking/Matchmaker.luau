--!strict
--[[
	One leader tick for one queued destination (spec §19): read tickets, form matches
	(Domain/MatchFormer), reserve a server per match, write the match record (looked up by the
	reserved server via its PrivateServerId) and an assignment per ticket, and drop tickets that can
	never be placed. Pure over injected adapters, so it is unit-testable.
]]

local Queue = require(script.Parent.Queue)
local MatchFormer = require(script.Parent.Parent.Domain.MatchFormer)

export type Deps = {
	Stores: Queue.Stores,
	Matches: Queue.SortedMap,
	Reserve: () -> (string, string), -- returns (accessCode, privateServerId); may error
	PlaceId: number,
	Destination: string,
	Mode: string,
	Spec: MatchFormer.Spec,
	Now: number,
	MaxTickets: number,
	AssignmentSeconds: number,
	MatchRecordSeconds: number,
	Token: string, -- unique per leader tick (e.g. JobId + time)
	TicketSeconds: number,
}

export type Result = { Formed: number, Rejected: { string }, Failed: number }

local Matchmaker = {}

function Matchmaker.Tick(deps: Deps): Result
	local tickets = Queue.Read(deps.Stores, deps.MaxTickets, deps.Now)
	local byId = {}
	for _, ticket in tickets do
		byId[ticket.Id] = ticket
	end
	local matches, rejected = MatchFormer.Form(tickets :: any, deps.Spec, deps.Now)
	for _, ticketId in rejected do
		local ticket = byId[ticketId]
		if ticket then
			Queue.Cancel(deps.Stores, ticket)
			deps.Stores.Assignments:SetAsync(
				ticketId,
				{ Rejected = true, Reason = "PartyTooLarge" },
				deps.AssignmentSeconds
			)
		end
	end
	local formed, failed = 0, 0
	for index, match in matches do
		-- Claim every ticket first; if another leader holds any of them, release ours and skip.
		local claimedIds = {}
		local allClaimed = true
		for _, ticketId in match.TicketIds do
			if Queue.Claim(deps.Stores, ticketId, `{deps.Token}:{index}`, deps.Now, deps.TicketSeconds) then
				table.insert(claimedIds, ticketId)
			else
				allClaimed = false
				break
			end
		end
		local ok, accessCode, privateServerId = false, nil, nil
		if allClaimed then
			ok, accessCode, privateServerId = pcall(deps.Reserve)
		end
		if not ok then
			for _, ticketId in claimedIds do
				Queue.Release(deps.Stores, ticketId, `{deps.Token}:{index}`, deps.TicketSeconds)
			end
			failed += 1 -- tickets stay queued; the next tick retries
		else
			local record = {
				Destination = deps.Destination,
				Mode = deps.Mode,
				Teams = match.Teams,
				Private = false,
				AccessCode = accessCode,
				PlaceId = deps.PlaceId,
				CreatedAt = deps.Now,
			}
			deps.Matches:SetAsync(privateServerId, record, deps.MatchRecordSeconds)
			for _, ticketId in match.TicketIds do
				Queue.Assign(deps.Stores, ticketId, {
					PlaceId = deps.PlaceId,
					AccessCode = accessCode,
					PrivateServerId = privateServerId,
				}, deps.AssignmentSeconds)
			end
			formed += 1
		end
	end
	return { Formed = formed, Rejected = rejected, Failed = failed }
end

return Matchmaker
