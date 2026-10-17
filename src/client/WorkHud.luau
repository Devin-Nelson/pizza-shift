--!strict
-- The HUD for working the store, so players can run it however they like:
--  * Station bar (bottom center, on shift but not at a station): one button
--    per station your job can use, with how much is waiting there.
--  * Station rail (left side, while at a station): jump straight to any other
--    station, follow the pizza you just finished to its next step, read the
--    station's job aid up close, switch how loaded pizzas are matched to
--    orders (at the toppings and loading spots), or exit.
--  * Queue panel (right side), depending on the station (Config.Stations
--    `queue`): the make-line queue (orders still waiting on pizzas to go in the
--    oven, loaded ones ticked), the ovens (every pizza baking, with countdowns,
--    and the ones at the exit about to fall), or the heat rack (orders ready to
--    go out - click one to take it - and the ones on the road).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Loading = require(script.Parent.Loading)
local StationMode = require(script.Parent.StationMode)
local StationPicks = require(script.Parent.StationPicks)
local Ui = require(script.Parent.Ui)
local T = Ui.Theme

local WorkHud = {}

local player = Players.LocalPlayer

local FOLLOW_SECONDS = 12 -- how long the "follow this pizza" button stays up
local LOADED = Color3.fromRGB(90, 210, 110)

local function stationLabel(id: string): string
	local info = Config.StationInfo(id)
	return if info then info.label else id
end

local function myStations(): { string }
	local job = player:GetAttribute("Job")
	local def = if type(job) == "string" then Config.Jobs[job] else nil
	local list = {}
	if def then
		for _, s in Config.Stations do
			if table.find(def.stations, s.id) then
				table.insert(list, s.id)
			end
		end
	end
	return list
end

