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
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local GameClock = require(ReplicatedStorage.Shared.GameClock)
local Pizza3D = require(ReplicatedStorage.Shared.Pizza3D)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CarService = require(script.Parent.CarService)
local ClockService = require(script.Parent.ClockService)
local DataService = require(script.Parent.DataService)
local SalesPlan = require(script.Parent.SalesPlan)

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
	cancelled: boolean,
	stage: string, -- "Making" | "Rack" | "Out" | "Pickup" | "Done"
	claimedBy: Player?,
}

type Ticket = {
	id: number,
	order: Order,
	index: number,
	item: Item,
	stage: string, -- "Sauce" | "Cheese" | "Toppings" | "Oven" | "Cut" (end of belt) | "Ready" (boxed) | "Done"
	claimedBy: Player?,
	quality: { number },
	visual: Model?,
	counts: { [string]: number }?,
	sauce: number?, -- sauce score once sauced (nil = not yet)
	cheese: number?, -- cheese, as a ratio of the portion, once cheesed (nil = not yet)
	cheeseFactor: number, -- cheese portion accuracy
	portionFactor: number, -- cheese x topping portion accuracy (penalizes satisfaction)
	boxWrong: boolean,
	exitAt: number?, -- when it reached the end of the oven belt (real clock)
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
	orderCounter: number,
	ticketCounter: number,
	rng: Random,
	week: SalesPlan.Week?,
	weekNumber: number,
	day: number,
	mix: SalesPlan.Mix,
	demandToday: number, -- forecast dollars generated so far today
	sales: { today: number, week: number, crewToday: number, ordersToday: number, loadSum: number, loadCount: number },
	rack: { [number]: RackSkin }, -- dough rack slot -> stretched skin (nil = empty)
	lastRestock: number,
	spawning: number,
	alive: boolean,
}

type Session = {
	token: string,
	kind: string,
	shop: Shop,
	started: number,
	pending: PendingOrder?,
	ticket: Ticket?,
	order: Order?,
	data: any,
	consumed: { [string]: number }?,
	skin: { skin: RackSkin, slot: number }?, -- dough skin taken for a make-line session (returned on cancel)
	tool: Tool?,
}

local ShopService = {}

local shops: { Shop } = {}
local sessions: { [Player]: Session } = {}
local playerShop: { [Player]: Shop } = {}
local houses: { Part } = {}
local nextShopId = 0

local STATION_KIND = {
	Register = "Register",
	Dough = "Dough",
	Sauce = "Sauce",
	Cheese = "Cheese",
	Toppings = "Toppings",
	CutTable = "Cut",
	DeliveryRack = "Delivery",
	SupplyTruck = "Supply",
}
-- Derived from Config so adding or changing a job can't leave these out of date.
local STAFF_JOBS = Config.JobsWithStation("Register") -- anyone who takes orders / makes pizzas
local DRIVING_JOBS = Config.JobsWithStation("DeliveryRack")
local MANAGEMENT_JOBS = Config.ManagementJobs()

local SESSION_TIMEOUT = 120
local FLAT = Pizza3D.FLAT

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function notify(player: Player?, text: string, color: Color3?)
	if player and player.Parent then
		Remotes.Notify:FireClient(player, text, color)
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
			disc("Screen", 2.55, 0.03, CFrame.new(slotMarker.Position + Vector3.new(0, 0.02, 0)), Color3.fromRGB(150, 152, 156), Enum.Material.DiamondPlate)
			disc("Skin", Config.PizzaDiameter[skin.size], 0.06, CFrame.new(slotMarker.Position + Vector3.new(0, 0.065, 0)), Config.IngredientColors.Dough, Enum.Material.SmoothPlastic)
		end
	end
end

---------------------------------------------------------------------------
-- Screens: kitchen display, lobby order tracker, stock tablet, sales board
---------------------------------------------------------------------------

local KDS_LABEL = { Sauce = "SAUCE", Cheese = "CHEESE", Toppings = "TOPPINGS", Oven = "OVEN", Cut = "CUT/BOX", Ready = "BOXED" }

local function trackerStep(o: Order): number
	if o.stage == "Rack" then
		return 4
	elseif o.stage == "Out" or o.stage == "Pickup" then
		return 5
	end
	local lowest = 5
	for _, t in o.tickets do
		local step = if t.stage == "Sauce" or t.stage == "Cheese" or t.stage == "Toppings" then 2 elseif t.stage == "Oven" then 3 else 4
		lowest = math.min(lowest, step)
	end
	return lowest
end

