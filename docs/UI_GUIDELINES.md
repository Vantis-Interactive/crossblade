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
Rarity always appears as **symbol + name + colour**, for example `✦ LEGENDARY` in Legendary orange. Colour is never the only signal (WEAPON_CATALOG.md §6, tested). The HUD weapon slots already follow this rule.

## 3. Combat HUD layout (implemented: `src/client/Controllers/HUDController.luau`)

| Region | Element |
|---|---|
| Bottom-left | Health panel: numeric HP plus bar. "SPAWN PROTECTION" label above it while a force field is active. |
| Bottom-centre | Three weapon-slot buttons (number, slot, weapon name, rarity tag). The active slot is olive; a thrown knife shows "THROWN - RECOVER OR USE STATION" in Warning. Clickable and tappable. |
| Bottom-right | Ammo panel: weapon name, `magazine / reserve` (Danger when empty), reload progress bar. Shows `KNIFE` or `THROWN` for the knife slot. |
| Centre | Crosshair (Cross, Dot or Circle; settings colour and size; blooms after firing and tightens when aiming). Hit marker on server confirmation only, gold for headshots. |
| Around centre | Directional damage arcs at radius 110 pointing toward the attacker, fading over 1 s. |
| Top-centre | Match bar: mode and map, timer (or "NEXT ROUND" during intermission), current leader. |
| Top-right | Kill feed: up to 5 entries for 6 s each; `◎` marks headshots; entries involving you use the olive background. |
| Top-left | SCORE and SETTINGS buttons, for touch and mouse users who prefer clicking. |
| Centre overlays | Elimination panel (killer, weapon, killer HP, killer level, respawn countdown); killstreak announcement; "ELIMINATED <name>" toast; scoreboard (hold Tab or D-pad left) and round results during intermission. |
| Below the match bar | Notification toasts: pickups (green), warnings (amber, 6 s). |

Damage numbers (optional setting) float above targets in world space.

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

- Touch buttons are created by ContextActionService only on touch devices, at configured positions near the bottom-right.
- Movement and jump use Roblox's standard controls, including the mobile thumbstick.
- Camera look uses the mouse (cursor locked at centre), the right stick, or touch drag.
- A rebinding UI is planned (NET-07).

## 5. Accessibility (implemented unless noted)
- **Scalable UI:** a `UIScale` on the HUD scales with the viewport (`min(width/1600, height/900)`, clamped to 0.6–1.3), so the same layout works on phone, tablet, desktop and TV. Planned: a user text-scale setting.
- **Reduced motion:** disables viewmodel sway, damage-number rise and FOV easing, and makes toasts disappear without a fade.
- **Not colour alone:** rarity uses symbols; headshots use `◎` as well as colour; an empty magazine shows `0` as well as turning red.
- **Controller navigation:** the settings panel selects its first control when opened (`GuiService.SelectedObject`), and all buttons are `Selectable`.
- **Crosshair customization:** 3 styles, 5 colours, sizes 4–40.
- Planned: colour-blind presets for HUD signal colours, subtitles for announcer audio when audio exists, and a screen-reader-friendly menu order audit (Phase 10).

## 6. Settings panel (implemented: `src/client/Controllers/SettingsController.luau`)

Field of view (70–100), sensitivity (0.1–3.0), aim sensitivity (0.1–1.5), default camera, crosshair style, colour and size, reduced motion and damage numbers. Actions: DEFAULTS, CANCEL and SAVE. The server sanitizes and persists the settings, then echoes the result back. Every control is functional; nothing is a placeholder.

## 7. Required interfaces (spec §20)

| Interface | Status |
|---|---|
| Combat HUD, health display, ammunition display, weapon selection | Implemented |
| Kill feed, scoreboard | Implemented |
| Settings | Implemented |
| Main menu | Planned (LOB-01) |
| Inventory, armory, weapon customization | Planned (ECO-03, LOB-02) |
| Crate shop, crate reveal (with reduced-animation path and odds disclosure) | Planned (ECO-04, LOB-03) |
| Matchmaking, party management, server browser | Planned (LOB-04, NET-01 to NET-03) |
| Player profile, leaderboards, ranked progression | Planned (RNK-04, RNK-02) |
| Battle pass, challenges, achievements | Planned (MON-03, PRG-04, PRG-02) |
| Tutorial | Planned (LOB-06) |
| Player reporting | Planned (SEC-03); Roblox's built-in report remains available meanwhile |
| Administrative dashboard | Planned (SEC-02) |

## 8. Rules for new UI
1. Use `Build.Panel`, `Build.Label` and `Build.Button` with Theme tokens. No raw colours.
2. Every visible control must work with mouse, touch and gamepad. No placeholder buttons.
3. Any animation must have a reduced-motion path.
4. Never communicate state by colour alone.
5. Gameplay-critical feedback (hit markers, eliminations) comes from server confirmation, not prediction.
