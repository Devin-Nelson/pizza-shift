--!strict
-- The store's in-world screens in the store-systems look (Style.luau), the
-- same as the HUD: the kitchen display over the make-line (order tickets),
-- the lobby order tracker, the walk-in's stock tablet and the back-office
-- sales board. ShopService hands each one plain data every update; a screen
-- is only rebuilt when what it shows changes, and ticking times and ticket
-- colours update in place (keeps replication light).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Style = require(ReplicatedStorage.Shared.Style)
local TicketRows = require(ReplicatedStorage.Shared.TicketRows)

local Screens = {}

local C = Style.Color
local F = Style.Font

type Live = { sig: string, refs: { [any]: any } }
local live: { [Instance]: Live } = setmetatable({}, { __mode = "k" }) :: any

local function frame(parent: Instance, props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for k, v in props do
		(f :: any)[k] = v
	end
	f.Parent = parent
	return f
end

local function text(parent: Instance, str: string, font: Font, size: number, props: { [string]: any }?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.FontFace = font
	t.TextSize = size
	t.TextColor3 = C.Cream
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Text = str
	if props then
		for k, v in props do
			(t :: any)[k] = v
		end
	end
	t.Parent = parent
	return t
end

-- Starts a screen over: clears it and remembers what it now shows.
local function rebuild(gui: SurfaceGui, sig: string): (Frame, { [any]: any })
	for _, c in gui:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	gui.LightInfluence = 0
	local refs = {}
	live[gui] = { sig = sig, refs = refs }
	local bg = frame(gui, { Name = "Screen", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Panel })
	return bg, refs
end

local function unchanged(gui: SurfaceGui, sig: string): { [any]: any }?
	local l = live[gui]
	return if l and l.sig == sig then l.refs else nil
end

---------------------------------------------------------------------------
-- Kitchen display (over the make-line, 1000 x 150 canvas)
---------------------------------------------------------------------------
export type KdsOrder = { id: number, delivery: boolean, age: number, items: { TicketRows.Item } }
export type Kds = {
	dough: { [string]: number },
	used: number,
	capacity: number,
	ready: number,
	readyCapacity: number,
	orders: { KdsOrder },
	idle: string?,
}

local KDS_TICKET_W = 156
local KDS_MAX_TICKETS = 6
local KDS_MAX_ROWS = 7 -- lines per ticket

function Screens.kds(gui: SurfaceGui, m: Kds)
	local parts = { m.idle or "", m.used, m.ready, m.dough.Small or 0, m.dough.Medium or 0, m.dough.Large or 0 }
	for i, o in m.orders do
		if i > KDS_MAX_TICKETS then
			table.insert(parts, "+" .. (#m.orders - KDS_MAX_TICKETS))
			break
		end
		local loaded = 0
		for _, item in o.items do
			if item.loaded then
				loaded += 1
			end
		end
		table.insert(parts, string.format("%d:%d:%d", o.id, #o.items, loaded))
	end
	local sig = table.concat(parts :: { any }, "|")
	local refs = unchanged(gui, sig)
	if not refs then
		local bg, r = rebuild(gui, sig)
		refs = r
		-- Header: the dough racks and the ready rack.
		local head = frame(bg, { Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = C.Ink })
		frame(head, { Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = C.Red })
		text(head, "MAKE-LINE", F.Heading, 16, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0, 110, 1, 0) })
		text(head, string.format("DOUGH  S %d   M %d   L %d     RACKS %d/%d     READY %d/%d", m.dough.Small or 0, m.dough.Medium or 0, m.dough.Large or 0, m.used, m.capacity, m.ready, m.readyCapacity), F.Mono, 14, {
			TextColor3 = C.CreamDim,
			Position = UDim2.fromOffset(122, 0),
			Size = UDim2.new(1, -132, 1, 0),
		})
		if #m.orders == 0 then
			text(bg, string.upper(m.idle or "No orders"), F.Heading, 30, {
				TextColor3 = C.CreamDim,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(0, 26),
				Size = UDim2.new(1, 0, 1, -26),
			})
		end
		for i, o in m.orders do
			local x = 10 + (i - 1) * (KDS_TICKET_W + 6)
			if i > KDS_MAX_TICKETS then
				local more = frame(bg, { Position = UDim2.fromOffset(x - 2, 32), Size = UDim2.fromOffset(40, 22), BackgroundColor3 = C.Tile })
				text(more, "+" .. (#m.orders - KDS_MAX_TICKETS), F.LabelBold, 14, { TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1) })
				break
			end
			local ticket = frame(bg, { Position = UDim2.fromOffset(x, 32), Size = UDim2.fromOffset(KDS_TICKET_W, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.Cream })
			local list = Instance.new("UIListLayout")
			list.SortOrder = Enum.SortOrder.LayoutOrder
			list.Parent = ticket
			local h = frame(ticket, { Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 0 })
			local title = text(h, string.format("#%d %s", o.id, if o.delivery then "DELIVERY" else "CARRYOUT"), F.LabelBold, 14, { Position = UDim2.fromOffset(6, 0), Size = UDim2.new(1, -60, 1, 0) })
			local time = text(h, "", F.Mono, 14, { TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 0), Size = UDim2.new(0, 54, 1, 0) })
			refs[o.id] = { head = h, title = title, time = time }
			local rows, hidden = TicketRows.fit(TicketRows.group(o.items), KDS_MAX_ROWS)
			local n = 0
			for _, row in rows do
				local done = TicketRows.done(row)
				-- The size on the first line; each topping on a line of its own.
				for k, label in TicketRows.lines(row) do
					n += 1
					local line = frame(ticket, { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, LayoutOrder = n })
					if k == 1 then
						frame(line, { Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = C.Rule })
						local sq = frame(line, { Position = UDim2.fromOffset(6, 3), Size = UDim2.fromOffset(13, 13), BackgroundColor3 = C.Panel })
						text(sq, string.sub(row.size, 1, 1), F.Mono, 10, { TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1) })
					end
					text(line, if done then "<s>" .. label .. "</s>" else label, F.Label, 13, {
						RichText = true,
						TextColor3 = if done then Color3.fromRGB(139, 132, 120) else C.Ink,
						Position = UDim2.fromOffset(24, 1),
						Size = UDim2.new(1, -28, 1, -1),
						TextTruncate = Enum.TextTruncate.AtEnd,
					})
				end
			end
			if hidden > 0 then
				local line = frame(ticket, { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, LayoutOrder = 99 })
				frame(line, { Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = C.Rule })
				text(line, string.format("+%d MORE", hidden), F.Label, 13, { TextColor3 = C.Ink, Position = UDim2.fromOffset(24, 1), Size = UDim2.new(1, -28, 1, -1) })
			end
		end
	end
	-- Ages tick and headers change colour as orders wait.
	for _, o in m.orders do
		local r = refs[o.id]
		if r then
			local bg, fg = Style.ticketColor(o.age)
			r.head.BackgroundColor3 = bg
			r.title.TextColor3 = fg
			r.time.TextColor3 = fg
			r.time.Text = Style.clock(o.age)
		end
	end
end

---------------------------------------------------------------------------
-- Order tracker (lobby TV, 640 x 352 canvas)
---------------------------------------------------------------------------
export type Tracked = { id: number, step: number, delivery: boolean }

function Screens.tracker(gui: SurfaceGui, orders: { Tracked }, idle: string?)
	local parts = { idle or "" }
	for i, o in orders do
		if i > 8 then
			break
		end
		table.insert(parts, string.format("%d:%d:%s", o.id, o.step, tostring(o.delivery)))
	end
	local sig = table.concat(parts, "|")
	if unchanged(gui, sig) then
		return
	end
	local bg = rebuild(gui, sig)
	local head = frame(bg, { Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = C.Red })
	text(head, "ORDER TRACKER", F.Heading, 26, { TextColor3 = C.White, Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -32, 1, 0) })
	if #orders == 0 then
		text(bg, string.upper(idle or "No orders right now"), F.Heading, 22, {
			TextColor3 = C.CreamDim,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = true,
			Position = UDim2.fromOffset(20, 46),
			Size = UDim2.new(1, -40, 1, -46),
		})
		return
	end
	for i, o in orders do
		if i > 8 then
			break
		end
		local y = 54 + (i - 1) * 36
		text(bg, "#" .. o.id, F.Mono, 18, { Position = UDim2.fromOffset(16, y), Size = UDim2.fromOffset(64, 30) })
		local steps = { "Placed", "Prep", "Bake", "Quality check", if o.delivery then "Out for delivery" else "Ready" }
		local w = (640 - 92 - 16 - 4 * 4) / #steps
		for s, name in steps do
			local bgColor, fg = C.Tile, C.CreamDim
			if s == o.step then
				bgColor, fg = C.Gold, C.Ink
			elseif s < o.step then
				bgColor, fg = C.Cream, C.Ink
			end
			local chip = frame(bg, { Position = UDim2.fromOffset(92 + (s - 1) * (w + 4), y + 2), Size = UDim2.fromOffset(w, 26), BackgroundColor3 = bgColor })
			text(chip, string.upper(name), if s == o.step then F.LabelBold else F.Label, 13, { TextColor3 = fg, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1) })
		end
	end
end

---------------------------------------------------------------------------
-- Stock tablet (walk-in, 190 x 340 canvas)
---------------------------------------------------------------------------
export type StockLine = { name: string, n: number, color: Color3, low: boolean }

function Screens.stock(gui: SurfaceGui, lines: { StockLine })
	local parts = {}
	for _, l in lines do
		table.insert(parts, l.name .. "=" .. l.n)
	end
	local sig = table.concat(parts, "|")
	if unchanged(gui, sig) then
		return
	end
	local bg = rebuild(gui, sig)
	local head = frame(bg, { Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = C.Ink })
	frame(head, { Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = C.Red })
	text(head, "STOCK", F.Heading, 20, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -20, 1, 0) })
	for i, l in lines do
		local y = 38 + (i - 1) * 33
		local row = frame(bg, { Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 31), BackgroundColor3 = if l.low then Color3.fromRGB(70, 34, 32) else C.Panel })
		frame(row, { Position = UDim2.fromOffset(8, 7), Size = UDim2.fromOffset(6, 17), BackgroundColor3 = l.color })
		text(row, string.upper(l.name), F.LabelBold, 15, { Position = UDim2.fromOffset(22, 0), Size = UDim2.new(1, -80, 1, 0) })
		text(row, tostring(l.n), F.Mono, 17, {
			TextColor3 = if l.low then C.Red else C.Cream,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 0),
			Size = UDim2.new(0, 56, 1, 0),
		})
	end
