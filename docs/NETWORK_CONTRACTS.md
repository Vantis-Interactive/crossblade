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

### FireWeapon

| Field | Schema |
|---|---|
| `Slot` | `FIREARM_SLOT` |
| `ShotId` | `Integer(0, 2^31)` |
| `ClientTime` | `TIME` (client `GetServerTimeNow()` at fire) |
| `Origin` | `Vector3(20000)` (client's standardized head position) |
| `Direction` | `Vector3(1.01)` (unit aim direction before spread) |
| `Hits` | `Array(HitReport, 16)` |
| `HitReport.TargetUserId` | `USER_ID` |
| `HitReport.Position` | `Vector3(20000)` |
| `HitReport.Zone` | `Enum{Head, Body}` |
| `HitReport.Pellet` | `Integer(1, 16)` |

Server checks after the schema (`CombatService.onFire`): the shooter is alive and `MatchService:IsCombatAllowed`. `Slot` must equal the server-equipped slot; otherwise the server sends a `LoadoutState` resync. The equip delay must have elapsed, with 0.08 s tolerance. The firearm is resolved from the server loadout (`UnownedWeapon` signal if none). Fire cadence must pass (`ImpossibleFireRate` on `RateExceeded`). The server consumes ammunition (resync on failure) and ends spawn protection. `ShotFired` is broadcast. The rewind time must be valid (`InvalidShot` / `FutureTimestamp`). `#Hits ≤ Pellets` (`TooManyPellets`). For each hit: unique pellet index, target alive and in the match, then `HitValidator.ValidateShot` against the rewound target. Valid hits take server-computed damage through `DamageService.Apply`. Statistics are updated, and a `HitConfirmed` is sent when damage was dealt.

### MeleeAttack

| Field | Schema |
|---|---|
| `Attack` | `Enum{Slash, Stab}` |
| `ClientTime` | `TIME` |
| `Origin` | `Vector3(20000)` |
| `Direction` | `Vector3(1.01)` |
| `TargetUserId` | `Optional(USER_ID)` |

Server checks: alive and in the match; the knife is equipped and in hand; equip and melee cooldowns have elapsed (0.08 s tolerance). The cooldown is set from the attack's `CooldownSeconds`, spawn protection ends, and `MeleeSwing` is broadcast. If there is a target: valid rewind, then `HitValidator.ValidateMelee` (origin deviation, range + 1.5, cone + 15°, line of sight). Damage is the attack's configured value.

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
| `MatchState` | RemoteEvent | all, or the joining player | `MatchService` (round start, round end, profile loaded) |
| `Scoreboard` | RemoteEvent | all | `MatchService` (batched, at most every 0.5 s when changed) |
| `Announcement` | RemoteEvent | all | `MatchService` (killstreaks) |
| `Notification` | RemoteEvent | one player | `PickupService`, `PlayerDataService` (Studio ephemeral warning) |
| `SettingsApplied` | RemoteEvent | one player | `PlayerDataService` (SaveSettings) |

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

HitConfirmed = { Hits = { { TargetUserId, Damage, Zone = "Head" | "Body", Eliminated = boolean } } }

DamageTaken = { FromUserId, FromPosition = Vector3?, Amount, Health }

ShotFired = { ShooterUserId, Origin = Vector3, Direction = Vector3, Pellets = int, Range = number }

MeleeSwing = { AttackerUserId, Attack = "Slash" | "Stab" }

KillFeed = {
	KillerUserId?, KillerName?, VictimUserId, VictimName,
	WeaponId?, Kind = "Firearm" | "Knife" | "ThrownKnife" | "Finished" | "Environment",
	Headshot = boolean, AssistUserIds = { UserId },
}

Eliminated = { KillerUserId?, KillerName?, WeaponId?, KillerHealth?, KillerLevel?, RespawnAt = serverTime }

MatchState = {
	Mode = "FreeForAll", ModeName, Phase = "Active" | "Intermission", RoundId,
	EndsAt = serverTime, MapName,
	Results = { { Rank, Name, Eliminations, Deaths, Assists } }?,  -- top 10, intermission only
}

Scoreboard = { Rows = { { Rank, UserId, Name, Eliminations, Deaths, Assists, Streak, Level, Ping } } }

Announcement = { Kind = "Killstreak", UserId, Name, Streak }

Notification = { Kind = "Pickup" | "Warning", Text }

SettingsApplied = <Settings> (sanitized)
```

All `serverTime` values come from `workspace:GetServerTimeNow()`, the same synchronized clock the client uses. Unreliable events are cosmetic only: losing them never affects game state.

## 4. Change procedure

1. Edit `Contracts.luau`: add or modify the entry, schema and rate limit.
2. Use the remote only through `net.OnEvent` / `net.OnInvoke` / `net.Fire*` (server) or `Net.Fire` / `Net.Invoke` / `Net.On` (client).
3. Update this document, then run `lune run tests/run`. The integrity test catches undeclared or unused remotes.
4. Removing or renaming a remote is a breaking change for clients still on an older build. Roblox replaces client code on server restart, so ship it with a server migration (OPERATIONS.md).
