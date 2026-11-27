# UI Guidelines

The visual language is a premium tactical interface: charcoal backgrounds, olive accents, gunmetal strokes, clear type and restrained motion. All UI is built in code from `src/shared/Config/Theme.luau` through `src/client/UI/Build.luau`. Interface code never hardcodes colours or fonts.

## 1. Theme tokens (implemented)

| Token | RGB | Use |
|---|---|---|
| Background | 28, 30, 29 | Charcoal base |
| Panel | 38, 41, 39 | Panels (85% opaque) |
| PanelRaised | 50, 54, 51 | Buttons, alternating rows |
| Stroke | 92, 98, 90 | Gunmetal borders |
| Accent | 122, 140, 74 | Olive: selection, primary actions, own kill-feed entries |
| AccentBright | 164, 186, 98 | Highlights, spawn protection, own scoreboard row |
| Text | 232, 234, 226 | Primary text |
| TextMuted | 160, 166, 152 | Labels and captions |
| Danger | 214, 84, 66 | Empty magazine, elimination title, damage direction |
| Warning | 226, 176, 64 | Warnings, thrown-knife state |
| Health / HealthLow | 132, 196, 96 / 214, 84, 66 | Health bar (low at 30% or less) |
| HitMarker / HeadshotMarker | 255, 255, 255 / 255, 196, 64 | Hit confirmation |

- **Fonts:** Heading GothamBold, Body Gotham, Mono RobotoMono.
- **Text sizes:** Small 14, Body 16, Large 22, Huge 34.
- **Shape:** corner radius 4 px, padding 8 px.
- **Motion:** Fast 0.12 s, Normal 0.25 s. Reduced motion replaces motion with immediate changes.

## 2. Rarity presentation
Rarity always appears as **symbol + name + colour**, for example `✦ LEGENDARY` in Legendary orange. Colour is never the only signal (WEAPON_CATALOG.md §6, tested). The HUD weapon slots, the Armory lists, the crate odds rows and the crate reveal all follow this rule.

## 3. Combat HUD layout (implemented: `src/client/Controllers/HUDController.luau`)

| Region | Element |
|---|---|
| Bottom-left | Health panel: numeric HP plus bar. "SPAWN PROTECTION" label above it while a force field is active. |
| Bottom-centre | Three weapon-slot buttons (number, slot, weapon name, rarity tag). The active slot is olive; a thrown knife shows "THROWN - RECOVER OR USE STATION" in Warning. Clickable and tappable. |
| Bottom-right | Ammo panel: weapon name, `magazine / reserve` (Danger when empty), reload progress bar. Shows `KNIFE` or `THROWN` for the knife slot. |
| Centre | Crosshair (Cross, Dot or Circle; settings colour and size; blooms after firing and tightens when aiming). Hit marker on server confirmation only, gold for headshots. |
| Around centre | Directional damage arcs at radius 110 pointing toward the attacker, fading over 1 s. |
| Top-centre | Match bar. Line 1: mode, map and, in team modes, `YOU: ALPHA` / `YOU: BRAVO`. Line 2 by phase: `SOCIAL HUB`, `WAITING FOR PLAYERS <n>/<needed>`, `STARTING IN <s>`, the match or round timer, `NEXT ROUND <s>` (duel), or `NEXT MATCH <m:ss>`. Line 3: Free-for-All leader; Team Deathmatch `ALPHA <a> - <b> BRAVO   FIRST TO <limit>`; duel `ROUND <r>   ALPHA <a> - <b> BRAVO   FIRST TO <n>`; hub "Weapons work on training dummies only". |
| Top-right | Kill feed: up to 5 entries for 6 s each; `◎` marks headshots; entries involving you use the olive background. |
| Top-left | SCORE, SETTINGS and COLLECTION buttons, then PLAY (hub) or HUB (arenas) from `LobbyController` (y = 64, below the Roblox top bar), for touch and mouse users. Below them, a wallet panel: `◈ <coins>`, `LV <level>  <into>/<next> XP` (`MAX` at the level cap), and an XP progress bar. |
| Centre overlays | Elimination panel (killer, weapon, killer HP, killer level, and a respawn countdown, or "Spectating until the next round" in duels). Announcements: killstreaks, `ROUND <n>`, `<TEAM> WINS THE ROUND` / `ROUND DRAWN: REPLAYING`, and `VICTORY` or `<TEAM> WINS THE MATCH`. "ELIMINATED <name>" toast. Scoreboard (hold Tab or D-pad left) and match results during intermission; in team modes each row is prefixed `ALPHA · ` or `BRAVO · `. |
| Bottom-right, above the ammo panel | Map vote panel during intermission (§12). |
| Bottom-centre, above the slots | Spectator line in duels (§12). |
| Right side | Tutorial panel in the hub (§11). |
| Below the match bar | Notification toasts: pickups and rewards (green), info, warnings (amber, 6 s). Reward toasts read `+<coins> coins  +<XP> XP  (<reasons>)`. Level-ups show `LEVEL UP: LEVEL <n> (+<coins> coins)`. A capped grant adds a warning that the hourly match reward limit was reached. |

