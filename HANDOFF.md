# Handoff (2026-10-19)

Read `CLAUDE.md` first (architecture, conventions, every design decision). This file is the state of play.

## Done (all pushed to `main`)
- **Gameplay rounds 1-3** (2026-10-17): stay-at-station mode, free-form make-line with load-time order matching (Auto/Pick), ready rack + Load Oven, three stacked real-time ovens (6 slots), oven tender flow (pull at exit, box in world, rocker cuts, seasoning), dough QTE, endless-spoodle sauce, job aid cards, heat rack + delivery, load/total times.
- **UI overhaul** (2026-10-19, 5 batches): "store systems" look, tickets, Stations tab/bar, work strips, first-visit tips, restyled menus and in-world screens.
- **Audit fixes 1-4** (`b1e2053`): truck farming, franchise double charge, DataStore session lock, carryout patience.
- **Store lots, no clock-in or roles** (`9b15521`): 5 lots per server (lot 1 = old HQ site); a store picker on join (open your own, join one with room up to 4, leave); owner handover to the longest-serving member; every player works every station; deliveries need 2+ players or a hired driver, otherwise they arrive as carryout. FranchiseService, the time clock, roles and management slots are gone.
- **Hired NPC staff** (`014002d`): Staff menu (HUD button beside the Stations tab); owner buys insiders (assigned to a station, click to move) and drivers; saved in the owner's profile (`Staff`). Insiders do the real station work through shared step functions; drivers take delivery orders on a timed trip. Roll/spin prepared but off (`Config.StaffRoll.Enabled = false`).
- **Team members: stats, levels, shifts** (`1868920`): one hire kind (team member) for any station incl. the heat rack; per-station levels with XP, reliability (call-outs), availability (Lunch / Dinner / Late Night; open = all 3); the owner schedules shifts (8 per shift, roster 16); hires 200 coins rising x1.25; new `src/shared/Staff.luau` holds the rules. Insiders/Drivers as separate kinds are gone.
- **No off-screen crew; managers; cap of 3** (`8ce35b6`): every forecast order is a real order with a patience timer; lost sales (timed out, wrong house, open at midnight) on the sales board instead of "crew-covered". Assistant/Store Managers work several stations, limited by Flexibility (overwhelmed = slower and sloppier); granted in Studio only until the roll exists. Team members capped at 3 (managers extra: 2 Assistant, 1 Store).
- **Make-line overhaul** (`787b5b2`, `8884c9f`, `277e19e`): build-your-own pizzas (size + up to 3 toppings, priced per topping, one ticket line per topping; register POS toggles toppings); pepperoni/ham by the piece, other toppings by the ounce; no crust seasoning; no job aid cards (tip cards carry the charts); idle at a make station moves you back a step (or waits on whoever's there); flashing Next button; highlighted needed size and oldest ticket; scales on the make-line; toppings picked from the pans.
- Tooling: `lune run tests/specs` (48 specs, incl. shifts, levels, call-outs, hire generation, save repair, roll odds), `selene src` (0/0), `rojo build`.

## In progress
- Nothing mid-edit; the working tree is clean and everything is pushed (`798edfa`).
- The user announced "some more gameplay changes" but the list never came through. Ask for it before starting anything else.

## Verified in Studio (scripted, 2026-10-19)
- Picker opens on join; claiming lot 1 builds the store, sets `StoreId`/`StoreOwner`, uniform on, player placed at the entrance; leaving frees the lot; opening on lot 2 works; stations work with no clock-in.
- With Studio's Config temporarily patched (free hires, 7-insider cap, start at 4:54 PM; restored afterwards): 7 insiders auto-assigned one per station + 1 driver; the cap is enforced; NPCs stand at their stations (register one on the floor after a raycast fix); orders were rung in, made, baked, cut, boxed, and delivered by the NPC driver (who walked out, vanished and came back); sales board recorded load/total times.
- A player at a station an NPC works hides that NPC locally and no longer stands on its head.

- Team members (Studio Config patched: free hires, start 3:54 PM; restored): 12 hires with random stats/availability, auto-scheduled up to 8 per shift; at 4 PM the Lunch crew left, the Dinner crew came in and one (reliability 3) called out with a notice; unavailable shifts refused; taking someone off the current shift sends them home; moving a station works; XP accrued per job and a level-up notice fired; the menu renders (screenshot checked).

- Managers and lost sales (Studio Config patched: free hires, 4:54 PM start, 60 s patience; restored): the 4th team member and 3rd Assistant Manager were refused; granted managers got better stats and Flexibility; toggling stations works and over the limit shows OVERWHELMED (red) with a notice; managers moved between their stations for work; a manager with the heat rack turned deliveries on; lost sales counted on the board; no sales recorded off-screen.

- Make-line overhaul (scripted): orders carry topping lists and party orders repeat favourites; tickets show one line per topping; the Toppings tip card shows the portion chart; Cheese with nothing cascaded back to Stretch with notices; stretch -> sauce -> cheese via the Next button (ready at once, "NEXT: SAUCE"...); Sauce highlighted the needed size; the oldest ticket has its outline; "waiting on Leo at Sauce" when a team member held Sauce; the scale read-outs exist and reset; all six pans and the scale are in view from the rebuilt Toppings camera (geometry check, Studio wasn't rendering).

## Not verified
- The user has **not** hand-playtested any of this (or the earlier UI overhaul).
- Owner handover and joining another player's store need 2 players; not run.
- Saves (Studio has API access off): hires persisting across sessions, and the save lock.
- Clicking a pan, the scale changing as you pour or top, the hover outline on pans, the Next button's flashing and the register POS toggles: nothing was clicked by hand or seen rendered this round (Studio didn't render; screenshots timed out).
- Menu buttons clicked by hand (only the remotes were driven); the staff menu with a non-owner viewing; a long session (XP saved by autosave, levels after a rejoin).

## Known bugs / open findings
- From this session: dough is the bottleneck with one NPC stretcher (10 s a skin at level 1 x1.5); NPCs walk straight through counters to the driver door; any staff change rebuilds every NPC (a short pop, jobs in hand go back); earlier Insider/Driver saves are dropped by `Staff.sanitize` (test data only).
- Old saves: the `Franchise` field was dropped (anyone who bought a franchise loses it, no refund); fine if the game has no real players yet.
- From the 2026-10-19 audit (numbers match that report): 5 Auto-match can put a pizza on a different recipe (NPC loaders only load exact matches; players still can); 6 pay/scoring rules have no specs; 7 Register accepts up to 40 pizzas; 8 `ShopService.luau` is ~3,300 lines (now also holds the staff); 9 duplicate formatters; 10 dead code; 11 racks rebuild every part; 12 topping names only on hover.
- Also: the Stations tab sits in the mobile thumbstick zone; extras are paid as "Sloppy"; the 120 s bake is the whole belt.

- From the make-line overhaul: being moved back is immediate (even right after you finish a step, while Next points forward); topping prices, ToppingCount / ToppingPopularity and oz portions are placeholders; the cheese pans by the cheese spot are decoration only.
- From the no-crew change: a solo store at dinner gets far more orders than it can make, so most are lost until it's staffed (intended pressure, but the numbers are untuned); lost walk-ins who were never rung in aren't announced, only counted.

## Exact next step
1. Ask the user for their next list of gameplay changes (it didn't arrive), clarify anything ambiguous with AskUserQuestion, plan it into batches, and work batch by batch: build, lint (`luau-analyze`), `selene src`, `lune run tests/specs`, `rojo build`, a scripted Studio run, then commit + push.
2. Still owed by the user: a hands-on playtest (`rojo serve` in this folder, Connect in the Rojo plugin) of the store picker, Staff menu (team members 200 coins, Studio-only manager grant), the make-line flow (moving back, Next button, highlights), the scales and clicking topping pans, and, with a second player, owner handover.
3. Later: design the roll/spin with the user (team-member stat pool as a `Config.StaffGen` entry, duplicates, what managers do beyond Flexibility, coins vs Robux, the spin presentation), then the visual overhaul.
