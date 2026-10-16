--!strict
-- Central tuning for Dominus Pizza. Everything balance-related lives here.
-- Store operations are modeled on a delivery-first pizza chain: orders mostly
-- come in by phone/online, dough is stretched ahead of time, pizzas run down a
-- make-line into a conveyor oven, get cut and boxed, then go out with drivers
-- in topper-signed cars.

local Config = {}

Config.GameName = "Dominus Pizza"

-- Our own brand identity (deliberately not any real chain's trade dress).
Config.Brand = {
	Red = Color3.fromRGB(214, 48, 39),
	Charcoal = Color3.fromRGB(38, 40, 46),
	Cream = Color3.fromRGB(250, 240, 225),
	Gold = Color3.fromRGB(255, 190, 60),
}

---------------------------------------------------------------------------
-- Jobs
---------------------------------------------------------------------------

-- `stations` lists the station kinds a job may use; xpMult scales XP per task.
-- Tips follow the order instead of the job: delivery tips go to the driver,
-- carryout tips are split among the insiders who made it.
-- CSRs run the store (phones, counter, every make step, cut table) and level
-- fastest. Drivers can do everything a CSR does plus deliveries: less XP, more
-- tip cash. Managers can work every station, including unloading the truck.
local KITCHEN = { "Register", "Dough", "Sauce", "Cheese", "Toppings", "CutTable" }
local DRIVER = table.clone(KITCHEN)
table.insert(DRIVER, "DeliveryRack")
local EVERYTHING = table.clone(DRIVER)
table.insert(EVERYTHING, "SupplyTruck")

Config.Jobs = {
	CSR = { display = "CSR", color = Color3.fromRGB(52, 152, 219), stations = KITCHEN, xpMult = 1.5 },
	Delivery = { display = "Delivery Driver", color = Color3.fromRGB(46, 204, 113), stations = DRIVER, xpMult = 0.6 },
	ShiftManager = { display = "Shift Manager", color = Color3.fromRGB(155, 89, 182), stations = EVERYTHING, xpMult = 1.2, management = true },
	GeneralManager = { display = "General Manager", color = Color3.fromRGB(230, 126, 34), stations = EVERYTHING, xpMult = 1.2, management = true },
}
Config.JobOrder = { "CSR", "Delivery", "ShiftManager", "GeneralManager" }

-- Management: finite slots per store, filled by XP. If nobody at the store holds
-- a management role, anyone may step up; otherwise minLevel applies, and when
-- every slot is taken a higher-XP player bumps the lowest-XP holder.
Config.Management = {
	ShiftManager = { slots = 4, minLevel = 5 },
	GeneralManager = { slots = 1, minLevel = 10 },
}

-- Jobs allowed to use `station`, in JobOrder.
function Config.JobsWithStation(station: string): { string }
	local list = {}
	for _, name in Config.JobOrder do
		if table.find(Config.Jobs[name].stations, station) then
			table.insert(list, name)
		end
	end
	return list
end

-- Jobs flagged as management, in JobOrder.
function Config.ManagementJobs(): { string }
	local list = {}
	for _, name in Config.JobOrder do
		if Config.Jobs[name].management then
			table.insert(list, name)
		end
	end
	return list
end

-- Work stations as the HUD shows them, in workflow order. `stage` is the
-- ticket stage a station works (stations without one don't work tickets).
Config.Stations = {
	{ id = "Register", label = "Register" },
	{ id = "Dough", label = "Stretch" },
	{ id = "Sauce", label = "Sauce", stage = "Sauce" },
	{ id = "Cheese", label = "Cheese", stage = "Cheese" },
	{ id = "Toppings", label = "Toppings", stage = "Toppings" },
	{ id = "CutTable", label = "Cut & Box", stage = "Cut" },
	{ id = "DeliveryRack", label = "Heat Rack" },
	{ id = "SupplyTruck", label = "Truck" },
}

-- The station that works a ticket stage (nil for stages nobody works, like the oven).
function Config.StationForStage(stage: string): string?
	for _, s in Config.Stations do
		if s.stage == stage then
			return s.id
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Menu, ingredients, portions
---------------------------------------------------------------------------

Config.Ingredients = { "Dough", "Sauce", "Cheese", "Pepperoni", "Ham", "Pineapple", "Peppers", "Mushrooms", "Olives" }
Config.Toppings = { "Pepperoni", "Ham", "Pineapple", "Peppers", "Mushrooms", "Olives" }
Config.IngredientColors = {
	Dough = Color3.fromRGB(240, 220, 170),
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
-- of sizes. Presses: rhythm presses per skin.
Config.Dough = { Presses = 6, Racks = 2, SlotsPerRack = 15 }

function Config.RackCapacity(): number
	return Config.Dough.Racks * Config.Dough.SlotsPerRack
end
-- Sauce: one ladle per pizza, spread over a ring/sector grid. Evenness is scored.
Config.Sauce = { Ladle = 100, PourRate = 28, Rings = 3, Sectors = 8, Coverage = 0.86 }
-- Cheese: hold to pour; the pour speeds up the longer you hold.
Config.CheesePour = { StartRate = 1.2, Accel = 2.0, MaxRate = 5 }
-- Conveyor oven: hands-off, consistent bake. FallAfter: real seconds a baked
-- pizza can sit at the end of the belt before it falls off.
Config.Oven = { BakeTime = 18, FallAfter = 25 }
-- Cut & box: slices per size (cuts = slices / 2), chance of cheese bubbles to pop.
Config.Cut = { Slices = { Small = 6, Medium = 8, Large = 8 }, BubbleChance = 0.6, MaxBubbles = 3 }
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
	ClockInEarly = 0.5, -- staff can clock in 30 minutes before opening to prep
	CloseHour = 24,
	StartWeekHour = 9.4, -- new servers start Monday ~9:25 AM, just before clock-in opens
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

-- How much of the order flow players get. Orders that would exceed this many
-- open pizzas per staff member on shift are handled by the off-screen crew
-- (they still count as store sales). With nobody on shift, the crew runs the store.
Config.Crew = { PizzasPerWorker = 4 }

---------------------------------------------------------------------------
-- Store, franchises, monetization
---------------------------------------------------------------------------

Config.Shop = {
	StartingStock = 20,
	MaxStock = 60,
	MaxCustomers = 6, -- NPCs in the lobby at once
	CustomerPatience = 170, -- real seconds for a 1-pizza order...
	PatiencePerPizza = 75, -- ...plus this much per extra pizza (big orders take a while)
	AutoRegisterDelay = 12, -- online kiosk takes an order if no one answers (x3 while staff are on shift)
	AutoRestockInterval = 20, -- trickle restock when no manager is on shift
	AutoRestockAmount = 2,
}

Config.Franchise = {
	Cost = 15000,
	MinLevel = 8,
	OwnerRoyalty = 0.2, -- owner earns 20% of worker pay at their shop (paid by the house, not deducted)
	SaleCut = 0.5, -- owner earns 50% of each completed sale's price
}

-- Set these after creating the products on the Creator Dashboard. 0 = disabled.
Config.GamePasses = {
	DoublePay = 0,
}

return Config
