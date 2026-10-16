--!strict
-- The HUD for working the store, so players can run it however they like:
--  * Station bar (bottom center, on shift): one button per station your job
--    can use, with how many pizzas / orders are waiting there.
--  * Order queue (right side, on shift): every open order and where each of
--    its pizzas is. Click a waiting pizza to go work it.
--  * "What next?" bar after each step: follow this pizza to its next station,
--    take the next one at the same station, or stop.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Ui = require(script.Parent.Ui)
local T = Ui.Theme

local WorkHud = {}

local player = Players.LocalPlayer

local STAGE_COLOR = {
	Sauce = Color3.fromRGB(200, 70, 55),
	Cheese = Color3.fromRGB(230, 190, 70),
	Toppings = Color3.fromRGB(90, 170, 90),
	Oven = Color3.fromRGB(230, 120, 50),
	Cut = Color3.fromRGB(120, 160, 230),
	Ready = Color3.fromRGB(150, 150, 160),
}
local STAGE_TEXT = { Sauce = "needs sauce", Cheese = "needs cheese", Toppings = "needs toppings", Oven = "in the oven", Cut = "at oven exit", Ready = "boxed" }

local function stationLabel(id: string): string
	for _, s in Config.Stations do
		if s.id == id then
			return s.label
		end
	end
	return id
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

