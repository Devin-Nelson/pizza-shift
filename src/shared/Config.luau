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

-- There are no roles: every player at a store can work every station, the
-- truck and deliveries included (deliveries need the store to take them, see
-- Config.Store.DeliveryMinPlayers).

-- Work stations as the HUD shows them, in workflow order. `stage` is the stage
-- of the pizzas a station works (pizzas waiting there are in that stage).
-- `stay`: you stay at the station between jobs (first-person view) until you
-- leave or switch stations. The next job loads as soon as one is waiting,
-- unless the station is `pick`: there the player picks each job (a pizza at
-- the oven exit, an order on the heat rack). `queue`: the HUD queue panel shown
-- there ("make" = the make-line order queue, "oven", "delivery").
Config.Stations = {
	{ id = "Register", label = "Register", stay = true },
	{ id = "Dough", label = "Stretch", stay = true, queue = "make" },
	{ id = "Sauce", label = "Sauce", stay = true, queue = "make" },
	{ id = "Cheese", label = "Cheese", stage = "Sauced", stay = true, queue = "make" },
	{ id = "Toppings", label = "Toppings", stage = "Cheesed", stay = true, queue = "make" },
	{ id = "Load", label = "Load Oven", stay = true, pick = true, queue = "make" },
	{ id = "CutTable", label = "Cut & Box", stage = "Exit", stay = true, pick = true, queue = "oven" },
	{ id = "DeliveryRack", label = "Heat Rack", stay = true, pick = true, queue = "delivery" },
	{ id = "SupplyTruck", label = "Truck" },
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

-- Real seconds between finishing a job at a station and the next one loading.
Config.NextJobDelay = 0.8

-- Fixed first-person camera at each station, relative to its work spot (studs):
-- `height` above it, `back` toward the worker, `side` to the worker's right;
-- it aims at the spot, nudged by `focusBack` / `focusUp`. `stand`: how far
-- from the spot the character stands. Every visit looks the same, whatever
-- the character's size or where they walked up from.
Config.StationView = {
	-- Make stations aim straight at the work spot so the pizza sits dead centre
	-- on screen (user: no UI may cover it, and it must be the centre of focus).
	Default = { height = 2.9, back = 1.75, focusBack = 0, fov = 70, stand = 1.9 }, -- looking down ~59 degrees at the pizza
	-- Make-line spots: the grate is deep, so the work spot sits further back from
	-- the front; stand back far enough to clear the cabinet.
	Cheese = { height = 2.9, back = 1.75, focusBack = 0, fov = 70, stand = 2.6 },
	Toppings = { height = 2.9, back = 1.75, focusBack = 0, fov = 70, stand = 2.6 },
	-- Load: facing the ready rack, high enough to see down onto every slot.
	Load = { height = 2.8, back = 5.0, focusUp = -0.3, fov = 70, stand = 2.6 },
	-- Cut table: wide, from behind the oven tender: all six oven exits and the open boxes.
	CutTable = { height = 5.0, back = 7.0, side = -2.0, focusUp = 0.5, fov = 75, stand = 3.4 },
	Register = { height = 1.6, back = 2.2, side = 1.2, focusBack = -4, focusUp = 0.4, fov = 70, stand = 2.8 }, -- over the POS, out to the customers
	DeliveryRack = { height = 1.2, back = 4.5, focusUp = 1.0, fov = 70, stand = 3.0 }, -- facing the heat rack shelves
}
-- Close-up of a job aid card when you click it at a station (studs in front of the card).
Config.JobAidView = { distance = 2.4, fov = 60 }

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

-- Every pizza gets sauce + cheese; these are its toppings.
Config.Recipes = {
	Cheese = {},
	Pepperoni = { "Pepperoni" },
	Hawaiian = { "Ham", "Pineapple" },
	Veggie = { "Peppers", "Mushrooms", "Olives" },
	Supreme = { "Pepperoni", "Peppers", "Mushrooms", "Olives" },
}
Config.PizzaOrder = { "Cheese", "Pepperoni", "Hawaiian", "Veggie", "Supreme" }

Config.Sizes = { "Small", "Medium", "Large" }
Config.SizePrice = { Small = 10, Medium = 14, Large = 17 } -- dollars; store sales are tracked in these
-- Real pizza sizes (10" / 12" / 14"), scaled so a Large is 2.4 studs across.
Config.PizzaInches = { Small = 10, Medium = 12, Large = 14 }
Config.StudsPerInch = 2.4 / 14
Config.PizzaDiameter = {}
Config.BoxSize = {} -- box footprint: a little bigger than the pizza
for size, inches in Config.PizzaInches do
	Config.PizzaDiameter[size] = inches * Config.StudsPerInch
	Config.BoxSize[size] = Config.PizzaDiameter[size] + 0.15
end

-- Topping portions (piece counts) by size, for pizzas with
-- { 1 topping, 2-3 toppings, 4+ toppings }. Large Pepperoni is the spec;
-- everything else is a PLACEHOLDER to be fleshed out.
Config.Portions = {
	Pepperoni = { Small = { 20, 16, 12 }, Medium = { 30, 24, 18 }, Large = { 40, 32, 24 } },
	Ham = { Small = { 12, 10, 8 }, Medium = { 18, 14, 11 }, Large = { 24, 19, 14 } },
	Pineapple = { Small = { 12, 10, 8 }, Medium = { 18, 14, 11 }, Large = { 24, 19, 14 } },
	Peppers = { Small = { 14, 11, 8 }, Medium = { 21, 17, 13 }, Large = { 28, 22, 17 } },
	Mushrooms = { Small = { 14, 11, 8 }, Medium = { 21, 17, 13 }, Large = { 28, 22, 17 } },
	Olives = { Small = { 18, 14, 11 }, Medium = { 27, 22, 16 }, Large = { 36, 29, 22 } },
}
Config.CheesePortion = { Small = 4, Medium = 6, Large = 8 } -- ounces (PLACEHOLDER)
Config.PortionTolerance = 0.10 -- within ±10% = no penalty

function Config.ToppingTier(count: number): number
	return if count <= 1 then 1 elseif count <= 3 then 2 else 3
end

function Config.PortionFor(topping: string, size: string, toppingCount: number): number
	local bySize = Config.Portions[topping]
	local tiers = bySize and bySize[size]
	return if tiers then tiers[Config.ToppingTier(toppingCount)] else 0
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
	Presses = { Small = 6, Medium = 8, Large = 10 },
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
-- The ready rack at the end of the make-line: finished pizzas wait on its
-- screens to be loaded. A toppings job only starts if there's a slot for it.
Config.ReadyRack = { Slots = 15 }
-- Cut & box: slices per size (cuts = slices / 2), chance of cheese bubbles to
-- pop, how fast the rocker blade spins (degrees/second) and how long a cut
-- takes, and how many sectors of crust the seasoning is scored over.
Config.Cut = { Slices = { Small = 6, Medium = 8, Large = 8 }, BubbleChance = 0.6, MaxBubbles = 3, SpinSpeed = 220, CutTime = 0.3, SeasonSectors = 24 }
-- Supply truck: crates per run and how much each restocks.
Config.Supply = { Crates = 5, RestockPerCrate = 12 }
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
	Supply = 25,
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

-- How much of the order flow a store's crew (its players) gets. Orders that
-- would exceed this many open pizzas per worker are handled by the off-screen
-- crew (they still count as store sales).
Config.Crew = { PizzasPerWorker = 4 }

---------------------------------------------------------------------------
-- Stores, monetization
---------------------------------------------------------------------------

Config.Shop = {
	StartingStock = 20,
	MaxStock = 60,
	MaxCustomers = 6, -- NPCs in the lobby at once
	CustomerPatience = 300, -- real seconds for a 1-pizza order (the bake alone is ~90 s)...
	PatiencePerPizza = 75, -- ...plus this much per extra pizza (big orders take a while)
	AutoRegisterDelay = 12, -- online kiosk takes an order if no one answers (x3 while a player is at the store)
	AutoRestockInterval = 20, -- trickle restock (up to StartingStock); the truck fills to MaxStock
	AutoRestockAmount = 2,
}

-- Store slots: each server has Slots lots (the first is the old HQ site).
-- A player opens their own store on a free lot or joins one with room.
-- The owner earns SaleCut of every completed sale there and OwnerRoyalty on
-- every other worker's pay (paid by the house, not deducted). When the owner
-- leaves, the longest-serving worker takes over with their own store.
-- Delivery orders only come in with DeliveryMinPlayers players at the store
-- or a hired driver; otherwise they arrive as carryout.
Config.Store = {
	MaxPlayers = 4,
	SaleCut = 0.5,
	OwnerRoyalty = 0.2,
	DeliveryMinPlayers = 2,
}

-- Set these after creating the products on the Creator Dashboard. 0 = disabled.
Config.GamePasses = {
	DoublePay = 0,
}

-- Saves: a server holds a player's save while they're in it (session lock).
-- LockTTL: seconds after which a lock counts as left behind by a dead server;
-- LoadTries: tries (waiting 1, 2, 3... s) before taking over a held save.
Config.Save = { LockTTL = 300, LoadTries = 5 }

return Config
