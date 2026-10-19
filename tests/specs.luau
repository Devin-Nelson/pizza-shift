-- Headless specs for pizza-shift's pure modules (Config, GameClock, SalesPlan).
-- Loads the real files from disk with Roblox datatypes from @lune/roblox and
-- tiny stubs for game/script/require/Random. Run from the repo root:
--   lune run tests/specs
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local process = require("@lune/process")

local repo = process.args[1] or process.cwd

-- Deterministic Random stand-in (Park-Miller), same surface the game uses.
local Random = {}
Random.__index = Random
function Random.new(seed: number?)
	return setmetatable({ s = math.max(1, math.floor((seed or 1) % 2147483646)) }, Random)
end
function Random:_next(): number
	self.s = (self.s * 48271) % 2147483647
	return self.s / 2147483647
end
function Random:NextNumber(a: number?, b: number?): number
	local u = self:_next()
	if a == nil then
		return u
	end
	return a + (b - a) * u
end
function Random:NextInteger(a: number, b: number): number
	return a + math.floor(self:_next() * (b - a + 1))
end

local CONFIG = newproxy()
local Config

local function load(path: string, extra: { [string]: any })
	local env = {
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Enum = roblox.Enum,
		NumberRange = roblox.NumberRange,
		BrickColor = roblox.BrickColor,
		Font = roblox.Font,
		Random = Random,
		require = function(target)
			if target == CONFIG then
				return Config
			end
			error("unexpected require: " .. tostring(target))
		end,
	}
	for k, v in extra do
		env[k] = v
	end
	local chunk = luau.load(fs.readFile(repo .. "/" .. path), { debugName = path, environment = env })
	return chunk()
end

local attrs = {}
local ReplicatedStorage = {
	Shared = { Config = CONFIG },
	GetAttribute = function(_, name)
		return attrs[name]
	end,
}
local game = {
	GetService = function(_, name)
		assert(name == "ReplicatedStorage", "unexpected service " .. name)
		return ReplicatedStorage
	end,
}

Config = load("src/shared/Config.luau", { script = { Parent = {} }, game = game })
local GameClock = load("src/shared/GameClock.luau", { script = { Parent = { Config = CONFIG } }, game = game })
local SalesPlan = load("src/server/SalesPlan.luau", { script = { Parent = {} }, game = game })
local Style = load("src/shared/Style.luau", { script = { Parent = { Config = CONFIG } }, game = game })

local specs: { { string | () -> () } } = {}
local function spec(name: string, fn: () -> ())
	table.insert(specs, { name, fn })
end
local function eq(got, want, what: string?)
	if got ~= want then
		error(string.format("%s: expected %s, got %s", what or "value", tostring(want), tostring(got)), 2)
	end
end
local function near(got: number, want: number, what: string?)
	if math.abs(got - want) > 1e-6 then
		error(string.format("%s: expected ~%s, got %s", what or "value", tostring(want), tostring(got)), 2)
	end
end
local function sum(t: { number }): number
	local s = 0
	for _, v in t do
		s += v
	end
	return s
end

----------------------------------------------------------------- Config wiring
spec("every station a job can work is defined in Config.Stations", function()
	for job, info in Config.Jobs do
		for _, id in info.stations do
			assert(Config.StationInfo(id), job .. " lists unknown station " .. id)
		end
	end
end)

spec("every StationView entry is a real station (or Default)", function()
	for id in Config.StationView do
		assert(id == "Default" or Config.StationInfo(id), "StationView has unknown station " .. id)
	end
end)

spec("each pizza stage is worked by the right station", function()
	eq(Config.StationForStage("Sauced"), "Cheese", "Sauced")
	eq(Config.StationForStage("Cheesed"), "Toppings", "Cheesed")
	eq(Config.StationForStage("Exit"), "CutTable", "Exit")
	eq(Config.StationForStage("Oven"), nil, "Oven (nobody works it)")
end)

spec("every station a player stays at is a stay station, with a known queue panel", function()
	local panels = { make = true, oven = true, delivery = true }
	for _, s in Config.Stations do
		if s.queue then
			assert(panels[s.queue], s.id .. " has unknown queue " .. s.queue)
			assert(s.stay, s.id .. " shows a queue but is not a stay station")
		end
	end
end)

