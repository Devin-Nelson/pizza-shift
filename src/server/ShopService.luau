--!strict
-- Runs every store: the sales forecast and order flow, carryout customers,
-- phone + online orders (one or many pizzas each), dough prep (skins on the
-- rack), the per-pizza ticket pipeline (Make-Line -> conveyor Oven -> end of
-- belt -> Cut & Box), the heat rack and deliveries, hired staff (NPCs), stock,
-- open hours, and the server side of every station minigame. The client only
-- ever reports inputs; scoring and payouts happen here.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Follow = require(ReplicatedStorage.Shared.Follow)
local GameClock = require(ReplicatedStorage.Shared.GameClock)
local Pizza3D = require(ReplicatedStorage.Shared.Pizza3D)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Staff = require(ReplicatedStorage.Shared.Staff)
local Style = require(ReplicatedStorage.Shared.Style)
local CarService = require(script.Parent.CarService)
local ClockService = require(script.Parent.ClockService)
local DataService = require(script.Parent.DataService)
local SalesPlan = require(script.Parent.SalesPlan)
local Screens = require(script.Parent.Screens)
local StationArt = require(script.Parent.StationArt)

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
	name: string, -- "John P.": what they say at the counter to collect a carryout order
	atCounter: number?, -- when they stepped up to the counter, their order on the carryout rack
}

