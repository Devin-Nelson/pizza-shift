--!strict
-- In-world pizza minigames, one per make step: the camera switches to first
-- person at the station, you work a real 3D pizza with the station's tool
-- (your own hands are hidden), and a slim control strip at the bottom carries
-- the meters and buttons. Each step starts from the pizza exactly as the last
-- step left it. Results are raw inputs; the server scores.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Pizza3D = require(ReplicatedStorage.Shared.Pizza3D)
local Ui = require(script.Parent.Ui)
local Workstation = require(script.Parent.Workstation)
local T = Ui.Theme

local Minigames3D = {}

type Finish = (payload: any) -> ()
type Cancel = () -> ()

local ACTION = "PizzaMinigameInput"
local STEEL = Color3.fromRGB(200, 204, 210)

local active: { ws: Workstation.Workstation, dock: Frame, cleanup: { () -> () } }? = nil

function Minigames3D.Close()
	local a = active
	if not a then
		return
	end
	active = nil
	ContextActionService:UnbindAction(ACTION)
	for _, fn in a.cleanup do
		pcall(fn)
	end
	a.dock:Destroy()
	a.ws:leave()
end

function Minigames3D.IsOpen(): boolean
	return active ~= nil
end

-- Common setup. Returns workstation, dock body, cleanup list, and a "hold" reader
-- (true while the mouse / a finger is held down on the 3D view).
local function open(title: string, height: number, station: any, cancel: Cancel, view: string?): (Workstation.Workstation?, Frame, { () -> () }, () -> boolean)
	Minigames3D.Close()
	local cleanup = {}
	local ws = if typeof(station) == "Instance" and station:IsA("BasePart") then Workstation.enter(station, view) else nil
	if not ws then
		cancel()
		return nil, Instance.new("Frame"), cleanup, function()
			return false
		end
	end
	local dock, body, close = Ui.dock(title, height)
	active = { ws = ws, dock = dock, cleanup = cleanup }
	close.Activated:Connect(function()
		Minigames3D.Close()
		cancel()
	end)
	local holding = false
	ws:track(UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			holding = true
		end
	end))
	ws:track(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			holding = false
		end
	end))
	return ws, body, cleanup, function()
		return holding
	end
end

-- Space / gamepad A without jumping. `onEnd` (optional) fires on release.
local function bindSpace(onBegin: () -> (), onEnd: (() -> ())?)
	ContextActionService:BindActionAtPriority(ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			onBegin()
		elseif state == Enum.UserInputState.End and onEnd then
			onEnd()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
end

local function localPart(ws: Workstation.Workstation, name: string, size: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Parent = ws.folder
	return p
end

-- Hides the shared (server) copy of the pizza this player is working on, on
-- their screen only, until the minigame closes.
local function hideShared(visual: any, cleanup: { () -> () })
	if typeof(visual) ~= "Instance" then
		return
	end
	local hidden = {}
	for _, p in visual:GetDescendants() do
		if p:IsA("BasePart") then
			p.LocalTransparencyModifier = 1
			table.insert(hidden, p)
		end
	end
	table.insert(cleanup, function()
		for _, p in hidden do
			p.LocalTransparencyModifier = 0
		end
	end)
end

local function header(body: Frame, text: string)
	Ui.label(text, { Size = UDim2.new(1, 0, 0, 20), TextColor3 = T.Muted, TextXAlignment = Enum.TextXAlignment.Left, MaxText = 15, Parent = body })
end

local function meter(parent: Instance, y: number, labelText: string): (Frame, TextLabel)
	local bar = Ui.new("Frame", { Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, -170, 0, 18), BackgroundColor3 = T.Card, Parent = parent }, { Ui.corner(6) })
	local fill = Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.Accent2, Parent = bar }, { Ui.corner(6) })
	local l = Ui.label(labelText, { Size = UDim2.fromScale(1, 1), MaxText = 14, ZIndex = 3, Parent = bar })
	return fill, l
end

