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
local StationMode = require(script.Parent.StationMode)
local StationPicks = require(script.Parent.StationPicks)
local WorkHud = require(script.Parent.WorkHud)
local T = Ui.Theme

local player = Players.LocalPlayer

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

---------------------------------------------------------------------------
-- HUD: one slim pill, top right - day, time, open dot | coins, level (XP
-- progress along its bottom edge). Clock In and the Stations tab are WorkHud's.
---------------------------------------------------------------------------
local C = Style.Color
local pillWrap = Ui.box(C.Panel, {
	Name = "StatusPill",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 10),
	Size = UDim2.fromOffset(0, 28),
	AutomaticSize = Enum.AutomaticSize.X,
	Parent = Ui.Root,
})
Ui.edge(pillWrap, "left", 3, C.Red)
local pill = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X, Parent = pillWrap })
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
player:GetAttributeChangedSignal("Job"):Connect(refreshHud)
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
-- Prompt filtering: only show stations for your job.
---------------------------------------------------------------------------
-- Every station some job is restricted to (derived from Config.Jobs).
local JOB_STATIONS: { [string]: boolean } = {}
for _, def in Config.Jobs do
	for _, stationName in def.stations do
		JOB_STATIONS[stationName] = true
	end
end
local delivering = false

local function applyPrompt(pp: ProximityPrompt)
	local parent = pp.Parent
	if not parent then
		return
	end
	local station = parent:GetAttribute("Station")
	if pp.Name == "ClockPrompt" then
		pp.Enabled = true -- clocking in/out is always available at the register
	elseif type(station) == "string" and JOB_STATIONS[station] then
		local job = player:GetAttribute("Job")
		local def = if type(job) == "string" then Config.Jobs[job] else nil
		-- Off duty: show everything so players discover stations (the server explains how to clock in).
		pp.Enabled = def == nil or table.find(def.stations, station) ~= nil
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
player:GetAttributeChangedSignal("Job"):Connect(applyAll)
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
-- Job menu
---------------------------------------------------------------------------
local JOB_BLURBS = {
	CSR = "Take orders and make pizzas: dough, make-line, cut & box. Earns the most XP toward management.",
	Delivery = "Everything a CSR does, plus deliveries in your own car. Less XP, but the best tip money.",
	ShiftManager = string.format("%d slots, highest XP wins. Runs any station and unloads the supply truck. Level %d+ unless no manager is on.", Config.Management.ShiftManager.slots, Config.Management.ShiftManager.minLevel),
	GeneralManager = string.format("%d slot, highest XP wins. Runs the store. Level %d+ unless no manager is on.", Config.Management.GeneralManager.slots, Config.Management.GeneralManager.minLevel),
}
local menuOpen: Frame? = nil

local function closeMenu()
	if menuOpen then
		menuOpen:Destroy()
		menuOpen = nil
	end
end

Remotes.OpenJobMenu.OnClientEvent:Connect(function(shopName: string)
	closeMenu()
	local root, body, close = Ui.panel("Clock In - " .. tostring(shopName), 520, 470)
	menuOpen = root
	close.Activated:Connect(closeMenu)
	Ui.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = body })
	for i, jobName in Config.JobOrder do
		local def = Config.Jobs[jobName]
		local row = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 76), BackgroundColor3 = T.Card, LayoutOrder = i, Parent = body }, { Ui.corner(10), Ui.pad(8) })
		Ui.new("Frame", { Size = UDim2.new(0, 6, 1, 0), BackgroundColor3 = def.color, Parent = row }, { Ui.corner(3) })
		Ui.label(def.display, { Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -150, 0, 28), TextXAlignment = Enum.TextXAlignment.Left, Font = T.Title, Parent = row })
		Ui.label(JOB_BLURBS[jobName] or "", { Position = UDim2.fromOffset(16, 30), Size = UDim2.new(1, -150, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, TextColor3 = T.Muted, MaxText = 15, Parent = row })
		local current = player:GetAttribute("Job") == jobName
		local b = Ui.button(if current then "On shift" else "Clock In", if current then T.Good else def.color, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.fromOffset(120, 44),
			Parent = row,
		})
		b.Activated:Connect(function()
			Remotes.ChooseJob:FireServer(jobName)
			closeMenu()
		end)
	end
	local out = Ui.button("Clock Out", Color3.fromRGB(90, 70, 70), { Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 99, Parent = body })
	out.Activated:Connect(function()
		Remotes.ChooseJob:FireServer(nil)
		closeMenu()
	end)
end)

---------------------------------------------------------------------------
-- Franchise menu
---------------------------------------------------------------------------
Remotes.OpenFranchiseMenu.OnClientEvent:Connect(function(info: any)
	closeMenu()
	local root, body, close = Ui.panel("Open a Franchise", 520, 420)
	menuOpen = root
	close.Activated:Connect(closeMenu)

	local text
	if info.owned then
		text = "You already own a franchise! It opens on a free lot whenever you're in a server."
	else
		text = string.format(
			"Run your own " .. Config.GameName .. " store!\n\n- Earn %d%% of every sale at your shop\n- Earn a %d%% royalty on what your workers make\n- Name it yourself\n\nRequires level %d and %d coins.\nYou: level %d, %d coins.",
			math.floor(info.saleCut * 100), math.floor(info.royalty * 100), info.minLevel, info.cost, info.level, info.coins
		)
	end
	Ui.label(text, { Size = UDim2.new(1, 0, 0, 200), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, MaxText = 18, Parent = body })
	if info.owned then
		return
	end
	local eligible = info.level >= info.minLevel and info.coins >= info.cost
	local box = Ui.new("TextBox", {
		Position = UDim2.fromOffset(0, 214),
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = T.Card,
		PlaceholderText = "Name your shop (3-24 chars)",
		PlaceholderColor3 = T.Muted,
		Text = player.DisplayName .. "'s Pizza",
		TextColor3 = T.Text,
		Font = T.Font,
		TextSize = 20,
		ClearTextOnFocus = false,
		Parent = body,
	}, { Ui.corner(8) })
	local buy = Ui.button(if eligible then string.format("Buy Franchise (%d coins)", info.cost) else "Not eligible yet", if eligible then T.Good else T.Card, {
		Position = UDim2.new(0, 0, 1, -50),
		Size = UDim2.new(1, 0, 0, 50),
		Parent = body,
	})
	buy.Activated:Connect(function()
		if eligible then
			Remotes.BuyFranchise:FireServer(box.Text)
			closeMenu()
		end
	end)
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
	beam.Color = ColorSequence.new(T.Good)
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
	Ui.toast(string.format("Welcome to %s. Clock in to start a shift (%s).", Config.GameName, GameClock.hoursText()), C.Gold)
end)

Driving.Init()
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
