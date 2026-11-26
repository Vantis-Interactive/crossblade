# Network Contracts

Single source of truth: `src/shared/Net/Contracts.luau` (D-020). The server creates every remote in `ReplicatedStorage.CrossbladeRemotes` at boot (`src/server/Core/Net.luau`, `Net.Init`). Clients use `src/client/Core/Net.luau`. An integrity test fails if any code references a remote that is not declared for that direction, or if a declared remote is unused (`tests/specs/Integrity.spec.luau`: "every remote referenced in code exists in the contracts with the right direction").

## 1. Admission pipeline (client → server)

Every client-to-server request passes, in order (`admit` in `src/server/Core/Net.luau`):

1. **Argument count:** exactly one payload argument. Otherwise it is dropped and `Violation(player, "MalformedPayload", remote, "argument count")` fires.
2. **Rate limit:** a per-player, per-remote token bucket (`Shared/Util/RateLimiter.luau`) with the remote's `RateCapacity` and `RatePerSecond`, timed by `workspace:GetServerTimeNow()`. Otherwise it is dropped and `Violation(player, "RateLimitExceeded", remote)` fires. Buckets are cleared when the player leaves.
3. **Schema:** `Schema.Check(contract.Payload, payload)`. Otherwise it is dropped and `Violation(player, "MalformedPayload", remote, reason)` fires.
4. **Handler:** runs inside `pcall`. Errors are logged (`Net` scope) and never propagate to the client. For the RemoteFunction, a failed handler returns `nil`.

`Net.Violation` is consumed by `AntiCheatService`, which converts it into suspicion signals (SECURITY.md §6).

### Schema primitives (`src/shared/Net/Schema.luau`)

| Primitive | Accepts |
|---|---|
| `Number(min, max)` | finite number in `[min, max]` |
| `Integer(min, max)` | finite integer in `[min, max]` |
| `Boolean()` | boolean |
| `String(maxLength)` / `Enum({...})` | string up to its length limit / one of the listed values |
| `Vector3(maxMagnitude)` | `Vector3` with finite components and magnitude ≤ max |
| `Optional(inner)` | `nil` or `inner` |
| `Array(inner, maxLength)` | dense 1..n array, length ≤ max, every element valid |
| `Struct(fields)` | table whose keys are exactly declared string fields; unknown keys rejected |

Shared bounds used below: `MAX_WORLD = 20000` studs; `USER_ID = Integer(−1e12, 1e12)` (negative ids exist for Studio test players); `TIME = Number(0, 1e10)`; `SLOT = Enum{Primary, Secondary, Knife}`; `FIREARM_SLOT = Enum{Primary, Secondary}`.

## 2. Client → server

| Remote | Kind | Rate (capacity / per s) | Sent by |
|---|---|---|---|
| `FireWeapon` | RemoteEvent | 20 / 16 | WeaponController, each shot |
| `MeleeAttack` | RemoteEvent | 6 / 5 | WeaponController, slash or stab |
| `ThrowKnife` | RemoteEvent | 3 / 1 | WeaponController |
| `Reload` | RemoteEvent | 4 / 2 | WeaponController |
| `EquipSlot` | RemoteEvent | 8 / 6 | WeaponController |
| `AimUpdate` | UnreliableRemoteEvent | 15 / 12 | WeaponController, at most every 0.1 s on change |
| `SaveSettings` | RemoteEvent | 3 / 0.5 | SettingsController (Save button) |
| `GetSnapshot` | RemoteFunction | 3 / 0.5 | SnapshotController (retries every 1 s, up to 60 times) |
| `SetLoadout` | RemoteEvent | 4 / 1 | InventoryController (Armory tab) |
| `OpenCrate` | RemoteFunction | 3 / 1 | InventoryController (Crates tab OPEN button; one retry with the same RequestId) |
| `GetEconomy` | RemoteFunction | 4 / 1 | InventoryController (retries every 1 s, up to 30 times, until a state arrives) |
| `VoteMap` | RemoteEvent | 4 / 1 | VoteController (map vote panel button) |
| `RequestTeleport` | RemoteEvent | 2 / 0.2 | LobbyController (portal prompt, PLAY / HUB menu) |
| `TutorialAction` | RemoteEvent | 6 / 2 | TutorialController (client-checked steps, EXIT), LobbyController (Training station prompt sends `Start`) |

### FireWeapon