local function ticketTitle(data: any): string
	return string.format("#%s %s %s", tostring(data.ticket), string.upper(tostring(data.size)), string.upper(tostring(data.pizza)))
end

---------------------------------------------------------------------------
-- Stretch (dough table): pick a size, then press in rhythm to slap a dough
-- ball out into a skin for the racks.
---------------------------------------------------------------------------
local function dough(data: any, finish: Finish, cancel: Cancel)
	local ws, body, cleanup = open("Stretch Dough", 150, data.station, cancel)
	if not ws then
		return
	end
	local presses = tonumber(data.presses) or Config.Dough.Presses
	local skins = if type(data.skins) == "table" then data.skins else {}
	local rackUsed = tonumber(data.rackUsed) or 0
	local rackCapacity = tonumber(data.rackCapacity) or Config.RackCapacity()
	local diameter, thickness = 0.8, 0.45
	local pizza = Pizza3D.new(ws.frame * CFrame.new(0, thickness / 2, 0), diameter, ws.folder, thickness)
	table.insert(cleanup, function()
		pizza:Destroy()
	end)

	local function stretch(size: string)
		for _, c in body:GetChildren() do
			c:Destroy()
		end
		local targetD = Config.PizzaDiameter[size] or 2.4
		header(body, string.format("%s skin (%d\") - press in the green zone to stretch it out", string.upper(size), Config.PizzaInches[size] or 0))
		local bar = Ui.new("Frame", { Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, -170, 0, 30), BackgroundColor3 = Color3.fromRGB(120, 60, 50), Parent = body }, { Ui.corner(8) })
		Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(0.4, 1), BackgroundColor3 = Color3.fromRGB(220, 180, 60), Parent = bar }, { Ui.corner(8) })
		Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(0.12, 1), BackgroundColor3 = T.Good, Parent = bar }, { Ui.corner(8) })
		local markerBar = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(0, 6, 1, 10), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 3, Parent = bar })
		local feedback = Ui.label("", { Position = UDim2.fromOffset(0, 62), Size = UDim2.new(1, -170, 0, 26), Font = T.Title, Parent = body })
		local button = Ui.button("STRETCH!  [Space]", T.Accent, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 22), Size = UDim2.fromOffset(160, 64), Parent = body })

		local hits = {}
		local t, speed, pos = 0, 2.4, 0.5
		local done = false
		ws:track(RunService.RenderStepped:Connect(function(dt)
			t += dt * speed
			pos = 0.5 + 0.5 * math.sin(t)
			markerBar.Position = UDim2.fromScale(pos, 0.5)
		end))

		local cooldown = false
		local function press()
			if cooldown or done then
				return
			end
			cooldown = true
			task.delay(0.4, function()
				cooldown = false
			end)
			local d = math.abs(pos - 0.5)
			local q = if d <= 0.06 then 1 else math.clamp(1 - (d - 0.06) / 0.3, 0, 1)
			table.insert(hits, q)
			feedback.Text = if q >= 0.95 then "PERFECT!" elseif q >= 0.6 then "Good" elseif q > 0 then "Meh" else "Miss!"
			feedback.TextColor3 = if q >= 0.95 then T.Good elseif q >= 0.6 then T.Accent2 else T.Accent
			-- Grow toward the chosen size; sloppy presses leave it undersized and thick.
			diameter = math.min(targetD, diameter + (targetD - 0.8) / presses * (0.55 + 0.45 * q))
			thickness = math.max(0.12, thickness - (0.45 - 0.12) / presses)
			pizza:setDough(diameter, thickness)
			pizza.crust.CFrame = (ws.frame * CFrame.new(0, thickness / 2, 0)) * Pizza3D.FLAT
			speed += 0.35
			if #hits >= presses then
				done = true
				task.delay(0.6, function()
					if active then
						Minigames3D.Close()
						finish({ hits = hits, size = size })
					end
				end)
			end
		end
		button.Activated:Connect(press)
		bindSpace(press)
	end

	-- Step 1: choose what size to prep (shows what's already on the racks).
	header(body, string.format("Prep dough for the rush: pick a size to stretch. Racks: %d/%d slots used.", rackUsed, rackCapacity))
	local row = Ui.new("Frame", { Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 64), BackgroundTransparency = 1, Parent = body }, {
		Ui.new("UIGridLayout", { CellSize = UDim2.new(1 / 3, -8, 1, 0), CellPadding = UDim2.fromOffset(8, 0) }),
	})
	for _, size in (data.sizes or Config.Sizes) do
		local have = tonumber(skins[size]) or 0
		local b = Ui.button(string.format("%s %d\"  (%d on rack)", size, Config.PizzaInches[size] or 0, have), Color3.fromRGB(200, 160, 100), { Parent = row, MaxText = 18 })
		b.Activated:Connect(function()
			stretch(size)
		end)
	end
