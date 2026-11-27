--!nocheck
local Config = Runtime:Get("ReplicatedStorage/Shared/Config")
local MatchFormer = Runtime:Get("ServerScriptService/Server/Domain/MatchFormer")
local PartyState = Runtime:Get("ServerScriptService/Server/Domain/PartyState")
local ReservedRoster = Runtime:Get("ServerScriptService/Server/Domain/ReservedRoster")
local Queue = Runtime:Get("ServerScriptService/Server/Matchmaking/Queue")
local Matchmaker = Runtime:Get("ServerScriptService/Server/Matchmaking/Matchmaker")
local Bindings = Runtime:Get("ReplicatedStorage/Shared/Bindings")
local Settings = Runtime:Get("ReplicatedStorage/Shared/Settings")

local function ticket(id, members, createdAt)
	return {
		Id = id,
		Destination = "CasualDuelTeam",
		Members = members,
		CreatedAt = createdAt or 0,
		HubJobId = "hub",
		Retries = 0,
	}
end

describe("MatchFormer", function()
	local duel = { TeamSize = 1 }
	local team = { TeamSize = 2 }

	it("pairs solo duel tickets oldest first", function()
		local matches = MatchFormer.Form(
			{ ticket("c", { 3 }, 3), ticket("a", { 1 }, 1), ticket("b", { 2 }, 2) },
			duel,
			10
		)
		expect(#matches).toBe(1)
		expect(matches[1].TicketIds).toEqual({ "a", "b" })
	end)

	it("never splits a party and keeps parties on one team", function()
		local matches = MatchFormer.Form(
			{ ticket("p1", { 1, 2 }, 1), ticket("s1", { 3 }, 2), ticket("s2", { 4 }, 3) },
			team,
			10
		)
		expect(#matches).toBe(1)
		local m = matches[1]
		local a, b = m.Teams.A, m.Teams.B
		local partyTogether = (table.find(a, 1) and table.find(a, 2))
			or (table.find(b, 1) and table.find(b, 2))
		expect(partyTogether ~= nil).toBe(true)
		expect(#a).toBe(2)
		expect(#b).toBe(2)
	end)

	it("waits for a full match unless the relaxed rule applies", function()
		local tdm = Config.Matchmaking.Queues.TeamDeathmatch
		local tickets = { ticket("a", { 1, 2 }, 0), ticket("b", { 3, 4 }, 5) }
		expect(#MatchFormer.Form(tickets, tdm, 10)).toBe(0)
		local relaxed = MatchFormer.Form(tickets, tdm, tdm.RelaxAfterSeconds + 1)
		expect(#relaxed).toBe(1)
		expect(#relaxed[1].Teams.A).toBe(2)
		expect(#relaxed[1].Teams.B).toBe(2)
	end)

	it("rejects parties larger than a team", function()
		local matches, rejected = MatchFormer.Form({ ticket("big", { 1, 2, 3 }, 0) }, team, 10)
		expect(#matches).toBe(0)
		expect(rejected).toEqual({ "big" })
	end)

	it("forms several matches in one pass and leaves the remainder queued", function()
		local tickets = {}
		for i = 1, 5 do
			table.insert(tickets, ticket(`t{i}`, { i }, i))
		end
		local matches = MatchFormer.Form(tickets, duel, 10)
		expect(#matches).toBe(2)
	end)
end)

describe("PartyState", function()
	it("supports invite, accept, and a maximum of eight members", function()
		local state = PartyState.new(Config.Matchmaking.MaxPartySize)
		for user = 2, 8 do
			expect((PartyState.Invite(state, 1, user, 0, 60))).toBe(true)
			local party = PartyState.PartyOf(state, 1)
			expect((PartyState.Accept(state, user, party.Id, 1))).toBe(true)
		end
		expect(#PartyState.Group(state, 1)).toBe(8)
		local ok, reason = PartyState.Invite(state, 1, 9, 0, 60)
		expect(ok).toBe(false)
		expect(reason).toBe("Full")
	end)

	it("requires a valid, unexpired invite", function()
		local state = PartyState.new(8)
		PartyState.Invite(state, 1, 2, 0, 60)
		local party = PartyState.PartyOf(state, 1)
		expect(select(2, PartyState.Accept(state, 3, party.Id, 1))).toBe("NoInvite")
		expect(select(2, PartyState.Accept(state, 2, party.Id, 61))).toBe("NoInvite")
	end)

	it("only the leader invites, kicks and promotes; leader leaving promotes the next member", function()
		local state = PartyState.new(8)
		PartyState.Invite(state, 1, 2, 0, 60)
		local party = PartyState.PartyOf(state, 1)
		PartyState.Accept(state, 2, party.Id, 1)
		PartyState.Invite(state, 1, 3, 0, 60)
		PartyState.Accept(state, 3, party.Id, 1)
		expect(select(2, PartyState.Invite(state, 2, 4, 0, 60))).toBe("NotLeader")
		expect(select(2, PartyState.Kick(state, 2, 3))).toBe("NotLeader")
		PartyState.Leave(state, 1)
		expect(PartyState.PartyOf(state, 2).Leader).toBe(2)
		expect((PartyState.Kick(state, 2, 3))).toBe(true)
		expect(PartyState.PartyOf(state, 2)).toBeNil() -- disbanded when one member is left
		expect(PartyState.IsLeaderOrSolo(state, 2)).toBe(true)
	end)
end)

describe("ReservedRoster", function()
	local roster = { Teams = { A = { 1, 2 }, B = { 3, 4 } } }

	it("admits only rostered players", function()
		local state = ReservedRoster.new(roster, 0, 45)
		expect((ReservedRoster.Admit(state, 1, 1))).toBe(true)
		expect(select(2, ReservedRoster.Admit(state, 99, 1))).toBe("NotRostered")
	end)

	it("starts when everyone arrives, or at the deadline if both teams are present", function()
		local state = ReservedRoster.new(roster, 0, 45)
		for _, id in { 1, 2, 3, 4 } do
			ReservedRoster.Admit(state, id, 1)
		end
		expect(ReservedRoster.Decide(state, 2, true)).toBe("Start")
		local partial = ReservedRoster.new(roster, 0, 45)
		ReservedRoster.Admit(partial, 1, 1)
		ReservedRoster.Admit(partial, 3, 1)
		expect(ReservedRoster.Decide(partial, 10, true)).toBe("Wait")
		expect(ReservedRoster.Decide(partial, 46, true)).toBe("Start")
	end)

	it("cancels when a team never arrives", function()
		local state = ReservedRoster.new(roster, 0, 45)
		ReservedRoster.Admit(state, 1, 1)
		ReservedRoster.Admit(state, 2, 1)
		expect(ReservedRoster.Decide(state, 46, true)).toBe("Cancel")
	end)

	it("lets a disconnected player reconnect inside the window only", function()
		local state = ReservedRoster.new(roster, 0, 45)
		ReservedRoster.Admit(state, 1, 1)
		ReservedRoster.Disconnect(state, 1, 10, 90)
		expect((ReservedRoster.Admit(state, 1, 50))).toBe(true)
		ReservedRoster.Disconnect(state, 1, 60, 90)
		expect(ReservedRoster.Expired(state, 100)).toEqual({})
		expect(ReservedRoster.Expired(state, 151)).toEqual({ 1 })
		expect(select(2, ReservedRoster.Admit(state, 1, 152))).toBe(nil)
	end)
end)

describe("Matchmaking queue (MemoryStore semantics)", function()
	local clock = 0
	local function now()
		return clock
	end
	local function stores()
		return {
			Tickets = MemorySortedMap.new(now),
			Users = MemorySortedMap.new(now),
			Assignments = MemorySortedMap.new(now),
		}
	end
	beforeEach(function()
		clock = 1000
	end)

	it("prevents a player from holding two tickets across servers", function()
		local s = stores()
		expect((Queue.Enqueue(s, ticket("t1", { 1, 2 }, clock), clock, 120))).toBe(true)
		local ok, reason = Queue.Enqueue(s, ticket("t2", { 2, 3 }, clock), clock, 120)
		expect(ok).toBe(false)
		expect(reason).toBe("AlreadyQueued")
		-- The rollback released player 3, who can queue alone.
		expect((Queue.Enqueue(s, ticket("t3", { 3 }, clock), clock, 120))).toBe(true)
		expect(#Queue.Read(s, 10)).toBe(2)
	end)

	it("abandoned tickets expire unless heartbeated", function()
		local s = stores()
		local t = ticket("t1", { 1 }, clock)
		Queue.Enqueue(s, t, clock, 120)
		clock += 100
		expect(Queue.Heartbeat(s, t, clock, 120)).toBe(true)
		clock += 100 -- 200s after enqueue, 100s after heartbeat: still alive
		expect(#Queue.Read(s, 10)).toBe(1)
		clock += 121
		expect(#Queue.Read(s, 10)).toBe(0)
		expect((Queue.Enqueue(s, ticket("t2", { 1 }, clock), clock, 120))).toBe(true) -- index expired too
	end)

	it("cancel removes the ticket and frees the players", function()
		local s = stores()
		local t = ticket("t1", { 1, 2 }, clock)
		Queue.Enqueue(s, t, clock, 120)
		Queue.Cancel(s, t)
		expect(#Queue.Read(s, 10)).toBe(0)
		expect((Queue.Enqueue(s, ticket("t2", { 1, 2 }, clock), clock, 120))).toBe(true)
	end)

	it("requeue after a failed teleport keeps the place in line, then gives up", function()
		local s = stores()
		local old = ticket("old", { 1 }, 1)
		Queue.Enqueue(s, old, clock, 120)
		Queue.Enqueue(s, ticket("new", { 2 }, 5), clock, 120)
		Queue.Assign(s, "old", { AccessCode = "x" }, 120)
		expect(#Queue.Read(s, 10)).toBe(1)
		expect(Queue.Requeue(s, old, clock, 120, 2)).toBe(true)
		expect(Queue.Read(s, 10)[1].Id).toBe("old")
		expect(Queue.Assignment(s, "old")).toBeNil()
		Queue.Requeue(s, old, clock, 120, 2)
		expect(Queue.Requeue(s, old, clock, 120, 2)).toBe(false) -- third failure cancels
		expect(#Queue.Read(s, 10)).toBe(1)
	end)

	it("only one server holds the leader lease until it expires", function()
		local leases = MemorySortedMap.new(now)
		expect(Queue.AcquireLease(leases, "lead:duel", "A", clock, 15)).toBe(true)
		expect(Queue.AcquireLease(leases, "lead:duel", "B", clock + 5, 15)).toBe(false)
		expect(Queue.AcquireLease(leases, "lead:duel", "A", clock + 5, 15)).toBe(true) -- renew
		clock += 30
		expect(Queue.AcquireLease(leases, "lead:duel", "B", clock, 15)).toBe(true)
	end)

	it("a leader tick reserves a server, records the match and assigns every ticket", function()
		local s = stores()
		local matchesStore = MemorySortedMap.new(now)
		for i = 1, 4 do
			Queue.Enqueue(s, ticket(`t{i}`, { i }, i), clock, 120)
		end
		local reserved = 0
		local result = Matchmaker.Tick({
			Stores = s,
			Matches = matchesStore,
			Reserve = function()
				reserved += 1
				return `code{reserved}`, `psid{reserved}`
			end,
			PlaceId = 42,
			Destination = "CasualDuel1v1",
			Mode = "CasualDuel1v1",
			Spec = Config.Matchmaking.Queues.CasualDuel1v1,
			Now = clock,
			MaxTickets = 100,
			AssignmentSeconds = 120,
			MatchRecordSeconds = 3600,
			Token = "leaderA",
			TicketSeconds = 120,
		})
		expect(result.Formed).toBe(2)
		expect(#Queue.Read(s, 10)).toBe(0)
		local assignment = Queue.Assignment(s, "t1")
		expect(assignment.AccessCode).toBe("code1")
		local record = matchesStore:GetAsync(assignment.PrivateServerId)
		expect(record.Mode).toBe("CasualDuel1v1")
		expect(#record.Teams.A + #record.Teams.B).toBe(2)
	end)

	it("two leaders can never claim the same ticket", function()
		local s = stores()
		Queue.Enqueue(s, ticket("t1", { 1 }, 1), clock, 120)
		expect(Queue.Claim(s, "t1", "A", clock, 120)).toBe(true)
		expect(Queue.Claim(s, "t1", "B", clock + 1, 120)).toBe(false)
		expect(#Queue.Read(s, 10, clock + 1)).toBe(0) -- claimed tickets are not offered to formers
		Queue.Release(s, "t1", "A", 120)
		expect(Queue.Claim(s, "t1", "B", clock + 2, 120)).toBe(true)
		-- A claim abandoned by a crashed leader expires.
		expect(Queue.Claim(s, "t1", "C", clock + 2 + Queue.ClaimSeconds, 120)).toBe(true)
	end)

	it("a leader skips a match whose tickets another leader already claimed", function()
		local s = stores()
		for i = 1, 2 do
			Queue.Enqueue(s, ticket(`t{i}`, { i }, i), clock, 120)
		end
		-- A competing leader has claimed t2 but has not finished.
		Queue.Claim(s, "t2", "other", clock, 120)
		local reserved = 0
		local deps = {
			Stores = s,
			Matches = MemorySortedMap.new(now),
			Reserve = function()
				reserved += 1
				return "code", "psid"
			end,
			PlaceId = 42,
			Destination = "CasualDuel1v1",
			Mode = "CasualDuel1v1",
			Spec = Config.Matchmaking.Queues.CasualDuel1v1,
			Now = clock,
			MaxTickets = 100,
			AssignmentSeconds = 120,
			MatchRecordSeconds = 3600,
			Token = "me",
			TicketSeconds = 120,
		}
		expect(Matchmaker.Tick(deps).Formed).toBe(0) -- only t1 is visible: no match, nothing reserved
		expect(reserved).toBe(0)
		expect(Queue.Assignment(s, "t1")).toBeNil()
	end)

	it("keeps tickets queued when reserving a server fails", function()
		local s = stores()
		Queue.Enqueue(s, ticket("t1", { 1 }, 1), clock, 120)
		Queue.Enqueue(s, ticket("t2", { 2 }, 2), clock, 120)
		local result = Matchmaker.Tick({
			Stores = s,
			Matches = MemorySortedMap.new(now),
			Reserve = function()
				error("ReserveServer failed")
			end,
			PlaceId = 42,
			Destination = "CasualDuel1v1",
			Mode = "CasualDuel1v1",
			Spec = Config.Matchmaking.Queues.CasualDuel1v1,
			Now = clock,
			MaxTickets = 100,
			AssignmentSeconds = 120,
			MatchRecordSeconds = 3600,
			Token = "leaderA",
			TicketSeconds = 120,
		})
		expect(result.Failed).toBe(1)
		expect(#Queue.Read(s, 10)).toBe(2)
	end)
end)

describe("Bindings", function()
	it("accepts allowed overrides and exposes them as effective bindings", function()
		local bindings = Bindings.Sanitize({ Reload = { Keyboard = "T", Gamepad = "ButtonR1" } })
		expect(bindings.Reload.Keyboard).toBe("T")
		local keyboard, gamepad = Bindings.Effective(bindings, "Reload")
		expect(keyboard).toBe("T")
		expect(gamepad).toBe("ButtonR1")
	end)

	it("never allows movement, jump, menu or unknown keys", function()
		local bindings = Bindings.Sanitize({
			Reload = { Keyboard = "W" },
			Fire = { Keyboard = "Space" },
			Aim = { Keyboard = "Escape" },
			Inspect = { Gamepad = "ButtonA" },
			Bogus = { Keyboard = "T" },
		})
		expect(next(bindings)).toBeNil()
	end)

	it("rejects an override that collides with another action", function()
		local bindings = Bindings.Sanitize({ Inspect = { Keyboard = "R" } }) -- R is Reload's default
		expect(bindings.Inspect).toBeNil()
		local swapped = Bindings.Sanitize({ Reload = { Keyboard = "T" }, Inspect = { Keyboard = "R" } })
		expect(swapped.Reload.Keyboard).toBe("T")
		expect(swapped.Inspect.Keyboard).toBe("R") -- swap accepted: R is freed by Reload's override
		local clash = Bindings.Sanitize({ Reload = { Keyboard = "T" }, Inspect = { Keyboard = "T" } })
		-- Two overrides on the same key: exactly one keeps it (deterministically), never both.
		local holders = (if clash.Reload then 1 else 0) + (if clash.Inspect then 1 else 0)
		expect(holders).toBe(1)
	end)

	it("round-trips through the network form and through Settings.Sanitize", function()
		local bindings = Bindings.Sanitize({ ThrowKnife = { Keyboard = "H" } })
		local wire = Bindings.ToWire(bindings)
		expect(wire).toEqual({ { Action = "ThrowKnife", Keyboard = "H" } })
		expect(Settings.Sanitize({ Bindings = wire }).Bindings.ThrowKnife.Keyboard).toBe("H")
		expect(Settings.Defaults().Bindings).toEqual({})
	end)

	it("resolves names to engine inputs", function()
		local inputs = Bindings.ToInputs("MouseButton2", "ButtonR1")
		expect(#inputs).toBe(2)
		expect(inputs[1]).toBe(Enum.UserInputType.MouseButton2)
		expect(inputs[2]).toBe(Enum.KeyCode.ButtonR1)
	end)
end)

describe("Settings on the wire", function()
	local Schema = Runtime:Get("ReplicatedStorage/Shared/Net/Schema")
	local Contracts = Runtime:Get("ReplicatedStorage/Shared/Net/Contracts")
	local SAVE = Contracts.ClientToServer.SaveSettings.Payload

	it("the wire form (bindings as an array) passes the SaveSettings schema", function()
		local settings = Settings.Sanitize({ Bindings = { Reload = { Keyboard = "T" } } })
		local payload = table.clone(settings)
		payload.Bindings = Bindings.ToWire(settings.Bindings)
		local ok, reason = Schema.Check(SAVE, payload)
		if not ok then
			error(reason)
		end
	end)

	it("the in-memory form (bindings as a dictionary) is rejected, so clients must convert", function()
		local settings = Settings.Sanitize({ Bindings = { Reload = { Keyboard = "T" } } })
		expect((Schema.Check(SAVE, settings))).toBe(false)
	end)
end)

describe("Private match mode", function()
	local MatchContext = Runtime:Get("ServerScriptService/Server/Core/MatchContext")

	it("derives a non-progression mode from the base mode and settings", function()
		MatchContext.Record = {
			Destination = "TeamDeathmatch",
			Mode = "Private",
			BaseMode = "TeamDeathmatch",
			Private = true,
			Settings = { DurationMinutes = 7, ScoreLimit = 25, MapId = "dev_outpost_yard" },
			Teams = { A = { 1 }, B = { 2 } },
			AccessCode = "x",
			PlaceId = 1,
			CreatedAt = 0,
		}
		local mode = MatchContext.ModeConfig("TeamDeathmatch")
		expect(mode.Kind).toBe("TeamDeathmatch")
		expect(mode.AwardsProgression).toBe(false)
		expect(mode.DurationSeconds).toBe(7 * 60)
		expect(mode.ScoreLimit).toBe(25)
		expect(mode.MapVote).toBe(false)
		expect(Config.GameModes.TeamDeathmatch.AwardsProgression).toBe(true) -- base config untouched
		MatchContext.Record = nil
	end)

	it("ladder reserved matches use the recorded mode unchanged", function()
		MatchContext.Record = { Mode = "CasualDuel1v1", Private = false, Teams = { A = { 1 }, B = { 2 } } }
		expect(MatchContext.ModeConfig("CasualDuel1v1")).toBe(Config.GameModes.CasualDuel1v1)
		MatchContext.Record = nil
		expect(MatchContext.ModeConfig("FreeForAll")).toBe(Config.GameModes.FreeForAll)
	end)
end)
