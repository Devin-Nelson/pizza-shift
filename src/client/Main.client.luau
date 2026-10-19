--!strict
-- Client entry point: HUD, menus, minigame and station wiring, delivery waypoint.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Config = require(ReplicatedStorage.Shared.Config)
local GameClock = require(ReplicatedStorage.Shared.GameClock)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Style = require(ReplicatedStorage.Shared.Style)
local Icons = require(ReplicatedStorage.Shared.Icons)
local Ui = require(script.Parent.Ui)
local Minigames = require(script.Parent.Minigames)
local Driving = require(script.Parent.Driving)
local Loading = require(script.Parent.Loading)
local Prompts = require(script.Parent.Prompts)
local StationMode = require(script.Parent.StationMode)
local StationPicks = require(script.Parent.StationPicks)
local WorkHud = require(script.Parent.WorkHud)

local player = Players.LocalPlayer

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

---------------------------------------------------------------------------
-- HUD: one slim pill, top right - day, time, open dot | coins, level (XP
-- progress along its bottom edge). Stores and the Stations tab are WorkHud's.
---------------------------------------------------------------------------
local C = Style.Color
-- The wrapper is sized from its contents by hand: its XP line spans the full
-- width, and auto-sizing it would feed back into itself.
local pillWrap = Ui.box(C.Panel, {
	Name = "StatusPill",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 10),
	Size = UDim2.fromOffset(200, 28),
	Parent = Ui.Root,
})
Ui.edge(pillWrap, "left", 3, C.Red)
local pill = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X, Parent = pillWrap })
Ui.fitWidth(pillWrap, pill)
Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = pill })
Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 10), Parent = pill })
local function pillText(font: Font, size: number, color: Color3, order: number): TextLabel
	return Ui.text("", font, size, { TextColor3 = color, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 28), LayoutOrder = order, Parent = pill })
end
local dayLabel = pillText(Style.Font.Label, Style.Size.Small, C.CreamDim, 1)
local timeLabel = pillText(Style.Font.Mono, Style.Size.Label, C.Cream, 2)
local openDot = Ui.box(C.Green, { Size = UDim2.fromOffset(8, 8), LayoutOrder = 3, Parent = pill }, { Ui.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
Ui.box(C.Line, { Size = UDim2.fromOffset(1, 16), LayoutOrder = 4, Parent = pill })
Icons.make("coin", 14, pill).LayoutOrder = 5
local coinsLabel = pillText(Style.Font.Mono, Style.Size.Label, C.Cream, 6)
local levelLabel = pillText(Style.Font.LabelBold, Style.Size.Small, C.CreamDim, 7)
-- XP progress: a 2 px line along the pill's bottom edge.
local xpTrack = Ui.box(C.Line, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 2), Parent = pillWrap })
local xpFill = Ui.box(C.Gold, { Size = UDim2.fromScale(0, 1), Parent = xpTrack })

-- Delivery readout (top centre while a delivery is out): house, distance, time left.
local deliveryBar = Ui.box(C.Panel, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 10),
	Size = UDim2.fromOffset(300, 30),
	Visible = false,
	Parent = Ui.Root,
})
local deliveryEdge = Ui.edge(deliveryBar, "left", 4, C.Green)
local deliveryLabel = Ui.text("", Style.Font.LabelBold, Style.Size.Label, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -20, 1, 0), Parent = deliveryBar })

local clockSince, clockBase = os.clock(), GameClock.weekHour()
ReplicatedStorage:GetAttributeChangedSignal("WeekHour"):Connect(function()
	clockSince, clockBase = os.clock(), GameClock.weekHour()
end)
RunService.RenderStepped:Connect(function()
	-- Interpolate between server updates so the minutes tick smoothly.
	local weekHour = (clockBase + (os.clock() - clockSince) / Config.Day.RealSecondsPerHour) % 168
	local day, hour = GameClock.split(weekHour)
	dayLabel.Text = string.sub(GameClock.dayName(day), 1, 3):upper()
	timeLabel.Text = GameClock.format(hour)
	openDot.BackgroundColor3 = if GameClock.isOpen(weekHour) then C.Green else C.Red
end)