Damage numbers (optional setting) float above targets in world space, including training dummies.

**Teams are never shown by colour alone.** Team identity appears as the names Alpha and Bravo in the match bar, scoreboard and announcements. No team colour is used anywhere yet.

**Disabled Roblox core UI:** Backpack, Health and PlayerList. Roblox's own menu, including reporting and blocking players, is left intact.

## 4. Input bindings (implemented: `src/shared/Config/Input.luau`)

| Action | Keyboard / mouse | Gamepad | Touch button |
|---|---|---|---|
| Fire / slash | Left mouse | R2 | FIRE |
| Aim / stab | Right mouse | L2 | AIM |
| Reload | R | X | RLD |
| Next weapon | Q, mouse wheel | Y | SWAP |
| Primary / Secondary / Knife | 1 / 2 / 3 | — / — / D-pad right | Slot buttons in the HUD |
| Throw knife | G | B | THROW |
| Inspect | F | D-pad down | — |
| Sprint (hold) | Left Shift | L3 | — |
| Toggle perspective | V | R3 | CAM |
| Scoreboard (hold) | Tab | D-pad left | SCORE button in the HUD |
| Settings | P | Select | SETTINGS button in the HUD |
| Collection (Armory / Crates) | I | D-pad up | COLLECTION button in the HUD |

- Touch buttons are created by ContextActionService only on touch devices, at configured positions near the bottom-right.
- Movement and jump use Roblox's standard controls, including the mobile thumbstick.
- Camera look uses the mouse (cursor locked at centre), the right stick, or touch drag.
- These are the defaults. Players can rebind every action for keyboard/mouse and for gamepad (§7, Settings > CONTROLS; rules in `src/shared/Bindings.luau`).

## 5. Accessibility (implemented unless noted)
- **Scalable UI:** a `UIScale` on the HUD scales with the viewport (`min(width/1600, height/900)`, clamped to 0.6–1.3), so the same layout works on phone, tablet, desktop and TV. Planned: a user text-scale setting.
- **Reduced motion:** disables viewmodel sway, damage-number rise and FOV easing, makes toasts disappear without a fade, and shows crate results instantly.
- **Not colour alone:** rarity uses symbols; headshots use `◎` as well as colour; an empty magazine shows `0` as well as turning red.
- **Controller navigation:** the settings panel selects its first control, and the Collection window selects the ARMORY tab, when opened (`GuiService.SelectedObject`). All buttons are `Selectable`.
- **Crosshair customization:** 3 styles, 5 colours, sizes 4–40.
- Planned: colour-blind presets for HUD signal colours, subtitles for announcer audio when audio exists, and a screen-reader-friendly menu order audit (Phase 10).

## 6. Collection window (implemented: `ArmoryController.luau`, `CrateController.luau`)

The window is a centred 820 × 560 panel with ARMORY and CRATES tabs and a CLOSE button. Its header shows the wallet (total, earned and purchased separately, and level) and `COLLECTION <owned> / <total>`. While open it releases the cursor and blocks combat input (`UIState.SetMenuOpen("Collection", ...)`; several menus can be open at once). Opening it focuses the ARMORY tab button for gamepad navigation.

**Armory tab.** Three columns (PRIMARY, SECONDARY, KNIFE) list owned weapons, highest rarity first. Each row shows the weapon name and `<symbol> <RARITY>` in the rarity colour; the equipped one has an olive background and `EQUIPPED`. Hovering or gamepad selection shows a stats line from the archetype: damage, RPM, magazine/reserve, reload and range for firearms; slash, stab and throw for knives. Activating a row requests `SetLoadout`; the change applies on the next spawn.