end

---------------------------------------------------------------------------
-- Sales board (back office, 600 x 360 canvas)
---------------------------------------------------------------------------
export type Sales = {
	clock: string, -- "MONDAY 11:17 AM"
	week: number,
	daypart: string, -- "LUNCH - 20% OF SALES" or "CLOSED"
	today: string,
	todayForecast: string,
	todayShare: number, -- 0-1 of the day's forecast
	weekSales: string,
	weekForecast: string,
	weekShare: number,
	orders: number,
	avgTicket: string,
	avgLoad: string,
	avgTotal: string,
	lost: string,
}

function Screens.sales(gui: SurfaceGui, m: Sales)
	local refs = unchanged(gui, "sales")
	if not refs then
		local bg, r = rebuild(gui, "sales")
		refs = r
		local head = frame(bg, { Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = C.Ink })
		frame(head, { Size = UDim2.new(0, 5, 1, 0), BackgroundColor3 = C.Red })
		text(head, "SALES", F.Heading, 24, { Position = UDim2.fromOffset(16, 0), Size = UDim2.new(0, 120, 1, 0) })
		r.clock = text(head, "", F.Mono, 16, { TextColor3 = C.CreamDim, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 0), Size = UDim2.new(0, 400, 1, 0) })
		r.daypart = text(bg, "", F.Label, 15, { TextColor3 = C.Gold, Position = UDim2.fromOffset(16, 50), Size = UDim2.new(1, -32, 0, 20) })
		local function block(y: number, label: string): (TextLabel, TextLabel, Frame)
			text(bg, label, F.Label, 13, { TextColor3 = C.CreamDim, Position = UDim2.fromOffset(16, y), Size = UDim2.fromOffset(120, 16) })
			local amount = text(bg, "", F.Mono, 30, { Position = UDim2.fromOffset(16, y + 16), Size = UDim2.fromOffset(240, 36) })
			local fcst = text(bg, "", F.Mono, 15, { TextColor3 = C.CreamDim, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.fromOffset(260, y + 26), Size = UDim2.fromOffset(324, 20) })
			local track = frame(bg, { Position = UDim2.fromOffset(16, y + 56), Size = UDim2.fromOffset(568, 6), BackgroundColor3 = C.Line })
			local fill = frame(track, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Gold })
			return amount, fcst, fill
		end
		r.today, r.todayFcst, r.todayFill = block(78, "TODAY")
		r.weekAmt, r.weekFcst, r.weekFill = block(150, "THIS WEEK")
		local stats = { { "ORDERS TODAY", "orders" }, { "AVG TICKET", "avgTicket" }, { "AVG LOAD", "avgLoad" }, { "AVG TOTAL", "avgTotal" } }
		for i, s in stats do
			local x = 16 + (i - 1) * 144
			local cell = frame(bg, { Position = UDim2.fromOffset(x, 230), Size = UDim2.fromOffset(136, 64), BackgroundColor3 = C.Tile })
			text(cell, s[1], F.Label, 12, { TextColor3 = C.CreamDim, Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 16) })
			r[s[2]] = text(cell, "", F.Mono, 22, { Position = UDim2.fromOffset(10, 26), Size = UDim2.new(1, -20, 0, 30) })
		end
		r.lost = text(bg, "", F.Label, 14, { TextColor3 = C.CreamDim, Position = UDim2.fromOffset(16, 306), Size = UDim2.new(1, -32, 0, 20) })
		text(bg, "LOAD = PLACED TO LAST PIZZA IN THE OVEN   TOTAL = PLACED TO LAST PIZZA BOXED   (REAL MIN)", F.Label, 11, {
			TextColor3 = Color3.fromRGB(120, 116, 110),
			Position = UDim2.fromOffset(16, 332),
			Size = UDim2.new(1, -32, 0, 16),
		})
	end
	refs.clock.Text = string.format("%s   WEEK %d", m.clock, m.week)
	refs.daypart.Text = m.daypart
	refs.today.Text = m.today
	refs.todayFcst.Text = "/ " .. m.todayForecast .. " FCST"
	refs.todayFill.Size = UDim2.fromScale(math.clamp(m.todayShare, 0, 1), 1)
	refs.weekAmt.Text = m.weekSales
	refs.weekFcst.Text = "/ " .. m.weekForecast .. " FCST"
	refs.weekFill.Size = UDim2.fromScale(math.clamp(m.weekShare, 0, 1), 1)
	refs.orders.Text = tostring(m.orders)
	refs.avgTicket.Text = m.avgTicket
	refs.avgLoad.Text = m.avgLoad
	refs.avgTotal.Text = m.avgTotal
	refs.lost.Text = "LOST TODAY  " .. m.lost
end

return Screens
