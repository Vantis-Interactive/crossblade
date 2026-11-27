--!strict
--[[
	Network contracts: the single source of truth for every remote in the experience.
	See docs/NETWORK_CONTRACTS.md for the narrative description of each message.

	ClientToServer entries are validated (schema + per-player token-bucket rate limit) by the server
	Net layer BEFORE any service handler runs. Every client->server remote carries exactly one payload.
	ServerToClient entries are documented for completeness; the server is trusted to send valid data.
]]

local Schema = require(script.Parent.Schema)
local InputConfig = require(script.Parent.Parent.Config.Input)

local ACTIONS = {}
for action in InputConfig do
	table.insert(ACTIONS, action)
end
table.sort(ACTIONS)

export type RemoteKind = "Event" | "UnreliableEvent" | "Function"

export type ClientContract = {
	Kind: RemoteKind,
	Payload: Schema.Schema,
	-- Token bucket: burst capacity and sustained requests/second per player.
	RateCapacity: number,
	RatePerSecond: number,
}

export type ServerContract = {
	Kind: RemoteKind,
}

local MAX_WORLD = 20000 -- generous world-space bound for positions
local SLOT = Schema.Enum({ "Primary", "Secondary", "Knife" })
local FIREARM_SLOT = Schema.Enum({ "Primary", "Secondary" })
local USER_ID = Schema.Integer(-1e12, 1e12) -- negative ids exist for Studio test players
local TIME = Schema.Number(0, 1e10)

-- Exactly one of TargetUserId / DummyId must be present (enforced by CombatService).
local HitReport = Schema.Struct({
	TargetUserId = Schema.Optional(USER_ID),
	DummyId = Schema.Optional(Schema.Integer(1, 100000)),
	Position = Schema.Vector3(MAX_WORLD),
	Zone = Schema.Enum({ "Head", "Body" }),
	Pellet = Schema.Integer(1, 16),
})