local function refreshHud()
	local stats = player:FindFirstChild("leaderstats")
	local coins = stats and stats:FindFirstChild("Coins") :: IntValue?
	local n = if coins then coins.Value else 0
	-- 1,240 with thousands separators
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	coinsLabel.Text = formatted
	local xp = tonumber(player:GetAttribute("XP")) or 0
	local level = Config.LevelFromXP(xp)
	local lo, hi = Config.XPForLevel(level), Config.XPForLevel(level + 1)
	levelLabel.Text = string.format("LV %d", level)
	xpFill.Size = UDim2.fromScale(math.clamp((xp - lo) / math.max(hi - lo, 1), 0, 1), 1)
end

task.spawn(function()
	local stats = player:WaitForChild("leaderstats", 30)
	if stats then
		for _, v in stats:GetChildren() do
			if v:IsA("IntValue") then
				v.Changed:Connect(refreshHud)
			end
		end
	end
	refreshHud()
end)
player:GetAttributeChangedSignal("XP"):Connect(refreshHud)
refreshHud()

Remotes.Notify.OnClientEvent:Connect(function(text: string, color: Color3?, payInfo: any?)
	-- Pay results arrive as a slip: grade, what was done, coins, XP.
	if type(payInfo) == "table" and type(payInfo.grade) == "string" and type(payInfo.what) == "string" then
		local q = tonumber(payInfo.quality) or 1
		local gradeColor = if q >= 0.7 then C.Green elseif q >= 0.45 then C.Gold else C.Red
		Ui.payToast(payInfo.grade, payInfo.what, tonumber(payInfo.coins) or 0, tonumber(payInfo.xp) or 0, gradeColor)
		return
	end
	Ui.toast(text, color)
end)

---------------------------------------------------------------------------
-- Prompt filtering: only your own store's stations.
---------------------------------------------------------------------------
local delivering = false

local function applyPrompt(pp: ProximityPrompt)
	local parent = pp.Parent
	if not parent then
		return
	end
	-- Drawn by Prompts in the store-systems look.
	pp.Style = Enum.ProximityPromptStyle.Custom
	local station = parent:GetAttribute("Station")
	if type(station) == "string" and Config.StationInfo(station) then
		-- Not at a store yet: show every store's, so players find them (the server
		-- points them to the Stores menu).
		local mine = player:GetAttribute("StoreId")
		local store = parent:FindFirstAncestorWhichIsA("Model")
		pp.Enabled = mine == nil or (store ~= nil and store:GetAttribute("StoreId") == mine)
	elseif parent:GetAttribute("HouseId") ~= nil then
		pp.Enabled = delivering
	elseif pp:GetAttribute("CarOwner") ~= nil then
		-- Delivery car: only its owner sees the Drive prompt.
		pp.Enabled = pp:GetAttribute("CarOwner") == player.UserId
	end
end

local function applyAll()
	for _, d in workspace:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			applyPrompt(d)
		end
	end
end
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("ProximityPrompt") then
		task.defer(applyPrompt, d)
	end
end)
player:GetAttributeChangedSignal("StoreId"):Connect(applyAll)
task.defer(applyAll)

---------------------------------------------------------------------------
-- Minigames
---------------------------------------------------------------------------
local currentToken: string? = nil

Remotes.StartMinigame.OnClientEvent:Connect(function(kind: string, token: string, data: any)
	currentToken = token
	Minigames.Start(kind, data, function(payload)
		if currentToken == token then
			currentToken = nil
			Remotes.MinigameResult:FireServer(token, payload)
		end
	end, function()
		if currentToken == token then
			currentToken = nil
			if StationMode.Current() then
				StationMode.Exit() -- X on a station job steps away from the station
			else
				Remotes.CancelMinigame:FireServer(token)
			end
		end
	end)
end)