spec("every size has dough presses, slices, price, inches, cheese, diameter and box", function()
	for _, size in Config.Sizes do
		for _, key in { "SizePrice", "PizzaInches", "CheesePortion", "PizzaDiameter", "BoxSize" } do
			assert(Config[key][size] ~= nil, key .. " missing " .. size)
		end
		assert(Config.Dough.Presses[size], "Dough.Presses missing " .. size)
		assert(Config.Cut.Slices[size], "Cut.Slices missing " .. size)
	end
end)

spec("bigger pizzas take more dough presses (6 / 8 / 10)", function()
	local P = Config.Dough.Presses
	assert(P.Small < P.Medium and P.Medium < P.Large, "presses must grow with size")
	eq(P.Small, 6, "Small")
	eq(P.Medium, 8, "Medium")
	eq(P.Large, 10, "Large")
end)

spec("the dough timing zone is a sane fraction of the bar", function()
	local g = Config.Dough.GreenWidth
	assert(0 < g[1] and g[1] < g[2] and g[2] < 1, "GreenWidth must be 0 < min < max < 1")
	assert(g[2] + 2 * Config.Dough.Yellow < 1, "green + yellow bands must fit on the bar")
end)

spec("every recipe topping is a portioned, colored topping for every size", function()
	for _, name in Config.PizzaOrder do
		local recipe = Config.Recipes[name]
		assert(recipe, "PizzaOrder has unknown recipe " .. name)
		for _, top in recipe do
			assert(table.find(Config.Toppings, top), name .. " uses non-topping " .. top)
			for _, size in Config.Sizes do
				local p = Config.Portions[top] and Config.Portions[top][size]
				assert(p and #p > 0, "no portion for " .. size .. " " .. top)
			end
		end
	end
	for _, ing in Config.Ingredients do
		assert(Config.IngredientColors[ing], "no color for " .. ing)
	end
end)

spec("capacities match the store design (30 skins, 15 ready, 6 oven slots, 2 min bake)", function()
	eq(Config.RackCapacity(), 30, "dough rack capacity")
	eq(Config.ReadyRack.Slots, 15, "ready rack")
	eq(Config.Oven.Slots, 6, "oven slots (3 ovens x 2 lanes)")
	eq(Config.Oven.BakeTime, 120, "bake time")
end)

spec("the sauce line is 3/4 inch in on every size and inside the pizza", function()
	eq(Config.Sauce.BorderInches, 0.75, "BorderInches")
	for _, size in Config.Sizes do
		local r = Config.SauceRadius(size)
		local edge = Config.PizzaDiameter[size] / 2
		assert(r > 0 and r < edge, size .. " sauce radius " .. r .. " not inside the pizza edge " .. edge)
		near(edge - r, 0.75 * Config.StudsPerInch, size .. " border in studs")
	end
end)

spec("the order-matching setting offers Auto and Pick", function()
	assert(table.find(Config.MatchModes, "Auto") and table.find(Config.MatchModes, "Pick"), "MatchModes")
end)

------------------------------------------------------------------ Sales config
spec("dayparts tile the open hours exactly and their shares sum to 1", function()
	local parts = Config.Sales.Dayparts
	eq(parts[1].from, Config.Day.OpenHour, "first daypart start")
	eq(parts[#parts].to, Config.Day.CloseHour, "last daypart end")
	for i = 2, #parts do
		eq(parts[i].from, parts[i - 1].to, "gap between dayparts " .. (i - 1) .. " and " .. i)
	end
	local s = 0
	for _, p in parts do
		s += p.share
	end
	near(s, 1, "daypart shares")
end)

spec("day shares cover 7 days and sum to 1", function()
	eq(#Config.Sales.DayShares, 7, "days")
	near(sum(Config.Sales.DayShares), 1, "day shares")
end)

spec("order-size tiers are consistent (1..30 pizzas)", function()
	local O = Config.OrderSizes
	near(O.Small.weight + O.Medium.weight + O.Large.weight, 1, "tier weights")
	eq(#O.Small.countWeights, O.Small.max - O.Small.min + 1, "Small countWeights length")
	eq(O.Small.min, 1, "smallest order")
	eq(O.Large.max, 30, "largest order")
	local mix = 0
	for _, w in O.SizeMix do
		mix += w
	end
	near(mix, 1, "SizeMix")
end)

--------------------------------------------------------------------- GameClock
spec("store is open 10 AM up to (not including) midnight", function()
	eq(GameClock.isOpen(9.99), false, "9:59")
	eq(GameClock.isOpen(10), true, "10:00")
	eq(GameClock.isOpen(23.99), true, "23:59")
	eq(GameClock.isOpen(24), false, "midnight")
end)

spec("clock-in opens at 9:30 AM", function()
	eq(GameClock.canClockIn(9.49), false, "9:29")
	eq(GameClock.canClockIn(9.5), true, "9:30")
	eq(GameClock.hoursUntilClockIn(0), 9.5, "from midnight")
	eq(GameClock.hoursUntilClockIn(9.5), 0, "at 9:30")
	near(GameClock.hoursUntilClockIn(24 + 6), 3.5, "Tuesday 6 AM")
end)

spec("a fresh server starts just before clock-in", function()
	attrs.WeekHour = nil
	eq(GameClock.weekHour(), Config.Day.StartWeekHour, "default week hour")
	eq(GameClock.canClockIn(), false, "can clock in at start")
	assert(GameClock.hoursUntilClockIn() < 0.25, "clock-in should be minutes away")
end)

spec("split maps week hours to Mon..Sun", function()
	local d, h = GameClock.split(0)
	eq(d, 1, "day of hour 0")
	eq(h, 0, "hour of hour 0")
	d, h = GameClock.split(167.5)
	eq(d, 7, "day of hour 167.5")
	eq(h, 23.5, "hour of hour 167.5")
end)

spec("times format like a wall clock", function()
	eq(GameClock.format(0), "12:00 AM", "0")
	eq(GameClock.format(12.5), "12:30 PM", "12.5")
	eq(GameClock.format(9.5), "9:30 AM", "9.5")
	eq(GameClock.shortTime(10), "10 AM", "short 10")
	eq(GameClock.shortTime(24), "midnight", "short 24")
	eq(GameClock.hoursText(), "open 10 AM to midnight, clock-in from 9:30 AM", "hoursText")
end)

spec("format's documented example: 17.7 reads 5:42 PM", function()
	eq(GameClock.format(17.7), "5:42 PM", "17.7")
end)

spec("every minute of the day formats to itself", function()
	local bad = {}
	for m = 0, 24 * 60 - 1 do
		local hour = m / 60
		local want = string.format("%d:%02d", (math.floor(hour) % 12 == 0) and 12 or math.floor(hour) % 12, m % 60)
		local got = GameClock.format(hour)
		if got:sub(1, #want) ~= want then
			table.insert(bad, string.format("%d min -> %s", m, got))
		end
	end
	assert(#bad == 0, #bad .. " minutes format wrong, e.g. " .. table.concat(bad, "; ", 1, math.min(3, #bad)))
end)

spec("dayparts look up by hour", function()
	eq(GameClock.daypart(12).name, "Lunch", "noon")
	eq(GameClock.daypart(18).name, "Dinner", "6 PM")
	eq(GameClock.daypart(23.9).name, "Late Night", "11:54 PM")
	eq(GameClock.daypart(9), nil, "9 AM (closed)")
end)

--------------------------------------------------------------------- SalesPlan
spec("a week's forecast stays in $25k-$30k and its days add up", function()
	for seed = 1, 300 do
		local wk = SalesPlan.newWeek(Random.new(seed))
		assert(wk.total >= 25000 and wk.total <= 30000, "total " .. wk.total)
		eq(#wk.days, 7, "days")
		near(sum(wk.days), wk.total, "days sum (seed " .. seed .. ")")
	end
end)

spec("the daily mix always leaves room for small orders and sums to 1", function()
	for seed = 1, 500 do
		local mix = SalesPlan.dayMix(Random.new(seed))
		assert(mix.small > 0.5, "small share " .. mix.small)
		near(mix.small + mix.medium + mix.large, 1, "mix sum")
	end
end)

spec("orders are 1 to 30 pizzas, and big ones do happen", function()
	local rng = Random.new(7)
	local mix = SalesPlan.dayMix(rng)
	local lo, hi = math.huge, 0
	for _ = 1, 20000 do
		local n = SalesPlan.rollPizzaCount(mix, rng)
		lo, hi = math.min(lo, n), math.max(hi, n)
	end
	eq(lo, 1, "smallest rolled")
	assert(hi <= 30 and hi >= 15, "largest rolled " .. hi)
end)

spec("party orders repeat at most 3 favorites", function()
	local rng = Random.new(11)
	local mix = { small = 0, medium = 1, large = 0 }
	for _ = 1, 200 do
		local items = SalesPlan.rollItems(mix, rng)
		local kinds = {}
		for _, it in items do
			assert(Config.Recipes[it.pizza] and Config.SizePrice[it.size], "bad item")
			kinds[it.size .. it.pizza] = true
		end
		local n = 0
		for _ in kinds do
			n += 1
		end
		assert(n <= 3, n .. " different pizzas in a party order")
	end
end)

spec("price, share-by-hour and describe", function()
	eq(SalesPlan.price({ { pizza = "Cheese", size = "Large" }, { pizza = "Cheese", size = "Small" } }), 27, "price")
	near(SalesPlan.shareByHour(10), 0, "share at open")
	near(SalesPlan.shareByHour(16), 0.2, "share after lunch")
	near(SalesPlan.shareByHour(24), 1, "share at close")
	eq(
		SalesPlan.describe({
			{ pizza = "Pepperoni", size = "Large" },
			{ pizza = "Cheese", size = "Medium" },
			{ pizza = "Pepperoni", size = "Large" },
		}),
		"2 Large Pepperoni, 1 Medium Cheese",
		"describe"
	)
	assert(SalesPlan.expectedTicket(SalesPlan.dayMix(Random.new(3))) > 0, "expected ticket")
end)

----------------------------------------------------------------------- Style
spec("order tickets go green, then gold, then red as they wait", function()
	local A = Config.TicketAge
	assert(A.Fresh < A.Aging, "Fresh must come before Aging")
	eq(Style.ticketColor(0), Style.Color.Green, "a new ticket")
	eq(Style.ticketColor(A.Fresh - 1), Style.Color.Green, "just before Fresh")
	eq(Style.ticketColor(A.Fresh), Style.Color.Gold, "at Fresh")
	eq(Style.ticketColor(A.Aging - 1), Style.Color.Gold, "just before Aging")
	eq(Style.ticketColor(A.Aging), Style.Color.Red, "at Aging")
end)

spec("text on a gold ticket header is dark, on green and red it is white", function()
	local _, fg = Style.ticketColor(0)
	eq(fg, Style.Color.White, "green header text")
	_, fg = Style.ticketColor(Config.TicketAge.Fresh)
	eq(fg, Style.Color.Ink, "gold header text")
	_, fg = Style.ticketColor(Config.TicketAge.Aging)
	eq(fg, Style.Color.White, "red header text")
end)

spec("timers read m:ss and never go negative", function()
	eq(Style.clock(0), "0:00", "zero")
	eq(Style.clock(65), "1:05", "65 s")
	eq(Style.clock(599.9), "9:59", "just under 10 min")
	eq(Style.clock(-3), "0:00", "negative")
end)

spec("the UI scale range keeps text readable and never inverts", function()
	local r = Config.UiScaleRange
	assert(r[1] > 0 and r[1] < 1 and r[2] > 1, "range should straddle 1")
	eq(Config.UiReference.X / Config.UiReference.Y > 1.7, true, "reference is widescreen")
end)

-------------------------------------------------------------------------- run
local failed = 0
for _, s in specs do
	local ok, err = pcall(s[2] :: () -> ())
	if ok then
		print("  ok   " .. (s[1] :: string))
	else
		failed += 1
		print("  FAIL " .. (s[1] :: string) .. "\n         " .. tostring(err))
	end
end
print(string.format("\n%d specs, %d failed", #specs, failed))
process.exit(if failed > 0 then 1 else 0)