end

---------------------------------------------------------------------------
-- Sauce (dough table): hold and drag the ladle in a spiral; one ladle per pizza.
---------------------------------------------------------------------------
local function sauce(data: any, finish: Finish, cancel: Cancel)
	local ws, body, cleanup, holding = open("Sauce", 150, data.station, cancel)
	if not ws then
		return
	end
	local d = tonumber(data.diameter) or 2.4
	local R = d / 2
	local S = Config.Sauce
	local pizza = Pizza3D.new(ws.frame * CFrame.new(0, 0.06, 0), d, ws.folder)
	table.insert(cleanup, function()
		pizza:Destroy()
	end)

	header(body, ticketTitle(data) .. "  |  Hold and drag the ladle in a spiral - even and edge to edge, not over the crust")
	local fill, l = meter(body, 30, "Ladle full")
	local doneBtn = Ui.button("Sauce Done", T.Good, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 24), Size = UDim2.fromOffset(160, 64), Parent = body })
	-- The ladle: bowl + handle angled up toward you
	local bowl = localPart(ws, "Ladle", Vector3.new(0.12, 0.5, 0.5), STEEL, Enum.Material.Metal, Enum.PartType.Cylinder)
	local handle = localPart(ws, "LadleHandle", Vector3.new(0.06, 0.06, 1.3), STEEL, Enum.Material.Metal)
	local grip = localPart(ws, "LadleGrip", Vector3.new(0.09, 0.09, 0.45), Color3.fromRGB(200, 30, 30), Enum.Material.Plastic)

	local cells = table.create(S.Rings * S.Sectors, 0)
	local overflow = 0
	local remaining = S.Ladle
	local lastSplat = Vector3.new(1e9, 0, 0)
	local sauceR = R * S.Coverage
	ws:track(RunService.RenderStepped:Connect(function(dt)
		local hit, x, z = ws:pointer(0.15)
		if not hit then
			return
		end
		local r = math.sqrt(x * x + z * z)
		if r > R + 0.6 then
			local k = (R + 0.6) / r
			x, z = x * k, z * k
		end
		local p = ws:at(x, 0.2, z)
		bowl.CFrame = CFrame.new(p) * Pizza3D.FLAT
		local handleEnd = p + ws.toWorker * 0.9 + Vector3.new(0, 0.7, 0)
		handle.CFrame = CFrame.lookAt((p + handleEnd) / 2, handleEnd)
		grip.CFrame = CFrame.lookAt(handleEnd, handleEnd + (handleEnd - p).Unit)
		if holding() and remaining > 0 then
			local amount = math.min(remaining, S.PourRate * dt)
			remaining -= amount
			if r > sauceR then
				overflow += amount
			else
				local ring = math.min(S.Rings, math.floor(r / sauceR * S.Rings) + 1)
				local angle = (math.atan2(z, x) + math.pi * 2) % (math.pi * 2)
				local sector = math.min(S.Sectors, math.floor(angle / (math.pi * 2) * S.Sectors) + 1)
				cells[(ring - 1) * S.Sectors + sector] += amount
			end
			local here = Vector3.new(x, 0, z)
			if (here - lastSplat).Magnitude > 0.09 and r < R + 0.1 then
				lastSplat = here
				pizza:addSauce(x, z, 0.2)
			end
			fill.Size = UDim2.fromScale(remaining / S.Ladle, 1)
			l.Text = if remaining <= 0 then "Ladle empty" else string.format("Ladle %d%%", math.floor(remaining / S.Ladle * 100 + 0.5))
		end
	end))
	doneBtn.Activated:Connect(function()
		Minigames3D.Close()
		finish({ sauce = { cells = cells, overflow = overflow } })
	end)