type PendingOrder = {
	kind: string, -- "walkin" | "phone"
	items: { Item },
	house: number?,
	customer: Customer?,
	created: number,
	claimedBy: any, -- a Player, or a hired staff member (Crew)
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
	claimedBy: any, -- a Player, or a hired staff member (Crew)
	lost: boolean?, -- the customer never got it (counted in sales.lostToday)
	rackSlot: number?, -- boxed carryout: its slot on the carryout rack
	stack: Model?, -- boxed carryout: its boxes (on the rack, or in someone's hands)
	carriedBy: Player?, -- boxed carryout: whoever took it off the rack to hand over
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
	claimedBy: any, -- a Player, or a hired staff member (Crew)
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

-- A hired staff member (an NPC) in a store. `member`: their saved record in
-- the owner's profile (XP goes straight into it). `station`: the one of
-- their stations they're at (managers move between theirs; `next` is where
-- they look for work first). `present`: in for this shift (scheduled and
-- didn't call out). `job`: what they're in the middle of, done at `busyUntil`.
type Crew = {
	member: Staff.Member,
	name: string,
	station: string, -- the heat rack: they drive
	next: number,
	present: boolean,
	npc: Model?,
	busyUntil: number,
	job: any?,
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
	sales: { today: number, week: number, lostToday: number, ordersToday: number, loadSum: number, loadCount: number, totalSum: number, totalCount: number },
	rack: { [number]: RackSkin }, -- dough rack slot -> stretched skin (nil = empty)
	trays: { [string]: { [number]: boolean } }, -- dough balls still in each size's tray on the stretch table, by Index
	lastRestock: number,
	spawning: number,
	crew: { Crew },
	shift: string?, -- the staff shift now on (Staff.shiftAt)
	calledOut: { [number]: boolean }, -- member ids who called out of this shift
	carryout: { [number]: Order }, -- carryout rack slot -> the boxed order waiting there
	carryQueue: { Order }, -- boxed carryout orders waiting for a free slot
	bags: { [Order]: BasePart }, -- delivery orders' hot bags on the delivery ready rack
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
-- for..." text sent to them. `size`: while following, the size the top pizza
-- needs stretched or sauced here (they don't choose).
type Stay = { shop: Shop, name: string, idleSince: number, status: string?, size: string? }

local ShopService = {}

local shops: { Shop } = {}
local sessions: { [Player]: Session } = {}
local stationed: { [Player]: Stay } = {}
-- Players who picked a make station from the HUD: they stay there instead of
-- following the top pizza (the default).
local parked: { [Player]: boolean } = {}
local playerShop: { [Player]: Shop } = {}
local carrying: { [Player]: Order } = {} -- the carryout order each player has in hand
local CARRYOUT_REACH = 18 -- how far away a carryout stack, the rack or a customer can be clicked
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
local SESSION_TIMEOUT = 120
local FLAT = Pizza3D.FLAT

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

-- The players working at `shop` (its members, see ShopService.SetMember).
local function membersOf(shop: Shop): { Player }
	local list = {}
	for player, s in playerShop do
		if s == shop and player.Parent then
			table.insert(list, player)
		end
	end
	return list
end

-- Delivery orders need a second player, or staff on shift who drive (the heat rack is one of their stations).
local function takesDeliveries(shop: Shop): boolean
	if #membersOf(shop) >= Config.Store.DeliveryMinPlayers then
		return true
	end
	for _, c in shop.crew do
		if c.present and table.find(c.member.stations, "DeliveryRack") then
			return true
		end
	end
	return false
end

-- Who has hold of something: a player or a hired staff member.
local function whoName(who: any): string?
	return if typeof(who) == "Instance" then (who :: Player).DisplayName elseif type(who) == "table" then who.name else nil
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

-- Stations open 30 minutes before the store (to prep) until midnight.
local function canWork(): boolean
	return GameClock.canWork(ClockService.WeekHour())
end

local function closedMessage(): string
	local hours = math.ceil(GameClock.hoursUntilWork(ClockService.WeekHour()))
	return string.format("We're closed (%s). That's about %d game hour%s away.", GameClock.hoursText(), hours, if hours == 1 then "" else "s")
end

local function formatMinutes(seconds: number): string
	return string.format("%d:%02d", seconds // 60, math.floor(seconds % 60))
end

local function itemKey(it: Item): string
	return it.size .. "|" .. table.concat(it.toppings, "+")
end

-- Items rung in vs. items wanted: fraction that match (as multisets).
local function itemAccuracy(entered: { Item }, desired: { Item }): number
	local want: { [string]: number } = {}
	for _, it in desired do
		local k = itemKey(it)
		want[k] = (want[k] or 0) + 1
	end
	local matched = 0
	for _, it in entered do
		local k = itemKey(it)
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
-- A full tray of `size` dough balls (Index -> still there).
local function fullTray(size: string): { [number]: boolean }
	local tray = {}
	for i = 1, Config.Dough.TrayBalls[size] or 0 do
		tray[i] = true
	end
	return tray
end

-- The dough trays on the stretch table: hides the balls used up (StationArt
-- `DoughBall` parts), on every screen.
local function updateTrays(shop: Shop)
	for _, d in shop.model:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "DoughBall" then
			local tray = shop.trays[d:GetAttribute("Size") :: string]
			d.Transparency = if tray and tray[d:GetAttribute("Index") :: number] then 0 else 1
		end
	end
end

-- A ball off the `size` tray, stretched into a skin: the one the player
-- clicked (`index`), or for staff (or if someone else took it first) the
-- highest-numbered one left. An emptied tray is refilled.
local function takeBall(shop: Shop, size: string, index: number?)
	local tray = shop.trays[size]
	if not tray then
		return
	end
	if not (index and tray[index]) then
		index = nil
		for i in tray do
			if not index or i > index then
				index = i
			end
		end
	end
	if index then
		tray[index] = nil
	end
	if next(tray) == nil then
		shop.trays[size] = fullTray(size)
	end
	updateTrays(shop)
end

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
			-- Each skin on a screen of its own size (the user: they fit it exactly).
			StationArt.Screen(skin.size, CFrame.new(slotMarker.Position + Vector3.new(0, 0.02, 0))).Parent = folder
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

-- Delivery ready rack (the user, 2026-10-21): each boxed delivery order waits
-- there in a hot bag labelled with its order number until a driver takes it
-- at dispatch; the dispatch screen lists them. (Placeholder bags: the user will
-- have the bags modelled later.)
local function hotBag(order: Order): Part
	local bag = Instance.new("Part")
	bag.Name = "HotBag" .. order.id
	bag.Size = Vector3.new(2.8, 0.45 + 0.25 * math.min(#order.tickets, 3), 2.8)
	bag.Color = Config.Brand.Red
	bag.Material = Enum.Material.Fabric
	bag.Anchored = true
	bag.CanCollide = false
	bag.CanQuery = false
	local gui = Instance.new("SurfaceGui") -- its number on the front, toward the driver
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(280, math.floor(bag.Size.Y * 100))
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.new(0, 120, 1, -12)
	label.BackgroundColor3 = Color3.new(1, 1, 1)
	label.BorderSizePixel = 0
	label.FontFace = Style.Font.Heading
	label.TextScaled = true
	label.TextColor3 = Config.Brand.Charcoal
	label.Text = "#" .. order.id
	label.Parent = gui
	gui.Parent = bag
	return bag
end

-- Puts a bag on the delivery rack for every boxed delivery order waiting on a
-- driver (oldest first; past the rack's slots they wait unseen), takes the
-- rest off, and lists them on the dispatch screen.
local function layoutBags(shop: Shop)
	local waiting = {}
	for _, o in shop.orders do
		if o.delivery and o.stage == "Rack" then
			table.insert(waiting, o)
		end
	end
	table.sort(waiting, function(a, b)
		return (a.readyAt or 0) < (b.readyAt or 0)
	end)
	local shown: { [Order]: boolean } = {}
	for i, o in waiting do
		local slot = marker(shop, "DeliverySlot_" .. i)
		if not slot then
			break
		end
		local bag = shop.bags[o]
		if not bag then
			bag = hotBag(o)
			shop.bags[o] = bag
			bag.Parent = shop.model
		end
		bag.CFrame = slot.CFrame * CFrame.new(0, bag.Size.Y / 2, 0)
		shown[o] = true
	end
	for o, bag in shop.bags do
		if not shown[o] then
			bag:Destroy()
			shop.bags[o] = nil
		end
	end
	local screen = marker(shop, "DispatchScreen")
	local text = screen and screen:FindFirstChild("Text", true) :: TextLabel?
	if text then
		local lines = { "DISPATCH" }
		for _, o in waiting do
			table.insert(lines, string.format("#%-4d House %d  (%d)", o.id, o.house or 0, #o.tickets))
		end
		if #waiting == 0 then
			table.insert(lines, "No deliveries waiting")
		end
		text.Text = table.concat(lines, "\n")
	end
end

local function updateBoards(shop: Shop)
	if not shop.alive then
		return
	end
	layoutBags(shop)
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
				table.insert(items, { size = t.item.size, toppings = t.item.toppings, loaded = t.pie ~= nil or t.boxed })
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
		lost = money(shop.sales.lostToday),
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
	local xp = Config.XPPerTask
	local leveled = DataService.AddXP(player, xp)
	local grade = if quality >= 0.9 then "PERFECT" elseif quality >= 0.7 then "Great" elseif quality >= 0.45 then "OK" else "Sloppy"
	-- The client shows this as a pay slip (grade, what, coins, XP); the text is the fallback.
	notify(player, string.format("+%d coins  +%d XP  %s - %s", amount, xp, what, grade), Color3.fromRGB(255, 220, 90), { grade = grade, what = what, coins = amount, xp = xp, quality = quality })
	if leveled then
		notify(player, "LEVEL UP! You're now level " .. DataService.GetLevel(player), Color3.fromRGB(120, 255, 160))
	end
	local owner = shop.owner
	if owner and owner ~= player and owner.Parent then
		DataService.AddCoins(owner, base * q * Config.Store.OwnerRoyalty, true)
	end
end

local function recordSale(shop: Shop, amount: number)
	shop.sales.today += amount
	shop.sales.week += amount
	shop.sales.ordersToday += 1
end

-- An order the customer never got (gave up, timed out, wrong house, closing
-- time): a lost sale, counted once.
local function loseSale(shop: Shop, order: Order?, items: { Item })
	if order then
		if order.lost then
			return
		end
		order.lost = true
	end
	shop.sales.lostToday += SalesPlan.price(items)
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

-- A first name and last initial ("John P."), not one already in the lobby.
local function customerName(shop: Shop): string
	local name
	repeat
		name = randomFrom(Config.CustomerNames) .. " " .. string.char(shop.rng:NextInteger(65, 90)) .. "."
		local taken = false
		for _, c in shop.customers do
			taken = taken or c.name == name
		end
	until not taken
	return name
end

-- Where the k-th customer collecting a carryout order stands: at the counter
-- by the carryout warmer, the next ones along it.
local function counterSpot(shop: Shop, k: number): Vector3
	local pickup = station(shop, "Pickup")
	if not pickup then
		return spot(shop, "Wait1")
	end
	return pickup.Position + pickup.CFrame.LookVector * 3.5 - pickup.CFrame.RightVector * (k - 1) * 2.5
end

local function layoutCustomers(shop: Shop)
	local q, w, k = 0, 0, 0
	for _, c in shop.customers do
		if c.state == "Queued" then
			q += 1
			local base = spot(shop, "Queue" .. math.min(q, 3))
			c.humanoid:MoveTo(base + Vector3.new(0, 0, math.max(0, q - 3) * 3))
		elseif c.atCounter then
			k += 1
			c.humanoid:MoveTo(counterSpot(shop, k))
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
	c.atCounter = nil
	CollectionService:RemoveTag(c.npc, "CarryoutPick")
	local i = table.find(shop.customers, c)
	if i then
		table.remove(shop.customers, i)
	end
	for _, entry in table.clone(shop.pending) do
		if entry.customer == c then
			removePending(shop, entry)
			loseSale(shop, nil, entry.items)
		end
	end
	if c.order and c.order.stage ~= "Done" then
		loseSale(shop, c.order, c.order.desired)
		c.order.customer = nil
		c.order.cancelled = true
		-- Say so out loud, otherwise the order just vanishes from the screens.
		for _, p in membersOf(shop) do
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
-- Carryout rack (the user, 2026-10-21): a boxed carryout order waits on the
-- rack as a stack of boxes tagged with its customer's name while they wait at
-- the counter saying it. Clicking a stack picks it up, clicking its customer
-- hands it over (anyone else won't take it), clicking the rack puts it back
-- (client/CarryoutPicks); Register staff hand orders over too.
---------------------------------------------------------------------------

-- An order's boxes as a stack, the biggest at the bottom (at most MaxStack
-- shown), its customer's name on a tag on the top box's front. `base`: the
-- stack's underside; its -Z is the front (the lids read from there).
local function makeStack(order: Order, base: CFrame): Model
	local stack = Instance.new("Model")
	stack.Name = "CarryoutOrder" .. order.id
	local sizes = {}
	for _, t in order.tickets do
		table.insert(sizes, t.item.size)
	end
	table.sort(sizes, function(a, b)
		return (Config.BoxSize[a] or 0) > (Config.BoxSize[b] or 0)
	end)
	local n = math.min(#sizes, Config.Carryout.MaxStack)
	for i = 1, n do
		local box = makeBoxPart(sizes[i])
		box.CFrame = base * CFrame.new(0, 0.15 + (i - 1) * 0.3, 0) * BOX_FLAT
		box.CanQuery = true -- client/CarryoutPicks raycasts at it
		box.Parent = stack
	end
	local width = Config.BoxSize[sizes[n]] or 2.55
	local tag = Instance.new("Part")
	tag.Name = "NameTag"
	tag.Size = Vector3.new(math.min(width - 0.2, 1.9), 0.26, 0.02)
	tag.CFrame = base * CFrame.new(0, 0.15 + (n - 1) * 0.3, -width / 2 - 0.012)
	tag.Color = Color3.new(1, 1, 1)
	tag.Material = Enum.Material.SmoothPlastic
	tag.Anchored = true
	tag.CanCollide = false
	tag.Massless = true
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(190, 26)
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.FontFace = Style.Font.LabelBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(25, 25, 28)
	label.Text = string.upper(if order.customer then order.customer.name else "#" .. order.id) .. (if #sizes > n then string.format("  (%d)", #sizes) else "")
	label.Parent = gui
	gui.Parent = tag
	tag.Parent = stack
	return stack
end

local function tagPick(inst: Instance, kind: string)
	inst:SetAttribute("CarryoutKind", kind) -- "Stack" | "Rack" | "Customer"
	CollectionService:AddTag(inst, "CarryoutPick")
end

-- Builds the order's stack on its rack slot, its tag to the carryout side (the rack's +Z).
local function stackOnRack(shop: Shop, order: Order)
	local m = if order.rackSlot then marker(shop, "CarryoutSlot_" .. order.rackSlot) else nil
	if not m then
		return
	end
	local stack = makeStack(order, m.CFrame * CFrame.Angles(0, math.pi, 0))
	tagPick(stack, "Stack")
	stack.Parent = shop.model
	order.stack = stack
end

-- Puts a boxed carryout order on a free rack slot (or in line for one); its
-- customer steps up to the counter and says their name.
local function rackOrder(shop: Shop, order: Order)
	local slot
	for n = 1, Config.Carryout.Slots do
		if not shop.carryout[n] and marker(shop, "CarryoutSlot_" .. n) then
			slot = n
			break
		end
	end
	if not slot then
		if not table.find(shop.carryQueue, order) then
			table.insert(shop.carryQueue, order)
		end
		return
	end
	order.rackSlot = slot
	shop.carryout[slot] = order
	stackOnRack(shop, order)
	local c = order.customer
	if c and c.state ~= "Leaving" then
		c.atCounter = os.clock()
		setBubble(c, "Pickup for " .. c.name .. "!")
		layoutCustomers(shop)
	end
	for _, p in membersOf(shop) do
		notify(p, string.format("Order #%d for %s is on the carryout rack.", order.id, if c then c.name else "?"), Color3.fromRGB(180, 220, 255))
	end
end

-- Out of whoever's hand it was in.
local function dropFromHands(order: Order)
	local player = order.carriedBy
	if player then
		carrying[player] = nil
		player:SetAttribute("Carrying", nil)
		order.carriedBy = nil
	end
	if order.stack then
		order.stack:Destroy()
		order.stack = nil
	end
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
		setBubble(customer, (if kind == "online" then "Picking up online order #" .. order.id else "Order #" .. order.id .. "...") .. " - I'm " .. customer.name)
		layoutCustomers(shop)
	end
	updateBoards(shop)
	return order
end

-- Takes an order off the books. Pizzas already made for it that aren't boxed
-- yet carry on through the kitchen as extras.
local function removeOrder(shop: Shop, order: Order)
	order.stage = "Done"
	-- Off the carryout rack (or out of someone's hands); the next in line gets its slot.
	dropFromHands(order)
	local q = table.find(shop.carryQueue, order)
	if q then
		table.remove(shop.carryQueue, q)
	end
	if order.rackSlot then
		shop.carryout[order.rackSlot] = nil
		order.rackSlot = nil
		local nextUp = table.remove(shop.carryQueue, 1)
		if nextUp then
			rackOrder(shop, nextUp)
		end
	end
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
			StationArt.Screen(p.size, CFrame.new(slotMarker.Position + Vector3.new(0, 0.02, 0))).Parent = screens
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
	for _, p in membersOf(shop) do
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
	local recipe = item.toppings
	local factors = {}
	for _, topping in Config.Toppings do
		local n = (counts and counts[topping]) or 0
		if table.find(recipe, topping) then
			-- Counted toppings by the piece, weighed ones by the ounce.
			table.insert(factors, Config.PortionFactor(Config.ToppingAmount(topping, n), Config.PortionFor(topping, item.size, #recipe)))
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
				local score = matchScore(t.item.toppings, pie.counts)
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
local function loadPie(shop: Shop, player: Player?, pie: Pie, orderId: number?): string?
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
	if player then
		pie.workers[player] = true
	end
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
			notify(topper, string.format("%s is a %s: its toppings or portions were off.", ticketLabel(ticket), SalesPlan.name(ticket.item)), Color3.fromRGB(255, 180, 100))
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
		loseSale(shop, order, order.desired)
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
	recordSale(shop, price)
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
		DataService.AddCoins(owner, price * Config.Store.SaleCut, true)
	end

	local c = order.customer
	if c and c.state ~= "Leaving" then
		local mood = if satisfaction >= 0.8 then "Smells amazing, thanks!" elseif satisfaction >= 0.5 then "Not bad." else "Ugh... this isn't right."
		customerLeave(shop, c, mood)
	end
end

-- A boxed carryout order goes onto the carryout rack for its customer.
local function serveCarryout(shop: Shop, order: Order)
	local c = order.customer
	if order.source == "online" and not c then
		-- Picked up by someone we never modeled (lobby was full).
		completeOrder(shop, order, 1, nil)
		return
	end
	if not c or c.state == "Leaving" then
		for worker in order.workers do
			notify(worker, "Order #" .. order.id .. " is ready but the customer already left.", Color3.fromRGB(255, 160, 100))
		end
		removeOrder(shop, order)
		return
	end
	order.stage = "Pickup"
	rackOrder(shop, order)
	updateBoards(shop)
end

-- Welds a stack of the order's boxes in front of `root` (whoever's carrying it).
local function stackInHands(order: Order, root: BasePart, parent: Instance): Model
	local stack = makeStack(order, root.CFrame * CFrame.new(0, -0.7, -1.8))
	for _, part in stack:GetChildren() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanQuery = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = part
		end
	end
	stack.Parent = parent
	return stack
end

-- `player` takes an order off the carryout rack (one at a time).
local function takeOrder(player: Player, order: Order)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not root or carrying[player] or order.carriedBy or order.claimedBy then
		return
	end
	if order.stack then
		order.stack:Destroy()
	end
	order.carriedBy = player
	carrying[player] = order
	player:SetAttribute("Carrying", order.id)
	order.stack = stackInHands(order, root, character)
	notify(player, string.format("%s's order - hand it to them at the counter.", if order.customer then order.customer.name else "#" .. order.id))
end

-- Back on its slot (put back, or whoever had it left).
local function returnOrder(shop: Shop, order: Order)
	dropFromHands(order)
	if shop.alive then
		stackOnRack(shop, order)
	end
end

-- Hands the order to its customer (`by` a player, or staff when nil): they
-- take the boxes and go, and the order's done.
local function handOver(shop: Shop, order: Order, by: Player?, quality: number)
	dropFromHands(order)
	if by then
		order.workers[by] = true
	end
	local c = order.customer
	local root = if c then c.npc:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if c and root and c.state ~= "Leaving" then
		stackInHands(order, root, c.npc)
		CollectionService:RemoveTag(c.npc, "CarryoutPick")
	end
	if by then
		notify(by, string.format("Handed %s their order.", if c then c.name else "the customer"), Color3.fromRGB(120, 255, 160))
	end
	completeOrder(shop, order, quality, nil)
end

-- `player` clicked customer `c` with an order in hand: theirs, they take it;
-- anyone else's, they say who they are.
local function giveTo(shop: Shop, player: Player, c: Customer)
	local order = carrying[player]
	if not order then
		return
	end
	if order.customer == c then
		handOver(shop, order, player, 1)
		return
	end
	setBubble(c, "That's not mine - I'm " .. c.name)
	notify(player, string.format("That's %s's order, not %s's.", if order.customer then order.customer.name else "someone else", c.name), Color3.fromRGB(255, 160, 100))
	task.delay(3, function()
		if c.atCounter and c.state ~= "Leaving" then
			setBubble(c, "Pickup for " .. c.name .. "!")
		end
	end)
end

-- Whatever `player` was carrying goes back on the rack (they left, reset, changed stores).
local function dropCarry(player: Player)
	local order = carrying[player]
	if not order then
		return
	end
	local shop = playerShop[player]
	if shop then
		returnOrder(shop, order)
	else
		dropFromHands(order)
	end
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

-- A plain R15 NPC in a `torso`-coloured shirt (yields), with the default
-- walk/idle so it doesn't slide around. Nil if the avatar service failed.
local function newNpc(torso: Color3): (Model?, Humanoid?)
	local desc = Instance.new("HumanoidDescription")
	local skin = randomFrom(SKIN)
	desc.HeadColor = skin
	desc.LeftArmColor = skin
	desc.RightArmColor = skin
	desc.TorsoColor = torso
	local pants = Color3.fromHSV(math.random(), 0.4, 0.4)
	desc.LeftLegColor = pants
	desc.RightLegColor = pants
	local ok, npc = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not npc then
		warn("[ShopService] couldn't build an NPC:", npc)
		return nil, nil
	end
	local humanoid = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
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
	return npc, humanoid
end

local function npcFolder(shop: Shop): Folder
	local folder = shop.model:FindFirstChild("NPCs")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "NPCs"
		folder.Parent = shop.model
	end
	return folder :: Folder
end

local function spawnCustomer(shop: Shop, items: { Item }, online: boolean)
	shop.spawning += 1
	task.spawn(function()
		local npc, hum = newNpc(Color3.fromHSV(math.random(), 0.5, 0.85))
		shop.spawning -= 1
		if not npc or not hum or not shop.alive or not isOpen() then
			if npc then
				npc:Destroy()
			end
			return
		end
		local humanoid = hum :: Humanoid
		npc.Name = "Customer"
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.WalkSpeed = 12
		npc:PivotTo(CFrame.new(spot(shop, "CustomerSpawn")))
		npc.Parent = npcFolder(shop)
		local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			pcall(function()
				root:SetNetworkOwner(nil)
			end)
		end

		local c: Customer = { npc = npc, humanoid = humanoid, items = items, state = "Queued", arrived = os.clock(), order = nil, name = customerName(shop), atCounter = nil }
		table.insert(shop.customers, c)
		tagPick(npc, "Customer") -- with an order in hand you can click any customer: only its own takes it
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

-- One new order from the forecast; every one comes to the store (what it
-- can't make in time is lost). A store that can't take deliveries gets them
-- as carryout instead.
local function newOrder(shop: Shop, items: { Item })
	local S = Config.Sales
	local delivery = shop.rng:NextNumber() < S.DeliveryShare and takesDeliveries(shop)
	local online = shop.rng:NextNumber() < S.OnlineShare
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
	-- A full lobby takes it online instead (they come when it's ready).
	if #shop.customers + shop.spawning < Config.Shop.MaxCustomers then
		spawnCustomer(shop, items, online)
	else
		createOrder(shop, "online", items, nil, table.clone(items), nil, 1, nil, nil)
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

---------------------------------------------------------------------------
-- Station steps: what each job does to the kitchen, whoever did it (a
-- player's minigame, or hired staff). `player` is nil for staff.
---------------------------------------------------------------------------

-- A skin off the rack, sauced: a new pizza on the make-line.
local function saucePie(shop: Shop, skin: RackSkin, score: number, player: Player?): Pie
	shop.pieCounter += 1
	local pie: Pie = {
		id = shop.pieCounter,
		size = skin.size,
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
		workers = {},
		ticket = nil,
		slot = nil,
		pos = 0,
		bake = 0,
		settleAt = 0,
		loadedAt = nil,
		exitAt = nil,
		boxWrong = false,
	}
	if player then
		pie.workers[player] = true
	end
	table.insert(shop.pies, pie)
	placeOnLine(shop, pie)
	updateBoards(shop)
	return pie
end

-- `oz` of cheese on it. Returns the portion factor.
local function cheesePie(shop: Shop, pie: Pie, oz: number, player: Player?): number
	local target = Config.CheesePortion[pie.size] or 6
	local factor = Config.PortionFactor(oz, target)
	pie.claimedBy = nil
	pie.cheese = oz / target
	pie.cheeseFactor = factor
	pie.portionFactor = factor
	table.insert(pie.quality, factor)
	if player then
		pie.workers[player] = true
	end
	setStage(pie, "Cheesed")
	placeOnLine(shop, pie)
	updateBoards(shop)
	return factor
end

-- `counts`: pieces of each topping put on. A bin that's out can't be used.
-- It's scored against an order when it's loaded.
local function topPie(shop: Shop, pie: Pie, counts: { [string]: number }, player: Player?)
	local placed: { [string]: number } = {}
	for _, topping in Config.Toppings do
		local n = counts[topping] or 0
		if n > 0 and (shop.stock[topping] or 0) <= 0 then
			n = 0
		end
		placed[topping] = n
		if n > 0 then
			shop.stock[topping] -= 1
		end
	end
	pie.claimedBy = nil
	pie.counts = placed
	pie.toppedBy = player
	if player then
		pie.workers[player] = true
	end
	pie.readySlot = freeReadySlot(shop) -- there's always one: it was counted when the job started
	setStage(pie, "Ready")
	placeOnLine(shop, pie)
	updateBoards(shop)
end

-- Off the belt and onto the cut table (others see it there while it's
-- worked). Returns where it was pulled from.
local function pullPie(shop: Shop, pie: Pie, who: any): Vector3?
	pie.claimedBy = who
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
	return exitPos
end

-- Cut and boxed. Returns its order ticket (nil: an extra nobody ordered).
local function boxPie(shop: Shop, pie: Pie, score: number, boxOk: boolean, player: Player?): Ticket?
	pie.claimedBy = nil
	pie.boxWrong = not boxOk
	table.insert(pie.quality, score)
	if player then
		pie.workers[player] = true
	end
	setStage(pie, "Boxed")
	removePie(shop, pie)
	local ticket = pie.ticket
	if ticket then
		ticket.boxed = true
		for w in pie.workers do
			ticket.order.workers[w] = true
		end
	end
	updateBoards(shop)
	if ticket then
		checkOrder(shop, ticket.order)
	end
	return ticket
end

---------------------------------------------------------------------------
-- Hired staff (NPCs)
---------------------------------------------------------------------------
-- The owner's team members (StoreService keeps them in the owner's save),
-- in on the shifts they're scheduled for unless they call out (startShift).
-- At a kitchen station they do its job on the real pizzas, at the speed and
-- quality of their level there (Staff.luau), and only sauce and top what
-- open orders still need. At the heat rack they drive: delivery orders go
-- out for a timed trip. Every job earns XP at that station.

local CREW_TAG = "CrewNPC" -- the client hides one standing where its player works

-- Order items still waiting on a pizza, oldest order first.
local function neededTickets(shop: Shop): { Ticket }
	local need = {}
	for _, o in shop.orders do
		if o.stage == "Making" and not o.cancelled then
			for _, t in o.tickets do
				if not t.pie and not t.boxed then
					table.insert(need, t)
				end
			end
		end
	end
	return need
end

-- The size of the oldest needed item that no pizza on the make-line (or in
-- a saucer's hands) covers yet. `spare`: more of each size that counts as
-- covering it (racked skins, when deciding what to stretch). `have`: only
-- sizes with one of these (skins, when deciding what to sauce).
local function neededSize(shop: Shop, spare: { [string]: number }?, have: { [string]: number }?): string?
	local inWork: { [string]: number } = table.clone(spare or {})
	for _, p in shop.pies do
		if p.stage == "Sauced" or p.stage == "Cheesed" or p.stage == "Ready" then
			inWork[p.size] = (inWork[p.size] or 0) + 1
		end
	end
	for _, c in shop.crew do
		if c.job and c.job.what == "Sauce" then
			inWork[c.job.skin.size] = (inWork[c.job.skin.size] or 0) + 1
		end
	end
	-- Followers stretching or saucing the size a ticket needs.
	for _, s in sessions do
		if s.shop == shop and (s.kind == "Dough" or s.kind == "Sauce") and type(s.data.size) == "string" then
			inWork[s.data.size] = (inWork[s.data.size] or 0) + 1
		end
	end
	for _, t in neededTickets(shop) do
		local size = t.item.size
		if (inWork[size] or 0) > 0 then
			inWork[size] -= 1
		elseif not have or (have[size] or 0) > 0 then
			return size
		end
	end
	return nil
end

-- Skins on the racks that no follower is saucing yet (a saucer takes theirs
-- off the rack when they finish).
local function freeSkins(shop: Shop): { [string]: number }
	local counts = rackCounts(shop)
	for _, s in sessions do
		if s.shop == shop and s.kind == "Sauce" and type(s.data.size) == "string" then
			counts[s.data.size] = (counts[s.data.size] or 0) - 1
		end
	end
	return counts
end

-- The size to stretch next: one open orders need that no pizza in the works,
-- skin on the racks or stretch in a staff member's hands covers yet.
local function doughNeed(shop: Shop, skins: { [string]: number }): string?
	local spare = table.clone(skins)
	for _, other in shop.crew do
		if other.job and other.job.what == "Dough" then
			spare[other.job.size] = (spare[other.job.size] or 0) + 1
		end
	end
	return neededSize(shop, spare, nil)
end

-- The toppings to put on a `size` pizza next: the oldest needed item of that
-- size not already covered by a topped pizza (or one being topped).
local function neededToppings(shop: Shop, size: string): { string }?
	local want: { { string } } = {}
	for _, t in neededTickets(shop) do
		if t.item.size == size then
			table.insert(want, t.item.toppings)
		end
	end
	local function cover(counts: { [string]: number }?)
		local best, bestScore = nil, -math.huge
		for i, toppings in want do
			local score = matchScore(toppings, counts)
			if score > bestScore then
				best, bestScore = i, score
			end
		end
		if best then
			table.remove(want, best)
		end
	end
	for _, p in shop.pies do
		if p.size == size and p.stage == "Ready" then
			cover(p.counts)
		end
	end
	for _, c in shop.crew do
		if c.job and c.job.what == "Toppings" and c.job.pie.size == size then
			cover(c.job.counts)
		end
	end
	return want[1]
end

-- Where a staff member stands: like a player at that station, facing the
-- work; the `k`th one there stands alongside.
local function crewSpot(shop: Shop, stationName: string, k: number): CFrame?
	local st = station(shop, stationName)
	if not st then
		return nil
	end
	local pizzaAt = st:GetAttribute("PizzaAt")
	local rel = if typeof(pizzaAt) == "Vector3" then pizzaAt else Vector3.new(0, st.Size.Y, -0.5)
	local art = st.CFrame * CFrame.new(0, -st.Size.Y / 2, 0)
	local workAt = (art * CFrame.new(rel)).Position
	local look = art.LookVector
	local toWorker = Vector3.new(look.X, 0, look.Z).Unit
	local right = Vector3.new(0, 1, 0):Cross(toWorker).Unit
	local view = Config.StationView[stationName] or Config.StationView.Default
	local side = if k == 0 then 0 else (if k % 2 == 1 then 1 else -1) * 2.2 * math.ceil(k / 2)
	local at = workAt + toWorker * (view.stand or 1.9) + right * side
	-- On the floor below (the station's base can be up on a counter, like the register).
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { npcFolder(shop) }
	params.RespectCanCollide = true
	local hit = workspace:Raycast(Vector3.new(at.X, workAt.Y + 1, at.Z), Vector3.new(0, -20, 0), params)
	at = Vector3.new(at.X, if hit then hit.Position.Y else art.Position.Y, at.Z)
	return CFrame.lookAt(at, at - toWorker)
end

-- Puts the NPC back at its post (after a delivery, or when it spawns).
local function crewToPost(shop: Shop, c: Crew)
	local npc = c.npc
	local root = npc and npc:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = npc and npc:FindFirstChildOfClass("Humanoid")
	if not npc or not root or not humanoid then
		return
	end
	local k = 0
	for _, other in shop.crew do
		if other == c then
			break
		elseif other.present and other.station == c.station then
			k += 1
		end
	end
	local cf = crewSpot(shop, c.station, k)
	if cf then
		root.Anchored = true
		npc:PivotTo(cf + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0))
	end
	npc.Parent = npcFolder(shop)
end

local function spawnCrew(shop: Shop, c: Crew)
	task.spawn(function()
		local npc, humanoid = newNpc(Config.Brand.Red)
		if not npc or not humanoid then
			return
		end
		-- Sent home (or already back in) while the avatar loaded.
		if not shop.alive or not table.find(shop.crew, c) or not c.present or c.npc then
			npc:Destroy()
			return
		end
		npc.Name = c.name
		humanoid.DisplayName = c.name
		humanoid.NameDisplayDistance = 30
		-- Workers never block anyone (they stand where players work).
		for _, d in npc:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = false
			end
		end
		setUniform(npc, true)
		CollectionService:AddTag(npc, CREW_TAG)
		c.npc = npc
		if c.job and c.job.what == "Delivery" then
			return -- out on the road; back at its post when the trip's done
		end
		crewToPost(shop, c)
	end)
end

-- Off to the car: walk to the driver door, then gone until the trip's done.
local function crewDriveOff(shop: Shop, c: Crew)
	local npc = c.npc
	local root = npc and npc:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = npc and npc:FindFirstChildOfClass("Humanoid")
	local door = marker(shop, "DriverDoorSign")
	if not npc or not root or not humanoid or not door then
		return
	end
	root.Anchored = false
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	-- shortcut: walks straight at the door (no pathfinding; it can't collide, so it cuts through counters).
	humanoid:MoveTo(Vector3.new(door.Position.X, root.Position.Y, door.Position.Z))
	local job = c.job
	task.delay(5, function()
		if c.job == job and c.npc == npc then
			npc.Parent = nil
		end
	end)
end

-- Drops whatever the staff member was doing, back where it came from.
local function releaseCrew(shop: Shop, c: Crew)
	local job = c.job
	c.job = nil
	if not job then
		return
	end
	local what = job.what
	if what == "Register" then
		job.entry.claimedBy = nil
	elseif what == "Handoff" then
		job.order.claimedBy = nil
	elseif what == "Dough" then
		shop.stock.Dough = math.min(Config.Shop.MaxStock, shop.stock.Dough + 1)
	elseif what == "Sauce" then
		rackAdd(shop, job.skin)
		updateSkinRack(shop)
		shop.stock.Sauce = math.min(Config.Shop.MaxStock, shop.stock.Sauce + 1)
	elseif what == "Cheese" or what == "Toppings" or what == "Load" then
		job.pie.claimedBy = nil
		if what == "Cheese" then
			shop.stock.Cheese = math.min(Config.Shop.MaxStock, shop.stock.Cheese + 1)
		end
		arrangeMakeLine(shop)
	elseif what == "Cut" then
		local pie = job.pie
		pie.claimedBy = nil
		if pie.stage == "Cutting" and pie.slot and table.find(shop.pies, pie) then
			returnToLane(shop, pie)
		end
	elseif what == "Delivery" then
		local o = job.order
		o.claimedBy = nil
		if o.stage == "Out" then
			o.stage = "Rack"
		end
		crewToPost(shop, c)
	end
	updateBoards(shop)
end

-- Starts the staff member's next job at its station, if there is one.
local function crewJobAt(shop: Shop, c: Crew, s: string): any?
	if s == "DeliveryRack" then
		for _, o in shop.orders do
			if o.stage == "Rack" and o.delivery and not o.claimedBy and houses[o.house or 0] then
				o.claimedBy = c
				o.stage = "Out"
				return { what = "Delivery", order = o }
			end
		end
	elseif s == "Register" then
		for _, o in shop.carryout do
			if not o.carriedBy and not o.claimedBy and o.customer and o.customer.atCounter then
				o.claimedBy = c
				return { what = "Handoff", order = o }
			end
		end
		for _, e in shop.pending do
			if not e.claimedBy and (e.kind == "phone" or (e.customer and e.customer.state == "Queued")) then
				e.claimedBy = c
				return { what = "Register", entry = e }
			end
		end
	elseif s == "Dough" then
		local skins, used = rackCounts(shop)
		if used >= Config.RackCapacity() or hasStock(shop, { Dough = 1 }) then
			return nil
		end
		-- A size open orders need and nothing covers yet; otherwise prep whichever
		-- size is shortest on the racks for how often it's ordered.
		local size = doughNeed(shop, skins)
		if not size then
			local best = math.huge
			for _, sz in Config.Sizes do
				local ratio = (skins[sz] or 0) / Config.OrderSizes.SizeMix[sz]
				if ratio < best then
					size, best = sz, ratio
				end
			end
		end
		consume(shop, { Dough = 1 })
		return { what = "Dough", size = size }
	elseif s == "Sauce" then
		local size = neededSize(shop, nil, freeSkins(shop))
		if not size or hasStock(shop, { Sauce = 1 }) then
			return nil
		end
		local skin = rackTake(shop, size)
		if not skin then
			return nil
		end
		consume(shop, { Sauce = 1 })
		updateSkinRack(shop)
		return { what = "Sauce", skin = skin }
	elseif s == "Cheese" then
		local pie = pickPie(shop, "Sauced")
		if not pie or hasStock(shop, { Cheese = 1 }) then
			return nil
		end
		consume(shop, { Cheese = 1 })
		pie.claimedBy = c
		return { what = "Cheese", pie = pie }
	elseif s == "Toppings" then
		if readyRoom(shop) <= 0 then
			return nil
		end
		for _, pie in shop.pies do
			local recipe = if pie.stage == "Cheesed" and not pie.claimedBy then neededToppings(shop, pie.size) else nil
			if recipe then
				local counts: { [string]: number } = {}
				for _, topping in recipe do
					counts[topping] = Config.PortionPieces(topping, pie.size, #recipe)
				end
				pie.claimedBy = c
				return { what = "Toppings", pie = pie, counts = counts }
			end
		end
	elseif s == "Load" then
		-- Only pizzas that are exactly what an open order needs (no guessing).
		for _, pie in shop.pies do
			if pie.stage == "Ready" and not pie.claimedBy then
				local t = matchTicket(shop, pie, nil)
				if t and matchScore(t.item.toppings, pie.counts) == 0 then
					pie.claimedBy = c
					return { what = "Load", pie = pie }
				end
			end
		end
	elseif s == "CutTable" then
		local pie = pickPie(shop, "Exit")
		if pie then
			pullPie(shop, pie, c)
			return { what = "Cut", pie = pie }
		end
	end
	return nil
end

-- The staff member's next job: at the first of their stations (managers
-- have several) with work waiting, looking round from where they last found it.
local function crewStart(shop: Shop, c: Crew): any?
	local list = c.member.stations
	for i = 1, #list do
		local k = (c.next + i - 1) % #list + 1
		local job = crewJobAt(shop, c, list[k])
		if job then
			c.next = k
			if c.station ~= list[k] then
				-- shortcut: managers step straight to the next station (no walking between them).
				c.station = list[k]
				crewToPost(shop, c)
			end
			return job
		end
	end
	return nil
end

-- Finishes the job the staff member started, and they learn from it.
local function crewFinish(shop: Shop, c: Crew)
	local job = c.job
	c.job = nil
	local quality = Staff.jobQuality(c.member, c.station)
	local what = job.what
	if what == "Register" then
		local e = job.entry
		e.claimedBy = nil
		if table.find(shop.pending, e) and (not e.customer or e.customer.state == "Queued") then
			removePending(shop, e)
			createOrder(shop, e.kind, e.items, e.house, table.clone(e.items), e.house, quality, nil, e.customer)
		end
	elseif what == "Handoff" then
		local o = job.order
		o.claimedBy = nil
		if o.stage == "Pickup" and o.rackSlot and not o.carriedBy then
			handOver(shop, o, nil, quality)
		end
	elseif what == "Dough" then
		local _, used = rackCounts(shop)
		if used >= Config.RackCapacity() then
			shop.stock.Dough = math.min(Config.Shop.MaxStock, shop.stock.Dough + 1)
		else
			rackAdd(shop, { size = job.size, quality = quality, made = os.clock() })
			takeBall(shop, job.size)
			updateSkinRack(shop)
			updateBoards(shop)
		end
	elseif what == "Sauce" then
		saucePie(shop, job.skin, quality, nil)
	elseif what == "Cheese" then
		if job.pie.stage == "Sauced" and table.find(shop.pies, job.pie) then
			cheesePie(shop, job.pie, Config.CheesePortion[job.pie.size] or 6, nil)
		end
	elseif what == "Toppings" then
		if job.pie.stage == "Cheesed" and table.find(shop.pies, job.pie) then
			topPie(shop, job.pie, job.counts, nil)
		end
	elseif what == "Load" then
		job.pie.claimedBy = nil
		if job.pie.stage == "Ready" then
			loadPie(shop, nil, job.pie, nil) -- the entrance may be busy: it's tried again next time
		end
	elseif what == "Cut" then
		if job.pie.stage == "Cutting" and table.find(shop.pies, job.pie) then
			boxPie(shop, job.pie, quality, true, nil)
		end
	elseif what == "Delivery" then
		job.order.claimedBy = nil
		completeOrder(shop, job.order, quality, nil)
		crewToPost(shop, c)
	end
	local stat = c.member.stats[c.station]
	if stat and Staff.addXP(stat, 1) then
		notify(shop.owner, string.format("%s's %s is now level %d!", c.name, Config.StaffStatNames[c.station] or c.station, stat.level), Color3.fromRGB(120, 255, 160))
	end
end

-- Brings in whoever should be working now (scheduled for this shift, didn't
-- call out) and sends home whoever shouldn't.
local function crewRoster(shop: Shop)
	for _, c in shop.crew do
		local should = shop.shift ~= nil and c.member.shifts[shop.shift] == true and not shop.calledOut[c.member.id]
		if should and not c.present then
			c.present = true
			c.busyUntil = 0
			spawnCrew(shop, c)
		elseif not should and c.present then
			c.present = false
			releaseCrew(shop, c)
			if c.npc then
				c.npc:Destroy()
				c.npc = nil
			end
		end
	end
end

-- A new shift: everyone scheduled for it might call out (Reliability).
local function startShift(shop: Shop, shift: string?)
	shop.shift = shift
	table.clear(shop.calledOut)
	if shift then
		for _, c in shop.crew do
			if c.member.shifts[shift] and shop.rng:NextNumber() < Staff.calloutChance(c.member.reliability) then
				shop.calledOut[c.member.id] = true
				notify(shop.owner, string.format("%s called out of the %s shift.", c.name, shift), Color3.fromRGB(255, 160, 100))
			end
		end
	end
	crewRoster(shop)
end

-- Once a second: staff finish what's done and pick up the next job.
local function crewStep(shop: Shop)
	local _, hour = GameClock.split(ClockService.WeekHour())
	local shift = Staff.shiftAt(hour)
	if shift ~= shop.shift then
		startShift(shop, shift)
	end
	local now = os.clock()
	for _, c in shop.crew do
		if not c.present then
			continue
		elseif c.job and now >= c.busyUntil then
			local ok, err = pcall(crewFinish, shop, c)
			if not ok then
				warn("[ShopService] staff job failed:", err)
			end
			c.busyUntil = now + Config.NextJobDelay
		elseif not c.job and now >= c.busyUntil and canWork() then
			c.job = crewStart(shop, c)
			if c.job then
				local speed = Staff.jobSpeed(c.member, c.station)
				if c.job.what == "Delivery" then
					local trip = Config.StaffWork.Trip
					c.busyUntil = now + shop.rng:NextNumber(trip[1], trip[2]) * speed
					crewDriveOff(shop, c)
				else
					c.busyUntil = now + (Config.StaffWork.WorkTime[c.station] or 8) * speed
				end
				updateBoards(shop)
			end
		end
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
-- `size`: following, the size to stretch or sauce (the top pizza's).
local function startStation(shop: Shop, stationName: string, player: Player, pickId: number?, size: string?): string?
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
			return "Out of dough! It's being restocked."
		end
		consume(shop, needs)
		begin(player, shop, stationName, {
			presses = Config.Dough.Presses,
			sizes = Config.Sizes,
			size = size, -- set: no choosing, it's the top pizza's size
			skins = counts,
			need = doughNeed(shop, counts), -- highlighted: the size the oldest ticket still needs
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
		if size and (freeSkins(shop)[size] or 0) <= 0 then
			return "No " .. size .. " skins on the racks."
		end
		local needs = { Sauce = 1 }
		if hasStock(shop, needs) then
			return "Out of sauce! It's being restocked."
		end
		consume(shop, needs)
		begin(player, shop, stationName, { skins = counts, sizes = Config.Sizes, size = size, need = neededSize(shop, nil, counts), station = station(shop, stationName) }, { consumed = needs })
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
				return "Out of " .. missing .. "! It's being restocked."
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
			-- Any toppings, no targets: makers go by the tickets and the tip card.
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
		local exitPos = pullPie(shop, pie, player)
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
			pizza = if ticket then SalesPlan.name(ticket.item) else "extra",
			size = pie.size,
			cuts = slices // 2,
			bubbles = bubbles,
			sizes = Config.Sizes,
			station = station(shop, stationName),
			spec = pieSpec(pie, true),
			visual = pie.visual, -- hidden locally while the cutter works on it
			exitPos = exitPos,
		}, { pie = pie })
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
			loseSale(shop, order, order.desired)
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

-- Whether a make station has anything for a player to work on right now.
local function hasWork(shop: Shop, stationName: string): boolean
	if stationName == "Dough" then
		return true -- prep: there's always dough to stretch
	elseif stationName == "Sauce" then
		local _, used = rackCounts(shop)
		return used > 0
	end
	local info = Config.StationInfo(stationName)
	for _, p in shop.pies do
		if info and p.stage == info.stage and not p.claimedBy then
			return true
		end
	end
	return false
end

-- Who's at `stationName` besides `except` (a player, or staff on shift), if anyone.
local function occupant(shop: Shop, stationName: string, except: Player?): string?
	for player, stay in stationed do
		if player ~= except and stay.shop == shop and stay.name == stationName and player.Parent then
			return player.DisplayName
		end
	end
	for _, c in shop.crew do
		if c.present and c.station == stationName then
			return c.name
		end
	end
	return nil
end

-- Following (the default, unless they parked at a station from the HUD): a
-- player in the make process goes with each pizza to its next step, then
-- picks up the top pizza on the tickets.
local function following(player: Player, stationName: string): boolean
	return not parked[player] and table.find(Config.MakeSteps, stationName) ~= nil
end

local function setParked(player: Player, on: boolean)
	parked[player] = if on then true else nil
	player:SetAttribute("Following", not on)
end

-- Someone who'll work `stationName` without a follower: a player parked
-- there, or staff on shift there.
local function manned(shop: Shop, stationName: string, except: Player?): boolean
	for player, stay in stationed do
		if player ~= except and parked[player] and stay.shop == shop and stay.name == stationName then
			return true
		end
	end
	for _, c in shop.crew do
		if c.present and c.station == stationName then
			return true
		end
	end
	return false
end

local MAKE_STAGES = { Ready = 1, Cheesed = 2, Sauced = 3 } -- furthest along first

-- Where a follower goes for the top pizza on the tickets (Follow.target):
-- pizzas being worked, staff at their posts and other followers' skins cover
-- the oldest tickets.
local function followTarget(shop: Shop, player: Player): (string, number?, string?)
	local covered: { [string]: number } = {}
	local function cover(size: string)
		covered[size] = (covered[size] or 0) + 1
	end
	local free: { Pie } = {}
	for _, p in shop.pies do
		if MAKE_STAGES[p.stage] then
			if p.claimedBy or manned(shop, Config.StationForStage(p.stage) :: string, player) then
				cover(p.size)
			else
				table.insert(free, p)
			end
		end
	end
	for other, s in sessions do
		if other ~= player and s.shop == shop and (s.kind == "Dough" or s.kind == "Sauce") and type(s.data.size) == "string" then
			cover(s.data.size)
		end
	end
	for _, c in shop.crew do
		if c.job and c.job.what == "Sauce" then
			cover(c.job.skin.size)
		elseif c.job and c.job.what == "Dough" then
			cover(c.job.size)
		end
	end
	table.sort(free, function(a, b)
		if a.stage ~= b.stage then
			return MAKE_STAGES[a.stage] < MAKE_STAGES[b.stage]
		end
		return a.id < b.id
	end)
	local waiting: { Follow.Waiting } = {}
	for _, p in free do
		table.insert(waiting, { id = p.id, size = p.size, station = Config.StationForStage(p.stage) :: string })
	end
	local needed = {}
	for _, t in neededTickets(shop) do
		table.insert(needed, t.item.size)
	end
	return Follow.target(needed, covered, waiting, freeSkins(shop))
end

local enterStation: (shop: Shop, player: Player, stationName: string, pickId: number?, size: string?) -> ()
local stepDone: (player: Player, stationName: string, pie: Pie?) -> ()

-- Gives a player standing at a station their next job there (or the one they
-- picked, `pickId`), if there is one. A follower is sent wherever the top
-- pizza needs them. A parked player at a make station with nothing to work on
-- is moved back a step, unless someone's there (then they wait).
local function assign(player: Player, pickId: number?)
	local stay = stationed[player]
	if not stay or sessions[player] or not stay.shop.alive or not canWork() then
		return
	end
	local shop = stay.shop
	local follows = following(player, stay.name)
	if follows and pickId == nil then
		local at, pick, size = followTarget(shop, player)
		if at ~= stay.name then
			enterStation(shop, player, at, pick, size)
			return
		end
		pickId, stay.size = pick, size
	end
	if follows and pickId and stay.name == "Load" then
		-- Following a finished pizza to the oven: it goes straight in.
		local pie = findPie(shop, pickId)
		if pie and pie.stage == "Ready" and not pie.claimedBy and not loadPie(shop, player, pie, nil) then
			stepDone(player, "Load", pie)
			return
		end
	end
	local why = startStation(shop, stay.name, player, pickId, stay.size)
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
	local back = if why and not session and not follows then Config.StepBefore(stay.name) else nil
	if back and not hasWork(stay.shop, stay.name) then
		local label = (Config.StationInfo(back) :: any).label
		local who = occupant(stay.shop, back, player)
		if not who then
			notify(player, string.format("Nothing to work at %s - back to %s.", (Config.StationInfo(stay.name) :: any).label, label), Color3.fromRGB(180, 220, 255))
			enterStation(stay.shop, player, back)
			return
		end
		why = string.format("Nothing here yet - waiting on %s at %s.", who, label)
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
-- `size`: following, the size to stretch or sauce there.
function enterStation(shop: Shop, player: Player, stationName: string, pickId: number?, size: string?)
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
		stay = { shop = shop, name = stationName, idleSince = os.clock(), status = nil }
		stationed[player] = stay
		Remotes.StationMode:FireClient(player, stationName, station(shop, stationName))
	end
	(stay :: Stay).size = size
	assign(player, pickId)
end

-- Every way of using a station ends up here: prompts, the HUD station bar and
-- rail, clicks on a pizza at the oven exit or an order on the heat rack, and
-- the HUD's Follow key. `park`: picked from the HUD, so at a make station they
-- stay there; otherwise (a prompt) they follow the top pizza.
local function useStation(shop: Shop, stationName: string, player: Player, pickId: number?, park: boolean?)
	if not shop.alive then
		return
	end
	if not canWork() then
		notify(player, closedMessage(), Color3.fromRGB(255, 160, 100))
		return
	end
	if playerShop[player] ~= shop then
		notify(player, "You don't work at this store. Open Stores (bottom left) to join it.", Color3.fromRGB(255, 160, 100))
		return
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.SeatPart then
		notify(player, "Hop out of the car first.", Color3.fromRGB(255, 160, 100))
		return
	end
	if table.find(Config.MakeSteps, stationName) then
		setParked(player, park == true)
	end
	enterStation(shop, player, stationName, pickId)
end

-- Results faster than a human could manage: drop the task instead of leaving the station stuck.
local function tooFast(player: Player)
	notify(player, "Whoa, too fast! Try that again.", Color3.fromRGB(255, 160, 100))
	ShopService.CancelSession(player)
end

local function isNumber(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- A station step is done: tell the client, then line up what's next. A
-- follower goes straight on with the pizza to its next make step, unless
-- someone stays at that station to do it; otherwise the next job loads at
-- the station (for a follower, wherever the top pizza needs them).
function stepDone(player: Player, stationName: string, pie: Pie?)
	local info: any = { station = stationName }
	if pie then
		info.pieId = pie.id
		info.size = pie.size
	end
	Remotes.StepDone:FireClient(player, info)
	local stay = stationed[player]
	if not stay then
		return
	end
	stay.idleSince = os.clock()
	local nextAt = if pie and (pie.stage == "Sauced" or pie.stage == "Cheesed") and not pie.claimedBy then Config.StationForStage(pie.stage) else nil
	if pie and nextAt and following(player, stationName) and not manned(stay.shop, nextAt, player) then
		enterStation(stay.shop, player, nextAt, pie.id)
		return
	end
	task.delay(Config.NextJobDelay, assign, player)
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
			if type(it) ~= "table" or type(it.size) ~= "string" or not table.find(Config.Sizes, it.size) or type(it.toppings) ~= "table" or #it.toppings > Config.MaxToppings then
				return
			end
			-- Known toppings, each once, kept in menu order.
			local on: { [string]: boolean } = {}
			for _, t in it.toppings do
				if type(t) ~= "string" or not table.find(Config.Toppings, t) or on[t] then
					return
				end
				on[t] = true
			end
			local toppings = {}
			for _, t in Config.Toppings do
				if on[t] then
					table.insert(toppings, t)
				end
			end
			table.insert(items, { size = it.size, toppings = toppings })
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
		if type(size) ~= "string" or not table.find(Config.Sizes, size) or (session.data.size and size ~= session.data.size) then
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
		takeBall(shop, size, if isNumber(payload.ball) then math.floor(payload.ball) else nil)
		updateSkinRack(shop)
		updateBoards(shop)
		pay(shop, player, Config.Pay.Dough, score, size .. " dough stretched")
		stepDone(player, "Dough")
	elseif kind == "Sauce" then
		-- Sauce: coverage inside the sauce line and a clean rim, nothing else (the spoodle never runs dry).
		local sauce, size = payload.sauce, payload.size
		local S = Config.Sauce
		if type(size) ~= "string" or not table.find(Config.Sizes, size) or (session.data.size and size ~= session.data.size) then
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
		local pie = saucePie(shop, skin, score, player)
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
		endSession(player, session, false)
		local factor = cheesePie(shop, pie, math.clamp(cheese, 0, target * 3), player)
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
			placed[topping] = if isNumber(n) then math.clamp(math.floor(n), 0, 80) else 0
		end
		endSession(player, session, false)
		topPie(shop, pie, placed, player)
		if payload.load == true then
			local orderId = if isNumber(payload.orderId) then payload.orderId else nil
			local why = loadPie(shop, player, pie, orderId)
			if why then
				notify(player, why, Color3.fromRGB(255, 160, 100))
			end
		end
		stepDone(player, "Toppings", pie)
	elseif kind == "Cut" then
		local angles, popped, box = payload.angles, payload.popped, payload.box
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
		local pie = session.pie :: Pie
		local boxOk = box == pie.size
		local score = 0.6 * cutScore + 0.2 * bubbleScore + (if boxOk then 0.2 else 0)

		endSession(player, session, false)
		local profile = DataService.Get(player)
		if profile then
			profile.PizzasMade += 1
		end
		pay(shop, player, Config.Pay.Cut, score, if boxOk then "Cut & boxed" else "Wrong box size!")
		if not boxPie(shop, pie, score, boxOk, player) then
			notify(player, "That one was an extra - no order needed it.", Color3.fromRGB(255, 160, 100))
		end
		stepDone(player, "CutTable")
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
	for _, c in shop.crew do
		releaseCrew(shop, c)
	end
	-- Clear orders before customers leave, so nobody gets "customer gave up" alerts at close.
	-- Whatever's still open is a lost sale.
	for _, e in shop.pending do
		loseSale(shop, nil, e.items)
	end
	table.clear(shop.pending)
	for _, o in table.clone(shop.orders) do
		loseSale(shop, o, o.desired)
		removeOrder(shop, o)
	end
	updateSalesBoard(shop)
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
	for _, player in membersOf(shop) do
		notify(player, string.format("The store's closed for the night (%s).", GameClock.hoursText()), Color3.fromRGB(180, 220, 255))
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
		shop.sales.lostToday = 0
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
				table.insert(items, { size = t.item.size, toppings = t.item.toppings, loaded = t.pie ~= nil or t.boxed })
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
				label = if t then string.format("#%s %s", string.sub(ticketLabel(t), 2), if #t.item.toppings > 0 then table.concat(t.item.toppings, " ") else "Cheese") else "extra",
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
				driver = whoName(o.claimedBy),
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
	crewStep(shop)

	-- Keep everyone working here up to date for the queue panel / station bar.
	local staff = membersOf(shop)
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

	-- Online kiosk picks up walk-ins and calls nobody has answered. Players get a
	-- longer window to take them first (they're often busy on the make-line).
	local kioskDelay = if #staff > 0 then S.AutoRegisterDelay * 3 else S.AutoRegisterDelay
	for _, e in table.clone(shop.pending) do
		if not e.claimedBy and now - e.created > kioskDelay then
			if not e.customer or e.customer.state == "Queued" then
				removePending(shop, e)
				createOrder(shop, if e.kind == "phone" then "phone" else "walkin", e.items, e.house, table.clone(e.items), e.house, 1, nil, e.customer)
			end
		end
	end

	-- Restock up to the starting stock (no supply truck for now).
	if now - shop.lastRestock > S.AutoRestockInterval then
		shop.lastRestock = now
		for _, ing in Config.Ingredients do
			if shop.stock[ing] < S.StartingStock then
				shop.stock[ing] = math.min(S.StartingStock, shop.stock[ing] + S.AutoRestockAmount)
			end
		end
		updateBoards(shop)
	end

	-- Impatient customers: waiting on their order, or at the counter with it on
	-- the carryout rack and nobody bringing it (not while it waits for a slot).
	for _, c in table.clone(shop.customers) do
		if c.state == "Leaving" then
			continue
		elseif c.atCounter then
			if now - c.atCounter > Config.Carryout.PickupPatience then
				customerLeave(shop, c, "Nobody's bringing my order?! >:(")
			end
		elseif not (c.order and c.order.stage == "Pickup") and now - c.arrived > Config.OrderPatience(#c.items) then
			customerLeave(shop, c, "I've waited forever! >:(")
		end
	end

	-- Orders nobody's standing in the lobby for (phone, online, delivery) give
	-- up too: still being made, or boxed and waiting on a driver.
	for _, o in table.clone(shop.orders) do
		if not o.customer and not o.cancelled and (o.stage == "Making" or o.stage == "Rack") and now - o.created > Config.OrderPatience(#o.desired) then
			loseSale(shop, o, o.desired)
			o.cancelled = true
			for _, p in membersOf(shop) do
				notify(p, string.format("Order #%d waited too long and was cancelled - a lost sale.", o.id), Color3.fromRGB(255, 120, 100))
			end
			if o.stage == "Rack" then
				removeOrder(shop, o)
			end
		end
	end

	-- Orders whose customer walked out come off the screens (and the carryout
	-- rack); any pizzas already made for them carry on as extras.
	for _, o in table.clone(shop.orders) do
		if o.cancelled and (o.stage == "Making" or o.stage == "Pickup") then
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
		sales = { today = 0, week = 0, lostToday = 0, ordersToday = 0, loadSum = 0, loadCount = 0, totalSum = 0, totalCount = 0 },
		rack = {},
		trays = { Small = fullTray("Small"), Medium = fullTray("Medium"), Large = fullTray("Large") },
		lastRestock = os.clock(),
		spawning = 0,
		crew = {},
		shift = nil,
		calledOut = {},
		carryout = {},
		carryQueue = {},
		bags = {},
		alive = true,
	}
	for _, ing in Config.Ingredients do
		shop.stock[ing] = Config.Shop.StartingStock
	end
	for slot = 1, Config.Oven.Slots do
		shop.lanes[slot] = {}
	end
	model:SetAttribute("StoreId", shop.id) -- the client matches prompts to the player's StoreId
	-- The carryout rack: clicking it puts back the order you're carrying.
	local slot1 = marker(shop, "CarryoutSlot_1")
	local rack = slot1 and slot1:FindFirstAncestorWhichIsA("Model")
	if rack then
		local cf, size = rack:GetBoundingBox()
		local hit = Instance.new("Part")
		hit.Name = "CarryoutRackHit"
		hit.Size = size
		hit.CFrame = cf
		hit.Transparency = 1
		hit.Anchored = true
		hit.CanCollide = false
		hit.CanTouch = false
		tagPick(hit, "Rack")
		hit.Parent = rack
	end

	-- A store that opens mid-day shouldn't dump the whole morning's orders at once.
	local day, hour = GameClock.split(ClockService.WeekHour())
	shop.weekNumber = ClockService.WeekNumber()
	shop.week = SalesPlan.newWeek(shop.rng, shop.volume)
	shop.day = day
	shop.mix = SalesPlan.dayMix(shop.rng)
	shop.demandToday = (shop.week :: SalesPlan.Week).days[day] * SalesPlan.shareByHour(hour)

	local stations = model:FindFirstChild("Stations") :: Folder
	for _, st in stations:GetChildren() do
		local pp = st:FindFirstChild("ProximityPrompt") :: ProximityPrompt?
		local stationName = st:GetAttribute("Station")
		if not pp or type(stationName) ~= "string" then
			continue
		end
		if stationName == "Pickup" then
			pp.Enabled = false
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
	table.clear(shop.crew) -- their NPCs go with the model
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
	for _, player in membersOf(shop) do
		ShopService.SetMember(player, nil)
	end
	local i = table.find(shops, shop)
	if i then
		table.remove(shops, i)
	end
	shop.model:Destroy()
end

-- The owner's hired staff at `shop`: their saved records (Staff.sanitize'd;
-- XP is written straight into them). Rebuilt whole: anyone mid-job puts it
-- back first; whoever's scheduled for the shift that's on comes in.
function ShopService.SetCrew(shop: Shop, members: { Staff.Member })
	for _, c in shop.crew do
		releaseCrew(shop, c)
		if c.npc then
			c.npc:Destroy()
		end
	end
	table.clear(shop.crew)
	for _, m in members do
		local first = m.stations[1]
		if first and station(shop, first) then
			table.insert(shop.crew, { member = m, name = m.name, station = first, next = 0, present = false, npc = nil, busyUntil = 0, job = nil })
		end
	end
	crewRoster(shop)
end

-- Makes `player` one of `shop`'s workers (nil: of no store). Who works where
-- is StoreService's call; this keeps the work state in step with it.
function ShopService.SetMember(player: Player, shop: Shop?)
	if playerShop[player] ~= shop then
		dropCarry(player)
		setParked(player, false)
		leaveStation(player)
		ShopService.CancelSession(player)
		CarService.Release(player)
		playerShop[player] = shop
	end
	player:SetAttribute("StoreId", if shop then shop.id else nil)
	if player.Character then
		setUniform(player.Character, shop ~= nil)
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

	Remotes.CarryoutPick.OnServerEvent:Connect(function(player, target)
		local shop = playerShop[player]
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not shop or not root or typeof(target) ~= "Instance" or not target:IsDescendantOf(shop.model) then
			return
		end
		local at = if target:IsA("Model") then target:GetPivot().Position elseif target:IsA("BasePart") then target.Position else nil
		if not at or (at - root.Position).Magnitude > CARRYOUT_REACH then
			return
		end
		local kind = target:GetAttribute("CarryoutKind")
		if kind == "Stack" then
			for _, o in shop.carryout do
				if o.stack == target then
					takeOrder(player, o)
				end
			end
		elseif kind == "Rack" then
			local held = carrying[player]
			if held then
				returnOrder(shop, held)
			end
		elseif kind == "Customer" then
			for _, c in shop.customers do
				if c.npc == target then
					giveTo(shop, player, c)
				end
			end
		end
	end)
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
		elseif pie then
			stepDone(player, "Load", pie)
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
	-- HUD keys work from anywhere in your store; you're moved to the station.
	local function hudShop(player: Player): Shop?
		local shop = playerShop[player]
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not shop or not shop.alive or not root then
			notify(player, "Open or join a store first (Stores, bottom left).", Color3.fromRGB(255, 160, 100))
			return nil
		end
		if (shop.model:GetPivot().Position - root.Position).Magnitude > 90 then
			notify(player, "Head back to your store to work a station.", Color3.fromRGB(255, 160, 100))
			return nil
		end
		return shop
	end
	-- HUD station bar and rail, queue panel clicks (a make station picked here parks you there).
	Remotes.UseStation.OnServerEvent:Connect(function(player, stationName, pickId)
		if type(stationName) ~= "string" or (pickId ~= nil and not isNumber(pickId)) then
			return
		end
		local shop = hudShop(player)
		if not shop or not station(shop, stationName) or stationName == "Pickup" or stationName == "Fridge" then
			return
		end
		useStation(shop, stationName, player, pickId, true)
	end)
	-- The HUD's Follow key: back to following the top pizza. Mid-job, the next step follows.
	Remotes.Follow.OnServerEvent:Connect(function(player)
		local shop = hudShop(player)
		if not shop then
			return
		end
		local stay = stationed[player]
		if stay and stay.shop == shop and table.find(Config.MakeSteps, stay.name) then
			setParked(player, false)
			assign(player)
		else
			useStation(shop, (followTarget(shop, player)), player)
		end
	end)

	local function hookCharacter(player: Player)
		player.CharacterAdded:Connect(function(character)
			dropCarry(player)
			leaveStation(player)
			ShopService.CancelSession(player)
			if playerShop[player] then
				character:WaitForChild("Head", 5)
				setUniform(character, playerShop[player] ~= nil)
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		hookCharacter(player)
	end
	Players.PlayerAdded:Connect(hookCharacter)
	Players.PlayerRemoving:Connect(function(player)
		dropCarry(player)
		stationed[player] = nil
		parked[player] = nil
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
