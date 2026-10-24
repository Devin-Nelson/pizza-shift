--!strict
-- The HUD for working the store, in the store-systems look (Style.luau):
--  * Tickets (top left), by the station you're at (Config.Stations `queue`):
--    during the make process, every order still waiting on pizzas (header goes
--    green, gold, red as it waits; loaded pizzas struck through); at the cut
--    table, every pizza in the ovens by slot (OUT to pull, red as it's about
--    to fall); at the heat rack, deliveries ready to go (click one to take it)
--    and the ones on the road.
--  * Station arrows (the user's pick, 2026-10-24, "just chevrons"): a big
--    rounded chevron on each side of the screen in the colour of the station
--    it goes to, its name under it; they step through the stations in order
--    (Register, Stretch, Sauce, Cut & Box, Dispatch, wrapping; Q / E or the
--    d-pad too), each arrow on the side its station really is from where you
--    stand, and park you there; only while you're at a station. The
--    station you're at shows above the work strip. Exit (bottom left) takes
--    you off the station, as jumping does (StationMode).
--  * Menu tab (bottom right, at your store): opens a short bar of Follow (lit
--    while you follow the top pizza, the default), Help (the station's tip),
--    the order-matching switch and Stores. While it's open the work strip
--    steps aside so nothing covers the pizza. The oldest make-line ticket
--    flashes: that's the top pizza.
--  * Staff button (beside the tab): the store's hired staff (Staff menu).
--  * Not at a store: a Stores button bottom left (open or join one).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Style = require(ReplicatedStorage.Shared.Style)
local Icons = require(ReplicatedStorage.Shared.Icons)
local TicketRows = require(ReplicatedStorage.Shared.TicketRows)
local Loading = require(script.Parent.Loading)
local StationMode = require(script.Parent.StationMode)
local StationTips = require(script.Parent.StationTips)
local Ui = require(script.Parent.Ui)

local WorkHud = {}

local C = Style.Color
local F = Style.Font
local S = Style.Size

local player = Players.LocalPlayer
local UserInputService = game:GetService("UserInputService")

-- Each station's colour on the arrows (bright, so kids learn the route by colour).
local STATION_COLORS: { [string]: Color3 } = {
	Register = Color3.fromRGB(47, 155, 255),
	Dough = Color3.fromRGB(255, 201, 60),
	Cheese = Color3.fromRGB(255, 122, 184), -- the makeline
	Sauce = Color3.fromRGB(255, 75, 62),
	CutTable = Color3.fromRGB(46, 212, 122),
	DeliveryRack = Color3.fromRGB(139, 92, 246),
}
local ROUND = Font.fromEnum(Enum.Font.FredokaOne)

local TICKET_W = 138
local MAX_TICKETS = 6
local MAX_ROWS = 8 -- lines per ticket; the rest fold into "+N more"
local KEY_W = 64 -- utility keys on the open bar
local function stationLabel(id: string): string
	local info = Config.StationInfo(id)
	return if info then info.nav or info.label else id
end

-- Every station (there are no roles), while you work at a store, except
-- the ones you only reach with a pizza (cheese and toppings: `bar` false).
local function myStations(): { string }
	local list = {}
	if player:GetAttribute("StoreId") ~= nil then
		for _, s in Config.Stations do
			if s.bar ~= false then
				table.insert(list, s.id)
			end
		end
	end
	return list
end

local function list(parent: Instance, dir: Enum.FillDirection, gap: number, valign: Enum.VerticalAlignment?): UIListLayout
	return Ui.new("UIListLayout", {
		FillDirection = dir,
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = valign or Enum.VerticalAlignment.Top,
		Parent = parent,
	})
end

---------------------------------------------------------------------------
-- Tickets
---------------------------------------------------------------------------
type Row = { size: string?, text: string, done: boolean?, indent: boolean? }

-- One ticket: a coloured header (title + time) over cream rows.
-- Returns the ticket and its time label.
local function ticket(parent: Instance, order: number, title: string, time: string, headBg: Color3, headFg: Color3, rows: { Row }, clickable: boolean?, dim: boolean?): (GuiObject, TextLabel)
	local t: GuiObject = Ui.new(if clickable then "TextButton" else "Frame", {
		BackgroundColor3 = C.Cream,
		BackgroundTransparency = if dim then 0.35 else 0,
		Size = UDim2.fromOffset(TICKET_W, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Parent = parent,
	})
	if clickable then
		(t :: any).Text = ""
		;(t :: any).AutoButtonColor = true
	end
	list(t, Enum.FillDirection.Vertical, 0)
	Ui.round(t :: GuiObject, 8)
	local head = Ui.box(headBg, { Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 0, Parent = t })
	Ui.round(head, 8)
	Ui.text(string.upper(title), F.LabelBold, S.Small, { TextColor3 = headFg, Position = UDim2.fromOffset(6, 0), Size = UDim2.new(1, -50, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, Parent = head })
	local timeLabel = Ui.text(time, F.Mono, S.Small, { TextColor3 = headFg, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 0), Size = UDim2.new(0, 60, 1, 0), Parent = head })
	for i, r in rows do
		local row = Ui.box(C.Cream, { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, LayoutOrder = i, Parent = t })
		if not r.indent then
			Ui.box(C.Rule, { Size = UDim2.new(1, 0, 0, 1), Parent = row })
		end
		local x = 6
		if r.size then
			local sq = Ui.box(C.Panel, { Position = UDim2.fromOffset(6, 3), Size = UDim2.fromOffset(15, 15), Parent = row })
			Ui.text(string.sub(r.size, 1, 1), F.Mono, S.Tiny, { TextColor3 = C.Cream, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = sq })
			x = 27
		elseif r.indent then
			x = 27 -- another topping of the pizza above
		end
		local text = string.upper(r.text)
		Ui.text(if r.done then "<s>" .. text .. "</s>" else text, F.Label, S.Small, {
			RichText = true,
			TextColor3 = if r.done then Color3.fromRGB(139, 132, 120) else C.Ink,
			Position = UDim2.fromOffset(x, 1),
			Size = UDim2.new(1, -x - 24, 1, -1),
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = row,
		})
		if r.done and not r.indent then
			local chk = Ui.box(C.Green, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -5, 0, 3), Size = UDim2.fromOffset(15, 15), Parent = row })
			local ico = Icons.make("check", 11, chk, { color = C.White })
			ico.AnchorPoint = Vector2.new(0.5, 0.5)
			ico.Position = UDim2.fromScale(0.5, 0.5)
		end
	end
	return t, timeLabel
end

function WorkHud.Init(isBusy: () -> boolean)
	local snapshot: any = nil
	local snapshotAt = 0
	local expanded = false

	-- Ticket rail ----------------------------------------------------------------
	local rail = Ui.new("Frame", {
		Name = "Tickets",
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset((TICKET_W + 6) * MAX_TICKETS + 60, 260),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = Ui.Root,
	})
	list(rail, Enum.FillDirection.Horizontal, 6)
	-- Ticking times: { label, base age or time left, kind }
	local timers: { { label: TextLabel, base: number, kind: string } } = {}

	local function clearRail()
		for _, c in rail:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		table.clear(timers)
	end

	local function overflow(n: number, order: number)
		if n > 0 then
			Ui.chip("+" .. n, C.Panel, C.Cream, { LayoutOrder = order, Parent = rail })
		end
	end

	local function rebuildRail()
		clearRail()
		if not snapshot then
			return
		end
		local here = StationMode.Current()
		local info = if here then Config.StationInfo(here) else nil
		local mode = if info then info.queue else nil
		if mode == "make" then
			for i, o in snapshot.orders do
				if i > MAX_TICKETS then
					overflow(#snapshot.orders - MAX_TICKETS, i)
					break
				end
				-- Identical pizzas share a row ("PEPPERONI x3"), so big orders still
				-- fit; each topping gets its own line under the size.
				local grouped, hidden = TicketRows.fit(TicketRows.group(o.items), MAX_ROWS)
				local rows: { Row } = {}
				for _, g in grouped do
					for j, text in TicketRows.lines(g) do
						table.insert(rows, { size = if j == 1 then g.size else nil, indent = j > 1, text = text, done = TicketRows.done(g) })
					end
				end
				if hidden > 0 then
					table.insert(rows, { text = string.format("+%d more", hidden) })
				end
				local bg, fg = Style.ticketColor(o.age)
				local kind: string = if o.delivery then "Delivery" else "Carryout"
				local title = string.format("#%d %s", o.id, kind)
				local t, timeLabel = ticket(rail, i, title, Style.clock(o.age), bg, fg, rows)
				if i == 1 then
					Ui.flashOutline(t, 2) -- the oldest: make this one first
				end
				table.insert(timers, { label = timeLabel, base = o.age, kind = "age" })
			end
		elseif mode == "oven" then
			for i, p in snapshot.oven do
				if i > MAX_TICKETS then
					overflow(#snapshot.oven - MAX_TICKETS, i)
					break
				end
				local bg, fg, time, kind
				if p.fallsIn then
					bg, fg, time, kind = C.Red, C.White, "FALLS " .. Style.clock(p.fallsIn), "falls"
				elseif p.out then
					bg, fg, time, kind = C.Green, C.White, "PULL", "out"
				else
					bg, fg, time, kind = C.Panel, C.Cream, Style.clock(p.left), "left"
				end
				local _, timeLabel = ticket(rail, i, "Slot " .. tostring(p.slot), time, bg, fg, { { size = p.size, text = tostring(p.label) } })
				table.insert(timers, { label = timeLabel, base = if kind == "falls" then p.fallsIn elseif kind == "left" then p.left else 0, kind = kind })
			end
		elseif mode == "delivery" then
			local n = 0
			for _, o in snapshot.delivery do
				if o.stage == "Rack" and n < MAX_TICKETS then
					n += 1
					local bg, fg = Style.ticketColor(o.age)
					local t, timeLabel = ticket(rail, n, string.format("#%d House %s", o.id, tostring(o.house)), Style.clock(o.age), bg, fg, { { text = string.format("%d pizza%s - take it", o.count, tostring(if o.count == 1 then "" else "s")) } }, true)
					table.insert(timers, { label = timeLabel, base = o.age, kind = "age" })
					local id = o.id;
					(t :: TextButton).Activated:Connect(function()
						Remotes.UseStation:FireServer("DeliveryRack", id)
					end)
				end
			end
			for _, o in snapshot.delivery do
				if o.stage == "Out" and n < MAX_TICKETS then
					n += 1
					ticket(rail, n, string.format("#%d House %s", o.id, tostring(o.house)), "OUT", C.Panel, C.CreamDim, { { text = "with " .. tostring(o.driver or "?") } }, false, true)
				end
			end
		end
	end

	-- Bottom left: Stores / Stations tab / open bar / follow chip ---------------
	local storesButton = Ui.flatButton("Stores", "primary", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -10),
		Size = UDim2.fromOffset(150, 44),
		TextSize = S.Big,
		Visible = false,
		Parent = Ui.Root,
	})
	storesButton.Activated:Connect(function()
		Remotes.RequestStores:FireServer()
	end)

	-- The Menu tab with the Staff button beside it, bottom right.
	local dock = Ui.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -10, 1, -10),
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = Ui.Root,
	})
	list(dock, Enum.FillDirection.Horizontal, 6)
	local tab = Ui.flatButton("", "key", {
		Name = "MenuTab",
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
		LayoutOrder = 1,
		Parent = dock,
	})
	list(tab, Enum.FillDirection.Horizontal, 8, Enum.VerticalAlignment.Center)
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = tab })
	Icons.make("grid", 14, tab).LayoutOrder = 1
	Ui.text("MENU", F.LabelBold, S.Label, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 40), LayoutOrder = 2, Parent = tab })

	local staffButton = Ui.flatButton("", "key", {
		Name = "StaffButton",
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
		LayoutOrder = 2,
		Parent = dock,
	})
	list(staffButton, Enum.FillDirection.Horizontal, 8, Enum.VerticalAlignment.Center)
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = staffButton })
	Icons.make("person", 14, staffButton).LayoutOrder = 1
	Ui.text("STAFF", F.LabelBold, S.Label, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 40), LayoutOrder = 2, Parent = staffButton })
	staffButton.Activated:Connect(function()
		Remotes.RequestStaff:FireServer()
	end)

	local bar = Ui.box(C.Panel, {
		Name = "MenuBar",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -10, 1, -10),
		Size = UDim2.fromOffset(0, 54),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
		Parent = Ui.Root,
	})
	list(bar, Enum.FillDirection.Horizontal, 0)

	local function setExpanded(on: boolean)
		expanded = on
		bar.Visible = on
	end

	local barSig = ""
	local function key(text: string, icon: string?, width: UDim2, order: number, onClick: () -> (), opts: { on: boolean?, badge: number?, dim: boolean?, iconOpts: any? }?): TextButton
		local o: any = opts or {}
		local b = Ui.flatButton("", "key", { Size = width, LayoutOrder = order, Parent = bar })
		if o.on then
			Ui.setButtonColor(b, C.Red)
		end
		Ui.box(C.Line, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 1, 1, 0), Parent = b })
		if icon then
			local ico = Icons.make(icon, 18, b, o.iconOpts)
			ico.AnchorPoint = Vector2.new(0.5, 0)
			ico.Position = UDim2.new(0.5, 0, 0, 9)
		end
		Ui.text(string.upper(text), F.Label, S.Small, {
			TextColor3 = if o.dim then C.CreamDim else C.Cream,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 2, 1, -6),
			Size = UDim2.new(1, -4, 0, 16),
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = b,
		})
		if o.badge and o.badge > 0 then
			Ui.badge(tostring(o.badge), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 5), Parent = b })
		end
		b.Activated:Connect(onClick)
		return b
	end

	local function rebuildBar()
		local here = StationMode.Current()
		local following = player:GetAttribute("Following") ~= false
		local sig = table.concat({ tostring(here), tostring(player:GetAttribute("StoreId")), Loading.mode, tostring(following) }, "|")
		if sig == barSig then
			return
		end
		barSig = sig
		for _, c in bar:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		-- Utility keys first (fixed width), so the station keys can share what's left.
		local utils: { { text: string, icon: string?, fn: () -> (), opts: any? } } = {}
		-- Follow the top pizza through the make process (lit while you do).
		table.insert(utils, { text = "Follow", icon = "chevron", fn = function()
			setExpanded(false)
			Remotes.Follow:FireServer()
		end, opts = { on = following } })
		local tipFor = here
		if tipFor and StationTips.Has(tipFor) then
			table.insert(utils, { text = "Help", icon = "help", fn = function()
				setExpanded(false)
				StationTips.Show(tipFor, true)
			end })
		end
		if here == "Toppings" then
			-- Tentative setting: who decides which order a loaded pizza is for.
			table.insert(utils, { text = if Loading.mode == "Pick" then "Pick order" else "Auto-match", icon = "check", fn = function()
				Loading.SetMode(if Loading.mode == "Pick" then "Auto" else "Pick")
				rebuildBar()
			end, opts = { iconOpts = { color = if Loading.mode == "Pick" then C.Gold else C.Green } } })
		end
		table.insert(utils, { text = "Stores", icon = "person", fn = function()
			setExpanded(false)
			Remotes.RequestStores:FireServer()
		end, opts = { dim = true, iconOpts = { color = C.CreamDim } } })
		local order = 0
		for _, u in utils do
			order += 1
			key(u.text, u.icon, UDim2.new(0, KEY_W, 1, 0), order, u.fn, u.opts)
		end
		order += 1
		local collapse = key("", "chevron", UDim2.new(0, 52, 1, 0), order, function()
			setExpanded(false)
		end, { iconOpts = { dir = "right" } })
		-- Centre the chevron (no label under it).
		local ico = collapse:FindFirstChild("Icon_chevron") :: Frame?
		if ico then
			ico.AnchorPoint = Vector2.new(0.5, 0.5)
			ico.Position = UDim2.fromScale(0.5, 0.5)
		end
	end

	tab.Activated:Connect(function()
		rebuildBar()
		setExpanded(true)
	end)

	-- Station arrows ------------------------------------------------------------
	-- A chunky rounded chevron drawn from two bars (no images), with a soft shadow.
	local function chevron(parent: Instance, dir: number, color: Color3): Frame
		local holder = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(60, 96), Parent = parent })
		for _, layer in { { offset = Vector2.new(3, 4), color = Color3.new(0, 0, 0), transparency = 0.55 }, { offset = Vector2.zero, color = color, transparency = 0 } } do
			for _, half in { -1, 1 } do
				local barPart = Ui.new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					-- Each bar's rounded end sits on the tip: its centre is (58 - 20) / 2
					-- along the bar from there, 13.4 off the middle at 45 degrees.
					Position = UDim2.fromOffset(30 + layer.offset.X, 48 + half * 13.4 + layer.offset.Y),
					Size = UDim2.fromOffset(58, 20),
					Rotation = -half * 45 * dir, -- the top bar slopes down to the tip (GUI rotation is clockwise)
					BackgroundColor3 = layer.color,
					BackgroundTransparency = layer.transparency,
					BorderSizePixel = 0,
					Parent = holder,
				})
				Ui.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = barPart })
			end
		end
		return holder
	end
	local function roundText(text: string, size: number, props: { [string]: any }): TextLabel
		local t = Ui.text(text, ROUND, size, props)
		t.TextColor3 = Color3.new(1, 1, 1)
		t.TextStrokeColor3 = Color3.new(0, 0, 0)
		t.TextStrokeTransparency = 0.45
		return t
	end
	local keyboard = UserInputService.KeyboardEnabled
	local lastStation = "Register"
	local function navBase(): string
		local here = StationMode.Current()
		-- Cheese and toppings are both the makeline stop.
		if here == "Toppings" then
			return "Cheese"
		end
		return here or lastStation
	end
	local function stationPart(id: string): BasePart?
		local ws = StationMode.Workstation()
		local folder = if ws then ws.station.Parent else nil
		for _, p in (if folder then folder:GetChildren() else {}) do
			if p:IsA("BasePart") and p:GetAttribute("Station") == id then
				return p
			end
		end
		return nil
	end
	-- The two neighbours on the route, each on the side of the screen it's
	-- really on from where you stand (the user, 2026-10-24: if Sauce is on
	-- your left, the left arrow goes there). dir -1 = left, 1 = right.
	local function stepTo(dir: number): string?
		local stations = myStations()
		local n = #stations
		if n == 0 then
			return nil
		end
		local i = table.find(stations, navBase()) or 1
		local left, right = stations[(i - 2) % n + 1], stations[i % n + 1]
		local ws = StationMode.Workstation()
		local a, b = stationPart(left), stationPart(right)
		if ws and a and b and (a.Position - ws.station.Position):Dot(ws.right) > (b.Position - ws.station.Position):Dot(ws.right) then
			left, right = right, left
		end
		return if dir < 0 then left else right
	end
	local arrows: { [number]: { button: TextButton, art: Frame?, name: TextLabel } } = {}
	for _, dir in { -1, 1 } do
		local button = Ui.new("TextButton", {
			Name = if dir < 0 then "PrevStation" else "NextStation",
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(if dir < 0 then 0 else 1, 0.5),
			Position = UDim2.new(if dir < 0 then 0 else 1, dir * -14, 0.5, -10),
			Size = UDim2.fromOffset(120, 150),
			Visible = false,
			Parent = Ui.Root,
		})
		local name = roundText("", 20, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Center, Parent = button })
		arrows[dir] = { button = button, art = nil, name = name }
		button.Activated:Connect(function()
			local target = stepTo(dir)
			if target then
				Remotes.UseStation:FireServer(target)
			end
		end)
	end
	local hereChip = Ui.new("Frame", {
		Name = "HereStation",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -96),
		Size = UDim2.fromOffset(0, 32),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
		Parent = Ui.Root,
	})
	list(hereChip, Enum.FillDirection.Horizontal, 8, Enum.VerticalAlignment.Center)
	local hereDot = Ui.new("Frame", { Size = UDim2.fromOffset(16, 16), BorderSizePixel = 0, LayoutOrder = 1, Parent = hereChip })
	Ui.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = hereDot })
	Ui.new("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2, Parent = hereDot })
	local hereText = roundText("", 26, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 32), LayoutOrder = 2, Parent = hereChip })
	local exitButton = Ui.new("TextButton", {
		Name = "ExitStation",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -14),
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
		Parent = Ui.Root,
	})
	list(exitButton, Enum.FillDirection.Horizontal, 8, Enum.VerticalAlignment.Center)
	Icons.make("close", 26, exitButton, { color = STATION_COLORS.Sauce }).LayoutOrder = 1
	roundText(if keyboard then "EXIT  [SPACE]" else "EXIT", 24, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 40), LayoutOrder = 2, Parent = exitButton })
	exitButton.Activated:Connect(function()
		StationMode.Exit()
	end)
	local navSig = ""
	local function refreshNav()
		local here = StationMode.Current()
		local base = navBase()
		local sig = table.concat({ tostring(here), base, #myStations() }, "|")
		if sig == navSig then
			return
		end
		navSig = sig
		for dir, a in arrows do
			local target = stepTo(dir)
			if a.art then
				a.art:Destroy()
			end
			local art = chevron(a.button, dir, if target then STATION_COLORS[target] or C.Cream else C.Cream)
			art.AnchorPoint = Vector2.new(0.5, 0)
			art.Position = UDim2.new(0.5, 0, 0, 10)
			a.art = art
			a.name.Text = if target then string.upper(stationLabel(target)) .. (if keyboard then (if dir < 0 then "  [Q]" else "  [E]") else "") else ""
		end
		hereDot.BackgroundColor3 = STATION_COLORS[base] or C.Cream
		hereText.Text = string.upper(stationLabel(base))
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not StationMode.Current() then
			return
		end
		local dir = if input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.DPadLeft then -1 elseif input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.DPadRight then 1 else nil
		local target = if dir then stepTo(dir) else nil
		if target then
			Remotes.UseStation:FireServer(target)
		end
	end)

	-- Wiring --------------------------------------------------------------------
	local railStation: string? = nil
	Remotes.QueueUpdate.OnClientEvent:Connect(function(snap: any)
		snapshot = snap
		snapshotAt = os.clock()
		rebuildRail()
		if expanded then
			rebuildBar()
		end
	end)
	player:GetAttributeChangedSignal("Following"):Connect(function()
		if expanded then
			rebuildBar()
		end
	end)
	player:GetAttributeChangedSignal("StoreId"):Connect(function()
		setExpanded(false)
		barSig = ""
		navSig = ""
	end)

	local lastTick = 0
	RunService.Heartbeat:Connect(function()
		local onShift = player:GetAttribute("StoreId") ~= nil
		local here = StationMode.Current()
		if here ~= railStation then
			-- Arriving somewhere new: tickets for that station, bar folded away.
			railStation = here
			setExpanded(false)
			rebuildRail()
		end
		-- Times tick between snapshots.
		if os.clock() - lastTick > 0.2 then
			lastTick = os.clock()
			local since = os.clock() - snapshotAt
			for _, t in timers do
				if t.kind == "age" then
					t.label.Text = Style.clock(t.base + since)
				elseif t.kind == "left" then
					t.label.Text = Style.clock(t.base - since)
				elseif t.kind == "falls" then
					t.label.Text = "FALLS " .. Style.clock(t.base - since)
				end
			end
		end
		local info = if here then Config.StationInfo(here) else nil
		rail.Visible = onShift and os.clock() - snapshotAt < 3 and info ~= nil and info.queue ~= nil
		storesButton.Visible = not onShift and here == nil
		tab.Visible = onShift and not expanded
		staffButton.Visible = onShift and not expanded
		if here and table.find(myStations(), here) then
			lastStation = here
		end
		refreshNav()
		-- Only while you're at a station (the user, 2026-10-24).
		for _, a in arrows do
			a.button.Visible = here ~= nil and not expanded
		end
		hereChip.Visible = here ~= nil and not expanded and not isBusy() -- out of a minigame's way
		exitButton.Visible = here ~= nil and not expanded
		if expanded and not onShift then
			setExpanded(false)
		end
		-- Work strips step aside while the bar is open (new ones live on Root,
		-- older 2D ones on the screen itself).
		for _, holder in { Ui.Root, Ui.Screen } do
			for _, c in holder:GetChildren() do
				if c:IsA("GuiObject") and c.Name == "Dock" then
					c.Visible = not expanded and not c:GetAttribute("Hidden") -- a minigame may hide its own strip
				end
			end
		end
	end)
end

return WorkHud
