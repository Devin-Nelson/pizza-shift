--!strict
-- Runs every store: the sales forecast and order flow, carryout customers,
-- phone + online orders (one or many pizzas each), dough prep (skins on the
-- rack), the per-pizza ticket pipeline (Make-Line -> conveyor Oven -> end of
-- belt -> Cut & Box), the heat rack and deliveries, stock, open hours, and the
-- server side of every station minigame. The client only ever reports inputs;
-- scoring and payouts happen here.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local GameClock = require(ReplicatedStorage.Shared.GameClock)
local Pizza3D = require(ReplicatedStorage.Shared.Pizza3D)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Style = require(ReplicatedStorage.Shared.Style)
local CarService = require(script.Parent.CarService)
local ClockService = require(script.Parent.ClockService)
local DataService = require(script.Parent.DataService)
local SalesPlan = require(script.Parent.SalesPlan)
local Screens = require(script.Parent.Screens)

type Item = SalesPlan.Item

-- A stretched dough skin on a rack screen.
type RackSkin = { size: string, quality: number, made: number }

type Customer = {
	npc: Model,
	humanoid: Humanoid,
	items: { Item },
	state: string, -- "Queued" | "Waiting" | "Leaving"
	arrived: number,
	order: Order?,
}

type PendingOrder = {
	kind: string, -- "walkin" | "phone"
	items: { Item },
	house: number?,
	customer: Customer?,
	created: number,
	claimedBy: Player?,
}

type Order = {
	id: number,
	source: string, -- "walkin" | "phone" | "online"
	delivery: boolean,
	entered: { Item }, -- what was rung in (what gets made)
	desired: { Item }, -- what the customer actually wanted
	house: number?, -- address rung in
	desiredHouse: number?,
	customer: Customer?,
	tickets: { Ticket },
	workers: { [Player]: boolean },
	registerScore: number,
	created: number,
	loadedAt: number?, -- when its last pizza went into the oven (load time = loadedAt - created)
	readyAt: number?, -- when its last pizza was boxed (total time = readyAt - created)
	cancelled: boolean,
	stage: string, -- "Making" | "Rack" | "Out" | "Pickup" | "Done"
	claimedBy: Player?,
}

-- One pizza an order asked for. It's filled when a finished pizza is loaded
-- into the oven for it (`pie`), and done once that pizza is boxed.
type Ticket = {
	id: number,
	order: Order,
	index: number,
	item: Item,
	pie: Pie?,
	boxed: boolean,
}

-- A physical pizza working its way through the kitchen. Pizzas are made
-- freely (not for a particular order): sauced from any skin, cheesed, topped,
-- then left on the ready rack until someone loads it, which is when it's
-- matched to an order (`ticket`; nil = an extra nobody ordered).
type Pie = {
	id: number,
	size: string,
	stage: string, -- "Sauced" | "Cheesed" | "Ready" (on the ready rack) | "Oven" | "Exit" (end of the belt) | "Cutting" | "Boxed"
	claimedBy: Player?,
	quality: { number }, -- dough, sauce, cheese, toppings, cut (each 0..1)
	visual: Model?,
	sauce: number?, -- sauce score (also how full the sauce layer looks)
	cheese: number?, -- cheese, as a ratio of the size's portion
	cheeseFactor: number, -- cheese portion accuracy
	counts: { [string]: number }?, -- toppings put on it
	portionFactor: number, -- cheese x topping portion accuracy vs. its order item
	toppedBy: Player?, -- paid when it's loaded (that's when we know what it should have been)
	workers: { [Player]: boolean },
	ticket: Ticket?,
	readySlot: number?, -- its ready rack slot while it waits to be loaded
	slot: number?, -- oven slot (1-6) while it's in the oven
	pos: number, -- distance along its oven lane from the entrance (studs)
	bake: number, -- how browned its visual is (0-1)
	settleAt: number, -- the oven leaves its visual alone until then (while it slides in)
	loadedAt: number?,
	exitAt: number?, -- when it reached the end of the belt
	boxWrong: boolean,
}

export type Shop = {
	id: number,
	name: string,
	model: Model,
	owner: Player?,
	volume: number,
	stock: { [string]: number },
	customers: { Customer },
	pending: { PendingOrder },
	orders: { Order },
	tickets: { Ticket },
	pies: { Pie },
	lanes: { { Pie } }, -- oven slot -> pizzas on that lane, front (nearest the exit) first
	nextSlot: number, -- where the next pizza gets loaded (wraps 1-6)
	orderCounter: number,
	ticketCounter: number,
	pieCounter: number,
	rng: Random,
	week: SalesPlan.Week?,
	weekNumber: number,
	day: number,
	mix: SalesPlan.Mix,
	demandToday: number, -- forecast dollars generated so far today
	sales: { today: number, week: number, crewToday: number, ordersToday: number, loadSum: number, loadCount: number, totalSum: number, totalCount: number },
	rack: { [number]: RackSkin }, -- dough rack slot -> stretched skin (nil = empty)
	lastRestock: number,
	spawning: number,
	alive: boolean,
}

type Session = {
	token: string,
	kind: string,
	station: string, -- the station it was started at
	shop: Shop,
	started: number,
	pending: PendingOrder?,
	pie: Pie?,
	order: Order?,
	data: any,
	consumed: { [string]: number }?,
	tool: Tool?,
}

-- A player standing at a station between jobs. `status` is the last "waiting
-- for..." text sent to them.
type Stay = { shop: Shop, name: string, idleSince: number, status: string? }

local ShopService = {}

local shops: { Shop } = {}
local sessions: { [Player]: Session } = {}
local stationed: { [Player]: Stay } = {}
local playerShop: { [Player]: Shop } = {}
local houses: { Part } = {}
local nextShopId = 0

local STATION_KIND = {
	Register = "Register",
	Dough = "Dough",
	Sauce = "Sauce",
	Cheese = "Cheese",
	Toppings = "Toppings",
	Load = "Load",
	CutTable = "Cut",
	DeliveryRack = "Delivery",
	SupplyTruck = "Supply",
}
-- Stations you stay at between jobs (Config.Stations `stay`). At `pick`
-- stations (cut table, heat rack) startStation never starts a job unless
-- the player picked one, so nobody gets handed the next job there.
local STAY: { [string]: boolean } = {}
for _, s in Config.Stations do
	STAY[s.id] = s.stay == true
end
-- A delivery is started from the heat rack but takes you out on the road, so
-- unlike every other job it doesn't keep you at the station.
local function holdsStation(session: Session): boolean
	return STAY[session.station] and session.kind ~= "Delivery"
end
-- Derived from Config so adding or changing a job can't leave these out of date.
local STAFF_JOBS = Config.JobsWithStation("Register") -- anyone who takes orders / makes pizzas
local DRIVING_JOBS = Config.JobsWithStation("DeliveryRack")
local MANAGEMENT_JOBS = Config.ManagementJobs()

local SESSION_TIMEOUT = 120
local FLAT = Pizza3D.FLAT
local SCREEN_COLOR = Color3.fromRGB(58, 58, 62) -- pizza screens, dark from use (matches StationArt)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function notify(player: Player?, text: string, color: Color3?, payInfo: any?)
	if player and player.Parent then
		Remotes.Notify:FireClient(player, text, color, payInfo)
	end
end

