--!strict
-- The HUD for working the store, in the store-systems look (Style.luau):
--  * Tickets (top left), by the station you're at (Config.Stations `queue`):
--    during the make process, every order still waiting on pizzas (header goes
--    green, gold, red as it waits; loaded pizzas struck through); at the cut
--    table, every pizza in the ovens by slot (OUT to pull, red as it's about
--    to fall); at the heat rack, deliveries ready to go (click one to take it)
--    and the ones on the road.
--  * Stations tab (bottom left, at your store): collapsed by default. It opens
--    sideways along the bottom into a key per station (gold badge = jobs
--    waiting), then Help (the station's tip), Job Aid, the order-matching
--    switch, Exit and Stores.
--    While it's open the work strip steps aside so nothing covers the pizza.
--  * Follow chip (above the tab) after a step: takes that pizza to its next
--    station.
--  * Staff button (beside the tab): the store's hired staff (Staff menu).
--  * Not at a store: a Stores button where the tab goes (open or join one).

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
local StationPicks = require(script.Parent.StationPicks)
local StationTips = require(script.Parent.StationTips)
local Ui = require(script.Parent.Ui)

local WorkHud = {}

local C = Style.Color
local F = Style.Font
local S = Style.Size

local player = Players.LocalPlayer

local FOLLOW_SECONDS = 12 -- how long the follow chip stays up
local TICKET_W = 138
local MAX_TICKETS = 6
local MAX_ROWS = 6 -- per ticket; the rest fold into "+N more"
local KEY_W = 64 -- utility keys on the open bar
local STATION_ICONS: { [string]: string } = {
	Register = "register",
	Dough = "dough",
	Sauce = "sauce",
	Cheese = "cheese",
	Toppings = "toppings",
	Load = "oven",
	CutTable = "box",
	DeliveryRack = "rack",
	SupplyTruck = "truck",
}

local function stationLabel(id: string): string
	local info = Config.StationInfo(id)
	return if info then info.label else id
end

-- Every station (there are no roles), while you work at a store.
local function myStations(): { string }
	local list = {}
	if player:GetAttribute("StoreId") ~= nil then
		for _, s in Config.Stations do
			table.insert(list, s.id)
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
type Row = { size: string?, text: string, done: boolean? }

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
	local head = Ui.box(headBg, { Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 0, Parent = t })
	Ui.text(string.upper(title), F.LabelBold, S.Small, { TextColor3 = headFg, Position = UDim2.fromOffset(6, 0), Size = UDim2.new(1, -50, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, Parent = head })
	local timeLabel = Ui.text(time, F.Mono, S.Small, { TextColor3 = headFg, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 0), Size = UDim2.new(0, 60, 1, 0), Parent = head })
	for i, r in rows do
		local row = Ui.box(C.Cream, { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, LayoutOrder = i, Parent = t })
		Ui.box(C.Rule, { Size = UDim2.new(1, 0, 0, 1), Parent = row })
		local x = 6
		if r.size then
			local sq = Ui.box(C.Panel, { Position = UDim2.fromOffset(6, 3), Size = UDim2.fromOffset(15, 15), Parent = row })
			Ui.text(string.sub(r.size, 1, 1), F.Mono, S.Tiny, { TextColor3 = C.Cream, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = sq })
			x = 27
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
		if r.done then
			local chk = Ui.box(C.Green, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -5, 0, 3), Size = UDim2.fromOffset(15, 15), Parent = row })
			local ico = Icons.make("check", 11, chk, { color = C.White })
			ico.AnchorPoint = Vector2.new(0.5, 0.5)
			ico.Position = UDim2.fromScale(0.5, 0.5)
		end
	end
	return t, timeLabel
end

