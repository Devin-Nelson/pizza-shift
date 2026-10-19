# Handoff (2026-10-19)

Read `CLAUDE.md` first (architecture, conventions, every design decision). This file is the state of play.

## Done (all pushed to `main`)
- **Gameplay rounds 1-3** (2026-10-17): stay-at-station mode, free-form make-line with load-time order matching (Auto/Pick), ready rack + Load Oven, three stacked real-time ovens (6 slots), oven tender flow (pull at exit, box in world, rocker cuts, seasoning), dough QTE, endless-spoodle sauce, job aid cards, heat rack + delivery, load/total times.
- **UI overhaul** (2026-10-19, 5 batches): "store systems" look, tickets, Stations tab/bar, work strips, first-visit tips, restyled menus and in-world screens.
- **Audit fixes 1-4** (`b1e2053`): truck farming, franchise double charge, DataStore session lock, carryout patience.
- **Store lots, no clock-in or roles** (`9b15521`): 5 lots per server (lot 1 = old HQ site); a store picker on join (open your own, join one with room up to 4, leave); owner handover to the longest-serving member; every player works every station; deliveries need 2+ players or a hired driver, otherwise they arrive as carryout. FranchiseService, the time clock, roles and management slots are gone.
- **Hired NPC staff** (`014002d`): Staff menu (HUD button beside the Stations tab); owner buys insiders (assigned to a station, click to move) and drivers; saved in the owner's profile (`Staff`). Insiders do the real station work through shared step functions; drivers take delivery orders on a timed trip. Roll/spin prepared but off (`Config.StaffRoll.Enabled = false`).
- **Team members: stats, levels, shifts** (this session's last commit): one hire kind (team member) for any station incl. the heat rack; per-station levels with XP, reliability (call-outs), availability (Lunch / Dinner / Late Night; open = all 3); the owner schedules shifts (8 per shift, roster 16); hires 200 coins rising x1.25; new `src/shared/Staff.luau` holds the rules. Insiders/Drivers as separate kinds are gone.
- Tooling: `lune run tests/specs` (43 specs, incl. shifts, levels, call-outs, hire generation, save repair, roll odds), `selene src` (0/0), `rojo build`.

## Verified in Studio (scripted, 2026-10-19)
- Picker opens on join; claiming lot 1 builds the store, sets `StoreId`/`StoreOwner`, uniform on, player placed at the entrance; leaving frees the lot; opening on lot 2 works; stations work with no clock-in.
- With Studio's Config temporarily patched (free hires, 7-insider cap, start at 4:54 PM; restored afterwards): 7 insiders auto-assigned one per station + 1 driver; the cap is enforced; NPCs stand at their stations (register one on the floor after a raycast fix); orders were rung in, made, baked, cut, boxed, and delivered by the NPC driver (who walked out, vanished and came back); sales board recorded load/total times.
- A player at a station an NPC works hides that NPC locally and no longer stands on its head.

- Team members (Studio Config patched: free hires, start 3:54 PM; restored): 12 hires with random stats/availability, auto-scheduled up to 8 per shift; at 4 PM the Lunch crew left, the Dinner crew came in and one (reliability 3) called out with a notice; unavailable shifts refused; taking someone off the current shift sends them home; moving a station works; XP accrued per job and a level-up notice fired; the menu renders (screenshot checked).

## Not verified
- The user has **not** hand-playtested any of this (or the earlier UI overhaul).
- Owner handover and joining another player's store need 2 players; not run.
- Saves (Studio has API access off): hires persisting across sessions, and the save lock.
- Menu buttons clicked by hand (only the remotes were driven); the staff menu with a non-owner viewing; a long session (XP saved by autosave, levels after a rejoin).

## Known bugs / open findings
- From this session: dough is the bottleneck with one NPC stretcher (10 s a skin at level 1 x1.5); NPCs walk straight through counters to the driver door; any staff change rebuilds every NPC (a short pop, jobs in hand go back); the Supreme job aid shows "PEPP" for both Pepperoni and Peppers; earlier Insider/Driver saves are dropped by `Staff.sanitize` (test data only).
- Old saves: the `Franchise` field was dropped (anyone who bought a franchise loses it, no refund); fine if the game has no real players yet.
- From the 2026-10-19 audit (numbers match that report): 5 Auto-match can put a pizza on a different recipe (NPC loaders only load exact matches; players still can); 6 pay/scoring rules have no specs; 7 Register accepts up to 40 pizzas; 8 `ShopService.luau` is ~3,300 lines (now also holds the staff); 9 duplicate formatters; 10 dead code; 11 racks rebuild every part; 12 topping names only on hover.
- Also: the Stations tab sits in the mobile thumbstick zone; the Follow chip disappears after 12 s; extras are paid as "Sloppy"; the 120 s bake is the whole belt.

## Exact next step
Ask the user to playtest (`rojo serve` in this folder, Connect in the Rojo plugin): pick a store, hire staff (needs coins: 250 / 400), assign insiders, and if possible join with a second player to try handover. Then design the roll/spin with them: its stat pool for team members (a `Config.StaffGen` entry), duplicates, what Assistant/Store Managers do, coins vs Robux, and the spin presentation.
