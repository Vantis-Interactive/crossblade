--!strict
--[[
	Cross-server matchmaking, parties, private matches, reconnection and the server browser
	(spec §19). PROPOSED values (D-041..D-046) unless marked SPEC.

	Queue: each destination either uses Direct join (public servers, filled by Roblox) or a Queue
	that forms reserved matches. Team sizes are per destination; parties are never split.
]]

export type QueueSpec = {
	TeamSize: number,
	-- If set: once the oldest ticket has waited RelaxAfterSeconds, start with at least this many players.
	RelaxedMinPlayers: number?,
	RelaxAfterSeconds: number?,
	MaxPartySize: number,
}

local Matchmaking = {
	MaxPartySize = 8, -- SPEC: friend parties of up to eight players
	InviteSeconds = 60,

	-- Destination -> "Direct" (public servers) or a queue spec (reserved servers).
	Queues = {
		TeamDeathmatch = { TeamSize = 5, RelaxedMinPlayers = 4, RelaxAfterSeconds = 45, MaxPartySize = 5 },
		CasualDuel1v1 = { TeamSize = 1, MaxPartySize = 1 },
		CasualDuelTeam = { TeamSize = 2, MaxPartySize = 2 },
	} :: { [string]: QueueSpec },

	Ticket = {
		TimeToLiveSeconds = 120, -- refreshed by the owning hub while queued; expires if abandoned
		HeartbeatSeconds = 30,
		MaxTeleportRetries = 2, -- failed teleports put the ticket back in the queue this many times
	},
	Leader = {
		LeaseSeconds = 15, -- one hub server forms matches per destination at a time
		TickSeconds = 3,
		MaxTicketsPerTick = 100,
	},
	Assignment = {
		TimeToLiveSeconds = 120,
		PollSeconds = 2,
	},
	Reserved = {
		-- Rostered players have this long to arrive before the match starts with whoever is present.
		ArrivalTimeoutSeconds = 45,
		-- A disconnected player may reconnect within this window (team and score preserved).
		ReconnectSeconds = 90,
		-- After a reserved match ends, players return to the hub after this delay.
		ReturnToHubSeconds = 15,
		MatchRecordSeconds = 3 * 60 * 60,
	},
	Private = {
		-- Private matches may use these base modes and limits; they never award progression (SPEC §5).
		Modes = { "FreeForAll", "TeamDeathmatch" },
		DurationMinutes = { Min = 3, Max = 30, Default = 10 },
		ScoreLimit = { Min = 5, Max = 200, Default = 50 },
	},
	Browser = {
		HeartbeatSeconds = 15,
		TimeToLiveSeconds = 45,
		MaxListed = 25,
	},
	StoreNames = {
		Tickets = "CB_MM_Tickets_",
		UserIndex = "CB_MM_Users",
		Assignments = "CB_MM_Assign",
		Leases = "CB_MM_Leases",
		Matches = "CB_MM_Matches",
		Active = "CB_MM_Active",
		Servers = "CB_MM_Servers_",
	},
}

return table.freeze(Matchmaking)