end

---------------------------------------------------------------------------
-- Cheese (make-line): hold to pour; the pour speeds up the longer you hold.
---------------------------------------------------------------------------
local function cheese(data: any, finish: Finish, cancel: Cancel)
	local ws, body, cleanup, holding = open("Cheese", 150, data.station, cancel)
	if not ws then
		return
	end
	hideShared(data.visual, cleanup)
	local spec = if type(data.spec) == "table" then data.spec else { size = data.size }
	local pizza = Pizza3D.fromSpec(ws.frame * CFrame.new(0, 0.06, 0), spec, ws.folder)
	table.insert(cleanup, function()
		pizza:Destroy()
	end)
	local R = (Config.PizzaDiameter[spec.size] or 2.4) / 2
	local target = tonumber(data.cheese) or 6
	local rng = Random.new()

	header(body, string.format("%s  |  Portion is %.1f oz (stay within 10%%). Hold [Space] or hold on the pizza - it pours faster the longer you hold.", ticketTitle(data), target))
	local scale = Ui.label("0.0 oz", { Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, -170, 0, 44), Font = Enum.Font.Code, TextColor3 = Color3.fromRGB(120, 255, 140), MaxText = 34, Parent = body })
	local doneBtn = Ui.button("Cheese Done", T.Good, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 24), Size = UDim2.fromOffset(160, 64), Parent = body })
	local spaceHeld = false
	bindSpace(function()
		spaceHeld = true
	end, function()
		spaceHeld = false
	end)
	local oz, held, lastShred, swirl, shreds = 0, 0, 0, 0, 0
	ws:track(RunService.RenderStepped:Connect(function(dt)
		local pouring = spaceHeld or holding()
		swirl += dt * (if pouring then 5 else 1.5)
		if not pouring then
			held = 0
			return
		end
		held += dt
		local rate = math.min(Config.CheesePour.MaxRate, Config.CheesePour.StartRate + Config.CheesePour.Accel * held)
		oz += rate * dt
		pizza:setCheese(oz / target)
		scale.Text = string.format("%.1f oz", oz)
		local off = math.abs(oz - target) / target
		scale.TextColor3 = if off <= Config.PortionTolerance then Color3.fromRGB(120, 255, 140) elseif oz < target then Color3.fromRGB(255, 220, 120) else Color3.fromRGB(255, 110, 90)
		-- Shreds fall from a spot circling over the pizza.
		lastShred += dt
		if lastShred > 0.025 and shreds < 220 then
			lastShred = 0
			shreds += 1
			local cx, cz = math.cos(swirl) * R * 0.45, math.sin(swirl) * R * 0.45
			local x, z = pizza:randomPoint(rng)
			local shred = localPart(ws, "Shred", Vector3.new(0.14, 0.03, 0.04), Config.IngredientColors.Cheese, Enum.Material.Sand)
			shred.CFrame = CFrame.new(ws:at(cx, 0.8, cz)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
			TweenService:Create(shred, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				CFrame = CFrame.new(ws:at(x, 0.15 + rng:NextNumber(0, 0.02), z)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
			}):Play()
		end
	end))
	doneBtn.Activated:Connect(function()
		Minigames3D.Close()
		finish({ cheese = oz })
	end)
end

---------------------------------------------------------------------------
-- Toppings (make-line): pick a topping, hold on the pizza to drop it.
---------------------------------------------------------------------------
local function toppings(data: any, finish: Finish, cancel: Cancel)
	local ws, body, cleanup, holding = open("Toppings", 150, data.station, cancel)
	if not ws then
		return
	end
	hideShared(data.visual, cleanup)
	local spec = if type(data.spec) == "table" then data.spec else { size = data.size }
	local pizza = Pizza3D.fromSpec(ws.frame * CFrame.new(0, 0.06, 0), spec, ws.folder)
	table.insert(cleanup, function()
		pizza:Destroy()
	end)
	local R = (Config.PizzaDiameter[spec.size] or 2.4) / 2
	local list: { string } = if type(data.toppings) == "table" then data.toppings else {}
	local portions = if type(data.portions) == "table" then data.portions else {}
	local rng = Random.new()
	local counts: { [string]: number } = {}

	header(body, ticketTitle(data) .. "  |  Pick a topping, then hold on the pizza to drop it. Hit each portion within 10%.")
	local selected = list[1]
	local buttons: { [string]: TextButton } = {}
	local row = Ui.new("Frame", { Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, -170, 0, 40), BackgroundTransparency = 1, Parent = body }, {
		Ui.new("UIGridLayout", { CellSize = UDim2.new(1 / math.max(#list, 1), -6, 1, 0), CellPadding = UDim2.fromOffset(6, 0) }),
	})
	local function refresh()
		for name, b in buttons do
			local n = pizza:count(name)
			counts[name] = n
			local target = tonumber(portions[name]) or 0
			b.Text = string.format("%s %d/%d", name, n, target)
			local off = if target > 0 then math.abs(n - target) / target else 0
			b.BackgroundColor3 = if name == selected then T.Accent2 elseif target > 0 and off <= Config.PortionTolerance then T.Good else T.Card
			b.TextColor3 = if name == selected then Color3.fromRGB(30, 30, 30) else T.Text
		end
	end
	for _, name in list do
		local b = Ui.button(name, T.Card, { Parent = row, MaxText = 16 })
		buttons[name] = b
		b.Activated:Connect(function()
			selected = name
			refresh()
		end)
	end
	local pick = Ui.button("Pick off 5", Color3.fromRGB(90, 70, 70), { Position = UDim2.fromOffset(0, 72), Size = UDim2.fromOffset(130, 36), Parent = body })
	pick.Activated:Connect(function()
		if selected then
			pizza:removeTopping(selected, 5)
			refresh()
		end
	end)
	local sendBtn = Ui.button("Send to Oven", T.Good, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 24), Size = UDim2.fromOffset(160, 64), Parent = body })
	sendBtn.Activated:Connect(function()
		Minigames3D.Close()
		finish({ counts = counts })
	end)
	refresh()

	-- A hand-sized scoop of the selected topping follows the pointer.
	local scoop = localPart(ws, "Scoop", Vector3.new(0.35, 0.12, 0.35), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	local acc = 0
	ws:track(RunService.RenderStepped:Connect(function(dt)
		local hit, x, z = ws:pointer(0.2)
		if hit then
			scoop.CFrame = CFrame.new(ws:at(x, 0.55, z))
			scoop.Color = if selected then Config.IngredientColors[selected] or scoop.Color else scoop.Color
		end
		if hit and holding() and selected then
			acc += dt
			while acc >= 0.1 do
				acc -= 0.1
				local jx, jz = x + rng:NextNumber(-0.18, 0.18), z + rng:NextNumber(-0.18, 0.18)
				local r = math.sqrt(jx * jx + jz * jz)
				local maxR = R * 0.82
				if r > maxR then
					jx, jz = jx * maxR / r, jz * maxR / r
				end
				if r < R + 0.4 then
					pizza:addTopping(selected, jx, jz, rng)
					refresh()
				end
			end
		else
			acc = 0
		end
	end))
end

---------------------------------------------------------------------------
-- Cut & Box: open boxes are laid out on the table. Pull the pizza off the end
-- of the oven belt onto the right box, pop any bubbles, rock the blade through
-- even cuts, close the lid.
---------------------------------------------------------------------------
local function cut(data: any, finish: Finish, cancel: Cancel)
	local ws, body, cleanup = open("Cut Table", 150, data.station, cancel, "wide")
	if not ws then
		return
	end
	hideShared(data.visual, cleanup)
	local cuts = tonumber(data.cuts) or 4
	local spec = if type(data.spec) == "table" then data.spec else { size = data.size, baked = true }
	local d = Config.PizzaDiameter[spec.size] or 2.4
	local top = 0.12
	local station = data.station :: BasePart

	-- The open boxes on the table (from the station art).
	local boxes: { [string]: BasePart } = {}
	for _, p in station:GetDescendants() do
		if p:IsA("BasePart") and type(p:GetAttribute("BoxSize")) == "string" then
			boxes[p:GetAttribute("BoxSize") :: string] = p
		end
	end

	-- Our copy of the pizza starts where the shared one sits at the end of the belt.
	local exitPos = if typeof(data.exitPos) == "Vector3" then data.exitPos else ws:at(-4.5, 0.4, 0)
	local rot = ws.frame.Rotation
	local pizza = Pizza3D.fromSpec(CFrame.new(exitPos) * rot, spec, ws.folder)
	table.insert(cleanup, function()
		pizza:Destroy()
	end)

	local popped = 0
	local angles: { number } = {}
	local chosenBox = ""
	local center = exitPos -- world center of the pizza once it's in its box
	local stepConn: RBXScriptConnection? = nil
	local function clearBody()
		for _, c in body:GetChildren() do
			c:Destroy()
		end
		if stepConn then
			stepConn:Disconnect()
			stepConn = nil
		end
		ContextActionService:UnbindAction(ACTION)
	end
	local function clickRay(include: { Instance }): RaycastResult?
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = include
		local camera = workspace.CurrentCamera
		local m = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(m.X, m.Y)
		return workspace:Raycast(ray.Origin, ray.Direction * 60, params)
	end

	-- 4) CLOSE THE LID ------------------------------------------------------
	local function closeLid()
		clearBody()
		header(body, "Closing it up...")
		local box = boxes[chosenBox]
		local bs = Config.BoxSize[chosenBox] or (d + 0.15)
		-- Hide the table's open lid locally and swing our own copy shut from the same spot.
		local artLid = box and box.Parent and box.Parent:FindFirstChild("Lid_" .. chosenBox) :: BasePart?
		if artLid then
			artLid.LocalTransparencyModifier = 1
			table.insert(cleanup, function()
				artLid.LocalTransparencyModifier = 0
			end)
		end
		local lid = localPart(ws, "BoxLid", Vector3.new(bs, 0.04, bs), Color3.fromRGB(225, 200, 160), Enum.Material.Cardboard)
		local printed = Instance.new("SurfaceGui")
		printed.Face = Enum.NormalId.Top -- the printed outside, face-up once closed
		printed.CanvasSize = Vector2.new(200, 200)
		local brand = Instance.new("TextLabel")
		brand.Size = UDim2.fromScale(1, 1)
		brand.BackgroundColor3 = Color3.fromRGB(205, 168, 118)
		brand.BorderSizePixel = 0
		brand.Font = Enum.Font.GothamBlack
		brand.TextScaled = true
		brand.TextColor3 = Config.Brand.Red
		brand.Text = (string.upper(Config.GameName):gsub(" ", "\n"))
		brand.Parent = printed
		printed.Parent = lid
		local baseCF = if box then box.CFrame else CFrame.new(center) * rot
		local wall = if box then (tonumber(box:GetAttribute("WallHeight")) or 0.2) else 0.2
		local hinge = baseCF * CFrame.new(0, wall - 0.025, bs / 2) -- back edge of the tray
		local angle = Instance.new("NumberValue")
		angle.Value = if artLid then (tonumber(artLid:GetAttribute("OpenAngle")) or 180) else 180
		angle.Parent = ws.folder -- cleaned up with the minigame
		local function placeLid()
			lid.CFrame = hinge * CFrame.Angles(math.rad(angle.Value), 0, 0) * CFrame.new(0, 0, -bs / 2)
		end
		placeLid()
		angle.Changed:Connect(placeLid)
		TweenService:Create(angle, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Value = 0 }):Play()
		task.delay(0.9, function()
			if active then
				Minigames3D.Close()
				finish({ angles = angles, popped = popped, box = chosenBox })
			end
		end)
	end

	-- 3) CUT ----------------------------------------------------------------
	local function cutPhase()
		clearBody()
		header(body, string.format("Rock the blade through %d even cuts (%d slices) - press [Space] as it lines up", cuts, cuts * 2))
		local status = Ui.label(string.format("Cuts left: %d", cuts), { Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, -170, 0, 30), Font = T.Title, Parent = body })
		local button = Ui.button("CUT!  [Space]", T.Accent, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 24), Size = UDim2.fromOffset(160, 64), Parent = body })
		local bladeLen = d * 1.12
		local blade = localPart(ws, "Rocker", Vector3.new(bladeLen, 0.24, 0.035), STEEL, Enum.Material.Metal)
		blade.Reflectance = 0.25
		local handles = {}
		for _, sx in { -1, 1 } do
			table.insert(handles, { part = localPart(ws, "Handle", Vector3.new(0.45, 0.13, 0.13), Color3.fromRGB(30, 30, 30), Enum.Material.Plastic, Enum.PartType.Cylinder), side = sx })
		end
		local yaw = 0
		local phase, phaseT, cutYaw = "hover", 0, 0
		stepConn = RunService.RenderStepped:Connect(function(dt)
			local height, roll = 0.55, 0
			if phase == "hover" then
				yaw = (yaw + dt * 75) % 360
			else
				phaseT += dt
				local p = phaseT / 0.45
				-- Down, rock side to side, back up.
				height = 0.55 - 0.42 * math.sin(math.clamp(p, 0, 1) * math.pi)
				roll = math.sin(p * math.pi * 3) * 10
				if p >= 1 then
					phase = "hover"
				end
			end
			local c = center + Vector3.new(0, top + height, 0)
			local cf = CFrame.new(c) * rot * CFrame.Angles(0, math.rad(if phase == "hover" then yaw else cutYaw), 0) * CFrame.Angles(0, 0, math.rad(roll))
			blade.CFrame = cf
			for _, h in handles do
				h.part.CFrame = cf * CFrame.new(h.side * (bladeLen / 2 + 0.2), 0.08, 0)
			end
		end)
		local function press()
			if phase ~= "hover" or #angles >= cuts then
				return
			end
			cutYaw = yaw
			table.insert(angles, yaw)
			phase, phaseT = "cut", 0
			task.delay(0.22, function()
				if active then
					pizza:addCut(cutYaw)
				end
			end)
			status.Text = string.format("Cuts left: %d", cuts - #angles)
			if #angles >= cuts then
				task.delay(0.7, function()
					if active then
						blade:Destroy()
						for _, h in handles do
							h.part:Destroy()
						end
						closeLid()
					end
				end)
			end
		end
		button.Activated:Connect(press)
		bindSpace(press)
	end

	-- 2) QUALITY CHECK: pop cheese bubbles -----------------------------------
	local function bubblePhase()
		local bubbles = if type(data.bubbles) == "table" then data.bubbles else {}
		if #bubbles == 0 then
			cutPhase()
			return
		end
		clearBody()
		header(body, "Quality check: click the cheese bubbles to pop them")
		local bubbleParts: { BasePart } = {}
		for _, b in bubbles do
			local x, z = ((tonumber(b.x) or 0.5) - 0.5) * d * 0.8, ((tonumber(b.y) or 0.5) - 0.5) * d * 0.8
			local bubble = localPart(ws, "Bubble", Vector3.new(0.26, 0.26, 0.26), Color3.fromRGB(255, 235, 170), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
			bubble.CanQuery = true
			bubble.CFrame = CFrame.new(center + ws.right * x + ws.toWorker * z + Vector3.new(0, top + 0.08, 0))
			table.insert(bubbleParts, bubble)
		end
		local moved = false
		ws:track(UserInputService.InputBegan:Connect(function(input, processed)
			if moved or processed or (input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch) then
				return
			end
			local result = clickRay(bubbleParts)
			if result and result.Instance.Name == "Bubble" then
				local hitPart = result.Instance :: BasePart
				hitPart.Name = "Popped"
				popped += 1
				TweenService:Create(hitPart, TweenInfo.new(0.15), { Size = Vector3.new(0.05, 0.05, 0.05) }):Play()
				task.delay(0.16, function()
					hitPart:Destroy()
				end)
				if popped >= #bubbles then
					moved = true
					cutPhase()
				end
			end
		end))
		local skip = Ui.button("Looks good - start cutting", T.Card, { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 48), Parent = body })
		skip.Activated:Connect(function()
			moved = true
			for _, p in bubbleParts do
				if p.Parent then
					p:Destroy()
				end
			end
			cutPhase()
		end)
	end

	-- 1) BOX IT: pick the right box for the pizza coming off the belt ---------
	clearBody()
	header(body, ticketTitle(data) .. " just came out of the oven - click the right box to pull it onto")
	local row = Ui.new("Frame", { Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 56), BackgroundTransparency = 1, Parent = body }, {
		Ui.new("UIGridLayout", { CellSize = UDim2.new(1 / 3, -8, 1, 0), CellPadding = UDim2.fromOffset(8, 0) }),
	})
	-- Look between the oven exit and the boxes so both are in view.
	ws.focus = (exitPos + ws:at(0, 0, 0)) / 2
	local picking = true
	local function pick(size: string)
		if not picking then
			return
		end
		picking = false
		chosenBox = size
		local box = boxes[size]
		local landing = if box then box.Position + Vector3.new(0, 0.025 + 0.06, 0) else ws:at(0, 0.11, 0)
		center = landing - Vector3.new(0, 0.06, 0)
		ws.focus = center -- turn to look at the box we chose
		-- Slide the pizza off the belt onto the box.
		local slide = TweenService:Create(pizza.crust, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { CFrame = CFrame.new(landing) * rot * Pizza3D.FLAT })
		slide:Play()
		slide.Completed:Wait()
		if active then
			bubblePhase()
		end
	end
	for _, size in (data.sizes or Config.Sizes) do
		local b = Ui.button(size .. " Box", Color3.fromRGB(176, 130, 80), { Parent = row, MaxText = 18 })
		b.Activated:Connect(function()
			pick(size)
		end)
	end
	-- Clicking a box on the table works too.
	local boxParts = {}
	for _, p in boxes do
		table.insert(boxParts, p)
	end
	ws:track(UserInputService.InputBegan:Connect(function(input, processed)
		if not picking or processed or (input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch) then
			return
		end
		local result = clickRay(boxParts)
		local size = result and result.Instance:GetAttribute("BoxSize")
		if type(size) == "string" then
			pick(size)
		end
	end))
end

local HANDLERS: { [string]: (any, Finish, Cancel) -> () } = {
	Dough = dough,
	Sauce = sauce,
	Cheese = cheese,
	Toppings = toppings,
	Cut = cut,
}

function Minigames3D.Handles(kind: string): boolean
	return HANDLERS[kind] ~= nil
end

function Minigames3D.Start(kind: string, data: any, finish: Finish, cancel: Cancel)
	local handler = HANDLERS[kind]
	if handler then
		handler(data or {}, finish, cancel)
	end
end

return Minigames3D
