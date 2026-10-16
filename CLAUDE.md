# Dominus Pizza (Roblox)

Roblox job/roleplay game: "Work at a Pizza Place but better". Every station is a skill minigame on a 3D pizza, players can franchise their own store, and store operations are modeled on a delivery-first pizza chain (Domino's-style) **under our own brand**. Never use a real chain's name, logo, or trade dress; it would risk a Roblox IP takedown. Goal: ship ASAP, then monetize (game passes) and polish.

## Workflow
- Rojo 7.7.1 lives at `%USERPROFILE%\.rojo\bin\rojo.exe` (not on PATH). The Studio plugin is installed.
- Live sync: `rojo serve` in this folder, then Connect in the Studio Rojo plugin. Build check: `rojo build -o test.rbxlx`.
- Checks (binaries from the luau-lang/luau GitHub release): `luau-compile --null <file>` for syntax; `luau-analyze <file>` for lint (ignore Roblox globals/types it doesn't know; look for Unused/Shadow warnings and any unknown global that isn't a Roblox built-in). Only Studio playtesting catches runtime errors, so ask the user for Output-window errors or screenshots.
- The map is built entirely in code; MapBuilder deletes Studio's default Baseplate/SpawnLocation on start (the Baseplate z-fights with our grass).
- If Studio shows something the code no longer does (e.g. old station labels), the Rojo plugin has disconnected and Studio is running stale scripts. Reconnect before testing.

## Architecture
- `src/shared/Config.luau`: all balance, jobs, recipes, portions, brand, clock and sales tuning. Change numbers here first.
- `src/shared/Remotes.luau`: RemoteEvents (server creates, client waits).
- `src/shared/GameClock.luau` + `src/server/ClockService.luau`: 24h clock (ReplicatedStorage "WeekHour" attribute, 0-168 from Monday 00:00), sun, `Closed` event at midnight. `GameClock.hoursText()` builds hours text from Config.
- `src/shared/Pizza3D.luau`: 3D pizza builder used by client minigames and the server's oven/belt visuals (same seed = same layout).
- `src/server/MapBuilder.luau`: map, store layout, houses (16), franchise lots (4). `StationArt.luau`: station visuals; a Model in `ServerStorage/StationModels/<Kind>` overrides the generated art.
- `src/server/ShopService.luau`: order flow from the sales forecast (walk-in/phone/online, 1-30 pizzas), dough skins on two 15-slot screen racks on the dough table (30 slots shared by all sizes, oldest of a size used first), per-pizza tickets Sauce (dough table; takes a skin of the ticket's size) → Cheese → Toppings (make-line; cheese pizzas skip toppings) → conveyor Oven → waits at the belt end (falls off after `Config.Oven.FallAfter` real seconds and must be remade) → Cut & Box (pick the right open box) → Carryout / Heat Rack → Delivery. Stock, open hours, load times, **server-authoritative** scoring and pay, management slots.
- `src/server/SalesPlan.luau`: weekly forecast, day/daypart split, order-size rolls, pricing. `CarService.luau`: per-driver cars, network-owned by the driver. `FranchiseService.luau`, `DataService.luau`: franchises and DataStore saves.
- `src/client/`: `Main.client.luau` (HUD, menus, prompt filtering, delivery waypoint), `WorkHud.luau` (station bar with waiting counts, order queue panel with click-to-work, "what next?" bar after each step; fed by the server's 1/s `QueueUpdate` and `StepDone`), `Minigames.luau` (2D Register + Supply), `Minigames3D.luau` (in-world Stretch, Sauce, Cheese, Toppings, Cut & Box), `Workstation.luau` (stand at station, first-person camera that looks at `ws.focus`, head/arms/hands hidden locally), `Driving.luau`, `Ui.luau`.

## Conventions
- Stations are invisible hitbox Parts with a `Station` attribute and a ProximityPrompt; art is parented underneath. Gameplay code finds things by name and attribute, never by appearance.
- Never hard-code job names or store hours: use `Config.JobsWithStation`, `Config.ManagementJobs`, and `GameClock.hoursText()`.
- Shop-local coordinates: entrance faces +Z; Roblox's Front face is -Z (SurfaceGuis facing the street use `Back`). Station art: LookVector points at the worker.
- The client reports raw inputs only; validate every remote payload on the server.
- Road/lot surfaces are `CanCollide = false` so the flat-bottomed car chassis doesn't snag.
- The DataStore key is still `PizzaShift_v1` (pre-rename); changing it orphans saves.

## Game design decisions (from the user)
- Roles: **CSR** takes orders and makes pizzas; **Delivery Driver** does everything a CSR does plus deliveries (less XP, gets delivery tips); **Shift Manager** (4 slots) and **General Manager** (1 slot) run every station and unload the truck (Inventory was folded in). Management slots go to highest XP; anyone may step up while the store has no management, otherwise minLevel applies and a higher-XP player bumps the lowest. Manager duties beyond that are still to be designed. There is no supply-chain role.
- Portions: topping piece counts depend on size and topping count (1 / 2-3 / 4+), e.g. Large pepperoni 40/32/24. ±10% variance is allowed; beyond that, customer satisfaction drops (`Config.PortionFactor`). Only Large Pepperoni is spec'd; the other portions and cheese ounces are placeholders the user will supply.
- Pizza sizes are real proportions (10"/12"/14", `Config.PizzaInches`); 3D pizzas, dough skins and boxes all scale from them.
- Hours: open 10 AM to midnight every day; staff can clock in from 9:30 AM to prep (HUD "Clock In / Positions" button or the register); midnight clocks everyone out. Players can explore any time.
- Sales: weekly $25k-$30k; Mon/Tue/Wed 10% each, Thu/Sun 15%, Fri/Sat 20%, each jittered ~3%; dayparts 10-4 = 20%, 4-9 = 70%, 9-12 = 10%. Orders are generated against that dollar budget, so order count follows the (daily-randomized) average ticket. Order sizes: small 1-4 pizzas (common), medium 5-15 (less common), large 15-30 (rare). Load times are tracked in real minutes (placed → all pizzas boxed).
- Tips scale with the order total: delivery tips go to the driver; carryout ("insider") tips are lower and split among the crew.
- Throughput: forecast volume is far more than players can make by hand, so orders beyond `Config.Crew.PizzasPerWorker` open pizzas per staff member go to an off-screen crew (they still count as sales). Claude's call, not the user's; revisit when location dynamics are designed.
- Multiple locations with different volumes and sales dynamics are planned but not designed yet (`AddShop(..., volume)` exists).
- Brand: the user chose "Dominus Pizza" after being warned it is close to "Domino's" and could draw a trademark claim. It's a single value, `Config.GameName`.
- Make process: every pizza physically exists at every step (skins on racks, sauced/cheesed pizzas waiting on the make-line, oven belt). Each step is its own station; players can work one station repeatedly (e.g. sauce 5 in a row) or follow one pizza start to finish via HUD buttons. Player autonomy and time management matter more than forced flow. In first person the player's hands are invisible (only tools show).
- Dough table layout follows the user's reference photo: screen racks stand on the table (not the floor), the sauce bucket is on the same table, and saucing happens on that table off to the side of the stretching spot. Positions live in `StationArt.Layout`.

## Working with the user
- They steer with reference photos of real store equipment and Studio screenshots. Match the photo closely (layout, what sits where), and treat screenshot complaints as precise bug reports.
- Realism modeled on how a Domino's store actually operates is the goal, with player autonomy and time management over forced flows.
- They make the design calls: confirm before inventing game rules they didn't ask for, and say plainly when something is Claude's own call (see "Throughput" above).
- Before declaring work done: compile every file, run the luau-analyze lint (catches call-before-definition bugs the compiler misses), and `rojo build`. Say clearly that Studio playtesting hasn't happened.
- Loose ends: git is NOT set up yet (offered twice; recommend it before the visual overhaul). Rojo serve must be restarted in each new session.

## Status (2026-10-16)
A full proofread/cleanup pass is done. The make process is now split into Stretch / Sauce / Cheese / Toppings stations with physical waiting spots, a station bar, order queue panel and "what next?" bar. Everything since the 3D minigames is written, compiles, lints clean and builds, but hasn't been playtested. A full visual overhaul is planned; the user will send instructions. Other next steps: real portion numbers, manager duties, location dynamics, a 2x Pay game pass.