Remotes.CancelMinigame.OnClientEvent:Connect(function(token: string)
	if currentToken == token then
		currentToken = nil
		Minigames.Close()
	end
end)

---------------------------------------------------------------------------
-- Store picker: every lot in the server - open your own store on a free one,
-- join one with room, or leave yours.
---------------------------------------------------------------------------
local menuOpen: Frame? = nil

local function closeMenu()
	if menuOpen then
		menuOpen:Destroy()
		menuOpen = nil
	end
end

Remotes.OpenStorePicker.OnClientEvent:Connect(function(lots: { any }, focus: number?)
	closeMenu()
	local member = false
	for _, lot in lots do
		member = member or lot.mine
	end
	local root, body, close = Ui.panel("Stores", 540, 72 + #lots * 68 + (if member then 46 else 0))
	menuOpen = root
	close.Activated:Connect(closeMenu)
	Ui.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = body })
	for i, lot in lots do
		local row = Ui.box(C.Tile, { Size = UDim2.new(1, 0, 0, 62), LayoutOrder = i, Parent = body })
		Ui.edge(row, "left", 4, if lot.mine then C.Green elseif lot.id == focus then C.Gold else C.Line)
		local title, blurb
		if lot.owner == nil then
			title, blurb = string.format("Lot #%d", lot.id), "Free lot - open your own store here."
		else
			title = if lot.owned then "Your store" else string.format("%s's store", tostring(lot.owner))
			blurb = string.format("Lot #%d - %d/%d working", lot.id, lot.count, lot.max)
		end
		Ui.text(string.upper(title), Style.Font.Heading, Style.Size.Big, { Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -150, 0, 22), TextTruncate = Enum.TextTruncate.AtEnd, Parent = row })
		Ui.text(blurb, Style.Font.Body, Style.Size.Small, { TextColor3 = C.CreamDim, Position = UDim2.fromOffset(16, 34), Size = UDim2.new(1, -150, 0, 18), Parent = row })
		local at = { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(112, 40), Parent = row }
		if lot.mine then
			local chip = Ui.chip("You're here", C.Green, C.White, { AnchorPoint = at.AnchorPoint, Position = at.Position, Size = UDim2.fromOffset(0, 30), Parent = row })
			chip.TextSize = Style.Size.Body
		elseif lot.owner ~= nil and lot.count >= lot.max then
			Ui.flatButton("Full", "key", at)
		else
			local b = Ui.flatButton(if lot.owner == nil then "Open store" else "Join", "primary", at)
			b.Activated:Connect(function()
				Remotes.ChooseStore:FireServer(lot.id)
				closeMenu()
			end)
		end
	end
	if member then
		local leave = Ui.flatButton("Leave store", "ghost", { Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 99, Parent = body })
		leave.Activated:Connect(function()
			Remotes.ChooseStore:FireServer(nil)
			closeMenu()
		end)
	end
end)

---------------------------------------------------------------------------
-- Staff menu: your store's team members (NPCs). The owner hires them, sets
-- each one's station and schedules their shifts (within their availability);
-- co-workers can look. Managers come from the staff roll (not live yet).
---------------------------------------------------------------------------
local SHIFT_SHORT = { Lunch = "LUNCH", Dinner = "DINNER", ["Late Night"] = "LATE" }

