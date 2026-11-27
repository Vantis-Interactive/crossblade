--!strict
--[[
	Cross-server matchmaking queue (spec §19) over a sorted-map adapter (MemoryStoreSortedMap
	semantics: UpdateAsync with a transform that may cancel by returning nil; values expire).

	Guarantees:
	  - Duplicate prevention: a per-user index entry points at the user's live ticket; a player cannot
	    hold two live tickets across all servers.
	  - Expiration: tickets and index entries expire unless the owning hub heartbeats them, so a
	    crashed hub never leaves players queued forever (abandoned queue cleanup).
	  - Cancellation removes the ticket and its index entries.
	  - Requeue keeps the original CreatedAt, so a failed teleport goes back to the front of the line.
]]

export type SortedMap = {
	GetAsync: (self: any, key: string) -> any,
	SetAsync: (self: any, key: string, value: any, expiration: number, sortKey: number?) -> boolean,
	UpdateAsync: (
		self: any,
		key: string,
		transform: (old: any, sortKey: any) -> (any, any),
		expiration: number
	) -> any,
	RemoveAsync: (self: any, key: string) -> (),
	GetRangeAsync: (
		self: any,
		direction: "Ascending" | "Descending",
		count: number
	) -> { { key: string, value: any, sortKey: any } },
}

export type Stores = { Tickets: SortedMap, Users: SortedMap, Assignments: SortedMap }

export type Ticket = {
	Id: string,
	Destination: string,
	Members: { number },
	CreatedAt: number,
	HubJobId: string,
	Retries: number,
	ClaimedBy: string?, -- set atomically by a leader that is forming a match with this ticket
	ClaimedAt: number?,
}

local Queue = {}

-- A claim older than this is treated as abandoned (the claiming leader crashed mid-tick).
Queue.ClaimSeconds = 30

local function userKey(userId: number): string
	return `u{userId}`
end

function Queue.Enqueue(stores: Stores, ticket: Ticket, now: number, ttl: number): (boolean, string?)
	local claimed = {}
	for _, userId in ticket.Members do
		local conflict = false
		stores.Users:UpdateAsync(userKey(userId), function(old)
			conflict = false
			if type(old) == "table" and old.TicketId ~= ticket.Id and (old.ExpiresAt or 0) > now then
				conflict = true
				return nil
			end
			return { TicketId = ticket.Id, Destination = ticket.Destination, ExpiresAt = now + ttl }, nil
		end, ttl)
		if conflict then
			for _, claimedId in claimed do
				stores.Users:RemoveAsync(userKey(claimedId))
			end
			return false, "AlreadyQueued"
		end
		table.insert(claimed, userId)
	end
	stores.Tickets:SetAsync(ticket.Id, ticket, ttl, ticket.CreatedAt)
	return true, nil
end

function Queue.Cancel(stores: Stores, ticket: Ticket)
	stores.Tickets:RemoveAsync(ticket.Id)
	for _, userId in ticket.Members do
		stores.Users:RemoveAsync(userKey(userId))
	end
end

-- Refreshes expirations. Returns false if the ticket is gone (claimed into a match, or expired).
function Queue.Heartbeat(stores: Stores, ticket: Ticket, now: number, ttl: number): boolean
	local alive = false
	stores.Tickets:UpdateAsync(ticket.Id, function(old)
		alive = old ~= nil
		if old == nil then
			return nil
		end
		return old, ticket.CreatedAt
	end, ttl)
	if alive then
		for _, userId in ticket.Members do
			stores.Users:UpdateAsync(userKey(userId), function(old)
				if type(old) == "table" and old.TicketId == ticket.Id then
					old.ExpiresAt = now + ttl
					return old, nil
				end
				return nil
			end, ttl)
		end
	end
	return alive
end

-- Oldest first. Tickets currently claimed by a live leader are skipped unless includeClaimed.
function Queue.Read(stores: Stores, count: number, now: number?, includeClaimed: boolean?): { Ticket }
	local list = {}
	for _, item in stores.Tickets:GetRangeAsync("Ascending", count) do
		local ticket = item.value
		if type(ticket) == "table" then
			local claimed = ticket.ClaimedBy ~= nil
				and now ~= nil
				and now - (ticket.ClaimedAt or 0) < Queue.ClaimSeconds
			if includeClaimed or not claimed then
				table.insert(list, ticket)
			end
		end
	end
	return list
end

--[[
	Atomically claims a ticket for a match being formed by `token`. Fails if the ticket is gone or is
	held by another live claim. UpdateAsync is atomic per key, so two leaders (e.g. during a lease
	overlap caused by clock skew) can never both claim the same ticket.
]]
function Queue.Claim(stores: Stores, ticketId: string, token: string, now: number, ttl: number): boolean
	local claimed = false
	stores.Tickets:UpdateAsync(ticketId, function(old, sortKey)
		claimed = false
		if type(old) ~= "table" then
			return nil
		end
		if old.ClaimedBy and old.ClaimedBy ~= token and now - (old.ClaimedAt or 0) < Queue.ClaimSeconds then
			return nil
		end
		old.ClaimedBy = token
		old.ClaimedAt = now
		claimed = true
		return old, sortKey
	end, ttl)
	return claimed
end

function Queue.Release(stores: Stores, ticketId: string, token: string, ttl: number)
	stores.Tickets:UpdateAsync(ticketId, function(old, sortKey)
		if type(old) ~= "table" or old.ClaimedBy ~= token then
			return nil
		end
		old.ClaimedBy = nil
		old.ClaimedAt = nil
		return old, sortKey
	end, ttl)
end

function Queue.Assign(stores: Stores, ticketId: string, assignment: { [string]: any }, ttl: number)
	stores.Assignments:SetAsync(ticketId, assignment, ttl)
	stores.Tickets:RemoveAsync(ticketId)
end

function Queue.Assignment(stores: Stores, ticketId: string): { [string]: any }?
	local value = stores.Assignments:GetAsync(ticketId)
	return if type(value) == "table" then value else nil
end

-- A teleport failed: back to the front of the queue (same CreatedAt), or cancelled after max retries.
function Queue.Requeue(stores: Stores, ticket: Ticket, now: number, ttl: number, maxRetries: number): boolean
	stores.Assignments:RemoveAsync(ticket.Id)
	if ticket.Retries >= maxRetries then
		Queue.Cancel(stores, ticket)
		return false
	end
	ticket.Retries += 1
	stores.Tickets:SetAsync(ticket.Id, ticket, ttl, ticket.CreatedAt)
	Queue.Heartbeat(stores, ticket, now, ttl)
	return true
end

-- Lease-based leader election: only the lease holder forms matches for a destination.
function Queue.AcquireLease(
	leases: SortedMap,
	name: string,
	holder: string,
	now: number,
	seconds: number
): boolean
	local acquired = false
	leases:UpdateAsync(name, function(old)
		acquired = false
		if type(old) == "table" and old.Holder ~= holder and (old.ExpiresAt or 0) > now then
			return nil
		end
		acquired = true
		return { Holder = holder, ExpiresAt = now + seconds }, nil
	end, seconds)
	return acquired
end

return Queue