local function randomFrom<T>(list: { T }): T
	return list[math.random(1, #list)]
end

local function jobDef(player: Player): any
	local job = player:GetAttribute("Job")
	return if type(job) == "string" then Config.Jobs[job] else nil
end

local function jobAllows(player: Player, stationName: string): boolean
	local def = jobDef(player)
	return def ~= nil and table.find(def.stations, stationName) ~= nil
end

local function staffAt(shop: Shop, jobs: { string }): { Player }
	local list = {}
	for player, s in playerShop do
		if s == shop and player.Parent and table.find(jobs, player:GetAttribute("Job")) then
			table.insert(list, player)
		end
	end
	return list
end

local function onShift(shop: Shop, jobs: { string }): boolean
	return #staffAt(shop, jobs) > 0
end

local function average(list: { number }): number
	if #list == 0 then
		return 1
	end
	local sum = 0
	for _, v in list do
		sum += v
	end
	return sum / #list
end

local function marker(shop: Shop, name: string): BasePart?
	return shop.model:FindFirstChild(name, true) :: BasePart?
end

local function station(shop: Shop, name: string): BasePart?
	local stations = shop.model:FindFirstChild("Stations")
	return stations and stations:FindFirstChild(name) :: BasePart?
end

-- 12345.6 -> "$12,346"
local function money(n: number): string
	local digits = tostring(math.floor(n + 0.5))
	local grouped = (digits:reverse():gsub("(%d%d%d)", "%1,")):reverse()
	return "$" .. (grouped:gsub("^,", ""))
end

local function isOpen(): boolean
	return GameClock.isOpen(ClockService.WeekHour())
end

-- Staff can be on the clock from 30 minutes before opening (to prep) until midnight.
local function canWork(): boolean
	return GameClock.canClockIn(ClockService.WeekHour())
end

local function closedMessage(): string
	local hours = math.ceil(GameClock.hoursUntilClockIn(ClockService.WeekHour()))
	return string.format("We're closed (%s). That's about %d game hour%s away.", GameClock.hoursText(), hours, if hours == 1 then "" else "s")
end

local function formatMinutes(seconds: number): string
	return string.format("%d:%02d", seconds // 60, math.floor(seconds % 60))
end

-- Items rung in vs. items wanted: fraction that match (as multisets).
local function itemAccuracy(entered: { Item }, desired: { Item }): number
	local want: { [string]: number } = {}
	for _, it in desired do
		local k = it.size .. "|" .. it.pizza
		want[k] = (want[k] or 0) + 1
	end
	local matched = 0
	for _, it in entered do
		local k = it.size .. "|" .. it.pizza
		if (want[k] or 0) > 0 then
			want[k] -= 1
			matched += 1
		end
	end
	return matched / math.max(#entered, #desired, 1)
end

local function ticketLabel(t: Ticket): string
	return string.format("#%d-%d", t.order.id, t.index)
end

---------------------------------------------------------------------------
-- Dough rack: 30 screen slots shared by every size (Config.Dough)
---------------------------------------------------------------------------

-- How many skins of each size are on the rack, and how many slots are used.
local function rackCounts(shop: Shop): ({ [string]: number }, number)
	local counts = { Small = 0, Medium = 0, Large = 0 }
	local used = 0
	for _, skin in shop.rack do
		counts[skin.size] = (counts[skin.size] or 0) + 1
		used += 1
	end
	return counts, used
end

-- Puts a skin in `preferred` if that slot is empty, otherwise the first empty
-- slot (rack 1 top to bottom, then rack 2). Returns the slot, or nil if full.
local function rackAdd(shop: Shop, skin: RackSkin, preferred: number?): number?
	if preferred and not shop.rack[preferred] then
		shop.rack[preferred] = skin
		return preferred
	end
	for slot = 1, Config.RackCapacity() do
		if not shop.rack[slot] then
			shop.rack[slot] = skin
			return slot
		end
	end
	return nil
end

-- Takes the oldest skin of `size` off the rack (first in, first out).
local function rackTake(shop: Shop, size: string): (RackSkin?, number?)
	local bestSlot: number? = nil
	for slot, skin in shop.rack do
		if skin.size == size and (not bestSlot or skin.made < shop.rack[bestSlot].made) then
			bestSlot = slot
		end
	end
	if not bestSlot then
		return nil, nil
	end
	local skin = shop.rack[bestSlot]
	shop.rack[bestSlot] = nil
	return skin, bestSlot
end

-- Draws each skin on a pizza screen resting in its rack slot.
local function updateSkinRack(shop: Shop)
	local folder = shop.model:FindFirstChild("DoughSkins")
	if folder then
		folder:ClearAllChildren()
	else
		folder = Instance.new("Folder")
		folder.Name = "DoughSkins"
		folder.Parent = shop.model
	end
	local function disc(name: string, diameter: number, thickness: number, cf: CFrame, color: Color3, material: Enum.Material)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(thickness, diameter, diameter)
		p.Color = color
		p.Material = material
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CastShadow = false
		p.CFrame = cf * FLAT
		p.Parent = folder
	end
	for slot, skin in shop.rack do
		local slotMarker = marker(shop, "SkinSlot_" .. slot)
		if slotMarker then
			-- Screens are all rack-width; the skin on top is its real size.
			disc("Screen", 2.55, 0.03, CFrame.new(slotMarker.Position + Vector3.new(0, 0.02, 0)), SCREEN_COLOR, Enum.Material.DiamondPlate)
			disc("Skin", Config.PizzaDiameter[skin.size], 0.06, CFrame.new(slotMarker.Position + Vector3.new(0, 0.065, 0)), Config.IngredientColors.Dough, Enum.Material.SmoothPlastic)
		end
	end
end

---------------------------------------------------------------------------
-- Screens: kitchen display, lobby order tracker, stock tablet, sales board
---------------------------------------------------------------------------

-- How many of an order's pizzas are in the oven or past it.
local function loadedCount(o: Order): number
	local n = 0
	for _, t in o.tickets do
		if t.pie or t.boxed then
			n += 1
		end
	end
	return n
end

local function trackerStep(o: Order): number
	if o.stage == "Rack" then
		return 4
	elseif o.stage == "Out" or o.stage == "Pickup" then
		return 5
	end
	if loadedCount(o) < #o.tickets then
		return 2 -- still being made
	end
	for _, t in o.tickets do
		if not t.boxed and t.pie and t.pie.stage == "Oven" then
			return 3
		end
	end
	return 4
end

local function updateBoards(shop: Shop)
	if not shop.alive then
		return
	end
	local now = os.clock()

	-- Kitchen display: the dough racks and ready rack, then a ticket per order
	-- still waiting on pizzas to go in the oven (loaded ones struck through).
	local board = marker(shop, "TicketBoard")
	local kdsGui = board and board:FindFirstChild("Tickets")
	if kdsGui and kdsGui:IsA("SurfaceGui") then
		local counts, used = rackCounts(shop)
		local ready = 0
		for _, p in shop.pies do
			if p.stage == "Ready" then
				ready += 1
			end
		end
		local orders = {}
		for _, o in shop.orders do
			if o.stage ~= "Making" or o.cancelled or loadedCount(o) >= #o.tickets then
				continue
			end
			local items = {}
			for _, t in o.tickets do
				table.insert(items, { size = t.item.size, pizza = t.item.pizza, loaded = t.pie ~= nil or t.boxed })
			end
			table.insert(orders, { id = o.id, delivery = o.delivery, age = now - o.created, items = items })
		end
		Screens.kds(kdsGui, {
			dough = counts,
			used = used,
			capacity = Config.RackCapacity(),
			ready = ready,
			readyCapacity = Config.ReadyRack.Slots,
			orders = orders,
			idle = if isOpen() then "No orders - waiting on the phones" elseif canWork() then "Prep time - stretch dough" else "Closed",
		})
	end

	-- Lobby order tracker: each order's step, for the customers.
	local tv = marker(shop, "TrackerScreen")
	local tvGui = tv and tv:FindFirstChild("Tracker")
	if tvGui and tvGui:IsA("SurfaceGui") then
		local tracked = {}
		for _, o in shop.orders do
			table.insert(tracked, { id = o.id, step = trackerStep(o), delivery = o.delivery })
		end
		Screens.tracker(tvGui, tracked, if isOpen() then "No orders right now" else "Closed - " .. GameClock.hoursText())
	end

	-- Walk-in stock tablet.
	local fridge = station(shop, "Fridge")
	local stockGui = fridge and fridge:FindFirstChild("StockBoard", true)
	if stockGui and stockGui:IsA("SurfaceGui") then
		local lines = {}
		for _, ing in Config.Ingredients do
			local n = shop.stock[ing]
			table.insert(lines, { name = ing, n = n, color = Config.IngredientColors[ing] or Color3.new(1, 1, 1), low = n <= 3 })
		end
		Screens.stock(stockGui, lines)
	end
end

local function updateSalesBoard(shop: Shop)
	local board = marker(shop, "SalesBoard")
	local gui = board and board:FindFirstChild("Sales")
	if not gui or not gui:IsA("SurfaceGui") then
		return
	end
	local day, hour = GameClock.split(ClockService.WeekHour())
	local week = shop.week
	local part = GameClock.daypart(hour)
	local dayForecast = if week then week.days[day] else 0
	local weekForecast = if week then week.total else 0
	Screens.sales(gui, {
		clock = string.format("%s %s", string.upper(GameClock.dayName(day)), GameClock.format(hour)),
		week = ClockService.WeekNumber(),
		daypart = if part then string.format("%s - %d%% OF SALES", string.upper(part.name), math.floor(part.share * 100)) else "CLOSED",
		today = money(shop.sales.today),
		todayForecast = money(dayForecast),
		todayShare = if dayForecast > 0 then shop.sales.today / dayForecast else 0,
		weekSales = money(shop.sales.week),
		weekForecast = money(weekForecast),
		weekShare = if weekForecast > 0 then shop.sales.week / weekForecast else 0,
		orders = shop.sales.ordersToday,
		avgTicket = "~" .. money(SalesPlan.expectedTicket(shop.mix)),
		avgLoad = if shop.sales.loadCount > 0 then formatMinutes(shop.sales.loadSum / shop.sales.loadCount) else "--:--",
		avgTotal = if shop.sales.totalCount > 0 then formatMinutes(shop.sales.totalSum / shop.sales.totalCount) else "--:--",
		crew = money(shop.sales.crewToday),
	})
end

---------------------------------------------------------------------------
-- Pay
---------------------------------------------------------------------------

local function pay(shop: Shop, player: Player, base: number, quality: number, what: string)
	if not player.Parent then
		return
	end
	local q = math.clamp(math.max(Config.MinQualityPay, quality), 0, 1)
	local amount = DataService.AddCoins(player, base * q)
	local def = jobDef(player)
	local xp = math.max(1, math.floor(Config.XPPerTask * (if def then def.xpMult else 1) + 0.5))
	local leveled = DataService.AddXP(player, xp)
	local grade = if quality >= 0.9 then "PERFECT" elseif quality >= 0.7 then "Great" elseif quality >= 0.45 then "OK" else "Sloppy"
	-- The client shows this as a pay slip (grade, what, coins, XP); the text is the fallback.
	notify(player, string.format("+%d coins  +%d XP  %s - %s", amount, xp, what, grade), Color3.fromRGB(255, 220, 90), { grade = grade, what = what, coins = amount, xp = xp, quality = quality })
	if leveled then
		notify(player, "LEVEL UP! You're now level " .. DataService.GetLevel(player), Color3.fromRGB(120, 255, 160))
	end
	local owner = shop.owner
	if owner and owner ~= player and owner.Parent then
		DataService.AddCoins(owner, base * q * Config.Franchise.OwnerRoyalty, true)
	end
end

local function recordSale(shop: Shop, amount: number, crew: boolean)
	shop.sales.today += amount
	shop.sales.week += amount
	shop.sales.ordersToday += 1
	if crew then
		shop.sales.crewToday += amount
	end
end

---------------------------------------------------------------------------
-- Customers (carryout NPCs)
---------------------------------------------------------------------------

local SKIN = {
	Color3.fromRGB(255, 220, 190),
	Color3.fromRGB(234, 184, 146),
	Color3.fromRGB(198, 134, 94),
	Color3.fromRGB(141, 85, 54),
	Color3.fromRGB(94, 59, 38),
}

local function spot(shop: Shop, name: string): Vector3
	local spots = shop.model:FindFirstChild("Spots")
	local p = spots and spots:FindFirstChild(name) :: BasePart?
	return if p then p.Position else shop.model:GetPivot().Position
end

local function setBubble(c: Customer, text: string)
	local head = c.npc:FindFirstChild("Head")
	if not head then
		return
	end
	local gui = head:FindFirstChild("Bubble") :: BillboardGui?
	if not gui then
		local newGui = Instance.new("BillboardGui")
		newGui.Name = "Bubble"
		newGui.Size = UDim2.fromOffset(220, 50)
		newGui.StudsOffset = Vector3.new(0, 2.6, 0)
		newGui.MaxDistance = 60
		newGui.LightInfluence = 0
		local tl = Instance.new("TextLabel")
		tl.Name = "Text"
		tl.Size = UDim2.fromScale(1, 1)
		tl.BackgroundColor3 = Color3.new(1, 1, 1)
		tl.TextColor3 = Color3.fromRGB(30, 30, 30)
		tl.Font = Enum.Font.GothamBold
		tl.TextScaled = true
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = tl
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 6)
		pad.PaddingRight = UDim.new(0, 6)
		pad.Parent = tl
		tl.Parent = newGui
		newGui.Adornee = head
		newGui.Parent = head
		gui = newGui
	end
	((gui :: BillboardGui):FindFirstChild("Text") :: TextLabel).Text = text
end

local function layoutCustomers(shop: Shop)
	local q, w = 0, 0
	for _, c in shop.customers do
		if c.state == "Queued" then
			q += 1
			local base = spot(shop, "Queue" .. math.min(q, 3))
			c.humanoid:MoveTo(base + Vector3.new(0, 0, math.max(0, q - 3) * 3))
		elseif c.state == "Waiting" then
			w += 1
			local base = spot(shop, "Wait" .. ((w - 1) % 3 + 1))
			local ring = math.floor((w - 1) / 3)
			c.humanoid:MoveTo(base + Vector3.new(ring * 2.5, 0, ring * 2))
		end
	end
end

local function removePending(shop: Shop, entry: PendingOrder)
	local i = table.find(shop.pending, entry)
	if i then
		table.remove(shop.pending, i)
	end
end

local function customerLeave(shop: Shop, c: Customer, mood: string)
	if c.state == "Leaving" then
		return
	end
	c.state = "Leaving"
	local i = table.find(shop.customers, c)
	if i then
		table.remove(shop.customers, i)
	end
	for _, entry in table.clone(shop.pending) do
		if entry.customer == c then
			removePending(shop, entry)
		end
	end
	if c.order and c.order.stage ~= "Done" then
		c.order.customer = nil
		c.order.cancelled = true
		-- Say so out loud, otherwise the order just vanishes from the screens.
		for _, p in staffAt(shop, STAFF_JOBS) do
			notify(p, string.format("The customer for order #%d gave up and left - order cancelled.", c.order.id), Color3.fromRGB(255, 120, 100))
		end
	end
	setBubble(c, mood)
	if shop.alive then
		c.humanoid:MoveTo(spot(shop, "Exit"))
	end
	task.delay(7, function()
		c.npc:Destroy()
	end)
	layoutCustomers(shop)
end

-- Closed boxes are built standing on edge and turned flat with BOX_FLAT, so the
-- printed lid is the part's Front face: that face's text has a known "up" (the
-- part's +Y), which BOX_FLAT points away from whoever the box faces (its -Z).
-- Printing on a Top face instead comes out upside down from the front.
local BOX_FLAT = CFrame.Angles(math.rad(90), 0, 0)

-- A closed pizza box sized for `size` (for carryout boxes in the warmer).
-- Set its CFrame as `<where> * BOX_FLAT`.
local function makeBoxPart(size: string): Part
	local bs = Config.BoxSize[size] or 2.55
	local p = Instance.new("Part")
	p.Name = "PizzaBox"
	p.Size = Vector3.new(bs, bs, 0.3)
	p.Color = Color3.fromRGB(205, 168, 118)
	p.Material = Enum.Material.Cardboard
	p.CanCollide = false
	p.CanQuery = false
	p.Massless = true
	p.Anchored = true
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(110, 110)
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.FontFace = Style.Font.Heading
	tl.TextScaled = true
	tl.TextColor3 = Config.Brand.Red
	tl.Text = (string.upper(Config.GameName):gsub(" ", "\n"))
	tl.Parent = gui
	gui.Parent = p
	return p
end

---------------------------------------------------------------------------
-- Orders and tickets
---------------------------------------------------------------------------

local function createOrder(shop: Shop, kind: string, desired: { Item }, desiredHouse: number?, entered: { Item }, house: number?, registerScore: number, takenBy: Player?, customer: Customer?): Order
	shop.orderCounter += 1
	local order: Order = {
		id = shop.orderCounter,
		source = kind,
		delivery = desiredHouse ~= nil,
		entered = entered,
		desired = desired,
		house = house,
		desiredHouse = desiredHouse,
		customer = customer,
		tickets = {},
		workers = {},
		registerScore = registerScore,
		created = os.clock(),
		loadedAt = nil,
		readyAt = nil,
		cancelled = false,
		stage = "Making",
		claimedBy = nil,
	}
	if takenBy then
		order.workers[takenBy] = true
	end
	for i, item in entered do
		shop.ticketCounter += 1
		local ticket: Ticket = { id = shop.ticketCounter, order = order, index = i, item = item, pie = nil, boxed = false }
		table.insert(order.tickets, ticket)
		table.insert(shop.tickets, ticket)
	end
	table.insert(shop.orders, order)

	if customer and customer.state == "Queued" then
		customer.state = "Waiting"
		customer.order = order
		setBubble(customer, if kind == "online" then "Picking up online order #" .. order.id else "Order #" .. order.id .. "...")
		layoutCustomers(shop)
	end
	updateBoards(shop)
	return order
end

-- Takes an order off the books. Pizzas already made for it that aren't boxed
-- yet carry on through the kitchen as extras.
local function removeOrder(shop: Shop, order: Order)
	order.stage = "Done"
	for _, t in order.tickets do
		local pie = t.pie
		if pie and not t.boxed then
			pie.ticket = nil
			t.pie = nil
		end
		local i = table.find(shop.tickets, t)
		if i then
			table.remove(shop.tickets, i)
		end
	end
	local i = table.find(shop.orders, order)
	if i then
		table.remove(shop.orders, i)
	end
	updateBoards(shop)
end

-- Pizzas the players currently have on their plate (for crew overflow):
-- everything ordered that isn't boxed yet, plus calls and walk-ins not rung in.
local function openPizzas(shop: Shop): number
	local n = 0
	for _, t in shop.tickets do
		if not t.boxed then
			n += 1
		end
	end
	for _, e in shop.pending do
		n += #e.items
	end
	return n
end

---------------------------------------------------------------------------
-- Pizzas in the kitchen
---------------------------------------------------------------------------

local function pieSpec(pie: Pie, baked: boolean): Pizza3D.Spec
	return { size = pie.size, sauce = pie.sauce, cheese = pie.cheese, toppings = pie.counts, seed = pie.id, baked = baked }
end

-- (Re)builds a pizza's shared model with the layers it has so far. Clients find
-- it by its attributes (to load it from the ready rack, pull it at the oven exit).
local function buildVisual(shop: Shop, pie: Pie, at: CFrame, baked: boolean)
	if pie.visual then
		pie.visual:Destroy()
	end
	local model = Pizza3D.fromSpec(at, pieSpec(pie, baked), shop.model).model
	model.Name = "Pie" .. pie.id
	model:SetAttribute("PieId", pie.id)
	model:SetAttribute("PieSize", pie.size)
	model:SetAttribute("PieStage", pie.stage)
	pie.visual = model
end

local function setStage(pie: Pie, stage: string)
	pie.stage = stage
	if pie.visual then
		pie.visual:SetAttribute("PieStage", stage)
	end
end

local function findPie(shop: Shop, id: any): Pie?
	for _, p in shop.pies do
		if p.id == id then
			return p
		end
	end
	return nil
end

-- Takes a pizza out of the kitchen for good (boxed, dropped, closing time).
local function removePie(shop: Shop, pie: Pie, keepVisual: boolean?)
	local i = table.find(shop.pies, pie)
	if i then
		table.remove(shop.pies, i)
	end
	if pie.slot then
		local lanePies = shop.lanes[pie.slot]
		local j = table.find(lanePies, pie)
		if j then
			table.remove(lanePies, j)
		end
	end
	if pie.visual and not keepVisual then
		pie.visual:Destroy()
		pie.visual = nil
	end
end

-- The oldest pizza waiting in `stage` that nobody is working, or the one asked for.
local function pickPie(shop: Shop, stage: string, pieId: number?): Pie?
	for _, p in shop.pies do
		if p.stage == stage and not p.claimedBy and (pieId == nil or p.id == pieId) then
			return p
		end
	end
	return nil
end

-- Where pizzas wait between make steps (markers on the make-line board).
local WAITING_SPOT = { Sauced = "SaucedQueue", Cheesed = "CheesedQueue" }

-- Free slots on the ready rack, counting toppings jobs in progress (each
-- will need a slot when it's done).
local function readyRoom(shop: Shop): number
	local used = 0
	for _, p in shop.pies do
		if p.stage == "Ready" or (p.stage == "Cheesed" and p.claimedBy) then
			used += 1
		end
	end
	return Config.ReadyRack.Slots - used
end

-- The top-most empty slot on the ready rack (nil if it's full).
local function freeReadySlot(shop: Shop): number?
	local taken: { [number]: boolean } = {}
	for _, p in shop.pies do
		if p.stage == "Ready" and p.readySlot then
			taken[p.readySlot] = true
		end
	end
	for slot = 1, Config.ReadyRack.Slots do
		if not taken[slot] then
			return slot
		end
	end
	return nil
end

-- Lines up the pizzas waiting for cheese / toppings (several at one spot fan
-- out and stack a little so each stays visible), and puts finished ones on
-- screens in their ready rack slots.
local function arrangeMakeLine(shop: Shop)
	for stage, markerName in WAITING_SPOT do
		local spotMarker = marker(shop, markerName)
		if spotMarker then
			local n = 0
			for _, p in shop.pies do
				if p.stage == stage and p.visual then
					local fan = if n % 2 == 1 then 0.3 else -0.3 * math.min(n, 1)
					Pizza3D.place(p.visual, spotMarker.CFrame * CFrame.new(fan, 0.06 + n * 0.16, 0))
					n += 1
				end
			end
		end
	end
	local screens = shop.model:FindFirstChild("ReadyScreens")
	if screens then
		screens:ClearAllChildren()
	else
		screens = Instance.new("Folder")
		screens.Name = "ReadyScreens"
		screens.Parent = shop.model
	end
	for _, p in shop.pies do
		local slotMarker = if p.stage == "Ready" and p.readySlot then marker(shop, "ReadySlot_" .. p.readySlot) else nil
		if slotMarker and p.visual then
			local screen = Instance.new("Part")
			screen.Name = "Screen"
			screen.Shape = Enum.PartType.Cylinder
			screen.Size = Vector3.new(0.03, 2.55, 2.55)
			screen.Color = SCREEN_COLOR
			screen.Material = Enum.Material.DiamondPlate
			screen.Anchored = true
			screen.CanCollide = false
			screen.CanQuery = false
			screen.CFrame = CFrame.new(slotMarker.Position + Vector3.new(0, 0.02, 0)) * FLAT
			screen.Parent = screens
			Pizza3D.place(p.visual, CFrame.new(slotMarker.Position + Vector3.new(0, 0.1, 0)))
		end
	end
end

-- Moves a pizza's visual to `stage`'s waiting spot, rebuilt with its layers so far.
local function placeOnLine(shop: Shop, pie: Pie)
	buildVisual(shop, pie, shop.model:GetPivot(), false)
	arrangeMakeLine(shop)
end

---------------------------------------------------------------------------
-- Ovens: three stacked conveyors, two lanes each (slots 1-6)
---------------------------------------------------------------------------
-- Each slot's lane runs from its OvenIn_<n> marker to its OvenOut_<n> marker
-- (pizza centers at the entrance and at the end of the belt). Pizzas ride it
-- in real time (Config.Oven.BakeTime end to end), browning between the
-- chamber's mouths. The moment a pizza's leading edge comes out into the open
-- air it can be pulled; left to reach the end of the belt, it falls off after
-- Config.Oven.FallAfter. Pizzas behind it queue up on the belt.

type Lane = { a: Vector3, b: Vector3, dir: Vector3, length: number, mouthIn: number, mouthOut: number }

-- Lane geometry, looked up once per shop (the ovens don't move).
local laneCache: { [Shop]: { [number]: Lane } } = setmetatable({}, { __mode = "k" }) :: any
local function laneOf(shop: Shop, slot: number): Lane?
	local cache = laneCache[shop]
	if not cache then
		cache = {}
		laneCache[shop] = cache
	end
	local lane = cache[slot]
	if not lane then
		local a, b = marker(shop, "OvenIn_" .. slot), marker(shop, "OvenOut_" .. slot)
		if not a or not b then
			return nil
		end
		local dir = (b.Position - a.Position).Unit
		local length = (b.Position - a.Position).Magnitude
		-- How far along the lane the chamber starts and ends (custom oven models may leave these out).
		local mIn, mOut = marker(shop, "OvenMouthIn_" .. slot), marker(shop, "OvenMouthOut_" .. slot)
		local mouthIn = if mIn then (mIn.Position - a.Position):Dot(dir) else 0
		local mouthOut = if mOut then (mOut.Position - a.Position):Dot(dir) else length
		lane = { a = a.Position, b = b.Position, dir = dir, length = length, mouthIn = mouthIn, mouthOut = mouthOut }
		cache[slot] = lane
	end
	return lane
end

local function laneEnds(shop: Shop, slot: number): (Vector3?, Vector3?)
	local lane = laneOf(shop, slot)
	return if lane then lane.a else nil, if lane then lane.b else nil
end

local function diameter(size: string): number
	return Config.PizzaDiameter[size] or 2.4
end

-- Is there room at the entrance of `slot` for a pizza `d` across?
local function slotClear(shop: Shop, slot: number, d: number): boolean
	local lanePies = shop.lanes[slot]
	local last = lanePies[#lanePies]
	return last == nil or last.pos >= (diameter(last.size) + d) / 2 + Config.Oven.Gap
end

-- The next slot in the 1-6 rotation with room for this pizza (nil = all busy).
local function nextFreeSlot(shop: Shop, d: number): number?
	for i = 0, Config.Oven.Slots - 1 do
		local slot = (shop.nextSlot - 1 + i) % Config.Oven.Slots + 1
		if slotClear(shop, slot, d) then
			return slot
		end
	end
	return nil
end

-- Puts a pizza back on its lane at its old spot (after a pull is put down).
local function returnToLane(shop: Shop, pie: Pie)
	local slot = pie.slot
	local lane = if slot then laneOf(shop, slot) else nil
	if not slot or not lane then
		return
	end
	local lanePies = shop.lanes[slot]
	local index = #lanePies + 1
	for i, q in lanePies do
		if q.pos < pie.pos then
			index = i
			break
		end
	end
	table.insert(lanePies, index, pie)
	pie.exitAt = if index == 1 and pie.pos >= lane.length - 1e-3 then os.clock() else nil
	setStage(pie, "Exit")
	if pie.visual then
		Pizza3D.place(pie.visual, CFrame.new(lane.a + lane.dir * pie.pos))
	end
end

-- Left too long at the end of the belt: the pizza slides off onto the floor.
-- If it was for an order, that order needs another one made.
local function dropPie(shop: Shop, pie: Pie)
	local slot = pie.slot
	local a, b = if slot then laneEnds(shop, slot) else nil, nil
	local ticket = pie.ticket
	if ticket then
		ticket.pie = nil
		pie.ticket = nil
	end
	removePie(shop, pie, true)
	local visual = pie.visual
	pie.visual = nil
	if visual and visual.PrimaryPart and a and b then
		local out = (b - a).Unit
		-- The shop pivot is the floor slab's center (0.5 below its top surface).
		local floorTop = shop.model:GetPivot().Position.Y + 0.5
		local landing = b + out * 2
		TweenService:Create(visual.PrimaryPart, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			CFrame = CFrame.new(landing.X, floorTop + 0.15, landing.Z) * CFrame.Angles(math.rad(35), 0, math.rad(20)) * FLAT,
		}):Play()
		task.delay(4, function()
			visual:Destroy()
		end)
	elseif visual then
		visual:Destroy()
	end
	local what = if ticket then string.format("Pizza %s", ticketLabel(ticket)) else "An extra pizza"
	for _, p in staffAt(shop, STAFF_JOBS) do
		notify(p, string.format("%s fell off the end of oven slot %d!%s", what, slot or 0, if ticket then " Make another one." else ""), Color3.fromRGB(255, 110, 90))
	end
	updateBoards(shop)
end

-- Moves every pizza along its lane. Runs ~10 times a second.
local function ovenStep(shop: Shop, dt: number)
	local now = os.clock()
	for slot = 1, Config.Oven.Slots do
		local lanePies = shop.lanes[slot]
		local lane = laneOf(shop, slot)
		if #lanePies == 0 or not lane then
			continue
		end
		local speed = lane.length / Config.Oven.BakeTime
		for i, p in lanePies do
			-- Never past the end of the belt, or into the pizza ahead.
			local limit = lane.length
			if i > 1 then
				local ahead = lanePies[i - 1]
				limit = ahead.pos - (diameter(ahead.size) + diameter(p.size)) / 2 - Config.Oven.Gap
			end
			p.pos = math.min(p.pos + speed * dt, limit)
			if p.visual then
				-- Browns as it goes through the chamber (in steps, to keep replication light).
				local bake = math.clamp((p.pos - lane.mouthIn) / math.max(lane.mouthOut - lane.mouthIn, 0.1), 0, 1)
				if bake - p.bake >= 0.05 or (bake >= 1 and p.bake < 1) then
					p.bake = bake
					Pizza3D.bakeTint(p.visual, bake)
				end
				if now >= p.settleAt then
					Pizza3D.place(p.visual, CFrame.new(lane.a + lane.dir * p.pos))
				end
			end
			-- Out in the open air past the exit mouth: the oven tender can pull it.
			if p.stage == "Oven" and p.pos + diameter(p.size) / 2 >= lane.mouthOut then
				setStage(p, "Exit")
				updateBoards(shop)
			end
			-- At the very end of the belt the fall clock starts.
			if i == 1 and not p.exitAt and p.pos >= lane.length - 1e-3 then
				p.exitAt = now
			end
		end
		-- Tend the oven: a pizza left at the end of the belt too long falls off.
		local front = lanePies[1]
		if front and front.exitAt and now - front.exitAt > Config.Oven.FallAfter then
			dropPie(shop, front)
		end
	end
end

-- How well what's on a pizza matches a recipe: 0 when the same toppings are
-- on it, minus one for each topping missing or extra.
local function matchScore(recipe: { string }, counts: { [string]: number }?): number
	local on: { [string]: boolean } = {}
	for name, n in counts or {} do
		if n > 0 then
			on[name] = true
		end
	end
	local score = 0
	for _, name in recipe do
		if on[name] then
			on[name] = nil
		else
			score -= 1
		end
	end
	for _ in on do
		score -= 1
	end
	return score
end

-- Topping accuracy against an order item: Config.PortionFactor for each topping
-- on its recipe, half credit for anything that shouldn't be there.
local function toppingAccuracy(item: Item, counts: { [string]: number }?): number
	local recipe = Config.Recipes[item.pizza] or {}
	local factors = {}
	for _, topping in Config.Toppings do
		local n = (counts and counts[topping]) or 0
		if table.find(recipe, topping) then
			table.insert(factors, Config.PortionFactor(n, Config.PortionFor(topping, item.size, #recipe)))
		elseif n > 0 then
			table.insert(factors, 0.5)
		end
	end
	return if #factors > 0 then average(factors) else 1
end

-- The order item a finished pizza counts toward: in `order` if the player
-- picked one, otherwise across every order. Among items still waiting on a
-- pizza of its size, the best recipe match wins, then the oldest order.
local function matchTicket(shop: Shop, pie: Pie, order: Order?): Ticket?
	local best: Ticket? = nil
	local bestScore, bestAge = -math.huge, math.huge
	for _, o in (if order then { order } else shop.orders) do
		if o.cancelled or o.stage ~= "Making" then
			continue
		end
		for _, t in o.tickets do
			if not t.pie and not t.boxed and t.item.size == pie.size then
				local score = matchScore(Config.Recipes[t.item.pizza] or {}, pie.counts)
				if score > bestScore or (score == bestScore and o.created < bestAge) then
					best, bestScore, bestAge = t, score, o.created
				end
			end
		end
	end
	return best
end

-- Loads a pizza from the ready rack into the next free oven slot and matches
-- it to an order: the one picked if `orderId`, none at all if it's 0 (an
-- extra), otherwise automatically. Returns why not, if it can't.
local function loadPie(shop: Shop, player: Player, pie: Pie, orderId: number?): string?
	if pie.stage ~= "Ready" or pie.claimedBy then
		return "That pizza isn't on the ready rack any more."
	end
	local order: Order? = nil
	if orderId and orderId ~= 0 then
		for _, o in shop.orders do
			if o.id == orderId then
				order = o
			end
		end
		if not order or order.cancelled or order.stage ~= "Making" then
			return "That order isn't waiting on pizzas any more."
		end
	end
	local ticket = if orderId == 0 then nil else matchTicket(shop, pie, order)
	if order and not ticket then
		return string.format("Order #%d doesn't need a %s.", order.id, pie.size)
	end
	local slot = nextFreeSlot(shop, diameter(pie.size))
	if not slot then
		return "The oven entrance is full - give it a few seconds."
	end
	local now = os.clock()
	shop.nextSlot = slot % Config.Oven.Slots + 1
	pie.readySlot = nil
	pie.slot = slot
	pie.pos = 0
	pie.loadedAt = now
	pie.settleAt = now + 0.7 -- the slide into the slot plays first
	pie.workers[player] = true
	setStage(pie, "Oven")
	table.insert(shop.lanes[slot], pie)

	-- Now we know what it should have been: score the toppings and pay whoever topped it.
	local accuracy = if ticket then toppingAccuracy(ticket.item, pie.counts) else 0
	pie.portionFactor = pie.cheeseFactor * accuracy
	table.insert(pie.quality, accuracy)
	local topper = pie.toppedBy
	pie.toppedBy = nil
	if topper and topper.Parent then
		pay(shop, topper, Config.Pay.Toppings, accuracy, if ticket then "Topped " .. ticketLabel(ticket) else "Topped an extra pizza")
		if ticket and accuracy < 1 then
			notify(topper, string.format("%s is a %s %s: its toppings or portions were off.", ticketLabel(ticket), ticket.item.size, ticket.item.pizza), Color3.fromRGB(255, 180, 100))
		end
	end
	if ticket then
		pie.ticket = ticket
		ticket.pie = pie
		local o = ticket.order
		for w in pie.workers do
			o.workers[w] = true
		end
		-- Load time: from the order being placed to its last pizza going in (first time only).
		if not o.loadedAt and loadedCount(o) >= #o.tickets then
			o.loadedAt = now
			local loadTime = now - o.created
			shop.sales.loadSum += loadTime
			shop.sales.loadCount += 1
			for w in o.workers do
				notify(w, string.format("Order #%d is all in the oven - load time %s", o.id, formatMinutes(loadTime)), Color3.fromRGB(180, 220, 255))
			end
		end
	else
		notify(player, string.format("No order is waiting on a %s - it'll bake as an extra.", pie.size), Color3.fromRGB(255, 160, 100))
	end
	-- Slide it off the shelf into its slot.
	local a = laneEnds(shop, slot)
	if pie.visual and pie.visual.PrimaryPart and a then
		TweenService:Create(pie.visual.PrimaryPart, TweenInfo.new(0.7, Enum.EasingStyle.Quad), { CFrame = CFrame.new(a) * FLAT }):Play()
	end
	arrangeMakeLine(shop)
	updateBoards(shop)
	return nil
end

---------------------------------------------------------------------------
-- Finishing orders
---------------------------------------------------------------------------

-- Final reckoning when the customer receives (or doesn't receive) the order.
-- Delivery tips go to `driver`; carryout tips are split among the insiders.
local function completeOrder(shop: Shop, order: Order, extra: number, driver: Player?)
	removeOrder(shop, order)
	-- The kitchen makes what was rung in. If that didn't match what the customer
	-- asked for, tell the crew why the order finished "early" (or with the wrong pizzas).
	local accuracy = itemAccuracy(order.entered, order.desired)
	if accuracy < 1 then
		for worker in order.workers do
			notify(worker, string.format("Order #%d was rung in as %d pizza%s, but the customer wanted: %s", order.id, #order.entered, if #order.entered == 1 then "" else "s", SalesPlan.describe(order.desired)), Color3.fromRGB(255, 140, 90))
		end
	end
	local qualities = { order.registerScore }
	local portions, wrongBoxes = {}, 0
	for _, t in order.tickets do
		local pie = t.pie
		table.insert(qualities, if pie then average(pie.quality) else 0.5)
		table.insert(portions, if pie then pie.portionFactor else 0.5)
		if pie and pie.boxWrong then
			wrongBoxes += 1
		end
	end
	local boxFactor = 1 - 0.15 * (wrongBoxes / math.max(#order.tickets, 1))
	-- Portions more than 10% off penalize satisfaction directly.
	local satisfaction = average(qualities) * accuracy * extra * average(portions) * boxFactor

	if order.delivery and order.house ~= order.desiredHouse then
		local who = if driver then { driver } else {}
		for worker in order.workers do
			table.insert(who, worker)
		end
		for _, p in who do
			notify(p, string.format("Order #%d went to the wrong house! The customer at #%d never got it.", order.id, order.desiredHouse or 0), Color3.fromRGB(255, 120, 100))
		end
		return
	end

	local price = SalesPlan.price(order.entered)
	recordSale(shop, price, false)
	updateSalesBoard(shop)

	if order.delivery then
		if driver and driver.Parent then
			local range = Config.Tips.Delivery
			local tip = math.floor(price * shop.rng:NextNumber(range.min, range.max) * satisfaction + 0.5)
			if tip > 0 then
				local got = DataService.AddCoins(driver, tip)
				notify(driver, string.format("Tip on order #%d (%s): +%d", order.id, money(price), got), Color3.fromRGB(120, 255, 160))
			end
		end
	else
		local range = Config.Tips.Carryout
		local pool = price * shop.rng:NextNumber(range.min, range.max) * satisfaction
		local insiders = {}
		for worker in order.workers do
			if worker.Parent then
				table.insert(insiders, worker)
			end
		end
		local each = if #insiders > 0 then math.floor(pool / #insiders) else 0
		for _, worker in insiders do
			if each > 0 then
				local got = DataService.AddCoins(worker, each)
				notify(worker, string.format("Carryout tip on order #%d: +%d", order.id, got), Color3.fromRGB(150, 230, 255))
			end
		end
	end
	local owner = shop.owner
	if owner and owner.Parent then
		DataService.AddCoins(owner, price * Config.Franchise.SaleCut, true)
	end

	local c = order.customer
	if c and c.state ~= "Leaving" then
		local mood = if satisfaction >= 0.8 then "Smells amazing, thanks!" elseif satisfaction >= 0.5 then "Not bad." else "Ugh... this isn't right."
		customerLeave(shop, c, mood)
	end
end

local function serveCarryout(shop: Shop, order: Order)
	local c = order.customer
	local pickup = station(shop, "Pickup")
	if order.source == "online" and not c then
		-- Picked up by someone we never modeled (lobby was full).
		completeOrder(shop, order, 1, nil)
		return
	end
	if not c or c.state == "Leaving" or not pickup then
		for worker in order.workers do
			notify(worker, "Order #" .. order.id .. " is ready but the customer already left.", Color3.fromRGB(255, 160, 100))
		end
		removeOrder(shop, order)
		return
	end
	order.stage = "Pickup"
	updateBoards(shop)
	setBubble(c, "That's mine!")
	-- Boxes stack in the carryout warmer (hitbox center is 0.5 above the counter; shelf at +0.25).
	local boxes = {}
	for i = 1, math.min(#order.tickets, 3) do -- up to 3 fit under the warmer's middle shelf
		local box = makeBoxPart(order.tickets[i].item.size)
		box.CFrame = pickup.CFrame * CFrame.new(0, -0.1 + (i - 1) * 0.32, 0) * BOX_FLAT
		box.Parent = shop.model
		table.insert(boxes, box)
	end
	-- The carryout warmer faces the customers, so its LookVector points into the lobby.
	c.humanoid:MoveTo(pickup.Position + pickup.CFrame.LookVector * 3.5)

	task.delay(3, function()
		local root = c.npc:FindFirstChild("HumanoidRootPart") :: BasePart?
		for i, box in boxes do
			if root and c.state ~= "Leaving" then
				box.Anchored = false
				box.CFrame = root.CFrame * CFrame.new(0, -0.3 + (i - 1) * 0.32, -1.6) * BOX_FLAT
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = box
				weld.Parent = box
				box.Parent = c.npc
			else
				box:Destroy()
			end
		end
		if shop.alive then
			completeOrder(shop, order, 1, nil)
		end
	end)
end

-- After a pizza is boxed: is the whole order ready?
local function checkOrder(shop: Shop, order: Order)
	if order.stage ~= "Making" then
		return
	end
	for _, t in order.tickets do
		if not t.boxed then
			return
		end
	end
	-- Total time: real minutes from the order being placed to every pizza boxed.
	local now = os.clock()
	order.readyAt = now
	local total = now - order.created
	shop.sales.totalSum += total
	shop.sales.totalCount += 1
	for worker in order.workers do
		notify(worker, string.format("Order #%d ready - total time %s", order.id, formatMinutes(total)), Color3.fromRGB(180, 220, 255))
	end
	if order.delivery then
		order.stage = "Rack"
		updateBoards(shop)
	else
		serveCarryout(shop, order)
	end
end

local function spawnCustomer(shop: Shop, items: { Item }, online: boolean)
	shop.spawning += 1
	task.spawn(function()
		local desc = Instance.new("HumanoidDescription")
		local skin = randomFrom(SKIN)
		desc.HeadColor = skin
		desc.LeftArmColor = skin
		desc.RightArmColor = skin
		desc.TorsoColor = Color3.fromHSV(math.random(), 0.5, 0.85)
		local pants = Color3.fromHSV(math.random(), 0.4, 0.4)
		desc.LeftLegColor = pants
		desc.RightLegColor = pants

		local ok, npc = pcall(function()
			return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
		end)
		shop.spawning -= 1
		if not ok or not npc or not shop.alive or not isOpen() then
			if not ok then
				warn("[ShopService] couldn't spawn customer:", npc)
			end
			if ok and npc then
				npc:Destroy()
			end
			return
		end
		npc.Name = "Customer"
		local humanoid = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.WalkSpeed = 12
		npc:PivotTo(CFrame.new(spot(shop, "CustomerSpawn")))
		local folder = shop.model:FindFirstChild("NPCs")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "NPCs"
			folder.Parent = shop.model
		end
		npc.Parent = folder
		local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			pcall(function()
				root:SetNetworkOwner(nil)
			end)
		end

		-- Default R15 walk/idle so NPCs don't slide around.
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
		local walkAnim = Instance.new("Animation")
		walkAnim.AnimationId = "rbxassetid://507777826"
		local idleAnim = Instance.new("Animation")
		idleAnim.AnimationId = "rbxassetid://507766388"
		local okW, walkTrack = pcall(animator.LoadAnimation, animator, walkAnim)
		local okI, idleTrack = pcall(animator.LoadAnimation, animator, idleAnim)
		if okW and okI then
			idleTrack:Play()
			humanoid.Running:Connect(function(speed)
				if speed > 0.5 then
					if not walkTrack.IsPlaying then
						walkTrack:Play(0.2)
					end
				elseif walkTrack.IsPlaying then
					walkTrack:Stop(0.2)
				end
			end)
		end

		local c: Customer = { npc = npc, humanoid = humanoid, items = items, state = "Queued", arrived = os.clock(), order = nil }
		table.insert(shop.customers, c)
		if online then
			-- Ordered on the app; the tickets are already on the make-line.
			createOrder(shop, "online", items, nil, table.clone(items), nil, 1, nil, c)
		else
			table.insert(shop.pending, { kind = "walkin", items = items, house = nil, customer = c, created = os.clock(), claimedBy = nil })
			local text = SalesPlan.describe(items)
			setBubble(c, if #text > 60 then string.format("A big order - %d pizzas!", #items) else text .. ", please!")
		end
		layoutCustomers(shop)
	end)
end

-- One new order from the forecast: route it to the players or the off-screen crew.
local function newOrder(shop: Shop, items: { Item })
	local S = Config.Sales
	local delivery = shop.rng:NextNumber() < S.DeliveryShare
	local online = shop.rng:NextNumber() < S.OnlineShare
	local staff = #staffAt(shop, STAFF_JOBS)
	local capacity = staff * Config.Crew.PizzasPerWorker - openPizzas(shop)
	local playable = staff > 0 and #items <= capacity and (not delivery or onShift(shop, DRIVING_JOBS))
	if not playable then
		recordSale(shop, SalesPlan.price(items), true)
		return
	end
	if delivery then
		local house = shop.rng:NextInteger(1, #houses)
		local phones = 0
		for _, e in shop.pending do
			if e.kind == "phone" then
				phones += 1
			end
		end
		if online or phones >= 2 then
			createOrder(shop, "online", items, house, table.clone(items), house, 1, nil, nil)
		else
			table.insert(shop.pending, { kind = "phone", items = items, house = house, customer = nil, created = os.clock(), claimedBy = nil })
		end
		return
	end
	-- Carryout: a customer walks in (or comes to pick up an online order).
	if #shop.customers + shop.spawning < Config.Shop.MaxCustomers then
		spawnCustomer(shop, items, online)
	elseif online then
		createOrder(shop, "online", items, nil, table.clone(items), nil, 1, nil, nil)
	else
		recordSale(shop, SalesPlan.price(items), true)
	end
end

---------------------------------------------------------------------------
-- Uniform
---------------------------------------------------------------------------

local function setUniform(character: Model, on: boolean)
	local old = character:FindFirstChild("UniformCap")
	if old then
		old:Destroy()
	end
	local head = character:FindFirstChild("Head") :: BasePart?
	if not on or not head then
		return
	end
	local cap = Instance.new("Model")
	cap.Name = "UniformCap"
	local function capPart(name: string, size: Vector3, offset: CFrame, color: Color3, shape: Enum.PartType?)
		local p = Instance.new("Part")
		p.Name = name
		if shape then
			p.Shape = shape
		end
		p.Size = size
		p.CFrame = head.CFrame * offset
		p.Color = color
		p.Material = Enum.Material.Fabric
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = p
		weld.Parent = p
		p.Parent = cap
	end
	capPart("Crown", Vector3.new(0.55, 1.35, 1.35), CFrame.new(0, 0.5, 0.05) * FLAT, Config.Brand.Red, Enum.PartType.Cylinder)
	capPart("Brim", Vector3.new(1.1, 0.08, 0.75), CFrame.new(0, 0.3, -0.75), Config.Brand.Charcoal)
	capPart("Badge", Vector3.new(0.05, 0.4, 0.4), CFrame.new(0, 0.55, -0.66) * CFrame.Angles(0, math.pi / 2, 0), Config.Brand.Gold, Enum.PartType.Cylinder)
	cap.Parent = character
end

---------------------------------------------------------------------------
-- Sessions (minigames)
---------------------------------------------------------------------------

local function endSession(player: Player, session: Session, released: boolean)
	if sessions[player] ~= session then
		return
	end
	sessions[player] = nil
	if released then
		if session.pending then
			session.pending.claimedBy = nil
		end
		local pie = session.pie
		if pie then
			pie.claimedBy = nil
			if session.kind == "Cut" and pie.stage == "Cutting" and pie.slot and table.find(session.shop.pies, pie) then
				-- Put down mid-cut: back where it was on its belt (the fall clock starts over).
				returnToLane(session.shop, pie)
			end
			arrangeMakeLine(session.shop)
		end
		if session.order and session.order.stage == "Out" then
			session.order.claimedBy = nil
			session.order.stage = "Rack"
		end
		if session.consumed then
			for ing, n in session.consumed do
				session.shop.stock[ing] = math.min(Config.Shop.MaxStock, session.shop.stock[ing] + n)
			end
		end
	end
	if session.tool then
		session.tool:Destroy()
	end
	if session.kind == "Delivery" then
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = 16
		end
		Remotes.DeliveryTarget:FireClient(player, nil, 0)
	end
	updateBoards(session.shop)
end

function ShopService.CancelSession(player: Player)
	local session = sessions[player]
	if session then
		endSession(player, session, true)
		if session.kind ~= "Delivery" then
			Remotes.CancelMinigame:FireClient(player, session.token)
		end
	end
end

local function begin(player: Player, shop: Shop, stationName: string, data: any, extra: { [string]: any }?): Session
	local kind = STATION_KIND[stationName]
	local session: Session = {
		token = HttpService:GenerateGUID(false),
		kind = kind,
		station = stationName,
		shop = shop,
		started = os.clock(),
		data = data,
	}
	if extra then
		for k, v in extra do
			(session :: any)[k] = v
		end
	end
	sessions[player] = session
	if kind ~= "Delivery" then
		Remotes.StartMinigame:FireClient(player, kind, session.token, data)
	end
	updateBoards(shop)
	return session
end

local function hasStock(shop: Shop, needs: { [string]: number }): string?
	for ing, n in needs do
		if (shop.stock[ing] or 0) < n then
			return ing
		end
	end
	return nil
end

local function consume(shop: Shop, needs: { [string]: number })
	for ing, n in needs do
		shop.stock[ing] -= n
	end
end

local PHONE_LINES = {
	"Hi! Can I get %s delivered to house #%d?",
	"Yeah, I need %s. I'm at house #%d.",
	"Hello, delivery please: %s - house #%d!",
}
local WALKIN_LINES = {
	"Hi! Can I get %s for carryout?",
	"I'd like %s, please.",
	"Let me get %s, thanks!",
}

local function makeBag(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Delivery Bag"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.GripPos = Vector3.new(0, -0.6, 0)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(2.4, 1.0, 2.4)
	handle.Color = Color3.fromRGB(190, 30, 35)
	handle.Material = Enum.Material.Fabric
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool
	return tool
end

-- Starts `player` on the next job at a station. `pickId` picks a specific job
-- where there's a choice: a pizza (cheese / toppings / the oven exit) or an
-- order on the heat rack. Returns nil once a job has started, otherwise why
-- there's nothing to do there right now (shown as the station's "waiting
-- for..." status, or as a toast).
local function startStation(shop: Shop, stationName: string, player: Player, pickId: number?): string?
	local kind = STATION_KIND[stationName]

	if kind == "Register" then
		local entry: PendingOrder? = nil
		for _, e in shop.pending do
			if not e.claimedBy and (e.kind == "phone" or (e.customer and e.customer.state == "Queued")) then
				entry = e
				break
			end
		end
		if not entry then
			return "Waiting for customers or phone calls..."
		end
		entry.claimedBy = player
		local what = SalesPlan.describe(entry.items)
		local line = if entry.kind == "phone" then string.format(randomFrom(PHONE_LINES), what, entry.house or 0) else string.format(randomFrom(WALKIN_LINES), what)
		begin(player, shop, stationName, { line = line, phone = entry.kind == "phone", houses = #houses }, { pending = entry })
	elseif kind == "Dough" then
		-- Prep work, not made to order: stretch a skin of any size onto the rack.
		local counts, used = rackCounts(shop)
		if used >= Config.RackCapacity() then
			return string.format("The dough racks are full (%d/%d). Make some pizzas, then stretch more.", used, Config.RackCapacity())
		end
		local needs = { Dough = 1 }
		if hasStock(shop, needs) then
			return "Out of dough! A manager needs to unload the truck."
		end
		consume(shop, needs)
		begin(player, shop, stationName, {
			presses = Config.Dough.Presses,
			sizes = Config.Sizes,
			skins = counts,
			rackUsed = used,
			rackCapacity = Config.RackCapacity(),
			station = station(shop, stationName),
		}, { consumed = needs })
	elseif kind == "Sauce" then
		-- Sauce any skin on the racks: the saucer picks the size (the skin is taken at the end).
		local counts, used = rackCounts(shop)
		if used == 0 then
			return "No dough skins on the racks. Stretch some at the dough table."
		end
		local needs = { Sauce = 1 }
		if hasStock(shop, needs) then
			return "Out of sauce! A manager needs to unload the truck."
		end
		consume(shop, needs)
		begin(player, shop, stationName, { skins = counts, sizes = Config.Sizes, station = station(shop, stationName) }, { consumed = needs })
	elseif kind == "Cheese" or kind == "Toppings" then
		local stage = if kind == "Cheese" then "Sauced" else "Cheesed"
		local pie = pickPie(shop, stage, pickId)
		if not pie then
			if pickId then
				return "That pizza isn't waiting here any more."
			end
			return if kind == "Cheese" then "Waiting for sauced pizzas..." else "Waiting for cheesed pizzas..."
		end
		local needs: { [string]: number } = {}
		if kind == "Cheese" then
			needs.Cheese = 1
			local missing = hasStock(shop, needs)
			if missing then
				return "Out of " .. missing .. "! A manager needs to unload the truck."
			end
			consume(shop, needs)
		elseif readyRoom(shop) <= 0 then
			-- Every topped pizza needs a ready rack slot to go to.
			return string.format("The ready rack is full (%d/%d). Load some pizzas into the oven first.", Config.ReadyRack.Slots, Config.ReadyRack.Slots)
		end
		pie.claimedBy = player
		local data: any = {
			pieId = pie.id,
			size = pie.size,
			diameter = diameter(pie.size),
			station = station(shop, stationName),
			spec = pieSpec(pie, false), -- the layers it already has
			visual = pie.visual, -- the waiting copy, hidden locally while this player works it
		}
		if kind == "Toppings" then
			-- Any toppings, no targets: makers go by the order screen and the job aid.
			-- Bins that are out of stock can't be used.
			data.toppings = Config.Toppings
			data.out = {}
			for _, topping in Config.Toppings do
				if (shop.stock[topping] or 0) <= 0 then
					data.out[topping] = true
				end
			end
		end
		begin(player, shop, stationName, data, { pie = pie, consumed = needs })
	elseif kind == "Load" then
		-- Nothing to start: the loader clicks pizzas on the ready rack (LoadPizza).
		local ready = 0
		for _, p in shop.pies do
			if p.stage == "Ready" then
				ready += 1
			end
		end
		return if ready > 0 then string.format("%d pizza%s on the ready rack - click one to load it.", ready, if ready == 1 then "" else "s") else "The ready rack is empty."
	elseif kind == "Cut" then
		-- The oven tender picks which pizza to pull from the exit.
		local pie = if pickId then pickPie(shop, "Exit", pickId) else nil
		if not pie then
			if pickId then
				return "That pizza isn't at the oven exit any more."
			end
			local atExit, baking = 0, 0
			for _, p in shop.pies do
				if p.stage == "Exit" then
					atExit += 1
				elseif p.stage == "Oven" then
					baking += 1
				end
			end
			if atExit > 0 then
				return string.format("%d pizza%s at the oven exit - click one to pull it.", atExit, if atExit == 1 then "" else "s")
			end
			return if baking > 0 then string.format("Waiting on the oven: %d pizza%s baking...", baking, if baking == 1 then "" else "s") else "Waiting for pizzas to come out of the oven..."
		end
		-- Off the belt and onto the cut table (others see it there while it's worked).
		pie.claimedBy = player
		local exitPos = if pie.visual and pie.visual.PrimaryPart then pie.visual.PrimaryPart.Position else nil
		local lanePies = if pie.slot then shop.lanes[pie.slot] else {}
		local i = table.find(lanePies, pie)
		if i then
			table.remove(lanePies, i)
		end
		setStage(pie, "Cutting")
		local landing = marker(shop, "CutLanding")
		if pie.visual and landing then
			Pizza3D.place(pie.visual, CFrame.new(landing.Position))
		end
		local bubbles = {}
		if math.random() < Config.Cut.BubbleChance then
			for _ = 1, math.random(1, Config.Cut.MaxBubbles) do
				table.insert(bubbles, { x = 0.25 + math.random() * 0.5, y = 0.25 + math.random() * 0.5 })
			end
		end
		local slices = Config.Cut.Slices[pie.size] or 8
		local ticket = pie.ticket
		begin(player, shop, stationName, {
			ticket = if ticket then string.sub(ticketLabel(ticket), 2) else nil, -- UIs add their own "#"
			pizza = if ticket then ticket.item.pizza else "extra",
			size = pie.size,
			cuts = slices // 2,
			bubbles = bubbles,
			sizes = Config.Sizes,
			station = station(shop, stationName),
			spec = pieSpec(pie, true),
			visual = pie.visual, -- hidden locally while the cutter works on it
			exitPos = exitPos,
		}, { pie = pie })
	elseif kind == "Supply" then
		local sorted = table.clone(Config.Ingredients)
		table.sort(sorted, function(a, b)
			return shop.stock[a] < shop.stock[b]
		end)
		local crates = {}
		for _ = 1, Config.Supply.Crates do
			table.insert(crates, sorted[math.random(1, 6)])
		end
		begin(player, shop, stationName, { crates = crates, shelves = Config.Ingredients })
	elseif kind == "Delivery" then
		-- The driver picks which order on the heat rack to take out.
		local order: Order? = nil
		local onRack = 0
		for _, o in shop.orders do
			if o.stage == "Rack" and not o.claimedBy then
				onRack += 1
				if pickId == nil or o.id == pickId then
					order = order or o
				end
			end
		end
		if not order or pickId == nil then
			if pickId then
				return "That order isn't on the heat rack any more."
			end
			return if onRack > 0 then string.format("%d order%s on the heat rack - pick one to take out.", onRack, if onRack == 1 then "" else "s") else "No orders on the heat rack yet."
		end
		local door = houses[order.house or 0]
		if not door then
			-- The phone order was rung in with an address that doesn't exist.
			removeOrder(shop, order)
			return "Order #" .. order.id .. " has an invalid address - tossed."
		end
		order.claimedBy = player
		order.stage = "Out"
		local tool = makeBag()
		tool.Parent = player:FindFirstChildOfClass("Backpack")
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:EquipTool(tool)
			humanoid.WalkSpeed = Config.Delivery.WalkSpeed
		end
		CarService.Ensure(player, shop.model)
		begin(player, shop, stationName, { house = order.house }, { order = order, tool = tool })
		Remotes.DeliveryTarget:FireClient(player, door, Config.Delivery.SlowTime)
		notify(player, string.format("Order #%d (%d pizza%s, %s) to house #%d. Your car's out back - drive safe!", order.id, #order.entered, if #order.entered == 1 then "" else "s", money(SalesPlan.price(order.entered)), order.house or 0), Color3.fromRGB(120, 255, 160))
	end
	return nil
end

---------------------------------------------------------------------------
-- Staying at a station
---------------------------------------------------------------------------
-- At a `stay` station (Config.Stations) a player keeps the first-person view
-- between jobs until they leave or switch stations. The server hands them the
-- next job there as soon as one is waiting (to whoever has waited longest),
-- except at `pick` stations, where they choose each job themselves.

local function setStatus(player: Player, stay: Stay, status: string?)
	if status ~= stay.status then
		stay.status = status
		if status then
			Remotes.StationStatus:FireClient(player, status)
		end
	end
end

-- Gives a player standing at a station their next job there (or the one they
-- picked, `pickId`), if there is one.
local function assign(player: Player, pickId: number?)
	local stay = stationed[player]
	if not stay or sessions[player] or not stay.shop.alive or not canWork() then
		return
	end
	local why = startStation(stay.shop, stay.name, player, pickId)
	if why and pickId then
		-- What they picked was taken; give them the next one instead (or the status).
		notify(player, why, Color3.fromRGB(255, 160, 100))
		why = startStation(stay.shop, stay.name, player, nil)
	end
	local session = sessions[player]
	if session and not holdsStation(session) then
		-- Took a delivery off the heat rack: they're heading out to the car.
		stationed[player] = nil
		Remotes.StationMode:FireClient(player, nil)
		return
	end
	setStatus(player, stay, why)
end

-- Steps away from the station (any pizza in hand goes back where it was).
local function leaveStation(player: Player)
	local stay = stationed[player]
	if not stay then
		return
	end
	stationed[player] = nil
	local session = sessions[player]
	if session and holdsStation(session) then
		ShopService.CancelSession(player)
	end
	if player.Parent then
		Remotes.StationMode:FireClient(player, nil)
	end
end

-- Moves the player to a station (from wherever they are, including another
-- station) and starts them on the job there, or the one they picked.
local function enterStation(shop: Shop, player: Player, stationName: string, pickId: number?)
	local session = sessions[player]
	if session then
		if not holdsStation(session) then
			notify(player, "Finish what you're doing first!")
			return
		end
		local current = if session.pie then session.pie.id elseif session.order then session.order.id else nil
		if session.station == stationName and (pickId == nil or pickId == current) then
			return -- already on it
		end
		-- Switching pizzas or stations: this one goes back for someone else.
		ShopService.CancelSession(player)
	end
	local stay = stationed[player]
	if not stay or stay.shop ~= shop or stay.name ~= stationName then
		stationed[player] = { shop = shop, name = stationName, idleSince = os.clock(), status = nil }
		Remotes.StationMode:FireClient(player, stationName, station(shop, stationName))
	end
	assign(player, pickId)
end

-- Every way of using a station ends up here: prompts, the HUD station bar and
-- rail, clicks on a pizza at the oven exit or an order on the heat rack, and
-- the "follow" button.
local function useStation(shop: Shop, stationName: string, player: Player, pickId: number?)
	if not shop.alive then
		return
	end
	if not canWork() then
		notify(player, closedMessage(), Color3.fromRGB(255, 160, 100))
		return
	end
	if not jobAllows(player, stationName) then
		local needed = {}
		for _, jobName in Config.JobsWithStation(stationName) do
			table.insert(needed, Config.Jobs[jobName].display)
		end
		notify(player, "That station is for: " .. table.concat(needed, ", ") .. ". Use Clock In / Positions (bottom left) to change jobs.", Color3.fromRGB(255, 160, 100))
		return
	end
	playerShop[player] = shop
	if STAY[stationName] then
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.SeatPart then
			notify(player, "Hop out of the car first.", Color3.fromRGB(255, 160, 100))
			return
		end
		enterStation(shop, player, stationName, pickId)
		return
	end
	-- One-off jobs (the truck): step away from any station first.
	local session = sessions[player]
	if session and not holdsStation(session) then
		notify(player, "Finish what you're doing first!")
		return
	end
	leaveStation(player)
	local why = startStation(shop, stationName, player, pickId)
	if why then
		notify(player, why, Color3.fromRGB(255, 160, 100))
	end
end

-- Results faster than a human could manage: drop the task instead of leaving the station stuck.
local function tooFast(player: Player)
	notify(player, "Whoa, too fast! Try that again.", Color3.fromRGB(255, 160, 100))
	ShopService.CancelSession(player)
end

local function isNumber(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- A station step is done: tell the client (so it can offer to follow this
-- pizza to its next station), and if they're staying at the station, line up
-- the next job there.
local function stepDone(player: Player, stationName: string, pie: Pie?)
	local info: any = { station = stationName }
	if pie then
		info.pieId = pie.id
		info.size = pie.size
		local nextStation = Config.StationForStage(pie.stage)
		if nextStation and nextStation ~= stationName then
			info.next = nextStation
			info.label = pie.size
		end
	end
	Remotes.StepDone:FireClient(player, info)
	local stay = stationed[player]
	if stay then
		stay.idleSince = os.clock()
		task.delay(Config.NextJobDelay, assign, player)
	end
end

-- Handles the result for every UI minigame. `payload` comes from the client: validate everything.
function ShopService.FinishMinigame(player: Player, token: any, payload: any)
	local session = sessions[player]
	if not session or session.token ~= token or session.kind == "Delivery" then
		return
	end
	if type(payload) ~= "table" then
		return
	end
	local shop = session.shop
	local elapsed = os.clock() - session.started
	local kind = session.kind

	if kind == "Register" then
		local entry = session.pending :: PendingOrder
		local rawItems, house = payload.items, payload.house
		if type(rawItems) ~= "table" or #rawItems < 1 or #rawItems > 40 then
			return
		end
		local items: { Item } = {}
		for _, it in rawItems do
			if type(it) ~= "table" or type(it.pizza) ~= "string" or not Config.Recipes[it.pizza] or type(it.size) ~= "string" or not table.find(Config.Sizes, it.size) then
				return
			end
			table.insert(items, { pizza = it.pizza, size = it.size })
		end
		if entry.kind == "phone" then
			if not isNumber(house) or house ~= math.floor(house) then
				return
			end
		else
			house = nil
		end
		if elapsed < 0.8 then
			return tooFast(player)
		end
		endSession(player, session, false)
		if entry.customer and entry.customer.state ~= "Queued" then
			notify(player, "That customer left.")
			return
		end
		local score = itemAccuracy(items, entry.items)
		if entry.kind == "phone" and house ~= entry.house then
			score *= 0.5
		end
		if elapsed > 20 + 3 * #entry.items then
			score *= 0.8
		end
		removePending(shop, entry)
		createOrder(shop, entry.kind, entry.items, entry.house, items, house, score, player, entry.customer)
		pay(shop, player, Config.Pay.Register, score, "Order taken")
		stepDone(player, "Register")
	elseif kind == "Dough" then
		local hits, size = payload.hits, payload.size
		if type(size) ~= "string" or not table.find(Config.Sizes, size) then
			return
		end
		local presses = Config.Dough.Presses[size]
		if type(hits) ~= "table" or #hits ~= presses then
			return
		end
		local sum = 0
		for _, h in hits do
			if not isNumber(h) then
				return
			end
			sum += math.clamp(h, 0, 1)
		end
		if elapsed < presses * 0.3 then
			return tooFast(player)
		end
		local _, used = rackCounts(shop)
		if used >= Config.RackCapacity() then
			-- The racks filled up while we were stretching: give the dough back.
			ShopService.CancelSession(player)
			notify(player, "The dough racks filled up while you were stretching - dough returned.", Color3.fromRGB(255, 160, 100))
			return
		end
		endSession(player, session, false)
		local score = sum / presses
		rackAdd(shop, { size = size, quality = score, made = os.clock() })
		updateSkinRack(shop)
		updateBoards(shop)
		pay(shop, player, Config.Pay.Dough, score, size .. " dough stretched")
		stepDone(player, "Dough")
	elseif kind == "Sauce" then
		-- Sauce: coverage inside the sauce line and a clean rim, nothing else (the spoodle never runs dry).
		local sauce, size = payload.sauce, payload.size
		local S = Config.Sauce
		if type(size) ~= "string" or not table.find(Config.Sizes, size) then
			return
		end
		if type(sauce) ~= "table" or type(sauce.cells) ~= "table" or #sauce.cells ~= S.Rings * S.Sectors then
			return
		end
		if elapsed < 1.5 then
			return tooFast(player)
		end
		local covered, inside = 0, 0
		for _, amount in sauce.cells do
			if not isNumber(amount) then
				return
			end
			amount = math.clamp(amount, 0, 1000)
			inside += amount
			if amount >= S.CoverAmount then
				covered += 1
			end
		end
		local rim = if isNumber(sauce.rim) then math.clamp(sauce.rim, 0, 1000) else 0
		local coverage = covered / #sauce.cells
		local mess = if inside + rim > 0 then rim / (inside + rim) else 0
		local score = coverage * math.clamp(1 - mess * 2.5, 0, 1)
		-- The skin comes off the rack now (the oldest of that size).
		local skin = rackTake(shop, size)
		if not skin then
			ShopService.CancelSession(player)
			notify(player, "Someone took the last " .. size .. " skin - pick another size.", Color3.fromRGB(255, 160, 100))
			return
		end
		updateSkinRack(shop)
		endSession(player, session, false)
		shop.pieCounter += 1
		local pie: Pie = {
			id = shop.pieCounter,
			size = size,
			stage = "Sauced",
			claimedBy = nil,
			quality = { skin.quality, score }, -- how well the dough was stretched, then sauced
			visual = nil,
			sauce = score,
			cheese = nil,
			cheeseFactor = 1,
			counts = nil,
			portionFactor = 1,
			toppedBy = nil,
			workers = { [player] = true },
			ticket = nil,
			slot = nil,
			pos = 0,
			bake = 0,
			settleAt = 0,
			loadedAt = nil,
			exitAt = nil,
			boxWrong = false,
		}
		table.insert(shop.pies, pie)
		placeOnLine(shop, pie)
		updateBoards(shop)
		pay(shop, player, Config.Pay.Sauce, score, size .. " sauced")
		if mess > 0.05 then
			notify(player, "Sauce got on the rim - keep it inside the 3/4\" line.", Color3.fromRGB(255, 180, 100))
		end
		stepDone(player, "Sauce", pie)
	elseif kind == "Cheese" then
		local cheese = payload.cheese
		if not isNumber(cheese) then
			return
		end
		if elapsed < 1 then
			return tooFast(player)
		end
		local pie = session.pie :: Pie
		local target = Config.CheesePortion[pie.size] or 6
		local oz = math.clamp(cheese, 0, target * 3)
		local factor = Config.PortionFactor(oz, target)
		endSession(player, session, false)
		pie.claimedBy = nil
		pie.cheese = oz / target
		pie.cheeseFactor = factor
		pie.portionFactor = factor
		table.insert(pie.quality, factor)
		pie.workers[player] = true
		setStage(pie, "Cheesed")
		placeOnLine(shop, pie)
		updateBoards(shop)
		pay(shop, player, Config.Pay.Cheese, factor, "Cheesed")
		if factor < 1 then
			notify(player, "Cheese portion was more than 10% off - the customer will notice.", Color3.fromRGB(255, 180, 100))
		end
		stepDone(player, "Cheese", pie)
	elseif kind == "Toppings" then
		-- Whatever went on; it's scored against an order when it's loaded.
		local counts = payload.counts
		if type(counts) ~= "table" then
			return
		end
		if elapsed < 1 then
			return tooFast(player)
		end
		local pie = session.pie :: Pie
		local placed: { [string]: number } = {}
		for _, topping in Config.Toppings do
			local n = counts[topping]
			n = if isNumber(n) then math.clamp(math.floor(n), 0, 80) else 0
			if n > 0 and (shop.stock[topping] or 0) <= 0 then
				n = 0 -- that bin was empty
			end
			placed[topping] = n
			if n > 0 then
				shop.stock[topping] -= 1
			end
		end
		endSession(player, session, false)
		pie.claimedBy = nil
		pie.counts = placed
		pie.toppedBy = player
		pie.workers[player] = true
		pie.readySlot = freeReadySlot(shop) -- there's always one: it was counted when the job started
		setStage(pie, "Ready")
		placeOnLine(shop, pie)
		updateBoards(shop)
		if payload.load == true then
			local orderId = if isNumber(payload.orderId) then payload.orderId else nil
			local why = loadPie(shop, player, pie, orderId)
			if why then
				notify(player, why, Color3.fromRGB(255, 160, 100))
			end
		end
		stepDone(player, "Toppings", pie)
	elseif kind == "Cut" then
		local angles, popped, box, season = payload.angles, payload.popped, payload.box, payload.season
		local cuts = session.data.cuts
		if type(angles) ~= "table" or #angles ~= cuts then
			return
		end
		if type(box) ~= "string" or not table.find(Config.Sizes, box) then
			return
		end
		local norm = {}
		for _, a in angles do
			if not isNumber(a) then
				return
			end
			table.insert(norm, a % 180)
		end
		if elapsed < 2 then
			return tooFast(player)
		end
		-- Even slices: how far each gap between cuts is from the ideal.
		table.sort(norm)
		local ideal = 180 / cuts
		local err = 0
		for i = 1, cuts do
			local nextAngle = if i < cuts then norm[i + 1] else norm[1] + 180
			err += math.abs((nextAngle - norm[i]) - ideal)
		end
		local cutScore = math.clamp(1 - err / 180, 0, 1)
		local bubbleCount = #session.data.bubbles
		local poppedCount = if isNumber(popped) then math.clamp(math.floor(popped), 0, bubbleCount) else 0
		local bubbleScore = if bubbleCount == 0 then 1 else poppedCount / bubbleCount
		-- Seasoning: share of the crust's sectors covered, less what was shaken off the crust.
		local seasonScore = 0
		if type(season) == "table" and type(season.sectors) == "table" then
			local hit = 0
			for i = 1, Config.Cut.SeasonSectors do
				if season.sectors[i] == true then
					hit += 1
				end
			end
			local off = if isNumber(season.off) then math.clamp(season.off, 0, 1) else 0
			seasonScore = hit / Config.Cut.SeasonSectors * (1 - off * 0.5)
		end
		local pie = session.pie :: Pie
		local boxOk = box == pie.size
		local score = 0.45 * cutScore + 0.15 * bubbleScore + 0.2 * seasonScore + (if boxOk then 0.2 else 0)

		endSession(player, session, false)
		pie.claimedBy = nil
		pie.boxWrong = not boxOk
		table.insert(pie.quality, score)
		pie.workers[player] = true
		setStage(pie, "Boxed")
		removePie(shop, pie)
		local profile = DataService.Get(player)
		if profile then
			profile.PizzasMade += 1
		end
		pay(shop, player, Config.Pay.Cut, score, if boxOk then "Cut & boxed" else "Wrong box size!")
		local ticket = pie.ticket
		if ticket then
			ticket.boxed = true
			for w in pie.workers do
				ticket.order.workers[w] = true
			end
			updateBoards(shop)
			checkOrder(shop, ticket.order)
		else
			notify(player, "That one was an extra - no order needed it.", Color3.fromRGB(255, 160, 100))
			updateBoards(shop)
		end
		stepDone(player, "CutTable")
	elseif kind == "Supply" then
		local answers = payload.answers
		local crates = session.data.crates
		if type(answers) ~= "table" or #answers ~= #crates then
			return
		end
		if elapsed < #crates * 0.2 then
			return tooFast(player)
		end
		endSession(player, session, false)
		local correct = 0
		for i, crate in crates do
			if answers[i] == crate then
				correct += 1
				shop.stock[crate] = math.min(Config.Shop.MaxStock, shop.stock[crate] + Config.Supply.RestockPerCrate)
			end
		end
		updateBoards(shop)
		pay(shop, player, Config.Pay.Supply, correct / #crates, string.format("Put away %d/%d cases", correct, #crates))
		stepDone(player, "SupplyTruck")
	end
end

local function onDoor(player: Player, door: Part)
	local session = sessions[player]
	if not session or session.kind ~= "Delivery" then
		return
	end
	local order = session.order :: Order
	local houseId = door:GetAttribute("HouseId")
	if houseId ~= order.house then
		notify(player, "Wrong house! This one goes to #" .. tostring(order.house), Color3.fromRGB(255, 160, 100))
		return
	end
	local elapsed = os.clock() - session.started
	local d = Config.Delivery
	local speed = 1 - 0.6 * math.clamp((elapsed - d.FastTime) / (d.SlowTime - d.FastTime), 0, 1)
	local shop = session.shop
	endSession(player, session, false)
	order.claimedBy = nil
	local profile = DataService.Get(player)
	if profile then
		profile.Deliveries += 1
	end
	pay(shop, player, Config.Pay.Delivery, speed, string.format("Delivered in %ds", math.floor(elapsed)))
	completeOrder(shop, order, speed, player)
	notify(player, "Head back to the store for your next run.", Color3.fromRGB(180, 220, 255))
end

---------------------------------------------------------------------------
-- Store lifecycle
---------------------------------------------------------------------------

-- Closing time: send everyone home and clear the board.
local function closeStore(shop: Shop)
	for player, stay in table.clone(stationed) do
		if stay.shop == shop then
			leaveStation(player)
		end
	end
	for player, session in table.clone(sessions) do
		if session.shop == shop then
			ShopService.CancelSession(player)
		end
	end
	-- Clear orders before customers leave, so nobody gets "customer gave up" alerts at close.
	table.clear(shop.pending)
	for _, o in table.clone(shop.orders) do
		removeOrder(shop, o)
	end
	-- Whatever's left on the make-line, the shelf and the belts gets thrown out.
	for _, pie in table.clone(shop.pies) do
		removePie(shop, pie)
	end
	for slot = 1, Config.Oven.Slots do
		table.clear(shop.lanes[slot])
	end
	for _, c in table.clone(shop.customers) do
		customerLeave(shop, c, "Aw, they're closing...")
	end
	for player, s in table.clone(playerShop) do
		if s == shop and player:GetAttribute("Job") then
			ShopService.SetJob(player, nil)
			notify(player, string.format("The store's closed for the night and you've been clocked out (%s).", GameClock.hoursText()), Color3.fromRGB(180, 220, 255))
		end
	end
	updateBoards(shop)
	updateSalesBoard(shop)
end

-- Plans the week/day and generates orders against the forecast.
local function runDemand(shop: Shop)
	local weekHour = ClockService.WeekHour()
	local day, hour = GameClock.split(weekHour)
	if shop.weekNumber ~= ClockService.WeekNumber() or not shop.week then
		shop.weekNumber = ClockService.WeekNumber()
		shop.week = SalesPlan.newWeek(shop.rng, shop.volume)
		shop.sales.week = 0
	end
	if shop.day ~= day then
		shop.day = day
		shop.demandToday = 0
		shop.sales.today = 0
		shop.sales.crewToday = 0
		shop.sales.ordersToday = 0
		shop.sales.loadSum = 0
		shop.sales.loadCount = 0
		shop.sales.totalSum = 0
		shop.sales.totalCount = 0
		shop.mix = SalesPlan.dayMix(shop.rng)
	end
	if not GameClock.isOpen(weekHour) then
		return
	end
	local week = shop.week :: SalesPlan.Week
	local planned = week.days[day] * SalesPlan.shareByHour(hour)
	local guard = 0
	while shop.demandToday < planned and guard < 6 do
		guard += 1
		local items = SalesPlan.rollItems(shop.mix, shop.rng)
		shop.demandToday += SalesPlan.price(items)
		newOrder(shop, items)
	end
end

-- What staff see on the HUD: how much is waiting at each station (station bar
-- and rail), the make-line queue (orders still waiting on pizzas to go in the
-- oven; loaded ones ticked off), what's in the ovens (for the oven tender),
-- the heat rack (for drivers), and what's on the dough racks.
local function queueSnapshot(shop: Shop): any
	local now = os.clock()
	local waiting: { [string]: number } = {}
	for _, e in shop.pending do
		if not e.claimedBy then
			waiting.Register = (waiting.Register or 0) + 1
		end
	end
	local ready = 0
	for _, p in shop.pies do
		local stationName = Config.StationForStage(p.stage)
		if stationName and not p.claimedBy then
			waiting[stationName] = (waiting[stationName] or 0) + 1
		end
		if p.stage == "Ready" then
			ready += 1
		end
	end
	if ready > 0 then
		waiting.Load = ready
	end
	for _, o in shop.orders do
		if o.stage == "Rack" and not o.claimedBy then
			waiting.DeliveryRack = (waiting.DeliveryRack or 0) + 1
		end
	end
	local makeQueue = {}
	for _, o in shop.orders do
		if o.stage == "Making" and not o.cancelled and loadedCount(o) < #o.tickets and #makeQueue < 12 then
			local items = {}
			for _, t in o.tickets do
				table.insert(items, { size = t.item.size, pizza = t.item.pizza, loaded = t.pie ~= nil or t.boxed })
			end
			table.insert(makeQueue, { id = o.id, delivery = o.delivery, house = o.house, age = now - o.created, items = items })
		end
	end
	local oven = {}
	for slot = 1, Config.Oven.Slots do
		local lane = laneOf(shop, slot)
		if not lane then
			continue
		end
		local speed = lane.length / Config.Oven.BakeTime
		for _, p in shop.lanes[slot] do
			local t = p.ticket
			table.insert(oven, {
				id = p.id,
				slot = slot,
				size = p.size,
				label = if t then string.format("#%s %s", string.sub(ticketLabel(t), 2), t.item.pizza) else "extra",
				out = p.stage == "Exit", -- out of the chamber: can be pulled
				left = math.max(0, (lane.mouthOut - p.pos - diameter(p.size) / 2) / speed), -- until it comes out
				fallsIn = if p.exitAt then math.max(0, Config.Oven.FallAfter - (now - p.exitAt)) else nil,
			})
		end
	end
	table.sort(oven, function(x, y)
		return x.left < y.left
	end)
	local delivery = {}
	for _, o in shop.orders do
		if o.delivery and (o.stage == "Rack" or o.stage == "Out") then
			table.insert(delivery, {
				id = o.id,
				house = o.house,
				count = #o.tickets,
				stage = o.stage,
				age = now - (o.readyAt or o.created),
				driver = if o.claimedBy then o.claimedBy.DisplayName else nil,
			})
		end
	end
	local counts, used = rackCounts(shop)
	return {
		waiting = waiting,
		rack = { counts = counts, used = used, capacity = Config.RackCapacity() },
		orders = makeQueue,
		ready = ready,
		readyCapacity = Config.ReadyRack.Slots,
		oven = oven,
		delivery = delivery,
	}
end

local function tick(shop: Shop)
	local now = os.clock()
	local S = Config.Shop
	runDemand(shop)
	updateSalesBoard(shop)

	-- Hand waiting work to the players standing at stations, longest-waiting first.
	local idle = {}
	for player, stay in stationed do
		if stay.shop == shop and not sessions[player] then
			table.insert(idle, player)
		end
	end
	table.sort(idle, function(a, b)
		return stationed[a].idleSince < stationed[b].idleSince
	end)
	for _, player in idle do
		assign(player)
	end

	-- Keep everyone on shift here up to date for the queue panel / station bar.
	local staff = staffAt(shop, STAFF_JOBS)
	if #staff > 0 then
		local snapshot = queueSnapshot(shop)
		for _, p in staff do
			Remotes.QueueUpdate:FireClient(p, snapshot)
		end
	end

	-- Refresh the screens every second so load times tick up live.
	updateBoards(shop)

	if not isOpen() then
		return
	end

	-- Online kiosk picks up walk-ins and calls nobody has answered. Staff on shift
	-- get a longer window to take them first (they're often busy on the make-line).
	local kioskDelay = if onShift(shop, STAFF_JOBS) then S.AutoRegisterDelay * 3 else S.AutoRegisterDelay
	for _, e in table.clone(shop.pending) do
		if not e.claimedBy and now - e.created > kioskDelay then
			if not e.customer or e.customer.state == "Queued" then
				removePending(shop, e)
				createOrder(shop, if e.kind == "phone" then "phone" else "walkin", e.items, e.house, table.clone(e.items), e.house, 1, nil, e.customer)
			end
		end
	end

	-- Trickle restock when no manager is on shift to unload the truck.
	if not onShift(shop, MANAGEMENT_JOBS) and now - shop.lastRestock > S.AutoRestockInterval then
		shop.lastRestock = now
		for _, ing in Config.Ingredients do
			if shop.stock[ing] < S.StartingStock then
				shop.stock[ing] = math.min(S.StartingStock, shop.stock[ing] + S.AutoRestockAmount)
			end
		end
		updateBoards(shop)
	end

	-- Impatient customers (not ones already collecting their boxes).
	for _, c in table.clone(shop.customers) do
		local collecting = c.order ~= nil and c.order.stage == "Pickup"
		if c.state ~= "Leaving" and not collecting and now - c.arrived > S.CustomerPatience + S.PatiencePerPizza * (#c.items - 1) then
			customerLeave(shop, c, "I've waited forever! >:(")
		end
	end

	-- Orders whose customer walked out come off the screens; any pizzas already
	-- made for them carry on as extras.
	for _, o in table.clone(shop.orders) do
		if o.cancelled and o.stage == "Making" then
			removeOrder(shop, o)
		end
	end
end

function ShopService.AddShop(model: Model, name: string, owner: Player?, volume: number?): Shop
	nextShopId += 1
	local shop: Shop = {
		id = nextShopId,
		name = name,
		model = model,
		owner = owner,
		volume = volume or 1,
		stock = {},
		customers = {},
		pending = {},
		orders = {},
		tickets = {},
		pies = {},
		lanes = {},
		nextSlot = 1,
		orderCounter = 0,
		ticketCounter = 0,
		pieCounter = 0,
		rng = Random.new(),
		week = nil,
		weekNumber = 0,
		day = 0,
		mix = { small = 0.88, medium = 0.11, large = 0.01 },
		demandToday = 0,
		sales = { today = 0, week = 0, crewToday = 0, ordersToday = 0, loadSum = 0, loadCount = 0, totalSum = 0, totalCount = 0 },
		rack = {},
		lastRestock = os.clock(),
		spawning = 0,
		alive = true,
	}
	for _, ing in Config.Ingredients do
		shop.stock[ing] = Config.Shop.StartingStock
	end
	for slot = 1, Config.Oven.Slots do
		shop.lanes[slot] = {}
	end

	-- A store that opens mid-day shouldn't dump the whole morning's orders at once.
	local day, hour = GameClock.split(ClockService.WeekHour())
	shop.weekNumber = ClockService.WeekNumber()
	shop.week = SalesPlan.newWeek(shop.rng, shop.volume)
	shop.day = day
	shop.mix = SalesPlan.dayMix(shop.rng)
	shop.demandToday = (shop.week :: SalesPlan.Week).days[day] * SalesPlan.shareByHour(hour)

	local function openTimeClock(player: Player)
		if not canWork() then
			notify(player, closedMessage(), Color3.fromRGB(255, 160, 100))
			return
		end
		playerShop[player] = shop
		Remotes.OpenJobMenu:FireClient(player, shop.name)
	end

	local stations = model:FindFirstChild("Stations") :: Folder
	for _, st in stations:GetChildren() do
		local pp = st:FindFirstChild("ProximityPrompt") :: ProximityPrompt?
		local stationName = st:GetAttribute("Station")
		if not pp or type(stationName) ~= "string" then
			continue
		end
		if stationName == "Pickup" then
			pp.Enabled = false
		elseif stationName == "Register" then
			-- The register doubles as the time clock: F clocks in/out, and E
			-- while off duty opens the clock-in menu instead of taking an order.
			local clock = st:FindFirstChild("ClockPrompt") :: ProximityPrompt?
			if clock then
				clock.Triggered:Connect(openTimeClock)
			end
			pp.Triggered:Connect(function(player)
				if player:GetAttribute("Job") == nil then
					openTimeClock(player)
				else
					useStation(shop, stationName, player)
				end
			end)
		elseif stationName == "Fridge" then
			pp.Triggered:Connect(function(player)
				local parts = {}
				for _, ing in Config.Ingredients do
					table.insert(parts, ing .. " " .. shop.stock[ing])
				end
				notify(player, "Stock: " .. table.concat(parts, ", "))
			end)
		else
			pp.Triggered:Connect(function(player)
				useStation(shop, stationName, player)
			end)
		end
	end

	table.insert(shops, shop)
	updateBoards(shop)
	updateSalesBoard(shop)
	return shop
end

function ShopService.RemoveShop(shop: Shop)
	shop.alive = false
	for player, stay in table.clone(stationed) do
		if stay.shop == shop then
			leaveStation(player)
		end
	end
	for player, session in table.clone(sessions) do
		if session.shop == shop then
			ShopService.CancelSession(player)
		end
	end
	for player, s in table.clone(playerShop) do
		if s == shop then
			playerShop[player] = nil
			CarService.Release(player)
		end
	end
	local i = table.find(shops, shop)
	if i then
		table.remove(shops, i)
	end
	shop.model:Destroy()
end

-- Management slots are finite and go to the highest-XP players.
-- No management at the store: anyone may step up. Otherwise the role's
-- minLevel applies, and when every slot is taken you must out-XP the
-- lowest holder, who is bumped down (GM -> Shift Manager if a slot is free, else CSR).
function ShopService.TryManagement(player: Player, shop: Shop, role: string): (boolean, string)
	local M = Config.Management[role]
	if not M then
		return false, "Unknown role."
	end
	if #staffAt(shop, MANAGEMENT_JOBS) == 0 then
		return true, ""
	end
	if DataService.GetLevel(player) < M.minLevel then
		return false, string.format("%s needs level %d (management is already on shift).", Config.Jobs[role].display, M.minLevel)
	end
	local holders = staffAt(shop, { role })
	if #holders < M.slots then
		return true, ""
	end
	local function xpOf(p: Player): number
		return tonumber(p:GetAttribute("XP")) or 0
	end
	table.sort(holders, function(a, b)
		return xpOf(a) < xpOf(b)
	end)
	local lowest = holders[1]
	if xpOf(player) <= xpOf(lowest) then
		return false, "All " .. Config.Jobs[role].display .. " slots are held by players with more XP."
	end
	local demoteTo = "CSR"
	if role == "GeneralManager" and #staffAt(shop, { "ShiftManager" }) < Config.Management.ShiftManager.slots then
		demoteTo = "ShiftManager"
	end
	ShopService.SetJob(lowest, demoteTo)
	notify(lowest, string.format("%s has more XP and took your %s slot. You're now %s.", player.DisplayName, Config.Jobs[role].display, Config.Jobs[demoteTo].display), Color3.fromRGB(255, 160, 100))
	return true, ""
end

function ShopService.SetJob(player: Player, job: string?)
	leaveStation(player)
	ShopService.CancelSession(player)
	if job ~= "Delivery" then
		CarService.Release(player)
	end
	player:SetAttribute("Job", job)
	local character = player.Character
	if not character then
		return
	end
	setUniform(character, job ~= nil)
	local head = character:FindFirstChild("Head")
	if head then
		local old = head:FindFirstChild("JobTag")
		if old then
			old:Destroy()
		end
		if job then
			local def = Config.Jobs[job]
			local gui = Instance.new("BillboardGui")
			gui.Name = "JobTag"
			gui.Size = UDim2.fromOffset(140, 26)
			gui.StudsOffset = Vector3.new(0, 2.6, 0)
			gui.MaxDistance = 50
			local tl = Instance.new("TextLabel")
			tl.Size = UDim2.fromScale(1, 1)
			tl.BackgroundColor3 = def.color
			tl.BackgroundTransparency = 0.15
			tl.TextColor3 = Color3.new(1, 1, 1)
			tl.Font = Enum.Font.GothamBold
			tl.TextScaled = true
			tl.Text = def.display
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 8)
			corner.Parent = tl
			tl.Parent = gui
			gui.Parent = head
		end
	end
end

function ShopService.Init(houseDoors: { Part })
	houses = houseDoors
	for _, door in houses do
		local pp = door:FindFirstChildOfClass("ProximityPrompt")
		if pp then
			pp.Triggered:Connect(function(player)
				onDoor(player, door)
			end)
		end
	end

	Remotes.MinigameResult.OnServerEvent:Connect(function(player, token, payload)
		ShopService.FinishMinigame(player, token, payload)
	end)
	Remotes.CancelMinigame.OnServerEvent:Connect(function(player, token)
		local session = sessions[player]
		if session and session.token == token then
			if stationed[player] then
				leaveStation(player) -- otherwise the same job would just be handed straight back
			else
				ShopService.CancelSession(player)
			end
		end
	end)
	Remotes.LeaveStation.OnServerEvent:Connect(leaveStation)
	-- Loading a finished pizza from the ready rack into the oven (at the Load Oven station).
	Remotes.LoadPizza.OnServerEvent:Connect(function(player, pieId, orderId)
		if not isNumber(pieId) or (orderId ~= nil and not isNumber(orderId)) then
			return
		end
		local stay = stationed[player]
		if not stay or stay.name ~= "Load" then
			return
		end
		local pie = findPie(stay.shop, pieId)
		local why = if pie then loadPie(stay.shop, player, pie, orderId) else "That pizza isn't on the ready rack any more."
		if why then
			notify(player, why, Color3.fromRGB(255, 160, 100))
		end
	end)
	-- The oven belts move ten times a second.
	local sinceStep = 0
	RunService.Heartbeat:Connect(function(dt)
		sinceStep += dt
		if sinceStep < 0.1 then
			return
		end
		local step = sinceStep
		sinceStep = 0
		for _, shop in shops do
			if shop.alive then
				local ok, err = pcall(ovenStep, shop, step)
				if not ok then
					warn("[ShopService] oven error:", err)
				end
			end
		end
	end)
	-- HUD "Clock In" button: open the time clock for the nearest store.
	Remotes.RequestTimeClock.OnServerEvent:Connect(function(player)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return
		end
		local nearest: Shop? = nil
		local best = 220
		for _, shop in shops do
			local dist = (shop.model:GetPivot().Position - root.Position).Magnitude
			if shop.alive and dist < best then
				nearest, best = shop, dist
			end
		end
		if not nearest then
			notify(player, "Head to a " .. Config.GameName .. " store to clock in.", Color3.fromRGB(255, 160, 100))
			return
		end
		if not canWork() then
			notify(player, closedMessage(), Color3.fromRGB(255, 160, 100))
			return
		end
		playerShop[player] = nearest
		Remotes.OpenJobMenu:FireClient(player, nearest.name)
	end)

	-- HUD station bar and rail, queue panel clicks, and the "follow" button.
	-- Works from anywhere in your store; you're moved to the station.
	Remotes.UseStation.OnServerEvent:Connect(function(player, stationName, pickId)
		if type(stationName) ~= "string" or (pickId ~= nil and not isNumber(pickId)) then
			return
		end
		local shop = playerShop[player]
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not shop or not shop.alive or not root then
			notify(player, "Clock in at a store first.", Color3.fromRGB(255, 160, 100))
			return
		end
		if (shop.model:GetPivot().Position - root.Position).Magnitude > 90 then
			notify(player, "Head back to your store to work a station.", Color3.fromRGB(255, 160, 100))
			return
		end
		if not station(shop, stationName) or stationName == "Pickup" or stationName == "Fridge" then
			return
		end
		useStation(shop, stationName, player, pickId)
	end)

	Remotes.ChooseJob.OnServerEvent:Connect(function(player, job)
		if job ~= nil and (type(job) ~= "string" or not Config.Jobs[job]) then
			return
		end
		local shop = playerShop[player]
		if job and (not shop or not canWork()) then
			notify(player, if shop then closedMessage() else "Head to a store to clock in.", Color3.fromRGB(255, 160, 100))
			return
		end
		if job and Config.Management[job] and player:GetAttribute("Job") ~= job then
			local ok, reason = ShopService.TryManagement(player, shop :: Shop, job)
			if not ok then
				notify(player, reason, Color3.fromRGB(255, 160, 100))
				return
			end
		end
		ShopService.SetJob(player, job)
		if job then
			notify(player, "Clocked in as " .. Config.Jobs[job].display .. "!", Config.Jobs[job].color)
		else
			notify(player, "Clocked out.")
		end
		if job == "Delivery" and shop then
			CarService.Ensure(player, shop.model)
			notify(player, "Your delivery car is parked in the lot out back.", Color3.fromRGB(120, 255, 160))
		end
	end)

	local function hookCharacter(player: Player)
		player.CharacterAdded:Connect(function(character)
			leaveStation(player)
			ShopService.CancelSession(player)
			local job = player:GetAttribute("Job")
			if type(job) == "string" then
				character:WaitForChild("Head", 5)
				ShopService.SetJob(player, job)
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		hookCharacter(player)
	end
	Players.PlayerAdded:Connect(hookCharacter)
	Players.PlayerRemoving:Connect(function(player)
		stationed[player] = nil
		ShopService.CancelSession(player) -- also releases anything they had claimed
		playerShop[player] = nil
	end)

	ClockService.Closed:Connect(function()
		for _, shop in table.clone(shops) do
			if shop.alive then
				closeStore(shop)
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for player, session in table.clone(sessions) do
				local limit = if session.kind == "Delivery" then Config.Delivery.SlowTime * 2 else SESSION_TIMEOUT
				if now - session.started > limit then
					if stationed[player] then
						-- Away from the keyboard: take them off the station so the job isn't handed straight back.
						notify(player, "You were idle too long, so you stepped away from the station.", Color3.fromRGB(255, 160, 100))
						leaveStation(player)
					else
						notify(player, "You took too long - task cancelled.", Color3.fromRGB(255, 160, 100))
						ShopService.CancelSession(player)
					end
				end
			end
			for _, shop in table.clone(shops) do
				if shop.alive then
					local ok, err = pcall(tick, shop)
					if not ok then
						warn("[ShopService] tick error:", err)
					end
				end
			end
		end
	end)
end

return ShopService
