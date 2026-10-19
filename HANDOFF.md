# Handoff (2026-10-19)

Read `CLAUDE.md` first (architecture, conventions, every design decision). This file is the state of play.

## Done (all pushed to `main`)
- **Gameplay rounds 1-3** (2026-10-17): stay-at-station mode, free-form make-line with load-time order matching (Auto/Pick), ready rack + Load Oven, three stacked real-time ovens (6 slots), oven tender flow (pull at exit, box in world, rocker cuts, seasoning), dough QTE, endless-spoodle sauce, job aid cards, heat rack + delivery, load/total times.
- **UI overhaul** (2026-10-19, 5 batches, user-approved mockups): "store systems" look (`Style`, `Icons`, `Ui`); status pill; order tickets top-left; collapsible Stations tab/bar; controls-only work strips with the dough gauge inside; first-visit tip cards (saved per player); make-station cameras centred on the pizza; restyled menus, Register (POS), Supply; in-world screens (`Screens.luau`: kitchen display, order tracker, stock tablet, sales board); custom prompts (`Prompts.luau`); brand fonts on printed text. Dough sizes job aid removed (user).
- **Audit fixes 1-4** (`b1e2053`): truck job can't be farmed; franchise purchase can't double-charge; DataStore session lock (specced); carryout patience 300 s.
- Tooling: `lune run tests/specs` (36 specs), `selene src` (0/0), `rojo build`.

## In progress
- Nothing mid-edit. The working tree is clean.
- The user said this session would include **mechanics changes, new mechanics and a visual overhaul**; only the UI part is done. The mechanics list hasn't been given yet.

## Not verified
- The user has **not** hand-playtested the new UI. Claude checked it with scripted Studio runs and screenshots only.
- The save lock only runs in a published game (Studio has API access off, so it plays unsaved).
- Multi-player behaviour hasn't been run.

## Known bugs / open findings (from the 2026-10-19 audit; numbers match that report)
5. Auto-match puts a pizza on an order with a different recipe (`ShopService` `matchTicket`); fix needs the user's rule call (only exact recipe matches?).
6. Pay/scoring rules (`itemAccuracy`, `matchScore`, `toppingAccuracy`, cut evenness, `Config.PortionFactor`) have no specs.
7. Register accepts up to 40 pizzas for any order (cheat scripts can flood the make-line); cap at the order size + a margin.
8. `ShopService.luau` is ~3,000 lines doing ~10 jobs; split ovens and customers out first.
9. Duplicate formatters (`formatMinutes` vs `Style.clock`; two thousands-separator copies).
10. Dead code: `Ui.Style`, `Ui.Toasts`, `Icons.has`, the `exit` icon, `Style.Font.BodyBold`, shop `id`/`nextShopId`, `WorkHud.Init`'s `_isBusy`.
11. Dough/ready racks rebuild every part and re-search markers on each change (slow-ish, not broken).
12. Topping names show only on hover, so touch players see icons only.
- Also: the Stations tab sits in the mobile thumbstick zone; the Follow chip disappears after 12 s; extras are paid as "Sloppy"; the 120 s bake is the whole belt (~90 s until pullable); a solo CSR sees few orders (deliveries need a driver).

## Exact next step
Ask the user to playtest the new UI in Studio (`rojo serve` in this folder, Connect in the Rojo plugin, play a shift) and send screenshots of anything off. Then get their list of mechanics changes / new mechanics, plan it into batches for approval, and continue the session's workflow: commit + push each batch after build, lint and specs pass, plus a scripted Studio run.