**Crates tab.** The left list shows active crates only, meaning crates that passed server validation, with price and category. Selecting one shows the detail view:
- **Odds before purchase.** Every possible reward is listed with `<symbol> <RARITY>`, name, `OWNED → +<compensation>` when already owned, and its exact probability (`%.4g%%`). The list comes from `CrateOdds.Build`, the same function the server uses to select. The OPEN button is inside this view, so a purchase is always made with the odds on screen.
- The price and the coins the player can actually spend are shown. If purchased coins are not usable (PolicyService, fail closed), a note explains that only match-earned coins can be used. The button reads `OPEN FREE (<n> TOKEN[S])` when the player holds free crate tokens for that crate (tokens are used first), otherwise `OPEN FOR ◈ <price>`, `NEED ◈ <n> MORE`, or `OPENING...`.

**Reveal rules.**
- The reveal shows only the server's result. There is no spinning reel, no sequence of near-miss items, and nothing chosen on the client.
- The card shows `<symbol> <RARITY>` and the weapon name in a card tinted with the rarity colour. It then states either `NEW WEAPON ADDED TO YOUR COLLECTION` or `DUPLICATE: converted to +<n> coins`.
- Motion: a 0.45 s scale-in and fade. With reduced motion the result appears instantly.
- Failures show `NOT OPENED` with a plain-language reason, for example insufficient coins, purchased coins not usable, or no response (with a note that any charge will appear in the collection).

## 7. Settings panel (implemented: `src/client/Controllers/SettingsController.luau`)

Field of view (70–100), sensitivity (0.1–3.0), aim sensitivity (0.1–1.5), default camera, crosshair style, colour and size, reduced motion and damage numbers. Actions: DEFAULTS, CANCEL and SAVE. The server sanitizes and persists the settings, then echoes the result back. Every control is functional; nothing is a placeholder.

**CONTROLS page (Phase 5).** A CONTROLS button at the top right switches to a scrolling list with one row per action (from `Config.Input`), showing the effective keyboard/mouse and gamepad binding.
- **Rebinding:** click a binding (it reads `PRESS A KEY` or `PRESS A BUTTON`), then press the new input. Esc cancels. Inputs in the first 0.25 s are ignored, so the click itself is never captured.
- **Status line:** shows the result, for example `<key> cannot be bound.` (not on the allow-list) or `<key> is already used by <Action>.`. Clashes are refused before saving, using the same `Shared/Bindings` rules the server applies.
- **RESET CONTROLS** clears all overrides; GENERAL returns to the main page.
- Changes take effect on SAVE: `InputController:Rebind` re-binds every action, and the server stores the sanitized overrides.
- Touch buttons are not remappable; they keep their configured positions.

## 8. Required interfaces (spec §20)

| Interface | Status |
|---|---|
| Combat HUD, health display, ammunition display, weapon selection | Implemented |
| Kill feed, scoreboard | Implemented |
| Settings | Implemented |
| Main menu | Partial: the hub is the main menu (portals, stations) and the PLAY menu reaches every destination from the interface; a separate front-end menu is not planned |
| Inventory, armory | Implemented in the Collection window, also opened from the hub's Armory station (Studio verification pending) |
| Weapon customization (skins, charms, attachments) | Planned |
| Crate shop, crate reveal (with reduced-animation path and odds disclosure) | Implemented in the Collection window, also opened from the hub's Crate shop station (Studio verification pending) |
| Matchmaking | Implemented: portals, the PLAY menu, cross-server queues with a status banner, private match hosting (§13; needs published places) |
| Party management, server browser | Implemented (§13; needs published places for the browser) |
| Map vote, duel spectating | Implemented (§12) |
| Player profile, leaderboards, ranked progression | Planned (RNK-04, RNK-02) |
| Battle pass, challenges, achievements | Planned (MON-03, PRG-04, PRG-02) |
| Tutorial | Implemented (§11) |
| Player reporting | Planned (SEC-03); Roblox's built-in report remains available meanwhile |
| Administrative dashboard | Planned (SEC-02) |

## 9. Rules for new UI
1. Use `Build.Panel`, `Build.Label` and `Build.Button` with Theme tokens. No raw colours.
2. Every visible control must work with mouse, touch and gamepad. No placeholder buttons.
3. Any animation must have a reduced-motion path.
4. Never communicate state by colour alone.
5. Gameplay-critical feedback (hit markers, eliminations) comes from server confirmation, not prediction.

