--!strict
-- Central tuning for Dominus Pizza. Everything balance-related lives here.
-- Store operations are modeled on a delivery-first pizza chain: orders mostly
-- come in by phone/online, dough is stretched ahead of time, pizzas run down a
-- make-line into a conveyor oven, get cut and boxed, then go out with drivers
-- in topper-signed cars.

local Config = {}

Config.GameName = "Dominus Pizza"

-- Our own brand identity (deliberately not any real chain's trade dress).
-- The UI's "store systems" palette builds on it (see Style.luau).
Config.Brand = {
	Red = Color3.fromRGB(214, 48, 39),
	Charcoal = Color3.fromRGB(38, 40, 46),
	Cream = Color3.fromRGB(250, 240, 225),
	Gold = Color3.fromRGB(255, 190, 60),
	RedDark = Color3.fromRGB(168, 35, 28), -- the lip under a red button
	Charcoal2 = Color3.fromRGB(48, 51, 58), -- tiles and keys on a charcoal panel
	Line = Color3.fromRGB(67, 71, 79), -- hairlines between keys and rows
	CreamDim = Color3.fromRGB(201, 191, 176), -- secondary text on charcoal
	Green = Color3.fromRGB(51, 163, 92), -- fresh tickets, good grades, open
	Ink = Color3.fromRGB(29, 30, 34), -- text on cream and gold
	Rule = Color3.fromRGB(227, 214, 194), -- rules between lines on a cream ticket
}

-- UI scale: screens are laid out for this resolution and scaled to fit.
Config.UiReference = Vector2.new(1280, 720)
Config.UiScaleRange = { 0.7, 1.6 }
-- Order tickets turn from green to gold to red as they wait (real seconds).
Config.TicketAge = { Fresh = 120, Aging = 300 }

---------------------------------------------------------------------------
-- Stations and jobs
---------------------------------------------------------------------------

-- There are no roles: every player at a store can work every station,
-- deliveries included (deliveries need the store to take them, see
-- Config.Store.DeliveryMinPlayers) and hired staff can do the same (Config.Staff).

-- Work stations as the HUD shows them, in workflow order. `stage` is the stage
-- of the pizzas a station works (pizzas waiting there are in that stage).
-- `stay`: you stay at the station between jobs (first-person view) until you
-- leave or switch stations. The next job loads as soon as one is waiting,
-- unless the station is `pick`: there the player picks each job (a pizza at
-- the oven exit, an order on the heat rack). `queue`: the HUD queue panel shown
-- there ("make" = the make-line order queue, "oven", "delivery"). `bar`
-- false: not on the HUD's Stations bar (you only get there with a pizza).
-- No Load station for now (the user, 2026-10-23): a topped pizza goes
-- straight into the oven; the ready rack's code stays for a store builder.
Config.Stations = {
	{ id = "Register", label = "Register", stay = true },
	{ id = "Dough", label = "Stretch", stay = true, queue = "make" },
	{ id = "Sauce", label = "Sauce", stay = true, queue = "make" },
	{ id = "Cheese", label = "Cheese", stage = "Sauced", stay = true, queue = "make", bar = false },
	{ id = "Toppings", label = "Toppings", stage = "Cheesed", stay = true, queue = "make", bar = false },
	{ id = "CutTable", label = "Cut & Box", stage = "Exit", stay = true, pick = true, queue = "oven" },
	{ id = "DeliveryRack", label = "Dispatch", stay = true, pick = true, queue = "delivery" }, -- the id predates dispatch (staff stats are saved under it)
}

function Config.StationInfo(id: string): any?
	for _, s in Config.Stations do
		if s.id == id then
			return s
		end
	end
	return nil
end

-- The station that works pizzas in `stage` (nil for stages nobody works, like the oven).
function Config.StationForStage(stage: string): string?
	for _, s in Config.Stations do
		if s.stage == stage then
			return s.id
		end
	end
	return nil
end

-- The make process (everything before the bake), in order. Players follow
-- the top pizza through it by default (ShopService); whoever sauces a pizza
-- always takes it on through cheese and toppings (the user, 2026-10-23). One
-- who parked at one of these with nothing to work is moved back a step
-- (unless someone's at that one: then they wait).
Config.MakeSteps = { "Dough", "Sauce", "Cheese", "Toppings" }

function Config.StepBefore(id: string): string?
	local i = table.find(Config.MakeSteps, id)
	return if i and i > 1 then Config.MakeSteps[i - 1] else nil
end

-- Real seconds between finishing a job at a station and the next one loading.
Config.NextJobDelay = 0.8

-- Fixed first-person camera at each station, relative to its work spot (studs):
-- `height` above it, `back` toward the worker, `side` to the worker's right;
-- it aims at the spot, nudged by `focusBack` / `focusUp` / `focusSide`.
-- `stand`: how far from the spot the character stands. `idle`: the view
-- between jobs, if it differs; `pick`: the dough trays while choosing a ball.
-- Every visit looks the same, whatever the character's size or where they
-- walked up from.
Config.StationView = {
	-- Make stations aim straight at the work spot so the pizza sits dead centre
	-- on screen (user: no UI may cover it, and it must be the centre of focus).
	Default = { height = 2.9, back = 1.75, focusBack = 0, fov = 70, stand = 1.9 }, -- looking down ~59 degrees at the pizza
	-- Stretch: the close-up for stretching; picking a ball, a higher view takes
	-- in the trays (to the worker's right) and the cornmeal.
	Dough = { height = 2.9, back = 1.75, focusBack = 0, fov = 70, stand = 1.9, pick = { height = 6.0, back = 4.0, side = 3.2, focusBack = -0.8, focusSide = 3.4, fov = 70 } },
	-- Make-line spots: the grate is deep, so the work spot sits further back from
	-- the front; stand back far enough to clear the cabinet.
	Cheese = { height = 2.9, back = 1.75, focusBack = 0, fov = 70, stand = 2.6 },
	-- Toppings: a little shallower, so the pans on the rail (picked by clicking)
	-- sit below the tickets at the top of the screen.
	Toppings = { height = 2.6, back = 2.2, focusBack = 0, fov = 70, stand = 2.6 },
	-- Cut table (user, plan v4.1): the tender faces the carryout counter. Between
	-- jobs the camera looks left at the oven exits to pull a pizza; working, it
	-- turns back to the table and its three box stacks (pulled back and over to
	-- the right for the user's bigger table, 2026-10-21, so all three show).
	CutTable = { height = 4.6, back = 3.8, side = 1.6, focusBack = -0.4, focusSide = 1.6, fov = 72, stand = 2.6, idle = { height = 2.4, back = 2.2, side = 0, focusBack = 5.2, focusUp = 0.8, focusSide = -4.9, fov = 72 } },
	Register = { height = 1.6, back = 2.2, side = 1.2, focusBack = -4, focusUp = 0.4, fov = 70, stand = 2.8 }, -- over the POS, out to the customers
	DeliveryRack = { height = 1.0, back = 7.5, focusUp = 0.2, fov = 70, stand = 3.0 }, -- dispatch: the screen and the delivery rack's bags
}

-- Order matching when a finished pizza is loaded into the oven (a per-player
-- setting, tentative while we see which plays better): "Auto" assigns it to
-- the oldest order waiting on that size whose recipe best matches what's on
-- it; "Pick" has the player click the order it's for.
Config.MatchModes = { "Auto", "Pick" }

---------------------------------------------------------------------------
-- Menu, ingredients, portions
---------------------------------------------------------------------------

Config.Ingredients = { "Dough", "Sauce", "Cheese", "Pepperoni", "Ham", "Pineapple", "Peppers", "Mushrooms", "Olives" }
Config.Toppings = { "Pepperoni", "Ham", "Pineapple", "Peppers", "Mushrooms", "Olives" }
Config.IngredientColors = {
	Dough = Color3.fromRGB(234, 222, 186), -- pale cream, like the user's photos of fresh dough
	Sauce = Color3.fromRGB(190, 35, 25),
	Cheese = Color3.fromRGB(255, 225, 120),
	Pepperoni = Color3.fromRGB(165, 35, 35),
	Ham = Color3.fromRGB(240, 160, 160),
	Pineapple = Color3.fromRGB(255, 230, 80),
	Peppers = Color3.fromRGB(50, 150, 50),
	Mushrooms = Color3.fromRGB(200, 185, 160),
	Olives = Color3.fromRGB(35, 35, 35),
}

-- A pizza is a size plus up to MaxToppings toppings on the sauce and cheese
-- (no specialty pizzas, tentatively), listed one by one on the tickets, in
-- Config.Toppings order. Price: the size plus ToppingPrice per topping.
-- Customers pick 0..3 toppings with ToppingCount odds, each topping as
-- likely as its ToppingPopularity.
Config.MaxToppings = 3
-- No Small for now (the user, 2026-10-23): nobody orders or stretches one.
-- The per-size tables below keep Small (and the cut table its Small boxes).
Config.Sizes = { "Medium", "Large" }
Config.SizePrice = { Small = 10, Medium = 14, Large = 17 } -- dollars; store sales are tracked in these
Config.ToppingPrice = { Small = 1.5, Medium = 2, Large = 2.5 }
Config.ToppingCount = { 0.15, 0.40, 0.30, 0.15 } -- odds of 0, 1, 2, 3 toppings
Config.ToppingPopularity = { Pepperoni = 0.32, Ham = 0.12, Pineapple = 0.10, Peppers = 0.14, Mushrooms = 0.18, Olives = 0.14 }
-- Real pizza sizes (10" / 12" / 14"), scaled so a Large is 2.4 studs across.
Config.PizzaInches = { Small = 10, Medium = 12, Large = 14 }
Config.StudsPerInch = 2.4 / 14
Config.PizzaDiameter = {}
Config.BoxSize = {} -- box footprint: a little bigger than the pizza
for size, inches in Config.PizzaInches do
	Config.PizzaDiameter[size] = inches * Config.StudsPerInch
	Config.BoxSize[size] = Config.PizzaDiameter[size] + 0.15
end

-- Topping portions by size, for pizzas with { 1 topping, 2-3 toppings }, from
-- the user's portion chart (10" / 12" / 14"; it groups pepperoni with ham,
-- pineapple and mushrooms with sausage, peppers with olives). Pepperoni and
-- ham are counted in pieces; the rest are weighed in ounces on the make-line
-- scale (each piece put on weighs PieceOz).
Config.CountedToppings = { Pepperoni = true, Ham = true }
Config.PieceOz = { Pineapple = 0.1, Peppers = 0.08, Mushrooms = 0.1, Olives = 0.06 }
Config.Portions = {
	Pepperoni = { Small = { 20, 16 }, Medium = { 30, 24 }, Large = { 40, 32 } },
	Ham = { Small = { 20, 16 }, Medium = { 30, 24 }, Large = { 40, 32 } },
	Pineapple = { Small = { 2.5, 1.5 }, Medium = { 3.5, 2.5 }, Large = { 5, 3.5 } },
	Peppers = { Small = { 1.5, 1 }, Medium = { 2, 1.5 }, Large = { 3, 2 } },
	Mushrooms = { Small = { 2.5, 1.5 }, Medium = { 3.5, 2.5 }, Large = { 5, 3.5 } },
	Olives = { Small = { 1.5, 1 }, Medium = { 2, 1.5 }, Large = { 3, 2 } },
}
Config.CheesePortion = { Small = 3.5, Medium = 5, Large = 7 } -- ounces
Config.PortionTolerance = 0.10 -- within ±10% = no penalty

function Config.ToppingTier(count: number): number
	return if count <= 1 then 1 else 2
end

-- How much of `topping` that many pieces is, in its portion unit (pieces,
-- or ounces for a weighed topping).
function Config.ToppingAmount(topping: string, pieces: number): number
	return if Config.CountedToppings[topping] then pieces else pieces * (Config.PieceOz[topping] or 0.1)
end

-- "40 pcs" / "2.5 oz"
function Config.PortionText(topping: string, amount: number): string
	return if Config.CountedToppings[topping] then string.format("%d pcs", amount) else string.format("%g oz", amount)
end

function Config.PortionFor(topping: string, size: string, toppingCount: number): number
	local bySize = Config.Portions[topping]
	local tiers = bySize and bySize[size]
	return if tiers then tiers[Config.ToppingTier(toppingCount)] else 0
end

-- Pieces that make the portion (what hired staff put on).
function Config.PortionPieces(topping: string, size: string, toppingCount: number): number
	local target = Config.PortionFor(topping, size, toppingCount)
	return if Config.CountedToppings[topping] then target else math.floor(target / (Config.PieceOz[topping] or 0.1) + 0.5)
end

-- The price of one pizza.
function Config.PizzaPrice(size: string, toppings: { string }): number
	return (Config.SizePrice[size] or 0) + (Config.ToppingPrice[size] or 0) * #toppings
end

-- 1 inside the tolerance band, then falls off (0 at 60% off target).
function Config.PortionFactor(actual: number, target: number): number
	if target <= 0 then
		return if actual <= 0 then 1 else 0.5
	end
	local variance = math.abs(actual - target) / target
	if variance <= Config.PortionTolerance then
		return 1
	end
	return math.clamp(1 - (variance - Config.PortionTolerance) * 2, 0, 1)
end

---------------------------------------------------------------------------
-- Stations
---------------------------------------------------------------------------

-- Dough is stretched ahead of time (any size) and stocked on pizza-screen racks:
-- Racks x SlotsPerRack slots in total (2 x 15 = 30), one skin per slot, any mix
-- of sizes. Stretching is a timing game: Presses (by size) hits on a sweeping
-- marker. Each hit, the green zone moves somewhere new and changes width
-- (GreenWidth range, as a fraction of the bar), with a yellow band Yellow wide
-- on each side. Each hit scores Green / YellowScore / MissScore, and grows the
-- skin by that much of a full step (a miss still grows it a little).
Config.Dough = {
	Racks = 2,
	SlotsPerRack = 15,
	Presses = { Small = 3, Medium = 4, Large = 5 },
	TrayBalls = { Small = 10, Medium = 8, Large = 6 }, -- dough balls in a full tray (it refills when emptied)
	GreenWidth = { 0.07, 0.16 },
	Yellow = 0.08,
	YellowScore = 0.45,
	MissScore = 0,
	MissGrowth = 0.25,
}

function Config.RackCapacity(): number
	return Config.Dough.Racks * Config.Dough.SlotsPerRack
end
-- Sauce: an endless spoodle. Scored only on coverage (Rings x Sectors cells
-- inside the sauce line, each needing CoverAmount) and neatness (sauce on the
-- rim outside the line). The sauce line is BorderInches in from the edge on
-- every size. SpoodleRadius: how wide one pass spreads (studs).
Config.Sauce = { PourRate = 30, Rings = 4, Sectors = 16, CoverAmount = 1.2, BorderInches = 0.75, SpoodleRadius = 0.22 }

-- Radius of the sauced area of a pizza of `size` (studs).
function Config.SauceRadius(size: string): number
	return (Config.PizzaDiameter[size] or 2.4) / 2 - Config.Sauce.BorderInches * Config.StudsPerInch
end
-- Cheese: hold to pour; the pour speeds up the longer you hold.
Config.CheesePour = { StartRate = 1.2, Accel = 2.0, MaxRate = 5 }
-- Conveyor ovens: three stacked ovens, two lanes each = slots 1-6 (1-2 top,
-- 3-4 middle, 5-6 bottom). Loading fills slots in order and wraps around; a
-- slot takes a pizza once the last one has moved Gap studs clear of it.
-- BakeTime: real seconds from entrance to exit. FallAfter: real seconds a
-- pizza can sit at the exit before it falls off.
Config.Oven = { BakeTime = 120, FallAfter = 25, Slots = 6, Gap = 0.15 }
-- The ovens' paint (the user, 2026-10-21: silver by default, customizable):
-- the store's owner cycles through these at the oven (saved with them).
-- `metal`: stainless rather than painted.
Config.OvenPaints = {
	{ name = "Silver", color = Color3.fromRGB(140, 145, 152), metal = true },
	{ name = "Blue", color = Color3.fromRGB(34, 58, 168), metal = false },
	{ name = "Red", color = Config.Brand.Red, metal = false },
	{ name = "Charcoal", color = Config.Brand.Charcoal, metal = false },
}
-- The ready rack (not in the store for now: no Load station): finished
-- pizzas waited on its screens to be loaded.
Config.ReadyRack = { Slots = 15 }
-- The carryout rack across the cut table's far end (the user, 2026-10-21):
-- boxed carryout orders wait on it in stacks tagged with the customer's name;
-- the customer steps up to the counter and says it, and someone carries their
-- order over. Slots: stacks it holds (two a tier); MaxStack: boxes shown in a
-- stack on the rack (4 fit under the shelf above; the rest are counted on
-- the name tag, which is on the bottom box: the user, 2026-10-23); in hand
-- every box shows. PickupPatience: real seconds a customer waits once their
-- order is on the rack (doubled, the user, 2026-10-23).
Config.Carryout = { Slots = 6, MaxStack = 4, PickupPatience = 300 }
-- How a waiting customer feels, by the share of their patience used up (the
-- user, 2026-10-23: faces grow angrier, they grumble, and the longer the
-- wait the lower the satisfaction and the tips). `at`: from that share on;
-- `factor`: on the order's satisfaction if it's handed over then.
Config.Moods = {
	{ name = "Happy", at = 0, factor = 1 },
	{ name = "Fine", at = 0.3, factor = 0.9 },
	{ name = "Annoyed", at = 0.55, factor = 0.7 },
	{ name = "Angry", at = 0.8, factor = 0.45 },
}
Config.MoodLines = {
	Annoyed = { "Is it almost ready?", "Taking a while, huh...", "*checks phone*", "Any update on my order?", "Hmm. Still waiting." },
	Angry = { "Seriously?!", "I've been here forever!", "This is ridiculous.", "Where is my pizza?!", "Unbelievable..." },
}

-- The mood for a customer who has used up `share` (0..1+) of their patience.
function Config.MoodAt(share: number): any
	local mood = Config.Moods[1]
	for _, m in Config.Moods do
		if share >= m.at then
			mood = m
		end
	end
	return mood
end
-- The pizza box print (the user's pick, 2026-10-23: "classic white";
-- tools/blender/box_art.py): white board, the lid art and the side band as
-- Image assets (never Decal ids).
Config.BoxPrint = { Board = Color3.fromRGB(238, 235, 226), Lid = 80589939878510, Band = 139609335854778 } -- band_classic_any.png (no size on it)
-- Customers' first names; each gets a last initial ("John P.").
Config.CustomerNames = {
	"John", "Maria", "David", "Aisha", "Chris", "Elena", "Marcus", "Grace", "Tyler", "Sofia",
	"Kevin", "Hannah", "Diego", "Olivia", "Jamal", "Chloe", "Ethan", "Fatima", "Noah", "Lily",
	"Ryan", "Mei", "Lucas", "Nora", "Brandon", "Isabel", "Owen", "Jasmine", "Victor", "Emma",
	"Andre", "Hailey", "Mateo", "Rachel", "Derek", "Yuki", "Caleb", "Megan", "Luis", "Paige",
}
-- Cut & box: slices per size (cuts = slices / 2), chance of cheese bubbles to
-- pop, how fast the rocker blade spins (degrees/second) and how long a cut takes.
Config.Cut = { Slices = { Small = 6, Medium = 8, Large = 8 }, BubbleChance = 0.6, MaxBubbles = 3, SpinSpeed = 220, CutTime = 0.3 }
-- Delivery: real seconds from leaving the rack; full speed bonus under FastTime.
Config.Delivery = { FastTime = 50, SlowTime = 120, WalkSpeed = 20 }
-- Delivery car (arcade handling, client-driven).
Config.Car = { MaxSpeed = 70, ReverseSpeed = 22, Accel = 45, Brake = 90, TurnRate = 1.9 }

---------------------------------------------------------------------------
-- Pay, XP, tips
---------------------------------------------------------------------------

-- Base pay per completed task, multiplied by quality (0..1) with a floor.
Config.Pay = {
	Register = 12,
	Dough = 10,
	Sauce = 7,
	Cheese = 6,
	Toppings = 9,
	Cut = 14,
	Delivery = 35,
}
Config.MinQualityPay = 0.3 -- even a sloppy job earns 30%
Config.XPPerTask = 10

-- Tips as a share of the order total (x customer satisfaction). Bigger orders = bigger tips.
-- Delivery tips go to the driver; carryout ("insider") tips are lower and split among the crew.
Config.Tips = {
	Delivery = { min = 0.10, max = 0.22 },
	Carryout = { min = 0.00, max = 0.08 },
}

function Config.LevelFromXP(xp: number): number
	return math.floor(math.sqrt(xp / 25)) + 1
end

function Config.XPForLevel(level: number): number
	return (level - 1) ^ 2 * 25
end

---------------------------------------------------------------------------
-- Day cycle and sales
---------------------------------------------------------------------------

-- 24-hour game clock. The store is open 10 AM to midnight, every day.
Config.Day = {
	RealSecondsPerHour = 150, -- 1 game hour = 2.5 real minutes (day = 1 hr, week = 7 hrs)
	OpenHour = 10,
	PrepEarly = 0.5, -- stations open 30 minutes before the store does, to prep
	CloseHour = 24,
	StartWeekHour = 9.4, -- new servers start Monday ~9:25 AM, just before prep opens
	DayNames = { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" },
}

-- Sales forecast. Each store draws a weekly total, splits it across days (each
-- day jittered ~3% so no two match), then across dayparts. Orders are generated
-- against that budget, so order count falls out of the (randomized) average ticket.
Config.Sales = {
	Weekly = { min = 25000, max = 30000 },
	DayShares = { 0.10, 0.10, 0.10, 0.15, 0.20, 0.20, 0.15 }, -- Mon..Sun
	DayVariance = 0.03,
	Dayparts = {
		{ name = "Lunch", from = 10, to = 16, share = 0.20 },
		{ name = "Dinner", from = 16, to = 21, share = 0.70 },
		{ name = "Late Night", from = 21, to = 24, share = 0.10 },
	},
	DeliveryShare = 0.6, -- of orders (when a driver can take them)
	OnlineShare = 0.5, -- of orders that skip the phone/register entirely
}

-- Order sizes (pizza count). Small orders are common, medium less so, large rare.
-- Each day re-rolls the mix a little, which moves the average ticket.
Config.OrderSizes = {
	Small = { weight = 0.88, min = 1, max = 4, countWeights = { 0.45, 0.30, 0.15, 0.10 } },
	Medium = { weight = 0.11, min = 5, max = 15 },
	Large = { weight = 0.01, min = 15, max = 30 },
	DailyJitter = 0.25, -- +/- relative change to the medium/large weights per day
	SizeMix = { Small = 0.25, Medium = 0.35, Large = 0.40 }, -- how often each pizza size is ordered
}

---------------------------------------------------------------------------
-- Stores, monetization
---------------------------------------------------------------------------

Config.Shop = {
	StartingStock = 60,
	MaxStock = 60,
	MaxCustomers = 6, -- NPCs in the lobby at once
	CustomerPatience = 600, -- real seconds any order waits with 1 pizza (the bake alone is ~90 s)... (doubled: the user, 2026-10-23)
	PatiencePerPizza = 150, -- ...plus this much per extra pizza (big orders take a while)
	AutoRegisterDelay = 12, -- online kiosk takes an order if no one answers (x3 while a player is at the store)
	-- No supply truck for now: the shelves refill to StartingStock (full) on their own.
	AutoRestockInterval = 20,
	AutoRestockAmount = 60,
}

-- Every forecast order is a real order at the store; nothing is made off-screen.
-- Real seconds a customer waits for an order of `count` pizzas: walk-ins then
-- leave the lobby, and phone, online and delivery orders are cancelled. Either
-- way it's a lost sale.
function Config.OrderPatience(count: number): number
	return Config.Shop.CustomerPatience + Config.Shop.PatiencePerPizza * (math.max(count, 1) - 1)
end

-- Stores: each server has 5 lots (MapBuilder; lot 1 is the old HQ site).
-- A player opens their own store on a free lot or joins one with room.
-- The owner earns SaleCut of every completed sale there and OwnerRoyalty on
-- every other worker's pay (paid by the house, not deducted). When the owner
-- leaves, the longest-serving worker takes over with their own store.
-- Delivery orders only come in with DeliveryMinPlayers players at the store
-- or a team member on shift at the heat rack; otherwise they arrive as carryout.
Config.Store = {
	MaxPlayers = 4,
	SaleCut = 0.5,
	OwnerRoyalty = 0.2,
	DeliveryMinPlayers = 2,
}

-- Hired staff (NPCs), saved with the owner's store. Team members work the
-- station the owner assigns (any of StaffStations; the heat rack makes them a
-- driver) on the shifts the owner schedules, within their availability. Each
-- has a level per station (its stat, StaffStatNames) that rises with XP from
-- jobs done there, a Reliability (chance to call out of a shift) and an
-- Availability (which shifts they can work; all = "open"). The rules are in
-- Staff.luau. Buying hires a random basic member (StaffGen.Buy); the first
-- costs `cost`, each next one `growth` times the last; `max` per store.
-- `flexible` kinds (managers) work several stations at once, as many as their
-- Flexibility stat allows (Config.Flexibility). `hire = "roll"` kinds come
-- from the staff roll (StaffRoll), which isn't live yet (Studio can grant them).
Config.Staff = {
	TeamMember = { display = "Team Member", hire = "buy", cost = 200, growth = 1.25, max = 3 },
	AssistantManager = { display = "Assistant Manager", hire = "roll", max = 2, flexible = true },
	StoreManager = { display = "Store Manager", hire = "roll", max = 1, flexible = true },
}
Config.StaffOrder = { "TeamMember", "AssistantManager", "StoreManager" }
Config.StaffOnShift = 8 -- scheduled per shift
Config.StaffStations = { "Register", "Dough", "Sauce", "Cheese", "Toppings", "CutTable", "DeliveryRack" }
Config.StaffStatNames = {
	Register = "Service",
	Dough = "Stretching",
	Sauce = "Saucing",
	Cheese = "Cheese",
	Toppings = "Topping",
	Load = "Oven",
	CutTable = "Cutting",
	DeliveryRack = "Driving",
}
-- Station levels 1..Max. A level-1 member works at Quality[1] taking Speed[1]
-- times the base time; a maxed one at Quality[2] and Speed[2] (in between,
-- evenly). Jobs to go from level L to L+1: XPBase + XPPerLevel * L.
Config.StaffLevels = { Max = 20, Quality = { 0.5, 0.95 }, Speed = { 1.5, 0.6 }, XPBase = 5, XPPerLevel = 3 }
-- Base seconds per job at each station; a driver's round trip.
Config.StaffWork = {
	WorkTime = { Register = 8, Dough = 10, Sauce = 8, Cheese = 6, Toppings = 10, Load = 3, CutTable = 10 },
	Trip = { 45, 75 },
}
-- Reliability 1..Max; each point short of Max adds CalloutPerPoint to the
-- chance of calling out of a scheduled shift (checked as the shift starts).
Config.Reliability = { Max = 10, CalloutPerPoint = 0.03 }
-- Flexibility 1..Max (managers only): they handle 1 + Flexibility // 2
-- stations comfortably. Each station past that makes every job of theirs
-- Slow slower and Sloppy worse (orders back up, customers leave).
Config.Flexibility = { Max = 10, Slow = 0.5, Sloppy = 0.15 }
-- New hires, by pool (a Staff kind, or "Buy" for bought team members).
-- `levels`: each station's starting level (range); `reliability` (range);
-- `shifts`: odds of being available for 1, 2 or all 3 shifts; `flexibility`
-- (range, managers only).
Config.StaffGen = {
	Buy = { levels = { 1, 3 }, reliability = { 3, 8 }, shifts = { 0.5, 0.4, 0.1 } },
	AssistantManager = { levels = { 3, 6 }, reliability = { 5, 9 }, shifts = { 0.2, 0.5, 0.3 }, flexibility = { 2, 6 } },
	StoreManager = { levels = { 5, 9 }, reliability = { 7, 10 }, shifts = { 0.1, 0.3, 0.6 }, flexibility = { 5, 10 } },
}
Config.StaffNames = { "Maya", "Leo", "Priya", "Sam", "Ines", "Theo", "Rosa", "Kai", "Nadia", "Omar", "June", "Felix", "Ava", "Marco", "Zoe", "Eli", "Lena", "Ravi", "Tess", "Hugo" }
-- The staff roll (spin): odds per kind (summing to 1) and the coins per roll.
-- Not live until Enabled. Still to design: duplicates, what managers do,
-- coins vs Robux, and better-stat team members (a StaffGen entry of their own).
Config.StaffRoll = {
	Enabled = false,
	Cost = 2500,
	Odds = { { kind = "AssistantManager", weight = 0.9 }, { kind = "StoreManager", weight = 0.1 } },
}

-- Price of the next hire of `kind` when the store already has `owned` of them.
function Config.HireCost(kind: string, owned: number): number
	local def = Config.Staff[kind]
	return math.floor(def.cost * def.growth ^ owned + 0.5)
end

-- Set these after creating the products on the Creator Dashboard. 0 = disabled.
Config.GamePasses = {
	DoublePay = 0,
}

-- Saves: a server holds a player's save while they're in it (session lock).
-- LockTTL: seconds after which a lock counts as left behind by a dead server;
-- LoadTries: tries (waiting 1, 2, 3... s) before taking over a held save.
Config.Save = { LockTTL = 300, LoadTries = 5 }

return Config