Remotes.OpenStaffMenu.OnClientEvent:Connect(function(info: any)
	closeMenu()
	local root, body, close = Ui.panel(if info.canEdit then "Your staff" else string.format("%s's staff", tostring(info.owner)), 640, 600)
	menuOpen = root
	close.Activated:Connect(closeMenu)
	local scroll = Ui.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = C.CreamDim,
		Parent = body,
	})
	Ui.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	local function card(height: number, edge: Color3): Frame
		local r = Ui.box(C.Tile, { Size = UDim2.new(1, -8, 0, height), LayoutOrder = nextOrder(), Parent = scroll })
		Ui.edge(r, "left", 4, edge)
		return r
	end
	local function line(parent: Frame, text: string, font: Font, size: number, y: number, color: Color3?)
		Ui.text(text, font, size, { TextColor3 = color or C.Cream, Position = UDim2.fromOffset(16, y), Size = UDim2.new(1, -240, 0, size + 4), TextTruncate = Enum.TextTruncate.AtEnd, Parent = parent })
	end

	-- Who's on each shift (the one on now in green).
	local head = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 26), LayoutOrder = nextOrder(), Parent = scroll })
	Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = head })
	Ui.caption("On shift", { Size = UDim2.fromOffset(70, 16), LayoutOrder = 0, Parent = head })
	for i, sh in info.shifts do
		local chip = Ui.chip(string.format("%s %d/%d", sh.name, sh.count, sh.max), if sh.name == info.now then C.Green else C.Panel, C.Cream, { Size = UDim2.fromOffset(0, 24), LayoutOrder = i, Parent = head })
		chip.TextSize = Style.Size.Small
	end
	Ui.caption(string.format("Crew %d/%d", info.roster.count, info.roster.max), { LayoutOrder = nextOrder(), Parent = scroll })
	if #info.staff == 0 then
		Ui.text(if info.canEdit then "No staff yet - hire someone below." else "No staff yet.", Style.Font.Body, Style.Size.Body, { TextColor3 = C.CreamDim, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = nextOrder(), Parent = scroll })
	end

	for _, m in info.staff do
		local r = card(100, if m.open then C.Gold else C.Line)
		line(r, string.upper(m.name) .. (if m.open then "  -  OPEN AVAILABILITY" else ""), Style.Font.Heading, Style.Size.Big, 6)
		if not m.works then
			line(r, m.display .. " - what managers do is coming soon", Style.Font.Body, Style.Size.Small, 32, C.CreamDim)
			continue
		end
		-- Every station stat, three letters each; the one they work in brackets.
		local stats, statName = {}, ""
		for i, st in m.stats do
			local tag = string.format("%s %d", string.upper(string.sub(st.name, 1, 3)), st.level)
			if info.stations[i].id == m.station then
				tag, statName = "[" .. tag .. "]", st.name
			end
			table.insert(stats, tag)
		end
		line(r, string.format("%s level %d (%d/%d XP)  -  Reliability %d/%d", statName, m.level, m.xp, m.xpNext, m.reliability, info.reliabilityMax), Style.Font.Body, Style.Size.Small, 32, C.CreamDim)
		Ui.text(table.concat(stats, "  "), Style.Font.Mono, Style.Size.Small, { Position = UDim2.fromOffset(16, 76), Size = UDim2.new(1, -32, 0, 18), Parent = r })

		-- Right: station (click for the next one), then the shift keys.
		local stationAt = { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8), Size = UDim2.fromOffset(204, 32), Parent = r }
		if info.canEdit then
			local b = Ui.flatButton(tostring(m.stationLabel) .. "  >", "key", stationAt)
			b.Activated:Connect(function()
				local at = 1
				for j, s in info.stations do
					if s.id == m.station then
						at = j % #info.stations + 1
					end
				end
				Remotes.AssignStaff:FireServer(m.id, info.stations[at].id)
			end)
		else
			Ui.chip(tostring(m.stationLabel), C.Panel, C.Cream, stationAt)
		end
		local keys = Ui.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 44), Size = UDim2.fromOffset(204, 28), Parent = r })
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = keys })
		for i, sh in info.shifts do
			local shift = sh.name
			local can, on = m.avail[shift] == true, m.shifts[shift] == true
			local k = Ui.flatButton(if can then SHIFT_SHORT[shift] or shift else "-", "key", { Size = UDim2.fromOffset(65, 28), TextSize = Style.Size.Small, LayoutOrder = i, Parent = keys })
			if on then
				Ui.setButtonColor(k, C.Green)
			elseif not can then
				k.TextColor3 = C.CreamDim
				k.AutoButtonColor = false
			end
			if info.canEdit and can then
				k.Activated:Connect(function()
					Remotes.ScheduleStaff:FireServer(m.id, shift, not on)
				end)
			end
		end
	end

	Ui.caption("Hire", { LayoutOrder = nextOrder(), Parent = scroll })
	for _, k in info.hire do
		local r = card(54, C.Line)
		line(r, string.upper(k.display), Style.Font.Heading, Style.Size.Big, 6)
		line(r, "Random stats, reliability and availability", Style.Font.Body, Style.Size.Small, 30, C.CreamDim)
		local at = { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(204, 36), Parent = r }
		if info.roster.count >= info.roster.max then
			Ui.flatButton("Roster full", "key", at)
		elseif info.canEdit then
			local b = Ui.flatButton(string.format("Hire - %d", k.cost), if info.coins >= k.cost then "primary" else "key", at)
			b.Activated:Connect(function()
				Remotes.HireStaff:FireServer(k.kind)
			end)
		end
	end

	Ui.caption("Managers", { LayoutOrder = nextOrder(), Parent = scroll })
	local r = card(54, C.Red)
	line(r, "STAFF ROLL", Style.Font.Heading, Style.Size.Big, 6)
	line(r, "Roll for a " .. table.concat(info.roll.kinds, " or "), Style.Font.Body, Style.Size.Small, 30, C.CreamDim)
	Ui.flatButton(if info.roll.enabled then string.format("Roll - %d", info.roll.cost) else "Coming soon", "key", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(204, 36), Parent = r })
