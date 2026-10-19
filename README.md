# Dominus Pizza

A Roblox pizza-store job game. Every station is a hands-on minigame on a real 3D pizza, the store runs on a 24-hour clock with a sales forecast, and high-XP players move into management or franchise their own store.

## How the store works
Operations are modeled on a delivery-first pizza chain (under our own brand). The store is open 10 AM to midnight; staff can clock in from 9:30 AM to prep. Clock in with the **Clock In / Positions** button (bottom left) or at the front counter register.

Orders come in three ways: walk-in carryout and phone calls (taken at the register), and online orders (straight to the kitchen screen). Orders can have anywhere from 1 to 30 pizzas.

| Station | Who | What you do |
|---|---|---|
| Register | CSR, Driver, Managers | Listen to the customer or caller and ring in every pizza (+ house # for delivery). The kitchen makes exactly what you ring in. |
| Stretch (dough table) | CSR, Driver, Managers | Prep ahead: pick a size, then hit the green zone on the timing bar (6 / 8 / 10 hits for S / M / L) to press a dough ball out into a skin on the cornmeal. The zone jumps and changes width after every hit; yellow and misses cost score and leave the skin small and lopsided. Skins go on the two 15-slot screen racks (30 total, any mix of sizes). |
| Sauce (dough table) | CSR, Driver, Managers | Pick a skin off the racks and spread sauce with the spoodle (it never runs dry). Scored on coverage out to the sauce line (3/4" in on every size) and on keeping the rim clean. |
| Cheese (make-line) | CSR, Driver, Managers | Portion the cheese by the cheese card (within ±10%). The pour speeds up the longer you hold. |
| Toppings (make-line) | CSR, Driver, Managers | Any toppings, no targets on screen: go by the order screen and the portions card. Then put it on the ready rack, or load it straight into the oven. |
| Load Oven (ready rack) | CSR, Driver, Managers | Finished pizzas wait on the 15-slot ready rack at the end of the make-line. Click one to load it into the next free oven slot. |
| Ovens | — | Three stacked stainless conveyor ovens, two lanes each (slots 1-6). Pizzas bake in real time (2 minutes end to end); watch them go by through the door windows. One can be pulled the moment it comes out into the open, and it **falls off the end of the belt if nobody pulls it in time**. |
| Cut & Box (oven tender) | CSR, Driver, Managers | Click any pizza at an oven exit, click the right box on the table (click another to move it), pop bubbles, rock the blade through even cuts, season the crust by tracing it, close the lid. |
| Heat Rack | Driver, Managers | Pick an order from the heat rack queue, grab the bag, drive your topper car to the house, walk it to the door. Faster = bigger tip. |
| Supply Truck | Managers | Put away cases on the matching shelves. Makers get blocked when an ingredient runs out. |

**The make-line is free-form.** Pizzas aren't tied to an order while they're being made: sauce any skin, cheese it, top it, and it goes on the 15-slot ready rack at the end of the make-line (toppings won't start a new pizza while the rack is full). At the **Load Oven** station, click a pizza on the rack to load it into the next free oven slot; that's when it's matched to an order and its toppings are scored against it. How it's matched is a per-player setting on the Stations bar (tentative): **auto-match** (the oldest order waiting on that size whose recipe best fits), or **pick the order** yourself. A pizza no order needs bakes as an extra. Once all of an order's pizzas are loaded, its ticket leaves the make-line (loaded ones are struck through with a green ✓ until then). **Load time** is order placed → last pizza in the oven; **total time** is order placed → last pizza boxed.

Stations are always open: walk up (or use the **Stations** tab, bottom left) and you **stay at that station** in a fixed first-person view, with the pizza dead centre and nothing covering it, until you leave. The next job loads by itself as soon as one is waiting, except at the cut table and heat rack, where you pick each one. The **Stations** tab is collapsed by default; it opens sideways along the bottom into a key per station (a gold badge shows what's waiting), plus Help, Job Aid, the order-matching switch, Exit and Positions. After a step, a **Follow** chip above it takes that pizza to its next station. The work strip at the bottom holds only the controls for the job; the first visit to each station shows a short tip card (Help brings it back). **Tickets** (top left) show the make-line orders at make stations (green, then gold, then red as they wait), every pizza in the ovens by slot at the cut table, and the deliveries at the heat rack. The make stations and cut table have **job aid cards** (on the make-line they stand on top, out of the way); click one or press **Job Aid** on the Stations bar to read it up close. Space, a left click, or a tap on the screen all work as the action button.

- **Pay and XP:** every task pays coins × quality (toppings are paid when the pizza is loaded and matched). CSRs earn the most XP; drivers earn less XP but get delivery tips (bigger orders, bigger tips). Carryout tips are smaller and split among whoever made the order.
- **Management:** 4 Shift Manager slots and 1 General Manager slot per store, filled by highest XP.
- **Sales:** each store gets a weekly forecast ($25k–$30k) split across days and dayparts. The sales board in the back office shows today and this week vs. forecast, average ticket, and average load and total times. Orders beyond what the staff on shift can handle go to an off-screen crew.
- **Franchise:** at level 8 with 15,000 coins, buy a lot north of HQ and name your store. It opens whenever you're in a server; you get 50% of every sale there plus a 20% royalty on your workers' pay.

All balance numbers live in `src/shared/Config.luau`. Portions other than Large Pepperoni, and the cheese ounces, are placeholders.

## Develop
```bash
rojo serve
```
In Studio, open the place, click **Connect** in the Rojo plugin, and press Play. The map is built from code at runtime (the default Baseplate is removed automatically). Rojo lives at `%USERPROFILE%\.rojo\bin\rojo.exe`; add that folder to your PATH or use the full path.

If Studio shows something the code no longer does, the Rojo plugin has disconnected and Studio is running old scripts. Reconnect.

## Ship checklist
1. File → Publish to Roblox (create a new experience).
2. Game Settings → Security → **Enable Studio Access to API Services** (needed for saving).
3. Game Settings → Permissions → Public. Add an icon, thumbnails, and a description.
4. Optional: create a "2x Pay" game pass and put its ID in `Config.GamePasses.DoublePay`.
5. Test with 2–3 players (Test → Clients and Servers): register → dough → sauce → make-line → load → oven → cut → carryout and delivery.

## Swapping in real models
Station visuals are generated by `src/server/StationArt.luau`. To replace one with a Creator Store or custom model:
1. In Studio, create a folder `ServerStorage/StationModels` (Rojo doesn't manage ServerStorage, so it's saved in the place file).
2. Put a Model in it, named after the piece: `Register`, `DoughTable`, `MakeLine`, `ReadyRack`, `Oven`, `CutTable`, `DeliveryRack`, `Pickup`, `Fridge`, `SupplyTruck`. (The dough table carries the Stretch + Sauce stations; the make-line carries Cheese + Toppings; the ready rack carries Load Oven. Their work spots come from `StationArt.Layout`.)
3. Set the model's pivot to its **bottom center**, with the pivot's front (blue arrow / LookVector) pointing **toward where the worker stands** (for the oven: toward its exit end, where the oven tender is). Scale it to roughly the generated station's footprint.

The model replaces the generated art in the HQ and every franchise. Prompts and gameplay sit on an invisible hitbox, so they're unaffected, but some stations expose named parts that gameplay uses. Keep these if you want the feature:
- `Oven`: `OvenIn_1` … `OvenIn_6` and `OvenOut_1` … `OvenOut_6` parts (a pizza's center at the start and end of each lane; slots 1-2 top oven, 3-4 middle, 5-6 bottom), and `OvenMouthIn_<n>` / `OvenMouthOut_<n>` where each lane enters and leaves the bake chamber (pizzas brown between them and can be pulled once past the exit mouth).
- `CutTable`: `Box_Small` / `Box_Medium` / `Box_Large` parts with `BoxSize` and `WallHeight` attributes, `Lid_<Size>` parts with an `OpenAngle` attribute, and a `CutLanding` part (where a pulled pizza waits).
- `DoughTable`: `SkinSlot_1` … `SkinSlot_30` parts where each rack screen rests (rack 1 top to bottom, then rack 2).
- `MakeLine`: `SaucedQueue` and `CheesedQueue` parts where pizzas wait for cheese and toppings.
- `ReadyRack`: `ReadySlot_1` … `ReadySlot_15` parts where each screen rests (top first).
- Job aid cards: any part with a `JobAid` attribute set to its station (`Sauce`, `Cheese`, `Toppings`, `CutTable`) can be clicked to read up close.
- `Fridge`: a SurfaceGui named `StockBoard` with a TextLabel named `Text`.

## Layout
- `src/shared/` – `Config` (all tuning), `Remotes`, `GameClock`, `Pizza3D` (3D pizza builder used on both sides), `Style` + `Icons` (the store-systems UI look and code-drawn icons, used by the HUD and in-world screens), `TicketRows` (groups an order's pizzas into ticket rows)
- `src/server/` – `MapBuilder` + `StationArt` (the world, job aid cards), `Screens` (kitchen display, order tracker, stock tablet, sales board), `ShopService` (orders, pizzas, ovens, stations, scoring, pay), `SalesPlan` + `ClockService` (forecast and clock), `CarService`, `FranchiseService`, `DataService`
- `src/client/` – `Main.client` (HUD, menus, delivery waypoint), `StationMode` (staying at a station between jobs), `StationPicks` (clicking job aids and pizzas in the world), `Loading` (loading pizzas, order-matching setting), `WorkHud` (tickets, Stations tab and bar, follow chip, Clock In), `StationTips` (first-visit tip cards), `Prompts` (interaction prompts), `Minigames` (register, supply truck), `Minigames3D` + `Workstation` (first-person pizza stations and their work strips, fixed station cameras), `Driving`, `Ui` (the UI toolkit)