local function trackerLine(o: Order): string
	local steps = { "Placed", "Prep", "Bake", "Quality Check", if o.delivery then "Out for Delivery" else "Ready" }
	local current = trackerStep(o)
	local parts = {}
	for i, name in steps do
		if i == current then
			table.insert(parts, string.format('<font color="#FFBE3C"><b>%s</b></font>', string.upper(name)))
		elseif i < current then
			table.insert(parts, string.format('<font color="#FFFFFF">%s</font>', name))
		else
			table.insert(parts, string.format('<font color="#666C78">%s</font>', name))
		end
	end
	return string.format("<b>#%d</b> (%d) %s  %s", o.id, #o.entered, formatMinutes(os.clock() - o.created), table.concat(parts, "  >  "))
end

local function updateBoards(shop: Shop)
	if not shop.alive then
		return
	end
	local board = marker(shop, "TicketBoard")
	local gui = board and board:FindFirstChild("Tickets")
	local text = gui and gui:FindFirstChild("Text") :: TextLabel?
	if text then
		-- Header: dough skins on the rack, then tickets with their order's load time (real minutes).
		local counts, used = rackCounts(shop)
		local lines = {
			string.format("DOUGH  S:%d  M:%d  L:%d  (%d/%d)", counts.Small, counts.Medium, counts.Large, used, Config.RackCapacity()),
		}
		local now = os.clock()
		for _, t in shop.tickets do
			if t.stage == "Ready" then
				continue
			end
			if #lines >= 6 then
				table.insert(lines, "...")
				break
			end
			local o = t.order
			local tag = if o.delivery then string.format("DLV #%d", o.house or 0) else "CARRYOUT"
			local who = if t.claimedBy then " *" else ""
			table.insert(lines, string.format("%-7s %s %-10s %-8s %-9s %d/%d  %s%s", ticketLabel(t), string.sub(t.item.size, 1, 1), string.upper(t.item.pizza), KDS_LABEL[t.stage] or t.stage, tag, t.index, #o.tickets, formatMinutes(now - o.created), who))
		end
		if #lines == 1 then
			table.insert(lines, if isOpen() then "NO ORDERS - WAITING ON THE PHONES" elseif canWork() then "PREP TIME - STRETCH DOUGH" else "CLOSED")
		end
		text.Text = table.concat(lines, "\n")
	end

	local tv = marker(shop, "TrackerScreen")
	local tvGui = tv and tv:FindFirstChild("Tracker")
	local tvText = tvGui and tvGui:FindFirstChild("Text") :: TextLabel?
	if tvText then
		local lines = { '<font size="30"><b>ORDER TRACKER</b></font>', "" }
		for _, o in shop.orders do
			if #lines >= 10 then
				break
			end
			table.insert(lines, trackerLine(o))
		end
		if #lines == 2 then
			local idle = if isOpen() then "No orders right now." else "Closed - " .. GameClock.hoursText() .. "."
			table.insert(lines, '<font color="#666C78">' .. idle .. "</font>")
		end
		tvText.Text = table.concat(lines, "\n")
	end

	local fridge = station(shop, "Fridge")
	local stockGui = fridge and fridge:FindFirstChild("StockBoard", true)
	local stockText = stockGui and stockGui:FindFirstChild("Text") :: TextLabel?
	if stockText then
		local lines = { " STOCK" }
		for _, ing in Config.Ingredients do
			local n = shop.stock[ing]
			table.insert(lines, string.format(" %-10s %3d%s", ing, n, if n <= 3 then " LOW!" else ""))
		end
		stockText.Text = table.concat(lines, "\n")
	end
end

local function updateSalesBoard(shop: Shop)
	local board = marker(shop, "SalesBoard")
	local gui = board and board:FindFirstChild("Sales")
	local text = gui and gui:FindFirstChild("Text") :: TextLabel?
	if not text then
		return
	end
	local day, hour = GameClock.split(ClockService.WeekHour())
	local week = shop.week
	local part = GameClock.daypart(hour)
	text.Text = table.concat({
		string.format("%s  %s  (week %d)", string.upper(GameClock.dayName(day)), GameClock.format(hour), ClockService.WeekNumber()),
		string.format("Daypart: %s", if part then part.name .. string.format(" (%d%% of sales)", math.floor(part.share * 100)) else "CLOSED"),
		"",
		string.format("Today  %s / %s fcst", money(shop.sales.today), money(if week then week.days[day] else 0)),
		string.format("Week   %s / %s fcst", money(shop.sales.week), money(if week then week.total else 0)),
		string.format("Orders today %d   avg ticket ~%s", shop.sales.ordersToday, money(SalesPlan.expectedTicket(shop.mix))),
		string.format("Avg load time %s  (real min, order -> ready)", if shop.sales.loadCount > 0 then formatMinutes(shop.sales.loadSum / shop.sales.loadCount) else "--:--"),
		string.format("Crew-covered today %s", money(shop.sales.crewToday)),
	}, "\n")
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
	notify(player, string.format("+%d coins  +%d XP  %s - %s", amount, xp, what, grade), Color3.fromRGB(255, 220, 90))
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

-- A closed pizza box sized for `size` (for carryout boxes in the warmer).
local function makeBoxPart(size: string): Part
	local bs = Config.BoxSize[size] or 2.55
	local p = Instance.new("Part")
	p.Name = "PizzaBox"
	p.Size = Vector3.new(bs, 0.3, bs)
	p.Color = Color3.fromRGB(205, 168, 118)
	p.Material = Enum.Material.Cardboard
	p.CanCollide = false
	p.CanQuery = false
	p.Massless = true
	p.Anchored = true
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.CanvasSize = Vector2.new(110, 110)
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.Font = Enum.Font.FredokaOne
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
		cancelled = false,
		stage = "Making",
		claimedBy = nil,
	}
	if takenBy then
		order.workers[takenBy] = true
	end
	for i, item in entered do
		shop.ticketCounter += 1
		local ticket: Ticket = {
			id = shop.ticketCounter,
			order = order,
			index = i,
			item = item,
			stage = "Sauce", -- dough is stretched ahead of time; tickets start at the sauce spot
			claimedBy = nil,
			quality = {},
			visual = nil,
			counts = nil,
			sauce = nil,
			cheese = nil,
			cheeseFactor = 1,
			portionFactor = 1,
			boxWrong = false,
			exitAt = nil,
		}
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

local function removeOrder(shop: Shop, order: Order)
	order.stage = "Done"
	for _, t in order.tickets do
		t.stage = "Done"
		if t.visual then
			t.visual:Destroy()
			t.visual = nil
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

-- A pizza waiting at `stage` that nobody is working: the one asked for by id
-- if it qualifies, otherwise the next in line that `accept` allows (for the cut
-- table, the one closest to falling off the belt).
local function pickTicket(shop: Shop, stage: string, ticketId: number?, accept: ((Ticket) -> boolean)?): Ticket?
	local best: Ticket? = nil
	for _, t in shop.tickets do
		if t.stage == stage and not t.claimedBy and not t.order.cancelled and (ticketId ~= nil or not accept or accept(t)) then
			if ticketId then
				if t.id == ticketId then
					return t
				end
			elseif not best then
				best = t
			elseif stage == "Cut" and (t.exitAt or 0) < (best.exitAt or 0) then
				best = t
			end
		end
	end
	return best
end

-- Pizzas the players currently have on their plate (for crew overflow).
local function openPizzas(shop: Shop): number
	local n = 0
	for _, t in shop.tickets do
		if t.stage ~= "Ready" and t.stage ~= "Done" then
			n += 1
		end
	end
	for _, e in shop.pending do
		n += #e.items
	end
	return n
end

-- Baked pizzas wait at the end of the belt, oldest at the very edge, the rest
-- queued behind it. Someone has to pull them onto boxes before they fall off.
local function arrangeCutTable(shop: Shop)
	local inM, outM = marker(shop, "ConveyorIn"), marker(shop, "ConveyorOut")
	if not inM or not outM then
		return
	end
	local back = (inM.Position - outM.Position).Unit
	local waiting = {}
	for _, t in shop.tickets do
		if t.stage == "Cut" and t.visual then
			table.insert(waiting, t)
		end
	end
	table.sort(waiting, function(a, b)
		return (a.exitAt or 0) < (b.exitAt or 0)
	end)
	local offset = 0
	for _, t in waiting do
		local d = Config.PizzaDiameter[t.item.size] or 2.4
		offset += d / 2
		Pizza3D.place(t.visual :: Model, CFrame.new(outM.Position + back * (offset - 1.0)))
		offset += d / 2 + 0.1
	end
end

-- Left too long at the end of the belt: the pizza slides off onto the floor
-- and has to be remade from a fresh dough skin.
local function dropPizza(shop: Shop, ticket: Ticket)
	local outM = marker(shop, "ConveyorOut")
	local visual = ticket.visual
	ticket.visual = nil
	ticket.exitAt = nil
	-- Start over from a fresh skin: sauce, cheese and toppings all get redone.
	ticket.stage = "Sauce"
	ticket.sauce = nil
	ticket.cheese = nil
	ticket.cheeseFactor = 1
	ticket.portionFactor = 1
	ticket.counts = nil
	table.insert(ticket.quality, 0.5) -- the remake costs the order some quality/time
	if visual and visual.PrimaryPart and outM then
		local crust = visual.PrimaryPart :: BasePart
		local inM = marker(shop, "ConveyorIn")
		local out = if inM then (outM.Position - inM.Position).Unit else Vector3.new(1, 0, 0)
		-- The shop pivot is the floor slab's center (0.5 below its top surface).
		local floorTop = shop.model:GetPivot().Position.Y + 0.5
		local landing = outM.Position + out * 2
		TweenService:Create(crust, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			CFrame = CFrame.new(landing.X, floorTop + 0.15, landing.Z) * CFrame.Angles(math.rad(35), 0, math.rad(20)) * FLAT,
		}):Play()
		task.delay(4, function()
			visual:Destroy()
		end)
	elseif visual then
		visual:Destroy()
	end
	arrangeCutTable(shop)
	for _, p in staffAt(shop, STAFF_JOBS) do
		notify(p, string.format("Pizza %s fell off the end of the oven! It has to be remade from a fresh skin.", ticketLabel(ticket)), Color3.fromRGB(255, 110, 90))
	end
	updateBoards(shop)
end

local function pizzaSpec(ticket: Ticket, baked: boolean): Pizza3D.Spec
	return { size = ticket.item.size, sauce = ticket.sauce, cheese = ticket.cheese, toppings = ticket.counts, seed = ticket.id, baked = baked }
end

-- Where pizzas wait between make steps (markers on the make-line board).
local WAITING_SPOT = { Cheese = "SaucedQueue", Toppings = "CheesedQueue" }

-- Lines up the pizzas waiting for cheese / toppings at their spots. Several
-- waiting at once fan out and stack a little so each one stays visible.
local function arrangeMakeQueues(shop: Shop)
	for stage, markerName in WAITING_SPOT do
		local spotMarker = marker(shop, markerName)
		if not spotMarker then
			continue
		end
		local n = 0
		for _, t in shop.tickets do
			if t.stage == stage and t.visual then
				local fan = if n % 2 == 1 then 0.3 else -0.3 * math.min(n, 1)
				Pizza3D.place(t.visual, spotMarker.CFrame * CFrame.new(fan, 0.06 + n * 0.16, 0))
				n += 1
			end
		end
	end
end

-- Rebuilds a ticket's pizza with the layers it has so far and puts it in its
-- stage's waiting spot, so every pizza in the make process exists in the world.
local function placeInQueue(shop: Shop, ticket: Ticket)
	if ticket.visual then
		ticket.visual:Destroy()
	end
	local spotMarker = marker(shop, WAITING_SPOT[ticket.stage] or "")
	local at = if spotMarker then spotMarker.CFrame else shop.model:GetPivot()
	ticket.visual = Pizza3D.fromSpec(at, pizzaSpec(ticket, false), shop.model).model
	arrangeMakeQueues(shop)
end

-- Hands-off conveyor bake: the pizza (with what the maker actually put on it)
-- rides through the oven and waits at the end of the belt for the cutter.
local function startBake(shop: Shop, ticket: Ticket)
	ticket.stage = "Oven"
	if ticket.visual then
		ticket.visual:Destroy() -- its make-line copy; the oven gets a fresh one below
		ticket.visual = nil
	end
	arrangeMakeQueues(shop)
	local inM, outM = marker(shop, "ConveyorIn"), marker(shop, "ConveyorOut")
	local start = if inM then CFrame.new(inM.Position) else shop.model:GetPivot()
	local pizza = Pizza3D.fromSpec(start, pizzaSpec(ticket, false), shop.model)
	ticket.visual = pizza.model
	if outM then
		TweenService:Create(pizza.crust, TweenInfo.new(Config.Oven.BakeTime, Enum.EasingStyle.Linear), {
			CFrame = CFrame.new(outM.Position) * FLAT,
		}):Play()
	end
	updateBoards(shop)
	task.delay(Config.Oven.BakeTime / 2, function()
		if pizza.model.Parent then
			pizza:setBaked(true)
		end
	end)
	task.delay(Config.Oven.BakeTime, function()
		if not shop.alive or ticket.stage ~= "Oven" then
			return
		end
		ticket.stage = "Cut"
		ticket.exitAt = os.clock()
		arrangeCutTable(shop)
		updateBoards(shop)
	end)
end

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
		table.insert(qualities, average(t.quality))
		table.insert(portions, t.portionFactor)
		if t.boxWrong then
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
		box.CFrame = pickup.CFrame * CFrame.new(0, -0.1 + (i - 1) * 0.32, 0)
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
				box.CFrame = root.CFrame * CFrame.new(0, -0.3 + (i - 1) * 0.32, -1.6)
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
		if t.stage ~= "Ready" then
			return
		end
	end
	if order.cancelled then
		for worker in order.workers do
			notify(worker, "Order #" .. order.id .. "'s customer already left.", Color3.fromRGB(255, 160, 100))
		end
		removeOrder(shop, order)
		return
	end
	-- Load time: real minutes from order placed to every pizza boxed and ready.
	local loadTime = os.clock() - order.created
	shop.sales.loadSum += loadTime
	shop.sales.loadCount += 1
	for worker in order.workers do
		notify(worker, string.format("Order #%d ready - load time %s", order.id, formatMinutes(loadTime)), Color3.fromRGB(180, 220, 255))
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
		if session.ticket then
			session.ticket.claimedBy = nil
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
		if session.skin then
			-- Put the unused dough skin back in its slot.
			rackAdd(session.shop, session.skin.skin, session.skin.slot)
			updateSkinRack(session.shop)
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

local function begin(player: Player, shop: Shop, kind: string, data: any, extra: { [string]: any }?): Session
	local session: Session = {
		token = HttpService:GenerateGUID(false),
		kind = kind,
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

-- Starts `player` on a station. For stations that work tickets, `ticketId`
-- picks a specific waiting pizza (from the queue panel or "what next?");
-- otherwise they get the next one in line.
local function startStation(shop: Shop, stationName: string, player: Player, ticketId: number?)
	if not shop.alive then
		return
	end
	if not canWork() then
		notify(player, closedMessage(), Color3.fromRGB(255, 160, 100))
		return
	end
	if sessions[player] then
		notify(player, "Finish what you're doing first!")
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
			notify(player, "No customers or calls waiting right now.")
			return
		end
		entry.claimedBy = player
		local what = SalesPlan.describe(entry.items)
		local line = if entry.kind == "phone" then string.format(randomFrom(PHONE_LINES), what, entry.house or 0) else string.format(randomFrom(WALKIN_LINES), what)
		begin(player, shop, kind, { line = line, phone = entry.kind == "phone", houses = #houses }, { pending = entry })
	elseif kind == "Dough" then
		-- Prep work, not made to order: stretch a skin of any size onto the rack.
		local counts, used = rackCounts(shop)
		if used >= Config.RackCapacity() then
			notify(player, "The dough racks are full - make some pizzas first!")
			return
		end
		local needs = { Dough = 1 }
		if hasStock(shop, needs) then
			notify(player, "Out of Dough! A manager needs to unload the truck.", Color3.fromRGB(255, 120, 100))
			return
		end
		consume(shop, needs)
		begin(player, shop, kind, {
			presses = Config.Dough.Presses,
			sizes = Config.Sizes,
			skins = counts,
			rackUsed = used,
			rackCapacity = Config.RackCapacity(),
			station = station(shop, stationName),
		}, { consumed = needs })
	elseif kind == "Sauce" or kind == "Cheese" or kind == "Toppings" then
		-- At the sauce spot, skip pizzas whose size has no stretched skin on the racks.
		local skinCounts = rackCounts(shop)
		local hasSkin = if kind == "Sauce"
			then function(t: Ticket): boolean
				return (skinCounts[t.item.size] or 0) > 0
			end
			else nil
		local ticket = pickTicket(shop, kind, ticketId, hasSkin)
		if not ticket then
			local what = if kind == "Sauce" then "sauce" elseif kind == "Cheese" then "cheese" else "toppings"
			local message = if ticketId then "That pizza isn't waiting here any more." else "No pizzas waiting for " .. what .. "."
			if kind == "Sauce" and not ticketId and pickTicket(shop, "Sauce", nil) then
				message = "Pizzas are waiting for sauce, but there are no skins in their sizes. Stretch some at the dough table."
			end
			notify(player, message, Color3.fromRGB(255, 160, 100))
			return
		end
		local size = ticket.item.size
		local recipe = Config.Recipes[ticket.item.pizza] or {}
		if kind == "Sauce" and (rackCounts(shop))[size] == 0 then
			notify(player, string.format("No %s dough skins on the racks! Stretch some at the dough table.", size), Color3.fromRGB(255, 140, 90))
			return
		end
		local needs: { [string]: number } = {}
		if kind == "Sauce" then
			needs.Sauce = 1
		elseif kind == "Cheese" then
			needs.Cheese = 1
		else
			for _, topping in recipe do
				needs[topping] = 1
			end
		end
		local missing = hasStock(shop, needs)
		if missing then
			notify(player, "Out of " .. missing .. "! A manager needs to unload the truck.", Color3.fromRGB(255, 120, 100))
			return
		end
		consume(shop, needs)
		local extra: { [string]: any } = { ticket = ticket, consumed = needs }
		if kind == "Sauce" then
			-- Oldest skin of this size off the racks (first in, first out).
			local taken, slot = rackTake(shop, size)
			extra.skin = { skin = taken :: RackSkin, slot = slot :: number }
			updateSkinRack(shop)
		end
		ticket.claimedBy = player
		local data: any = {
			ticket = string.sub(ticketLabel(ticket), 2), -- UIs add their own "#"
			ticketId = ticket.id,
			pizza = ticket.item.pizza,
			size = size,
			diameter = Config.PizzaDiameter[size],
			station = station(shop, stationName),
			spec = pizzaSpec(ticket, false), -- the layers it already has
			visual = ticket.visual, -- the waiting copy, hidden locally while this player works it
		}
		if kind == "Cheese" then
			data.cheese = Config.CheesePortion[size]
		elseif kind == "Toppings" then
			data.toppings = recipe
			data.portions = {}
			for _, topping in recipe do
				data.portions[topping] = Config.PortionFor(topping, size, #recipe)
			end
		end
		begin(player, shop, kind, data, extra)
	elseif kind == "Cut" then
		local ticket = pickTicket(shop, "Cut", ticketId)
		if not ticket then
			notify(player, if ticketId then "That pizza isn't waiting here any more." else "Nothing's come out of the oven yet.")
			return
		end
		ticket.claimedBy = player
		local bubbles = {}
		if math.random() < Config.Cut.BubbleChance then
			for _ = 1, math.random(1, Config.Cut.MaxBubbles) do
				table.insert(bubbles, { x = 0.25 + math.random() * 0.5, y = 0.25 + math.random() * 0.5 })
			end
		end
		local slices = Config.Cut.Slices[ticket.item.size] or 8
		begin(player, shop, kind, {
			ticket = string.sub(ticketLabel(ticket), 2), -- UIs add their own "#"
			pizza = ticket.item.pizza,
			size = ticket.item.size,
			cuts = slices // 2,
			bubbles = bubbles,
			sizes = Config.Sizes,
			station = station(shop, stationName),
			spec = pizzaSpec(ticket, true),
			visual = ticket.visual, -- hidden locally while the cutter works on it
			exitPos = if ticket.visual and ticket.visual.PrimaryPart then ticket.visual.PrimaryPart.Position else nil,
		}, { ticket = ticket })
	elseif kind == "Supply" then
		local sorted = table.clone(Config.Ingredients)
		table.sort(sorted, function(a, b)
			return shop.stock[a] < shop.stock[b]
		end)
		local crates = {}
		for _ = 1, Config.Supply.Crates do
			table.insert(crates, sorted[math.random(1, 6)])
		end
		begin(player, shop, kind, { crates = crates, shelves = Config.Ingredients })
	elseif kind == "Delivery" then
		local order: Order? = nil
		for _, o in shop.orders do
			if o.stage == "Rack" and not o.claimedBy then
				order = o
				break
			end
		end
		if not order then
			notify(player, "No orders on the heat rack yet.")
			return
		end
		local door = houses[order.house or 0]
		if not door then
			-- The phone order was rung in with an address that doesn't exist.
			removeOrder(shop, order)
			notify(player, "Order #" .. order.id .. " has an invalid address - tossed.", Color3.fromRGB(255, 120, 100))
			return
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
		begin(player, shop, kind, { house = order.house }, { order = order, tool = tool })
		Remotes.DeliveryTarget:FireClient(player, door, Config.Delivery.SlowTime)
		notify(player, string.format("Order #%d (%d pizza%s, %s) to house #%d. Your car's out back - drive safe!", order.id, #order.entered, if #order.entered == 1 then "" else "s", money(SalesPlan.price(order.entered)), order.house or 0), Color3.fromRGB(120, 255, 160))
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

-- Tells the client a station step is done so it can offer what to do next:
-- follow this pizza to its next station, or take the next one at this station.
local function stepDone(player: Player, stationName: string, ticket: Ticket?)
	local info: any = { station = stationName }
	if ticket then
		local nextStation = Config.StationForStage(ticket.stage)
		if nextStation and nextStation ~= stationName then
			info.next = nextStation
			info.ticketId = ticket.id
			info.label = string.sub(ticketLabel(ticket), 2)
		end
	end
	Remotes.StepDone:FireClient(player, info)
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
		local hits = payload.hits
		if type(hits) ~= "table" or #hits ~= Config.Dough.Presses then
			return
		end
		local sum = 0
		for _, h in hits do
			if not isNumber(h) then
				return
			end
			sum += math.clamp(h, 0, 1)
		end
		local size = payload.size
		if type(size) ~= "string" or not table.find(Config.Sizes, size) then
			return
		end
		if elapsed < Config.Dough.Presses * 0.3 then
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
		local score = sum / Config.Dough.Presses
		rackAdd(shop, { size = size, quality = score, made = os.clock() })
		updateSkinRack(shop)
		updateBoards(shop)
		pay(shop, player, Config.Pay.Dough, score, size .. " dough stretched")
		stepDone(player, "Dough")
	elseif kind == "Sauce" then
		-- Sauce: even density across ring/sector cells, full coverage, nothing over the rim.
		local sauce = payload.sauce
		local S = Config.Sauce
		if type(sauce) ~= "table" or type(sauce.cells) ~= "table" or #sauce.cells ~= S.Rings * S.Sectors then
			return
		end
		if elapsed < 1.5 then
			return tooFast(player)
		end
		local densities, total = {}, 0
		for i, amount in sauce.cells do
			if not isNumber(amount) then
				return
			end
			amount = math.clamp(amount, 0, S.Ladle)
			total += amount
			local ring = (i - 1) // S.Sectors + 1
			local area = (ring * ring - (ring - 1) * (ring - 1)) / (S.Rings * S.Rings * S.Sectors)
			table.insert(densities, amount / area)
		end
		local overflow = if isNumber(sauce.overflow) then math.clamp(sauce.overflow, 0, S.Ladle) else 0
		local mean = 0
		for _, d in densities do
			mean += d
		end
		mean /= #densities
		local variance, covered = 0, 0
		for _, d in densities do
			variance += (d - mean) ^ 2
			if mean > 0 and d >= mean * 0.25 then
				covered += 1
			end
		end
		local cv = if mean > 0 then math.sqrt(variance / #densities) / mean else 1
		local amountFactor = math.min(1, total / (S.Ladle * 0.9))
		local spill = if total + overflow > 0 then overflow / (total + overflow) else 0
		local score = math.clamp(1 - cv * 0.6, 0, 1) * (covered / #densities) * amountFactor * (1 - spill)

		local ticket = session.ticket :: Ticket
		local skin = session.skin
		endSession(player, session, false)
		ticket.claimedBy = nil
		ticket.sauce = score
		if skin then
			table.insert(ticket.quality, skin.skin.quality) -- how well the dough was stretched
		end
		table.insert(ticket.quality, score)
		ticket.order.workers[player] = true
		ticket.stage = "Cheese"
		placeInQueue(shop, ticket)
		updateBoards(shop)
		pay(shop, player, Config.Pay.Sauce, score, "Sauced")
		stepDone(player, "Sauce", ticket)
	elseif kind == "Cheese" then
		local cheese = payload.cheese
		if not isNumber(cheese) then
			return
		end
		if elapsed < 1 then
			return tooFast(player)
		end
		local ticket = session.ticket :: Ticket
		local target = Config.CheesePortion[ticket.item.size] or 6
		local oz = math.clamp(cheese, 0, target * 3)
		local factor = Config.PortionFactor(oz, target)
		endSession(player, session, false)
		ticket.claimedBy = nil
		ticket.cheese = oz / target
		ticket.cheeseFactor = factor
		ticket.portionFactor = factor
		table.insert(ticket.quality, factor)
		ticket.order.workers[player] = true
		pay(shop, player, Config.Pay.Cheese, factor, "Cheesed")
		if factor < 1 then
			notify(player, "Cheese portion was more than 10% off - the customer will notice.", Color3.fromRGB(255, 180, 100))
		end
		if #(Config.Recipes[ticket.item.pizza] or {}) == 0 then
			startBake(shop, ticket) -- a cheese pizza has nothing to top
		else
			ticket.stage = "Toppings"
			placeInQueue(shop, ticket)
		end
		updateBoards(shop)
		stepDone(player, "Cheese", ticket)
	elseif kind == "Toppings" then
		-- Topping portions (+ penalty for anything that isn't on the recipe)
		local counts = payload.counts
		if type(counts) ~= "table" then
			return
		end
		if elapsed < 1 then
			return tooFast(player)
		end
		local ticket = session.ticket :: Ticket
		local size = ticket.item.size
		local recipe = Config.Recipes[ticket.item.pizza] or {}
		local placed: { [string]: number } = {}
		local factors = {}
		for _, topping in Config.Toppings do
			local n = counts[topping]
			n = if isNumber(n) then math.clamp(math.floor(n), 0, 80) else 0
			placed[topping] = n
			if table.find(recipe, topping) then
				table.insert(factors, Config.PortionFactor(n, Config.PortionFor(topping, size, #recipe)))
			elseif n > 0 then
				table.insert(factors, 0.5)
			end
		end
		local score = if #factors > 0 then average(factors) else 1
		endSession(player, session, false)
		ticket.claimedBy = nil
		ticket.counts = placed
		ticket.portionFactor = ticket.cheeseFactor * score
		table.insert(ticket.quality, score)
		ticket.order.workers[player] = true
		pay(shop, player, Config.Pay.Toppings, score, "Topped")
		if score < 1 then
			notify(player, "Topping portions were more than 10% off - the customer will notice.", Color3.fromRGB(255, 180, 100))
		end
		startBake(shop, ticket)
		stepDone(player, "Toppings", ticket)
		startBake(shop, ticket)
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
		if elapsed < 1.5 then
			return tooFast(player)
		end
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
		local ticket = session.ticket :: Ticket
		local boxOk = box == ticket.item.size
		local score = 0.5 * cutScore + 0.25 * bubbleScore + (if boxOk then 0.25 else 0)

		endSession(player, session, false)
		ticket.claimedBy = nil
		ticket.boxWrong = not boxOk
		table.insert(ticket.quality, score)
		ticket.order.workers[player] = true
		if ticket.visual then
			ticket.visual:Destroy()
			ticket.visual = nil
		end
		ticket.stage = "Ready"
		arrangeCutTable(shop)
		local profile = DataService.Get(player)
		if profile then
			profile.PizzasMade += 1
		end
		pay(shop, player, Config.Pay.Cut, score, if boxOk then "Cut & boxed" else "Wrong box size!")
		updateBoards(shop)
		checkOrder(shop, ticket.order)
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

-- What staff see in the queue panel and on the HUD station bar: every open
-- order with where each pizza is, how many pizzas wait at each station, and
-- what's on the dough racks.
local function queueSnapshot(shop: Shop): any
	local waiting: { [string]: number } = {}
	for _, t in shop.tickets do
		local stationName = Config.StationForStage(t.stage)
		if stationName and not t.claimedBy and not t.order.cancelled then
			waiting[stationName] = (waiting[stationName] or 0) + 1
		end
	end
	for _, e in shop.pending do
		if not e.claimedBy then
			waiting.Register = (waiting.Register or 0) + 1
		end
	end
	for _, o in shop.orders do
		if o.stage == "Rack" and not o.claimedBy then
			waiting.DeliveryRack = (waiting.DeliveryRack or 0) + 1
		end
	end
	local counts, used = rackCounts(shop)
	local orders = {}
	local now = os.clock()
	for _, o in shop.orders do
		if #orders >= 12 then
			break
		end
		local tickets = {}
		for _, t in o.tickets do
			table.insert(tickets, {
				id = t.id,
				index = t.index,
				size = t.item.size,
				pizza = t.item.pizza,
				stage = t.stage,
				claimedBy = if t.claimedBy then t.claimedBy.UserId else nil,
			})
		end
		table.insert(orders, {
			id = o.id,
			delivery = o.delivery,
			house = o.house,
			stage = o.stage,
			age = now - o.created,
			tickets = tickets,
		})
	end
	return { waiting = waiting, rack = { counts = counts, used = used, capacity = Config.RackCapacity() }, orders = orders }
end

local function tick(shop: Shop)
	local now = os.clock()
	local S = Config.Shop
	runDemand(shop)
	updateSalesBoard(shop)

	-- Keep everyone on shift here up to date for the queue panel / station bar.
	local staff = staffAt(shop, STAFF_JOBS)
	if #staff > 0 then
		local snapshot = queueSnapshot(shop)
		for _, p in staff do
			Remotes.QueueUpdate:FireClient(p, snapshot)
		end
	end

	-- Tend the oven: anything left at the end of the belt too long falls off.
	for _, t in table.clone(shop.tickets) do
		if t.stage == "Cut" and not t.claimedBy and t.exitAt and now - t.exitAt > Config.Oven.FallAfter then
			dropPizza(shop, t)
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

	-- Orders whose customer walked out: drop the pizzas nobody is holding (oven ones finish first).
	for _, o in table.clone(shop.orders) do
		if o.cancelled and o.stage == "Making" then
			local busy = false
			for _, t in o.tickets do
				if t.claimedBy or t.stage == "Oven" then
					busy = true
				end
			end
			if not busy then
				removeOrder(shop, o)
				arrangeCutTable(shop)
				arrangeMakeQueues(shop)
			end
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
		orderCounter = 0,
		ticketCounter = 0,
		rng = Random.new(),
		week = nil,
		weekNumber = 0,
		day = 0,
		mix = { small = 0.88, medium = 0.11, large = 0.01 },
		demandToday = 0,
		sales = { today = 0, week = 0, crewToday = 0, ordersToday = 0, loadSum = 0, loadCount = 0 },
		rack = {},
		lastRestock = os.clock(),
		spawning = 0,
		alive = true,
	}
	for _, ing in Config.Ingredients do
		shop.stock[ing] = Config.Shop.StartingStock
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
					startStation(shop, stationName, player)
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
				startStation(shop, stationName, player)
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
			ShopService.CancelSession(player)
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

	-- HUD station bar, queue panel clicks, and "what next?" buttons. Works from
	-- anywhere in your store; the minigame moves you to the station.
	Remotes.UseStation.OnServerEvent:Connect(function(player, stationName, ticketId)
		if type(stationName) ~= "string" or (ticketId ~= nil and not isNumber(ticketId)) then
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
		startStation(shop, stationName, player, ticketId)
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
					notify(player, "You took too long - task cancelled.", Color3.fromRGB(255, 160, 100))
					ShopService.CancelSession(player)
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