local ClientToServer: { [string]: ClientContract } = {
	FireWeapon = {
		Kind = "Event",
		Payload = Schema.Struct({
			Slot = FIREARM_SLOT,
			ShotId = Schema.Integer(0, 2 ^ 31),
			ClientTime = TIME,
			Origin = Schema.Vector3(MAX_WORLD),
			Direction = Schema.Vector3(1.01),
			Hits = Schema.Array(HitReport, 16),
		}),
		RateCapacity = 20,
		RatePerSecond = 16,
	},
	MeleeAttack = {
		Kind = "Event",
		Payload = Schema.Struct({
			Attack = Schema.Enum({ "Slash", "Stab" }),
			ClientTime = TIME,
			Origin = Schema.Vector3(MAX_WORLD),
			Direction = Schema.Vector3(1.01),
			TargetUserId = Schema.Optional(USER_ID),
			TargetDummyId = Schema.Optional(Schema.Integer(1, 100000)),
		}),
		RateCapacity = 6,
		RatePerSecond = 5,
	},
	ThrowKnife = {
		Kind = "Event",
		Payload = Schema.Struct({
			ClientTime = TIME,
			Origin = Schema.Vector3(MAX_WORLD),
			Direction = Schema.Vector3(1.01),
		}),
		RateCapacity = 3,
		RatePerSecond = 1,
	},
	Reload = {
		Kind = "Event",
		Payload = Schema.Struct({ Slot = FIREARM_SLOT }),
		RateCapacity = 4,
		RatePerSecond = 2,
	},
	EquipSlot = {
		Kind = "Event",
		Payload = Schema.Struct({ Slot = SLOT }),
		RateCapacity = 8,
		RatePerSecond = 6,
	},
	AimUpdate = {
		Kind = "UnreliableEvent",
		Payload = Schema.Struct({
			Pitch = Schema.Number(-1.6, 1.6),
			Aiming = Schema.Boolean(),
		}),
		RateCapacity = 15,
		RatePerSecond = 12,
	},
	SaveSettings = {
		Kind = "Event",
		Payload = Schema.Struct({
			FieldOfView = Schema.Number(1, 179),
			Sensitivity = Schema.Number(0, 100),
			AimSensitivity = Schema.Number(0, 100),
			Perspective = Schema.Enum({ "FirstPerson", "ThirdPerson" }),
			CrosshairStyle = Schema.Enum({ "Cross", "Dot", "Circle" }),
			CrosshairColor = Schema.Enum({ "White", "Green", "Yellow", "Cyan", "Magenta" }),
			CrosshairSize = Schema.Integer(4, 40),
			ReducedMotion = Schema.Boolean(),
			DamageNumbers = Schema.Boolean(),
			Bindings = Schema.Optional(Schema.Array(
				Schema.Struct({
					Action = Schema.Enum(ACTIONS),
					Keyboard = Schema.Optional(Schema.String(32)),
					Gamepad = Schema.Optional(Schema.String(32)),
				}),
				32
			)),
		}),
		RateCapacity = 3,
		RatePerSecond = 0.5,
	},
	SetLoadout = {
		Kind = "Event",
		Payload = Schema.Struct({
			Primary = Schema.String(64),
			Secondary = Schema.String(64),
			Knife = Schema.String(64),
		}),
		RateCapacity = 4,
		RatePerSecond = 1,
	},
	OpenCrate = {
		Kind = "Function",
		Payload = Schema.Struct({
			CrateId = Schema.String(32),
			-- Client-generated idempotency key (GUID). Retries reuse it; replays return the original result.
			RequestId = Schema.String(64),
			-- Spend a free crate token (e.g. the tutorial reward) instead of coins.
			UseToken = Schema.Optional(Schema.Boolean()),
		}),
		RateCapacity = 3,
		RatePerSecond = 1,
	},
	GetEconomy = {
		Kind = "Function",
		Payload = Schema.Struct({}),
		RateCapacity = 4,
		RatePerSecond = 1,
	},
	VoteMap = {
		Kind = "Event",
		Payload = Schema.Struct({ MapId = Schema.String(64) }),
		RateCapacity = 4,
		RatePerSecond = 1,
	},
	RequestTeleport = {
		Kind = "Event",
		Payload = Schema.Struct({
			Destination = Schema.Enum({
				"Hub",
				"FreeForAll",
				"TeamDeathmatch",
				"CasualDuel1v1",
				"CasualDuelTeam",
			}),
		}),
		RateCapacity = 2,
		RatePerSecond = 0.2,
	},
	TutorialAction = {
		Kind = "Event",
		Payload = Schema.Struct({
			Action = Schema.Enum({ "Start", "Complete", "Exit" }),
			Step = Schema.Optional(Schema.Integer(1, 64)),
		}),
		RateCapacity = 6,
		RatePerSecond = 2,
	},
	JoinQueue = {
		Kind = "Event",
		Payload = Schema.Struct({
			Destination = Schema.Enum({ "TeamDeathmatch", "CasualDuel1v1", "CasualDuelTeam" }),
		}),
		RateCapacity = 2,
		RatePerSecond = 0.5,
	},
	LeaveQueue = {
		Kind = "Event",
		Payload = Schema.Struct({}),
		RateCapacity = 3,
		RatePerSecond = 1,
	},
	PartyAction = {
		Kind = "Event",
		Payload = Schema.Struct({
			Action = Schema.Enum({ "Invite", "Accept", "Decline", "Leave", "Kick", "Promote" }),
			TargetUserId = Schema.Optional(USER_ID),
			PartyId = Schema.Optional(Schema.Integer(1, 1e9)),
		}),
		RateCapacity = 6,
		RatePerSecond = 2,
	},
	RequestReconnect = {
		Kind = "Event",
		Payload = Schema.Struct({}),
		RateCapacity = 2,
		RatePerSecond = 0.2,
	},
	GetServers = {
		Kind = "Function",
		Payload = Schema.Struct({ Destination = Schema.Enum({ "FreeForAll", "TeamDeathmatch" }) }),
		RateCapacity = 3,
		RatePerSecond = 0.5,
	},
	JoinServer = {
		Kind = "Event",
		Payload = Schema.Struct({
			Destination = Schema.Enum({ "FreeForAll", "TeamDeathmatch" }),
			JobId = Schema.String(64),
		}),
		RateCapacity = 2,
		RatePerSecond = 0.2,
	},
	GetPrivateOptions = {
		Kind = "Function",
		Payload = Schema.Struct({}),
		RateCapacity = 3,
		RatePerSecond = 0.5,
	},
	HostPrivate = {
		Kind = "Event",
		Payload = Schema.Struct({
			Mode = Schema.Enum({ "FreeForAll", "TeamDeathmatch" }),
			MapId = Schema.String(64),
			DurationMinutes = Schema.Integer(1, 60),
			ScoreLimit = Schema.Integer(1, 500),
		}),
		RateCapacity = 2,
		RatePerSecond = 0.1,
	},
	GetSnapshot = {
		Kind = "Function",
		Payload = Schema.Struct({}),
		RateCapacity = 3,
		RatePerSecond = 0.5,
	},
}

local ServerToClient: { [string]: ServerContract } = {
	LoadoutState = { Kind = "Event" }, -- full weapon/ammo/knife state for the local player
	HitConfirmed = { Kind = "Event" }, -- hit marker feedback for the shooter
	DamageTaken = { Kind = "Event" }, -- directional damage indicator for the victim
	ShotFired = { Kind = "UnreliableEvent" }, -- cosmetic tracers for everyone else
	MeleeSwing = { Kind = "UnreliableEvent" }, -- cosmetic swing for everyone else
	KillFeed = { Kind = "Event" },
	Eliminated = { Kind = "Event" }, -- sent to the victim: killer, weapon, killer HP and level
	MatchState = { Kind = "Event" },
	Scoreboard = { Kind = "Event" },
	Announcement = { Kind = "Event" },
	Notification = { Kind = "Event" },
	SettingsApplied = { Kind = "Event" },
	EconomyState = { Kind = "Event" }, -- wallet, level/XP, owned weapons, loadout, active crates
	Reward = { Kind = "Event" }, -- coins/XP granted with reasons and level-ups
	MapVote = { Kind = "Event" }, -- options, tallies and deadline during intermission
	TutorialState = { Kind = "Event" }, -- current step, completion, reward status
	TeleportStatus = { Kind = "Event" }, -- teleport started / failed (with reason)
	QueueStatus = { Kind = "Event" }, -- matchmaking ticket state for each party member
	PartyState = { Kind = "Event" }, -- party members, leader and pending invites
	ReconnectOffer = { Kind = "Event" }, -- an unfinished reserved match the player can rejoin
}

return table.freeze({
	FolderName = "CrossbladeRemotes",
	ClientToServer = table.freeze(ClientToServer),
	ServerToClient = table.freeze(ServerToClient),
})