local function clock(seconds: number): string
	seconds = math.max(0, seconds)
	return string.format("%d:%02d", seconds // 60, math.floor(seconds % 60))
end

-- Shrinks `frame` (designed at `size`) to fit the screen, leaving `margin` px.
local function fitToScreen(frame: GuiObject, size: Vector2, margin: Vector2)
	local scale = Ui.new("UIScale", { Parent = frame })
	local function fit()
		local view = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.min(1, (view.X - margin.X) / size.X, (view.Y - margin.Y) / size.Y)
	end
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
end

function WorkHud.Init(isBusy: () -> boolean)
	local snapshot: any = nil
	local snapshotAt = 0
	local follow: any = nil -- the last step's pizza and where it goes next
	local followAt = 0

	local function waitingAt(id: string): number
		return if snapshot then tonumber(snapshot.waiting[id]) or 0 else 0
	end

	-- Station bar (off-station) -------------------------------------------------
	local bar = Ui.new("Frame", {
		Name = "StationBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(820, 56),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = Ui.Screen,
	}, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6) }),
	})
	fitToScreen(bar, Vector2.new(820, 56), Vector2.new(24, 0))

	local barSig = ""
	local function rebuildBar()
		local sig = tostring(player:GetAttribute("Job"))
		for _, id in myStations() do
			sig ..= "|" .. waitingAt(id)
		end
		if sig == barSig then
			return
		end
		barSig = sig
		for _, c in bar:GetChildren() do
			if c:IsA("TextButton") then
				c:Destroy()
			end
		end
		for _, id in myStations() do
			local n = waitingAt(id)
			local b = Ui.button(if n > 0 then string.format("%s (%d)", stationLabel(id), n) else stationLabel(id), if n > 0 then T.Accent else T.Card, {
				Size = UDim2.fromOffset(98, 52),
				MaxText = 16,
				Parent = bar,
			})
			b.Activated:Connect(function()
				Remotes.UseStation:FireServer(id)
			end)
		end
	end

	-- Station rail (at a station) -----------------------------------------------
	local RAIL_W = 168
	local rail = Ui.new("Frame", {
		Name = "StationRail",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.45, 0),
		Size = UDim2.fromOffset(RAIL_W, 470),
		BackgroundColor3 = T.Bg,
		BackgroundTransparency = 0.15,
		Visible = false,
		Parent = Ui.Screen,
	}, {
		Ui.corner(12),
		Ui.stroke(T.Accent, 2),
		Ui.pad(8),
		Ui.new("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	fitToScreen(rail, Vector2.new(RAIL_W, 470), Vector2.new(0, 200))

	local railSig = ""
	local function rebuildRail()
		local here = StationMode.Current()
		local f0 = follow
		-- Only rebuild when something shown changes, so a click isn't lost mid-press.
		local sig = table.concat({ tostring(here), if f0 then tostring(f0.pieId) else "", tostring(player:GetAttribute("Job")), Loading.mode }, "|")
		for _, id in myStations() do
			sig ..= "|" .. waitingAt(id)
		end
		if sig == railSig then
			return
		end
		railSig = sig
		for _, c in rail:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local order = 0
		local function add(inst: GuiObject)
			order += 1
			inst.LayoutOrder = order
			inst.Parent = rail
		end
		local exit = Ui.button("Exit Station", Color3.fromRGB(90, 70, 70), { Size = UDim2.new(1, 0, 0, 38), MaxText = 17 })
		exit.Activated:Connect(StationMode.Exit)
		add(exit)
		local f = follow
		if f and os.clock() - followAt < FOLLOW_SECONDS and table.find(myStations(), f.next) and f.next ~= here then
			local b = Ui.button(string.format("Follow this %s to %s", tostring(f.label), stationLabel(f.next)), T.Good, { Size = UDim2.new(1, 0, 0, 46), MaxText = 15 })
			b.Activated:Connect(function()
				follow = nil
				Remotes.UseStation:FireServer(f.next, f.pieId)
			end)
			add(b)
		end
		if StationPicks.HasAid() then
			local aid = Ui.button("Job Aid", Color3.fromRGB(70, 110, 160), { Size = UDim2.new(1, 0, 0, 34), MaxText = 16 })
			aid.Activated:Connect(StationPicks.ToggleAid)
			add(aid)
		end
		if here == "Toppings" or here == "Load" then
			-- Tentative setting: who decides which order a loaded pizza is for.
			local b = Ui.button(if Loading.mode == "Pick" then "Loading: I pick the order" else "Loading: auto-match", T.Card, { Size = UDim2.new(1, 0, 0, 40), MaxText = 14 })
			b.Activated:Connect(function()
				Loading.SetMode(if Loading.mode == "Pick" then "Auto" else "Pick")
				rebuildRail()
			end)
			add(b)
		end
		add(Ui.label("STATIONS", { Size = UDim2.new(1, 0, 0, 18), TextColor3 = T.Muted, TextXAlignment = Enum.TextXAlignment.Left, MaxText = 14 }))
		for _, id in myStations() do
			local n = waitingAt(id)
			local text = if n > 0 then string.format("%s (%d)", stationLabel(id), n) else stationLabel(id)
			local isHere = id == here
			local b = Ui.button(if isHere then "> " .. text else text, if isHere then T.Accent2 elseif n > 0 then T.Accent else T.Card, {
				Size = UDim2.new(1, 0, 0, 36),
				TextColor3 = if isHere then Color3.fromRGB(30, 30, 30) else T.Text,
				MaxText = 16,
			})
			b.Activated:Connect(function()
				Remotes.UseStation:FireServer(id)
			end)
			add(b)
		end
	end

	-- Queue panel ---------------------------------------------------------------
	local panel = Ui.new("Frame", {
		Name = "QueuePanel",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 52),
		Size = UDim2.new(0, 300, 0.6, 0),
		BackgroundColor3 = T.Bg,
		BackgroundTransparency = 0.12,
		Visible = false,
		Parent = Ui.Screen,
	}, { Ui.corner(12), Ui.stroke(T.Accent2, 2) })
	local panelTitle = Ui.label("ORDERS", { Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 22), Font = T.Title, TextXAlignment = Enum.TextXAlignment.Left, MaxText = 18, Parent = panel })
	local subLabel = Ui.label("", { Position = UDim2.fromOffset(10, 28), Size = UDim2.new(1, -20, 0, 16), TextColor3 = T.Muted, TextXAlignment = Enum.TextXAlignment.Left, MaxText = 13, Parent = panel })
	local list = Ui.new("ScrollingFrame", {
		Position = UDim2.fromOffset(6, 48),
		Size = UDim2.new(1, -12, 1, -54),
		BackgroundTransparency = 1,
		ScrollBarThickness = 5,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = panel,
	}, { Ui.new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }) })

	-- Oven rows whose countdowns tick between snapshots.
	local timers: { { label: TextLabel, text: string, left: number, out: boolean, fallsIn: number? } } = {}

	local function line(text: string, color: Color3?, order: number, height: number?): TextLabel
		return Ui.label(text, {
			Size = UDim2.new(1, 0, 0, height or 22),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = color or T.Text,
			RichText = true,
			MaxText = 14,
			LayoutOrder = order,
			Parent = list,
		})
	end

	local function rebuildPanel()
		for _, c in list:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		table.clear(timers)
		if not snapshot then
			return
		end
		local here = StationMode.Current()
		local info = if here then Config.StationInfo(here) else nil
		local mode = if info then info.queue else nil
		local order = 0
		local function nextOrder(): number
			order += 1
			return order
		end
		if mode == "make" then
			local rack = snapshot.rack
			panelTitle.Text = string.format("MAKE-LINE (%d)", #snapshot.orders)
			subLabel.Text = string.format("Dough S %d  M %d  L %d (%d/%d)  |  Ready rack %d/%d", rack.counts.Small or 0, rack.counts.Medium or 0, rack.counts.Large or 0, rack.used, rack.capacity, tonumber(snapshot.ready) or 0, tonumber(snapshot.readyCapacity) or 0)
			for _, o in snapshot.orders do
				local where = if o.delivery then "DELIVERY #" .. tostring(o.house) else "CARRYOUT"
				line(string.format("#%d  %s  %s", o.id, where, clock(o.age)), T.Accent2, nextOrder())
				for _, item in o.items do
					if item.loaded then
						line(string.format("   \u{2713} %s %s", item.size, item.pizza), LOADED, nextOrder())
					else
						line(string.format("      %s %s", item.size, item.pizza), T.Text, nextOrder())
					end
				end
			end
			if #snapshot.orders == 0 then
				line("Nothing waiting on the make-line.", T.Muted, nextOrder())
			end
		elseif mode == "oven" then
			panelTitle.Text = string.format("OVENS (%d)", #snapshot.oven)
			subLabel.Text = "Pull pizzas as they come out of the oven"
			for _, p in snapshot.oven do
				local text = string.format("Slot %d  %s  %s", p.slot, string.sub(p.size, 1, 1), p.label)
				local row = line(text, if p.fallsIn then T.Accent elseif p.out then T.Accent2 else T.Text, nextOrder())
				table.insert(timers, { label = row, text = text, left = p.left, out = p.out == true, fallsIn = p.fallsIn })
			end
			if #snapshot.oven == 0 then
				line("The ovens are empty.", T.Muted, nextOrder())
			end
		elseif mode == "delivery" then
			local ready = 0
			for _, o in snapshot.delivery do
				if o.stage == "Rack" then
					ready += 1
				end
			end
			panelTitle.Text = string.format("HEAT RACK (%d)", ready)
			subLabel.Text = "Click an order to take it out"
			for _, o in snapshot.delivery do
				if o.stage == "Rack" then
					local b = Ui.button(string.format("#%d  House #%s  %d pizza%s  ready %s", o.id, tostring(o.house), o.count, if o.count == 1 then "" else "s", clock(o.age)), T.Card, {
						Size = UDim2.new(1, 0, 0, 30),
						TextXAlignment = Enum.TextXAlignment.Left,
						MaxText = 14,
						LayoutOrder = nextOrder(),
						Parent = list,
					})
					b.Activated:Connect(function()
						Remotes.UseStation:FireServer("DeliveryRack", o.id)
					end)
				end
			end
			for _, o in snapshot.delivery do
				if o.stage == "Out" then
					line(string.format("#%d  House #%s  out with %s", o.id, tostring(o.house), tostring(o.driver or "?")), T.Muted, nextOrder())
				end
			end
			if #snapshot.delivery == 0 then
				line("No deliveries yet.", T.Muted, nextOrder())
			end
		end
	end

	-- Wiring --------------------------------------------------------------------
	local panelStation: string? = nil
	Remotes.QueueUpdate.OnClientEvent:Connect(function(snap: any)
		snapshot = snap
		snapshotAt = os.clock()
		rebuildBar()
		rebuildRail()
		rebuildPanel()
	end)
	Remotes.StepDone.OnClientEvent:Connect(function(info: any)
		follow = if type(info) == "table" and type(info.next) == "string" then info else nil
		followAt = os.clock()
		rebuildRail()
	end)
	player:GetAttributeChangedSignal("Job"):Connect(function()
		follow = nil
		rebuildBar()
		rebuildRail()
	end)

	local lastTick = 0
	RunService.Heartbeat:Connect(function()
		local onShift = player:GetAttribute("Job") ~= nil
		local fresh = os.clock() - snapshotAt < 3
		local here = StationMode.Current()
		if here ~= panelStation then
			panelStation = here
			rebuildRail()
			rebuildPanel()
		end
		-- The follow button times out on its own.
		if follow and os.clock() - followAt > FOLLOW_SECONDS then
			follow = nil
			rebuildRail()
		end
		-- Oven countdowns tick between snapshots.
		if os.clock() - lastTick > 0.2 then
			lastTick = os.clock()
			local since = os.clock() - snapshotAt
			for _, t in timers do
				if t.fallsIn then
					t.label.Text = string.format("%s  <b>AT THE END - falls in %s</b>", t.text, clock(t.fallsIn - since))
				elseif t.out then
					t.label.Text = string.format("%s  <b>OUT - pull it</b>", t.text)
				else
					t.label.Text = string.format("%s  out in %s", t.text, clock(t.left - since))
				end
			end
		end
		local info = if here then Config.StationInfo(here) else nil
		panel.Visible = onShift and fresh and info ~= nil and info.queue ~= nil
		rail.Visible = onShift and here ~= nil
		bar.Visible = onShift and here == nil and not isBusy()
	end)
end

return WorkHud