| Field | Schema |
|---|---|
| `Slot` | `FIREARM_SLOT` |
| `ShotId` | `Integer(0, 2^31)` |
| `ClientTime` | `TIME` (client `GetServerTimeNow()` at fire) |
| `Origin` | `Vector3(20000)` (client's standardized head position) |
| `Direction` | `Vector3(1.01)` (unit aim direction before spread) |
| `Hits` | `Array(HitReport, 16)` |
| `HitReport.TargetUserId` | `Optional(USER_ID)` |
| `HitReport.DummyId` | `Optional(Integer(1, 100000))`: a training dummy (`TrainingService`) |
| `HitReport.Position` | `Vector3(20000)` |
| `HitReport.Zone` | `Enum{Head, Body}` |
| `HitReport.Pellet` | `Integer(1, 16)` |

Server checks after the schema (`CombatService.onFire`): the shooter is alive and `MatchService:IsCombatAllowed`. `Slot` must equal the server-equipped slot; otherwise the server sends a `LoadoutState` resync. The equip delay must have elapsed, with 0.08 s tolerance. The firearm is resolved from the server loadout (`UnownedWeapon` signal if none). Fire cadence must pass (`ImpossibleFireRate` on `RateExceeded`). The server consumes ammunition (resync on failure) and ends spawn protection. `ShotFired` is broadcast. The rewind time must be valid (`InvalidShot` / `FutureTimestamp`). `#Hits ≤ Pellets` (`TooManyPellets`). For each hit: unique pellet index; **exactly one** of `TargetUserId` / `DummyId` (otherwise `MalformedPayload` / `HitTargetAmbiguous`); a player target must pass `MatchService:CanDamage(shooter, target)` (both may fight, victim alive, opponents: never a teammate, never anyone in the hub); a dummy target must be alive. Then `HitValidator.ValidateShot` runs against the rewound player root, or the dummy's current root (dummies do not move). Valid player hits take server-computed damage through `DamageService.Apply`; valid dummy hits go through `TrainingService.ApplyHit` and never touch economy or statistics. Statistics change only when `MatchService:TracksStats()` is true (D-040). A `HitConfirmed` is sent when anything was hit.

### MeleeAttack

| Field | Schema |
|---|---|
| `Attack` | `Enum{Slash, Stab}` |
| `ClientTime` | `TIME` |
| `Origin` | `Vector3(20000)` |
| `Direction` | `Vector3(1.01)` |
| `TargetUserId` | `Optional(USER_ID)` |
| `TargetDummyId` | `Optional(Integer(1, 100000))` |

Server checks: alive and in the match; the knife is equipped and in hand; equip and melee cooldowns have elapsed (0.08 s tolerance). The cooldown is set from the attack's `CooldownSeconds`, spawn protection ends, and `MeleeSwing` is broadcast. If `TargetDummyId` names a living dummy, `HitValidator.ValidateMelee` runs against the dummy's root from the attacker's current head, and a valid hit goes through `TrainingService.ApplyHit`. Otherwise, if there is a player target that passes `MatchService:CanDamage`: valid rewind, then `HitValidator.ValidateMelee` (origin deviation, range + 1.5, cone + 15°, line of sight). Damage is the attack's configured value.

### ThrowKnife

| Field | Schema |
|---|---|
| `ClientTime` | `TIME` |
| `Origin` | `Vector3(20000)` |
| `Direction` | `Vector3(1.01)` |

Server checks: the `ThrownKnives` feature flag; alive and in the match; the knife is equipped and in hand; equip and throw cooldowns have elapsed. The origin must be within 4.5 studs of the current standardized head (`InvalidShot` / `ThrowOriginMismatch`). Then `KnifeState.Throw`, which sets both the throw and melee cooldowns to the throw cooldown, followed by `ProjectileService:LaunchKnife` (server-simulated).

### Reload

`{ Slot: FIREARM_SLOT }`. It is ignored unless `Slot` equals the equipped slot. The server calls `AmmoState.StartReload`, always sends `LoadoutState`, and sends another `LoadoutState` just after the reload completes.

### EquipSlot

`{ Slot: SLOT }`. Requires a living character. The server cancels reloads, sets `EquipReadyAt = now + EquipSeconds`, re-attaches the weapon model, and sends `LoadoutState`.

### AimUpdate

`{ Pitch: Number(−1.6, 1.6), Aiming: Boolean }`. The server writes the `AimPitch` and `Aiming` attributes on the character; other clients use them only for procedural poses. No gameplay effect.

### SaveSettings

| Field | Schema | Server clamp (`Settings.Sanitize`) |
|---|---|---|
| `FieldOfView` | `Number(1, 179)` | `[70, 100]` |
| `Sensitivity` | `Number(0, 100)` | `[0.1, 3.0]` |
| `AimSensitivity` | `Number(0, 100)` | `[0.1, 1.5]` |
| `Perspective` | `Enum{FirstPerson, ThirdPerson}` | — |
| `CrosshairStyle` | `Enum{Cross, Dot, Circle}` | — |
| `CrosshairColor` | `Enum{White, Green, Yellow, Cyan, Magenta}` | — |
| `CrosshairSize` | `Integer(4, 40)` | floor, `[4, 40]` |
| `ReducedMotion` | `Boolean` | — |
| `DamageNumbers` | `Boolean` | — |

Requires a loaded profile. The sanitized settings are stored in `profile.Data.Settings`, persisted with the next save, and echoed back in `SettingsApplied`.

### GetSnapshot

Payload `{}` (an empty struct; any field is rejected). It returns `nil` until the profile is loaded. Otherwise it returns:

```lua
{
	Settings = <Settings>,
	Level = number,
	Loadout = <LoadoutState payload> | nil,  -- nil before the first spawn
	Match = <MatchState payload>,
	Scoreboard = { <ScoreboardRow> },
}
```

### SetLoadout

| Field | Schema |
|---|---|
| `Primary` | `String(64)` |
| `Secondary` | `String(64)` |
| `Knife` | `String(64)` |

Server validation in `InventoryService`:
1. The profile must be loaded.
2. For each slot, `WeaponCatalog.SlotFor(id)` must equal that slot. Unknown ids fail this check.
3. The player must own the weapon (`Inventory.Weapons[id]`).

Any failure rejects the whole request, records a `LoadoutChangeRejected` security audit event, and sends the Warning notification "That loadout is not available." On success the active preset is replaced, `RequestSave` is called, the notification "Loadout saved. It applies on your next spawn." is sent, and `InventoryService.Changed` fires, which pushes `EconomyState`. The weapon in use changes only at the next spawn (`WeaponService.ResetForLife`).

### OpenCrate

| Field | Schema | Further server checks (`CrateService`) |
|---|---|---|
| `CrateId` | `String(32)` | Must be a crate that passed boot validation, otherwise `UnknownCrate` |
| `RequestId` | `String(64)` | Length ≥ 8 and only `[A-Za-z0-9-]`, otherwise `BadRequest`. The client sends `HttpService:GenerateGUID(false)` |
| `UseToken` | `Optional(Boolean)` | `true` spends one free crate token for this crate instead of coins (`NoToken` if there is none). No currency moves, so policy gating does not apply (D-037) |

The handler also requires a loaded profile (`NotLoaded`). The roll is made on the server. The open runs as transaction `crate:{RequestId}` (ECONOMY.md §4). The return value is the RemoteFunction result:

```lua
{ Ok = true, Replayed = boolean, Result = {
	RequestId, CrateId, WeaponId, Rarity, Duplicate = boolean, Compensation = int,
	FromEarned = int, FromPurchased = int, UsedToken = boolean, Time = os.time,
} }
-- or
{ Ok = false, Reason = "UnknownCrate" | "BadRequest" | "NotLoaded" | "InsufficientFunds"
                     | "InsufficientEarnedFunds" | "NoToken" | "AlreadyProcessed" | <mutation error> }
```

`Replayed = true` means the RequestId had already been applied; the stored result from `CrateHistory` is returned and nothing is charged or granted. `AlreadyProcessed` is returned if the id was applied but its result has since rotated out of the 50-entry history. The client reports `NoResponse` locally if both invoke attempts return nil.

### GetEconomy

Payload `{}`. Returns `nil` until the profile is loaded, otherwise the `EconomyState` payload (§3).

### VoteMap

| Field | Schema |
|---|---|
| `MapId` | `String(64)` |

Accepted only during `Intermission` while a vote is open, for a loaded profile, and only for one of the offered options (`MapVote.Cast`). A player's later vote replaces the earlier one. Accepted votes mark the vote dirty; the batch loop broadcasts `MapVote` at most every 0.5 s.

### RequestTeleport

| Field | Schema |
|---|---|
| `Destination` | `Enum{Hub, FreeForAll, TeamDeathmatch, CasualDuel1v1, CasualDuelTeam}` |

The client never sends a PlaceId. `PortalService` resolves the destination from `Config.Places.Destinations` and refuses, in this order: `UnknownDestination`; `AlreadyHere` (the destination's mode is this place's mode, or Hub from the hub); `NotLoaded`; `TutorialRequired` (hub only, tutorial not completed); `InProgress`; `Studio` (TeleportService does not work in Studio); `NotConfigured` (PlaceId is 0). Otherwise it sends `TeleportStatus` `Starting` and calls `TeleportService:TeleportAsync` with up to 3 attempts and backoff (`Config.Places.Teleport`). Teleport data `{ Destination, From }` is informational only: the destination place reads its mode from its own `PlaceConfig`.

### TutorialAction

| Field | Schema |
|---|---|
| `Action` | `Enum{Start, Complete, Exit}` |
| `Step` | `Optional(Integer(1, 64))` |

Hub only (`TutorialService`). `Start` begins a new session at step 1 (used for replays from the Training station). `Exit` ends the session only if the account has already completed the tutorial. `Complete` advances only if `Step` is the current step **and** that step is `Check = "Client"` (`TutorialProgress.ClientComplete`). Server-checked steps ignore client claims and advance only from server-observed events.

## 3. Server → client

Payloads as constructed at the call sites listed.

| Remote | Kind | Recipient | Fired from |
|---|---|---|---|
| `LoadoutState` | RemoteEvent | owner | `WeaponService.PushState` |
| `HitConfirmed` | RemoteEvent | attacker | `CombatService` (firearm, melee), `ProjectileService` (thrown knife) |
| `DamageTaken` | RemoteEvent | victim | `DamageService.Apply` |
| `ShotFired` | UnreliableRemoteEvent | everyone except the shooter | `CombatService.onFire` |
| `MeleeSwing` | UnreliableRemoteEvent | everyone except the attacker | `CombatService.onMelee` |
| `KillFeed` | RemoteEvent | all | `MatchService.onEliminated` |
| `Eliminated` | RemoteEvent | victim | `MatchService.onEliminated` |
| `MatchState` | RemoteEvent | all, or the joining player | `MatchService` (phase changes, match and round start and end, Team Deathmatch score changes, joins during Waiting/Countdown, profile loaded) |
| `Scoreboard` | RemoteEvent | all | `MatchService` (batched, at most every 0.5 s when changed) |
| `Announcement` | RemoteEvent | all | `MatchService` (killstreaks, duel round start and result, match winner) |
| `Notification` | RemoteEvent | one player | `PickupService`, `PlayerDataService` (Studio ephemeral warning), `InventoryService` (loadout saved or rejected) |
| `SettingsApplied` | RemoteEvent | one player | `PlayerDataService` (SaveSettings) |
| `EconomyState` | RemoteEvent | one player | `EconomyService.PushState`: on profile load, after every applied grant, after crate opens, on `InventoryService.Changed` and `PolicyComplianceService.StatusChanged` |
| `Reward` | RemoteEvent | one player | `EconomyService.Grant` (when an applied grant gave more than 0 coins or XP) and `EconomyService.GrantTutorialReward` |
| `MapVote` | RemoteEvent | all | `MatchService` batch loop, when votes changed (initial options arrive in `MatchState.Vote`) |
| `TutorialState` | RemoteEvent | one player | `TutorialService` (profile load, start, every step change, exit) |
| `TeleportStatus` | RemoteEvent | one player | `PortalService` (start, refusal, failure, `TeleportInitFailed`) |

### Payload shapes

```lua
LoadoutState = {
	Loadout = { Primary = weaponId, Secondary = weaponId, Knife = weaponId },
	Equipped = "Primary" | "Secondary" | "Knife",
	EquipReadyAt = serverTime,
	KnifeInHand = boolean,
	Ammo = { [slot] = { Magazine = int, Reserve = int, ReloadEndsAt = serverTime? } },
	ServerTime = serverTime,
}

HitConfirmed = { Hits = { {
	TargetUserId?, TargetDummyId?,   -- exactly one is set
	Damage, Zone = "Head" | "Body", Eliminated = boolean,  -- Eliminated = knocked down for dummies
} } }

DamageTaken = { FromUserId, FromPosition = Vector3?, Amount, Health }

ShotFired = { ShooterUserId, Origin = Vector3, Direction = Vector3, Pellets = int, Range = number }

MeleeSwing = { AttackerUserId, Attack = "Slash" | "Stab" }

KillFeed = {
	KillerUserId?, KillerName?, KillerTeam = "A" | "B" | nil,
	VictimUserId, VictimName, VictimTeam = "A" | "B" | nil,
	WeaponId?, Kind = "Firearm" | "Knife" | "ThrownKnife" | "Finished" | "Environment",
	Headshot = boolean, AssistUserIds = { UserId },
}

Eliminated = {
	KillerUserId?, KillerName?, WeaponId?, KillerHealth?, KillerLevel?,
	RespawnAt = serverTime?,        -- nil in duels (no respawn within a round)
	Spectating = boolean,           -- true in duels
}

MatchState = {
	Mode = modeId, ModeName, Kind = "Lobby" | "FreeForAll" | "TeamDeathmatch" | "Duel",
	Phase = "Lobby" | "Waiting" | "Countdown" | "Active" | "RoundEnd" | "Intermission",
	MatchId = int,
	EndsAt = serverTime,            -- phase deadline; the round deadline while a duel round is active
	MapName, MapId,
	TeamScores = { A = int, B = int }?,                 -- team modes
	ScoreLimit = int?,
	Duel = { Round = int, Wins = { A = int, B = int }, RoundsToWin = int }?,
	TeamSize = int?,                                    -- duels
	RespawnEnabled = boolean,
	PlayersNeeded = int, PlayerCount = int,             -- start threshold and loaded players
	Results = { { Rank, Name, Team?, Eliminations, Deaths, Assists } }?,  -- top 16, intermission only
	WinnerTeam = "A" | "B" | nil,                       -- intermission only
	Vote = MapVoteState?,
}

MapVoteState = { Options = { { Id = mapId, DisplayName, Votes = int } }, EndsAt = serverTime }
MapVote = MapVoteState

Scoreboard = { Rows = { { Rank, UserId, Name, Team?, Eliminations, Deaths, Assists, Streak, Level, Ping } } }

Announcement =
	  { Kind = "Killstreak", UserId, Name, Streak }
	| { Kind = "Round", Round = int, Wins = { A, B } }
	| { Kind = "RoundResult", Team?, TeamName?, Draw = boolean, Wins = { A, B } }
	| { Kind = "MatchWinner", Team, TeamName }

TutorialState = {
	Active = boolean, Index = int?, StepId = string?, Total = int,
	Completed = boolean, RewardClaimed = boolean,
}

TeleportStatus =
	  { Ok = true, Destination, Stage = "Starting" }
	| { Ok = false, Destination?, Reason = "UnknownDestination" | "AlreadyHere" | "NotLoaded"
	    | "TutorialRequired" | "InProgress" | "Studio" | "NotConfigured" | "Failed", Detail? }

Notification = { Kind = "Pickup" | "Warning" | "Info", Text }

EconomyState = {
	Coins = int,                     -- Earned + Purchased
	Earned = int, Purchased = int,
	PurchasedUsableForCrates = boolean,  -- PolicyService decision (fail closed)
	Level = int, XPIntoLevel = int, XPForNext = int,  -- XPForNext = 0 at max level
	Prestige = int,
	Owned = { weaponId },            -- sorted; only ids present in the catalog
	Loadout = { Primary, Secondary, Knife },  -- active preset
	ActiveCrates = { crateId },      -- crates that passed boot validation, in display order
	CrateTokens = { [crateId] = int },  -- free crate tokens (tutorial reward)
	RewardsEnabled = boolean,
}

Reward = {
	Coins = int, XP = int,           -- amounts actually applied after hourly caps
	Reasons = { "GunElimination" | "KnifeElimination" | "FinishedElimination" | "Headshot"
	          | "Assist" | "Streak<n>" | "MatchCompleted" | "FirstPlace" | "Victory" | "Tutorial" },
	LevelsGained = int, LevelCoins = int, Level = int,
	Capped = boolean,                -- true if the hourly cap reduced coins or XP
}

SettingsApplied = <Settings> (sanitized)
```

All `serverTime` values come from `workspace:GetServerTimeNow()`, the same synchronized clock the client uses. Unreliable events are cosmetic only: losing them never affects game state.

## 4. Change procedure

1. Edit `Contracts.luau`: add or modify the entry, schema and rate limit.
2. Use the remote only through `net.OnEvent` / `net.OnInvoke` / `net.Fire*` (server) or `Net.Fire` / `Net.Invoke` / `Net.On` (client).
3. Update this document, then run `lune run tests/run`. The integrity test catches undeclared or unused remotes.
4. Removing or renaming a remote is a breaking change for clients still on an older build. Roblox replaces client code on server restart, so ship it with a server migration (OPERATIONS.md).