end)

---------------------------------------------------------------------------
-- Delivery waypoint
---------------------------------------------------------------------------
local waypoint: { beam: Beam, a0: Attachment, a1: Attachment, conn: RBXScriptConnection }? = nil

local function clearWaypoint()
	if waypoint then
		waypoint.conn:Disconnect()
		waypoint.beam:Destroy()
		waypoint.a0:Destroy()
		waypoint.a1:Destroy()
		waypoint = nil
	end
	deliveryBar.Visible = false
	delivering = false
	applyAll()
end

Remotes.DeliveryTarget.OnClientEvent:Connect(function(door: BasePart?, seconds: number)
	clearWaypoint()
	if not door then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	delivering = true
	applyAll()
	local a0 = Instance.new("Attachment")
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, 4, 0)
	a1.Parent = door
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 1
	beam.Width1 = 1
	beam.FaceCamera = true
	beam.Color = ColorSequence.new(C.Green)
	beam.LightEmission = 1
	beam.Transparency = NumberSequence.new(0.3)
	beam.Parent = root
	local houseId = door:GetAttribute("HouseId")
	local start = os.clock()
	deliveryBar.Visible = true
	local conn = RunService.Heartbeat:Connect(function()
		local left = math.max(0, seconds - (os.clock() - start))
		local dist = (root.Position - door.Position).Magnitude
		deliveryLabel.Text = string.format("HOUSE #%s   %d M   %s", tostring(houseId), math.floor(dist / 3.5), Style.clock(left))
		deliveryEdge.BackgroundColor3 = if left > seconds * 0.6 then C.Green elseif left > 0 then C.Gold else C.Red
	end)
	waypoint = { beam = beam, a0 = a0, a1 = a1, conn = conn }
end)

player.CharacterAdded:Connect(function()
	Minigames.Close()
	StationMode.Leave()
	currentToken = nil
	clearWaypoint()
end)

task.delay(3, function()
	Ui.toast(string.format("Welcome to %s. Open your own store or join one (%s).", Config.GameName, GameClock.hoursText()), C.Gold)
end)

Driving.Init()
Prompts.Init()
StationMode.Init(Minigames.IsOpen, function()
	Minigames.Close()
	Loading.Close()
end)
Loading.Init()
-- Pizzas clicked in the world: load one from the ready rack, pull one at the oven exit.
StationPicks.Init(function(stationId: string, pieId: number, size: string)
	if stationId == "Load" then
		Loading.Load(pieId, size)
	elseif stationId == "CutTable" then
		Remotes.UseStation:FireServer("CutTable", pieId)
	end
end, Minigames.IsOpen)
WorkHud.Init(Minigames.IsOpen)