local function formatAge(seconds: number): string
	return string.format("%d:%02d", seconds // 60, math.floor(seconds % 60))
end

function WorkHud.Init(isBusy: () -> boolean)
	local snapshot: any = nil
	local snapshotAt = 0
	local currentStage: string? = nil -- stage of the minigame we're in, for highlighting
	local stepInfo: any = nil
	local stepShownAt = 0

	-- Station bar ------------------------------------------------------------
	local bar = Ui.new("Frame", {
		Name = "StationBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(640, 56),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = Ui.Screen,
	}, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6) }),
	})

	local function rebuildBar()
		for _, c in bar:GetChildren() do
			if c:IsA("TextButton") then
				c:Destroy()
			end
		end
		local waiting = if snapshot then snapshot.waiting else {}
		for _, id in myStations() do
			local n = tonumber(waiting[id]) or 0
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

	-- "What next?" bar ---------------------------------------------------------
	local nextBar = Ui.new("Frame", {
		Name = "WhatNext",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(640, 92),
		BackgroundColor3 = T.Panel,
		BackgroundTransparency = 0.08,
		Visible = false,
		Parent = Ui.Screen,
	}, { Ui.corner(14), Ui.stroke(T.Good, 2), Ui.pad(8) })
	local nextTitle = Ui.label("", { Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 17, Parent = nextBar })
	local nextRow = Ui.new("Frame", { Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1, Parent = nextBar }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }),
	})

	local function hideNext()
		stepInfo = nil
		nextBar.Visible = false
	end

	local function showNext(info: any)
		stepInfo = info
		stepShownAt = os.clock()
		for _, c in nextRow:GetChildren() do
			if c:IsA("TextButton") then
				c:Destroy()
			end
		end
		local here = tostring(info.station)
		nextTitle.Text = "Done at " .. stationLabel(here) .. ". What next?"
		if type(info.next) == "string" and table.find(myStations(), info.next) then
			local follow = Ui.button(string.format("Keep going: #%s to %s", tostring(info.label), stationLabel(info.next)), T.Good, { Size = UDim2.fromOffset(250, 46), MaxText = 16, Parent = nextRow })
			follow.Activated:Connect(function()
				hideNext()
				Remotes.UseStation:FireServer(info.next, info.ticketId)
			end)
		end
		local waiting = if snapshot then tonumber(snapshot.waiting[here]) or 0 else 0
		local againText = if here == "Dough" then "Stretch another" else string.format("Next at %s (%d waiting)", stationLabel(here), waiting)
		local again = Ui.button(againText, T.Accent, { Size = UDim2.fromOffset(220, 46), MaxText = 16, Parent = nextRow })
		again.Activated:Connect(function()
			hideNext()
			Remotes.UseStation:FireServer(here)
		end)
		local stop = Ui.button("Done", T.Card, { Size = UDim2.fromOffset(110, 46), MaxText = 16, Parent = nextRow })
		stop.Activated:Connect(hideNext)
		nextBar.Visible = true
	end

	-- Order queue panel --------------------------------------------------------
	local panel = Ui.new("Frame", {
		Name = "OrderQueue",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 52),
		Size = UDim2.new(0, 290, 0.6, 0),
		BackgroundColor3 = T.Bg,
		BackgroundTransparency = 0.12,
		Visible = false,
		Parent = Ui.Screen,
	}, { Ui.corner(12), Ui.stroke(T.Accent2, 2) })
	local panelTitle = Ui.label("ORDERS", { Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 22), Font = T.Title, TextXAlignment = Enum.TextXAlignment.Left, MaxText = 18, Parent = panel })
	local rackLabel = Ui.label("", { Position = UDim2.fromOffset(10, 28), Size = UDim2.new(1, -20, 0, 16), TextColor3 = T.Muted, TextXAlignment = Enum.TextXAlignment.Left, MaxText = 13, Parent = panel })
	local list = Ui.new("ScrollingFrame", {
		Position = UDim2.fromOffset(6, 48),
		Size = UDim2.new(1, -12, 1, -54),
		BackgroundTransparency = 1,
		ScrollBarThickness = 5,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = panel,
	}, { Ui.new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }) })

	local function rebuildPanel()
		for _, c in list:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		if not snapshot then
			return
		end
		local rack = snapshot.rack
		rackLabel.Text = string.format("Dough racks: S %d  M %d  L %d  (%d/%d)", rack.counts.Small or 0, rack.counts.Medium or 0, rack.counts.Large or 0, rack.used, rack.capacity)
		panelTitle.Text = string.format("ORDERS (%d)", #snapshot.orders)
		local mine = myStations()
		local order = 0
		for _, o in snapshot.orders do
			order += 1
			local where = if o.delivery then "DELIVERY #" .. tostring(o.house) else "CARRYOUT"
			local status = if o.stage == "Rack" then "  - on heat rack" elseif o.stage == "Out" then "  - out for delivery" elseif o.stage == "Pickup" then "  - picking up" else ""
			Ui.label(string.format("#%d  %s  %s%s", o.id, where, formatAge(o.age), status), {
				Size = UDim2.new(1, 0, 0, 20),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = T.Accent2,
				MaxText = 14,
				LayoutOrder = order,
				Parent = list,
			})
			for _, t in o.tickets do
				order += 1
				local stationId = Config.StationForStage(t.stage)
				local claimed = t.claimedBy ~= nil
				local byMe = t.claimedBy == player.UserId
				local canWork = stationId ~= nil and not claimed and table.find(mine, stationId) ~= nil
				local text = string.format("   %s %s - %s%s", string.sub(t.size, 1, 1), t.pizza, STAGE_TEXT[t.stage] or t.stage, if byMe then " (you)" elseif claimed then " (in progress)" else "")
				local b = Ui.button(text, if t.stage == currentStage then Color3.fromRGB(70, 60, 30) else T.Panel, {
					Size = UDim2.new(1, 0, 0, 24),
					TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = STAGE_COLOR[t.stage] or T.Text,
					AutoButtonColor = canWork,
					MaxText = 13,
					LayoutOrder = order,
					Parent = list,
				})
				if canWork then
					b.Activated:Connect(function()
						if not isBusy() then
							hideNext()
							Remotes.UseStation:FireServer(stationId, t.id)
						end
					end)
				end
			end
		end
		if #snapshot.orders == 0 then
			Ui.label("No open orders.", { Size = UDim2.new(1, 0, 0, 22), TextColor3 = T.Muted, MaxText = 14, Parent = list })
		end
	end

	-- Wiring --------------------------------------------------------------------
	Remotes.QueueUpdate.OnClientEvent:Connect(function(snap: any)
		snapshot = snap
		snapshotAt = os.clock()
		rebuildBar()
		rebuildPanel()
	end)
	Remotes.StepDone.OnClientEvent:Connect(function(info: any)
		currentStage = nil
		showNext(info)
	end)
	Remotes.StartMinigame.OnClientEvent:Connect(function(kind: string)
		hideNext()
		currentStage = if kind == "Sauce" or kind == "Cheese" or kind == "Toppings" or kind == "Cut" then kind else nil
	end)
	player:GetAttributeChangedSignal("Job"):Connect(function()
		hideNext()
		rebuildBar()
	end)

	RunService.Heartbeat:Connect(function()
		local onShift = player:GetAttribute("Job") ~= nil
		local fresh = os.clock() - snapshotAt < 3
		local busy = isBusy()
		if not busy and currentStage then
			currentStage = nil
		end
		-- The "what next?" bar times out on its own.
		if stepInfo and os.clock() - stepShownAt > 10 then
			hideNext()
		end
		panel.Visible = onShift and fresh
		nextBar.Visible = stepInfo ~= nil and not busy
		bar.Visible = onShift and not busy and stepInfo == nil
	end)
end

return WorkHud