function WorkHud.Init(_isBusy: () -> boolean)
	local snapshot: any = nil
	local snapshotAt = 0
	local follow: any = nil -- the last step's pizza and where it goes next
	local followAt = 0
	local expanded = false

	local function waitingAt(id: string): number
		return if snapshot then tonumber(snapshot.waiting[id]) or 0 else 0
	end

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
				-- Identical pizzas share a row ("PEPPERONI x3"), so big orders still fit.
				local grouped, hidden = TicketRows.fit(TicketRows.group(o.items), MAX_ROWS)
				local rows: { Row } = {}
				for _, g in grouped do
					table.insert(rows, { size = g.size, text = TicketRows.label(g), done = TicketRows.done(g) })
				end
				if hidden > 0 then
					table.insert(rows, { text = string.format("+%d more", hidden) })
				end
				local bg, fg = Style.ticketColor(o.age)
				local kind: string = if o.delivery then "Delivery" else "Carryout"
				local title = string.format("#%d %s", o.id, kind)
				local _, timeLabel = ticket(rail, i, title, Style.clock(o.age), bg, fg, rows)
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

	-- The Stations tab with the Staff button beside it.
	local dock = Ui.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -10),
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = Ui.Root,
	})
	list(dock, Enum.FillDirection.Horizontal, 6)
	local tab = Ui.flatButton("", "key", {
		Name = "StationsTab",
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
		LayoutOrder = 1,
		Parent = dock,
	})
	list(tab, Enum.FillDirection.Horizontal, 8, Enum.VerticalAlignment.Center)
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = tab })
	Icons.make("grid", 14, tab).LayoutOrder = 1
	Ui.text("STATIONS", F.LabelBold, S.Label, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 40), LayoutOrder = 2, Parent = tab })
	local tabBadge = Ui.badge("0", { LayoutOrder = 3, Visible = false, Parent = tab })
	Icons.make("chevron", 12, tab, { dir = "right" }).LayoutOrder = 4

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

	local followChip = Ui.flatButton("", "key", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -56),
		Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
		Parent = Ui.Root,
	})
	Ui.edge(followChip, "left", 3, C.Gold)
	list(followChip, Enum.FillDirection.Horizontal, 8, Enum.VerticalAlignment.Center)
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = followChip })
	Icons.make("chevron", 10, followChip, { dir = "right", color = C.Gold }).LayoutOrder = 1
	local followText = Ui.text("", F.LabelBold, S.Body, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 34), LayoutOrder = 2, Parent = followChip })
	followChip.Activated:Connect(function()
		local f = follow
		if f then
			follow = nil
			Remotes.UseStation:FireServer(f.next, f.pieId)
		end
	end)

	local bar = Ui.box(C.Panel, {
		Name = "StationsBar",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -10),
		Size = UDim2.new(1, -20, 0, 54),
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
		local stations = myStations()
		local sig = table.concat({ tostring(here), tostring(player:GetAttribute("StoreId")), Loading.mode, tostring(StationPicks.HasAid()) }, "|")
		for _, id in stations do
			sig ..= "|" .. waitingAt(id)
		end
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
		local tipFor = here
		if tipFor and StationTips.Has(tipFor) then
			table.insert(utils, { text = "Help", icon = "help", fn = function()
				setExpanded(false)
				StationTips.Show(tipFor, true)
			end })
		end
		if here and StationPicks.HasAid() then
			table.insert(utils, { text = "Job Aid", icon = "aid", fn = function()
				setExpanded(false)
				StationPicks.ToggleAid()
			end })
		end
		if here == "Toppings" or here == "Load" then
			-- Tentative setting: who decides which order a loaded pizza is for.
			table.insert(utils, { text = if Loading.mode == "Pick" then "Pick order" else "Auto-match", icon = "check", fn = function()
				Loading.SetMode(if Loading.mode == "Pick" then "Auto" else "Pick")
				rebuildBar()
			end, opts = { iconOpts = { color = if Loading.mode == "Pick" then C.Gold else C.Green } } })
		end
		if here then
			table.insert(utils, { text = "Exit", icon = "close", fn = function()
				setExpanded(false)
				StationMode.Exit()
			end, opts = { dim = true, iconOpts = { color = C.CreamDim } } })
		end
		table.insert(utils, { text = "Stores", icon = "person", fn = function()
			setExpanded(false)
			Remotes.RequestStores:FireServer()
		end, opts = { dim = true, iconOpts = { color = C.CreamDim } } })
		local fixed = #utils * KEY_W + 52
		local n = math.max(#stations, 1)
		local order = 0
		for _, id in stations do
			order += 1
			key(stationLabel(id), STATION_ICONS[id], UDim2.new(1 / n, -fixed / n, 1, 0), order, function()
				setExpanded(false)
				Remotes.UseStation:FireServer(id)
			end, { on = id == here, badge = waitingAt(id) })
		end
		for _, u in utils do
			order += 1
			key(u.text, u.icon, UDim2.new(0, KEY_W, 1, 0), order, u.fn, u.opts)
		end
		order += 1
		local collapse = key("", "chevron", UDim2.new(0, 52, 1, 0), order, function()
			setExpanded(false)
		end, { iconOpts = { dir = "left" } })
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

	local function refreshTab()
		local total = 0
		for _, id in myStations() do
			total += waitingAt(id)
		end
		tabBadge.Text = tostring(total)
		tabBadge.Visible = total > 0
	end

	-- Wiring --------------------------------------------------------------------
	local railStation: string? = nil
	Remotes.QueueUpdate.OnClientEvent:Connect(function(snap: any)
		snapshot = snap
		snapshotAt = os.clock()
		rebuildRail()
		refreshTab()
		if expanded then
			rebuildBar()
		end
	end)
	Remotes.StepDone.OnClientEvent:Connect(function(info: any)
		follow = if type(info) == "table" and type(info.next) == "string" then info else nil
		followAt = os.clock()
	end)
	player:GetAttributeChangedSignal("StoreId"):Connect(function()
		follow = nil
		setExpanded(false)
		barSig = ""
		refreshTab()
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
		-- Follow chip: only when the pizza's next station is one we can work.
		local f = follow
		if f and os.clock() - followAt > FOLLOW_SECONDS then
			follow = nil
			f = nil
		end
		local showFollow = f ~= nil and onShift and not expanded and f.next ~= here and table.find(myStations(), f.next) ~= nil
		followChip.Visible = showFollow
		if showFollow and f then
			followText.Text = string.upper(string.format("Follow to %s", stationLabel(f.next)))
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
		if expanded and not onShift then
			setExpanded(false)
		end
		-- Work strips step aside while the bar is open (new ones live on Root,
		-- older 2D ones on the screen itself).
		for _, holder in { Ui.Root, Ui.Screen } do
			for _, c in holder:GetChildren() do
				if c:IsA("GuiObject") and c.Name == "Dock" then
					c.Visible = not expanded
				end
			end
		end
	end)
end

return WorkHud