## 10. Hub interactions and travel (implemented: `LobbyController.luau`)

- **Prompts.** Portals show a "Join <destination>" ProximityPrompt (12-stud range) and stations show "Open" or "Start Tutorial" (10 studs). Prompts use Roblox's standard prompt UI, so they work with keyboard (E), gamepad and touch.
- **PLAY menu (hub).** A centred panel lists Free-for-All, Team Deathmatch, Duel 1v1 and Team Duel 2v2 from `Config.Places.PlayOrder`, plus CLOSE. In arenas the same button reads HUB and the panel offers RETURN TO HUB. The menu releases the cursor while open (`UIState.SetMenuOpen("Play", ...)`).
- **Travel feedback.** `TeleportStatus` becomes a toast: `Joining <destination>...`, or a plain-language refusal (published game required, destination not published yet, finish the tutorial first, already joining, already here, teleport failed).

## 11. Tutorial panel (implemented: `TutorialController.luau`, hub only)

A 340 × 150 panel on the right shows `TUTORIAL <i>/12  •  <TITLE>` and the step's instruction text from `Config.Tutorial`. The coins step shows a CONTINUE button. EXIT TUTORIAL appears only for players who have already completed the tutorial (replays); first-time players cannot dismiss it. Client-checked steps complete automatically when the player does the thing: moves for 1 s, sprints and jumps; switches camera; equips the secondary and the knife; or approaches a portal or opens the travel flow.

## 12. Map vote and spectating (implemented: `VoteController.luau`, `SpectatorController.luau`)

- **Map vote.** During intermission a 300 × 170 panel titled VOTE FOR THE NEXT MAP lists each option as a button with its live vote count; the player's choice shows `✓` and the olive background, so the choice is not shown by colour alone. Votes can be changed until the timer ends.
- **Spectating (duels).** While eliminated, the camera orbits a surviving participant (teammates first), and a line reads `SPECTATING <NAME>   •   FIRE / AIM to switch`.

## 13. Multiplayer interfaces (implemented, Phase 5: `LobbyController.luau`, `MatchmakingController.luau`, `PartyController.luau`)

`MatchmakingController` and `PartyController` build their UI in the hub only.

- **PLAY menu (hub).** One row per destination in `Config.Places.PlayOrder`:
  - A queued destination (Team Deathmatch, Duel 1v1, Team Duel 2v2) is labelled `(MATCHMAKING)` and sends `JoinQueue`. Free-for-All joins a public server directly.
  - Free-for-All and Team Deathmatch also have a SERVERS button that opens the server browser.
  - Below the rows: HOST PRIVATE MATCH, PARTY and CLOSE.
  - Portal prompts in the hub follow the same rule (queue or direct).
- **Queue banner** (top centre, under the match bar). `SEARCHING: <DESTINATION>  m:ss` with CANCEL while queued, then `MATCH FOUND: <DESTINATION>. JOINING...`. Refusals and cancellations become toasts in plain language, for example "Only the party leader can do that.", "Everyone in the party must finish the tutorial first.", "Matchmaking needs published places; it cannot run in Studio.", "Joining the match failed; you're back at the front of the queue."
- **Reconnect banner.** The same banner reads `YOUR <DESTINATION> MATCH IS STILL RUNNING` with REJOIN when the hub offers a reconnect.
- **Server browser.** A 520 × 420 panel titled `SERVERS: <DESTINATION>`, with one row per open server (`map  •  players/max  •  phase`) and a JOIN button. REFRESH re-queries; CLOSE. An empty list explains why ("No open servers right now…" or "Server browsing needs published places.").
- **Private host panel.** A 420 × 300 panel with MODE, MAP, DURATION and SCORE LIMIT rows, each with `<` / `>` steppers (SCORE LIMIT shows `n/a` for Free-for-All). A note states that private matches never award coins, XP or stats. CANCEL / HOST.
- **Party panel.** A 500 × 460 scrolling list:
  - The party size (`PARTY n/8`) and each member, marked `(leader)` and `(you)`.
  - For the leader: KICK and LEADER buttons per member, and an INVITE list of other players in the server.
  - LEAVE for members, and pending invites with ACCEPT / DECLINE.
  - New invites also raise a toast.
- Every panel registers with `UIState.SetMenuOpen` (`Browser`, `Private`, `Party`, `Play`), so the cursor is released and combat input is ignored while it is open.
