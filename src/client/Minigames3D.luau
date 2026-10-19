--!strict
-- In-world pizza minigames, one per make step. You're already standing at the
-- station in first person (StationMode); each job adds a real 3D pizza at the
-- work spot, the station's tool (your own hands are hidden), and a work strip
-- at the bottom with just the controls (short labels; the station's tip card
-- explains it on a first visit). Each step starts from the
-- pizza exactly as the last step left it. Space, a mouse click and a tap on
-- the screen all work as the action button. The make-line is free-form:
-- nothing tells you the portions (the job aids do), and pizzas only meet an
-- order when they're loaded. Results are raw inputs; the server scores.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Icons = require(ReplicatedStorage.Shared.Icons)
local Pizza3D = require(ReplicatedStorage.Shared.Pizza3D)
local Style = require(ReplicatedStorage.Shared.Style)
local Loading = require(script.Parent.Loading)
local StationMode = require(script.Parent.StationMode)
local StationPicks = require(script.Parent.StationPicks)
local Ui = require(script.Parent.Ui)
local Workstation = require(script.Parent.Workstation)

local C = Style.Color
local F = Style.Font
local S = Style.Size

local Minigames3D = {}

type Finish = (payload: any) -> ()
type Cancel = () -> ()

-- One open minigame: its workstation, local parts, control strip and input.
type Ctx = {
	ws: Workstation.Workstation,
	folder: Folder,
	body: Frame,
	cleanup: { () -> () },
	holding: () -> boolean,
	track: (RBXScriptConnection) -> (),
}

local ACTION = "PizzaMinigameInput"
local STEEL = Color3.fromRGB(200, 204, 210)
-- The key hint on action buttons (none on touch-only devices).
local KEY_HINT: string? = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then nil else "SPACE"
-- A closed box's printed lid is built standing on edge and laid flat with this,
-- so the print is the part's Front face, whose "up" points away from the
-- worker (a Top-face print reads upside down from the front).
local BOX_FLAT = CFrame.Angles(math.rad(90), 0, 0)

local active: { dock: Frame, folder: Folder, cleanup: { () -> () }, conns: { RBXScriptConnection } }? = nil

-- Closes the open minigame (you stay at the station).
function Minigames3D.Close()
	local a = active
	if not a then
		return
	end
	active = nil
	ContextActionService:UnbindAction(ACTION)
	for _, c in a.conns do
		c:Disconnect()
	end
	for _, fn in a.cleanup do
		pcall(fn)
	end
	a.dock:Destroy()
	a.folder:Destroy()
end

function Minigames3D.IsOpen(): boolean
	return active ~= nil
end

local function isPointer(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

-- A click/tap meant for the minigame (not a button, a job aid card, or a pizza you can pick).
local function isPlayClick(input: InputObject, processed: boolean): boolean
	return not processed and isPointer(input) and not StationPicks.IsPointerOverPick()
end

-- Common setup at the station the job was started at: its folder of local
-- parts and an empty work strip (leaving is on the Stations bar).
local function open(data: any, cancel: Cancel): Ctx?
	Minigames3D.Close()
	local ws = StationMode.Ensure(data.station)
	if not ws then
		cancel()
		return nil
	end
	local folder = Instance.new("Folder")
	folder.Name = "Minigame"
	folder.Parent = ws.folder
	local strip, body = Ui.strip()
	local a = { dock = strip, folder = folder, cleanup = {}, conns = {} }
	active = a
	local function track(conn: RBXScriptConnection)
		table.insert(a.conns, conn)
	end
	-- True while the mouse / a finger is held down on the 3D view (not on a button).
	local holding = false
	track(UserInputService.InputBegan:Connect(function(input, processed)
		if isPlayClick(input, processed) then
			holding = true
		end
	end))
	track(UserInputService.InputEnded:Connect(function(input)
		if isPointer(input) then
			holding = false
		end
	end))
	return {
		ws = ws,
		folder = folder,
		body = body,
		cleanup = a.cleanup,
		holding = function()
			return holding
		end,
		track = track,
	}
end

-- Space / gamepad A, without jumping. `onEnd` (optional) fires on release.
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

-- The action button: Space / gamepad A, or a click / tap anywhere on the 3D view.
local function bindPress(ctx: Ctx, onPress: () -> ())
	bindSpace(onPress)
	-- Ignore the click that opened this phase, if it's still being delivered.
	local armedAt = os.clock() + 0.15
	ctx.track(UserInputService.InputBegan:Connect(function(input, processed)
		if isPlayClick(input, processed) and os.clock() >= armedAt then
			onPress()
		end
	end))
end

local function localPart(folder: Instance, name: string, size: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
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
	p.Parent = folder
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

-- Empties the work strip for the next phase (keeps its layout).
local function clearBody(body: Frame)
	for _, c in body:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

-- The size being worked, at the start of the strip ("LARGE 14\"").
local function sizeChip(row: Frame, size: string, order: number): TextLabel
	local chip = Ui.chip(string.format("%s %d\"", size, Config.PizzaInches[size] or 0), C.Cream, C.Ink, { Size = UDim2.fromOffset(0, 28), LayoutOrder = order, Parent = row })
	chip.TextSize = S.Body
	return chip
end

-- The strip's main action, with its key hint when there is a keyboard.
local function actionButton(row: Frame, text: string, order: number, width: number?, hint: string?): TextButton
	local b = Ui.flatButton(text, "primary", { Size = UDim2.fromOffset(width or 150, 52), TextSize = S.Big, LayoutOrder = order, Parent = row })
	if hint then
		Ui.new("UIPadding", { PaddingRight = UDim.new(0, 40), Parent = b })
		Ui.text(hint, F.Mono, S.Tiny, {
			TextColor3 = C.White,
			TextTransparency = 0.3,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 34, 0.5, 0),
			Size = UDim2.fromOffset(40, 14),
			Parent = b,
		})
	end
	return b
end

-- A size picker: one tile per size with how many skins are on the racks.
-- `needSkin`: sizes with none on the racks can't be picked.
local function sizeTiles(row: Frame, counts: { [string]: any }, needSkin: boolean, onPick: (string) -> ())
	for i, size in Config.Sizes do
		local have = tonumber(counts[size]) or 0
		local usable = not needSkin or have > 0
		local b = Ui.flatButton("", "dark", { Size = UDim2.fromOffset(110, 54), LayoutOrder = i, Parent = row })
		if not usable then
			b.BackgroundTransparency = 0.6
			b.Active = false
		end
		Ui.text(string.format("%s %d\"", string.upper(size), Config.PizzaInches[size] or 0), F.LabelBold, S.Label, {
			TextColor3 = if usable then C.Cream else C.CreamDim,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 7),
			Size = UDim2.new(1, 0, 0, 20),
			Parent = b,
		})
		Ui.text(string.format("%d ON RACK", have), F.Label, S.Tiny, {
			TextColor3 = if have > 0 then C.Gold else C.CreamDim,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 30),
			Size = UDim2.new(1, 0, 0, 16),
			Parent = b,
		})
		if usable then
			b.Activated:Connect(function()
				onPick(size)
			end)
		end
	end
end

-- The dough on the table while it's stretched, after the user's photos: a
-- cornmeal-dusted ball sitting in a pile of cornmeal, pressed out into a
-- lopsided disc that grows a raised edge and pushes the cornmeal into a ring
-- around it, ending as a round skin. Returns set(diameter, progress 0-1,
-- oval) to reshape it (oval: how lopsided, 0 = round).
local CORNMEAL = Color3.fromRGB(236, 196, 92)
local function doughVisual(folder: Instance, at: CFrame): (number, number, number) -> ()
	local rng = Random.new()
	local dough = Config.IngredientColors.Dough
	-- The body: an ellipsoid sunk halfway into the table, so you see its top half.
	local body = localPart(folder, "Dough", Vector3.new(1, 1, 1), dough, Enum.Material.SmoothPlastic)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = body
	-- The raised edge, as short segments around the rim.
	local rim = {}
	for _ = 1, 22 do
		table.insert(rim, localPart(folder, "Rim", Vector3.new(0.3, 0.08, 0.08), dough:Lerp(Color3.fromRGB(205, 185, 140), 0.35), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder))
	end
	-- Cornmeal stuck to the top (positions on a unit disc).
	local specks = {}
	for _ = 1, 16 do
		local a, r = rng:NextNumber(0, math.pi * 2), math.sqrt(rng:NextNumber()) * 0.85
		table.insert(specks, { part = localPart(folder, "Speck", Vector3.new(0.01, 0.06, 0.06), CORNMEAL, Enum.Material.Sand, Enum.PartType.Cylinder), u = math.cos(a) * r, v = math.sin(a) * r })
	end
	-- The pile it started on, and the cornmeal it pushes out into a ring.
	local pile = localPart(folder, "CornmealPile", Vector3.new(0.012, 1.8, 1.6), CORNMEAL, Enum.Material.Sand, Enum.PartType.Cylinder)
	pile.CFrame = at * CFrame.new(0, 0.006, 0) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0) * Pizza3D.FLAT
	local ring = {}
	for i = 1, 20 do
		local w = rng:NextNumber(0.4, 0.8)
		table.insert(ring, {
			part = localPart(folder, "Cornmeal", Vector3.new(0.01, w, w * rng:NextNumber(0.35, 0.6)), CORNMEAL:Lerp(Color3.fromRGB(245, 215, 130), rng:NextNumber(0, 0.5)), Enum.Material.Sand, Enum.PartType.Cylinder),
			a = (i / 20) * math.pi * 2 + rng:NextNumber(-0.12, 0.12),
			out = rng:NextNumber(0, 0.25),
			y = 0.008 + i * 0.0007, -- each a hair higher, so none z-fight
		})
	end
	local yaw = rng:NextNumber(0, math.pi * 2)
	local lastT = 0
	return function(d: number, t: number, oval: number)
		-- It gets turned a little with every press.
		yaw += (t - lastT) * 4
		lastT = t
		local spin = CFrame.Angles(0, yaw, 0)
		local sx, sz = d * (1 + oval), d * (1 - oval)
		-- A tall dome at first, nearly flat at the end.
		local height = 0.16 + 0.74 * (1 - t) ^ 2.5
		body.Size = Vector3.new(sx, height, sz)
		body.CFrame = at * spin
		-- The edge rises once it's pressed out.
		local lip = math.clamp((t - 0.25) / 0.35, 0, 1)
		for i, seg in rim do
			local a = (i / #rim) * math.pi * 2
			local p = Vector3.new(math.cos(a) * sx / 2 * 0.95, 0, math.sin(a) * sz / 2 * 0.95)
			local tangent = Vector3.new(-math.sin(a) * sx, 0, math.cos(a) * sz).Unit
			local thick = 0.04 + 0.05 * lip
			seg.Size = Vector3.new(math.pi * d / #rim * 1.25, thick, thick)
			seg.Transparency = if lip > 0 then 0 else 1
			seg.CFrame = at * spin * CFrame.fromMatrix(p + Vector3.new(0, thick * 0.45, 0), tangent, Vector3.yAxis)
		end
		for _, s in specks do
			local top = height / 2 * math.sqrt(math.max(0, 1 - s.u * s.u - s.v * s.v))
			s.part.CFrame = at * spin * CFrame.new(s.u * sx / 2, top + 0.004, s.v * sz / 2) * Pizza3D.FLAT
		end
		for _, r in ring do
			local x, z = math.cos(r.a) * (sx / 2 + 0.15 + r.out), math.sin(r.a) * (sz / 2 + 0.15 + r.out)
			r.part.CFrame = at * spin * CFrame.new(x, r.y, z) * CFrame.Angles(0, math.pi / 2 - r.a, 0) * Pizza3D.FLAT -- long side along the ring
		end
	end
end

---------------------------------------------------------------------------
-- Stretch (dough table): pick a size, then hit the green zone as a marker
-- sweeps the timing bar. The zone jumps somewhere new (and changes width)
-- after every hit; yellow and misses cost score and stretch less.
---------------------------------------------------------------------------
local function dough(data: any, finish: Finish, cancel: Cancel)
	local ctx = open(data, cancel)
	if not ctx then
		return
	end
	local ws, body = ctx.ws, ctx.body
	local D = Config.Dough
	local skins = if type(data.skins) == "table" then data.skins else {}
	-- The dough ball (about 6" across) eases toward its new shape after every press.
	local BALL = 1.0
	local setShape = doughVisual(ctx.folder, ws.frame)
	local diameter, progress, sloppy = BALL, 0, 0
	local shownD, shownT = BALL, 0
	setShape(BALL, 0, 0.06)
	ctx.track(RunService.RenderStepped:Connect(function(dt)
		local k = math.min(1, dt * 10)
		shownD += (diameter - shownD) * k
		shownT += (progress - shownT) * k
		-- Lopsided while it's being worked; the sloppier the presses, the more it stays that way.
		setShape(shownD, shownT, 0.06 * (1 - shownT) + 0.05 * sloppy)
	end))

	local function stretch(size: string)
		clearBody(body)
		local presses = D.Presses[size] or 8
		local targetD = Config.PizzaDiameter[size] or 2.4
		sizeChip(body, size, 1)
		-- What the last press scored (blank until the first one).
		local feedback = Ui.chip("", C.Tile, C.White, {
			AutomaticSize = Enum.AutomaticSize.None,
			Size = UDim2.fromOffset(104, 30),
			TextXAlignment = Enum.TextXAlignment.Center,
			BackgroundTransparency = 1,
			LayoutOrder = 2,
			Parent = body,
		})
		feedback.TextSize = S.Body
		-- The timing gauge lives in the strip, below the dough (nothing covers the work).
		local gauge = Ui.box(C.Tile, { Size = UDim2.fromOffset(360, 30), LayoutOrder = 3, Parent = body })
		local gaugeStroke = Ui.new("UIStroke", { Color = C.Ink, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = gauge })
		for i = 1, 9 do
			Ui.box(C.Line, { Position = UDim2.fromScale(i / 10, 0), Size = UDim2.new(0, 1, 1, 0), Parent = gauge })
		end
		local yellow = Ui.box(C.Gold, { AnchorPoint = Vector2.new(0.5, 0), ZIndex = 2, Parent = gauge })
		local green = Ui.box(C.Green, { AnchorPoint = Vector2.new(0.5, 0), ZIndex = 3, Parent = gauge })
		local marker = Ui.box(C.White, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(0, 5, 1, 12), ZIndex = 4, Parent = gauge })
		Ui.new("UIStroke", { Color = C.Ink, Thickness = 1, Parent = marker })
		-- One square per press, coloured by how it went.
		local record = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 14), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 4, Parent = body }, {
			Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		local squares: { Frame } = {}
		for i = 1, presses do
			squares[i] = Ui.box(C.Tile, { Size = UDim2.fromOffset(12, 12), LayoutOrder = i, Parent = record }, { Ui.new("UIStroke", { Color = C.Line, Thickness = 1 }) })
		end
		local button = actionButton(body, "Stretch", 5, 150, KEY_HINT)

		local rng = Random.new()
		local center, width = 0.5, 0.1
		local function placeZone()
			width = rng:NextNumber(D.GreenWidth[1], D.GreenWidth[2])
			local half = width / 2 + D.Yellow
			local new = center
			for _ = 1, 12 do -- somewhere new, well clear of where it was
				new = rng:NextNumber(half, 1 - half)
				if math.abs(new - center) > 0.2 then
					break
				end
			end
			center = new
			green.Position = UDim2.fromScale(center, 0)
			green.Size = UDim2.fromScale(width, 1)
			yellow.Position = UDim2.fromScale(center, 0)
			yellow.Size = UDim2.fromScale(width + D.Yellow * 2, 1)
		end
		placeZone()

		local hits = {}
		local t, speed, pos = 0, 2.4, 0.5
		local done = false
		ctx.track(RunService.RenderStepped:Connect(function(dt)
			t += dt * speed
			pos = 0.5 + 0.5 * math.sin(t)
			marker.Position = UDim2.fromScale(pos, 0.5)
		end))

		local cooldown = false
		local function press()
			if cooldown or done then
				return
			end
			cooldown = true
			task.delay(0.35, function()
				cooldown = false
			end)
			local off = math.abs(pos - center)
			local q, color, text
			if off <= width / 2 then
				q, color, text = 1, C.Green, "PERFECT"
			elseif off <= width / 2 + D.Yellow then
				q, color, text = D.YellowScore, C.Gold, string.format("YELLOW -%d%%", math.floor((1 - D.YellowScore) * 100 + 0.5))
			else
				q, color, text = D.MissScore, C.Red, "MISS -100%"
			end
			feedback.Text = text
			feedback.BackgroundColor3 = color
			feedback.BackgroundTransparency = 0
			feedback.TextColor3 = if color == C.Gold then C.Ink else C.White
			gaugeStroke.Color = color
			TweenService:Create(gaugeStroke, TweenInfo.new(0.4), { Color = C.Ink }):Play()
			table.insert(hits, q)
			local square = squares[#hits]
			if square then
				square.BackgroundColor3 = color
			end
			-- Press it out toward the chosen size; sloppy presses leave it undersized and lopsided.
			local growth = math.max(q, D.MissGrowth)
			diameter = math.min(targetD, diameter + (targetD - BALL) / presses * growth)
			progress = #hits / presses
			sloppy += (1 - q) / presses
			speed += 0.25
			if #hits >= presses then
				done = true
				task.delay(0.6, function()
					if active then
						Minigames3D.Close()
						finish({ hits = hits, size = size })
					end
				end)
			else
				placeZone()
			end
		end
		button.Activated:Connect(press)
		bindPress(ctx, press)
	end

	-- Step 1: choose what size to prep (shows what's already on the racks).
	sizeTiles(body, skins, false, stretch)
end

---------------------------------------------------------------------------
-- Sauce (dough table): pick a skin off the racks, then spread sauce with the
-- spoodle (it never runs dry). Scored on coverage out to the sauce line and on
-- keeping the rim clean.
---------------------------------------------------------------------------
local function sauce(data: any, finish: Finish, cancel: Cancel)
	local ctx = open(data, cancel)
	if not ctx then
		return
	end
	local ws, body, holding = ctx.ws, ctx.body, ctx.holding
	local SC = Config.Sauce

	local function spread(size: string)
		clearBody(body)
		local d = Config.PizzaDiameter[size] or 2.4
		local R = d / 2
		local sauceR = Config.SauceRadius(size)
		local pizza = Pizza3D.new(ws.frame * CFrame.new(0, 0.06, 0), d, ctx.folder)
		sizeChip(body, size, 1)
		local doneBtn = actionButton(body, "Done", 2, 130)
		-- The spoodle: a flat-bottomed ladle, its handle angled up toward you
		local bowl = localPart(ctx.folder, "Spoodle", Vector3.new(0.08, SC.SpoodleRadius * 2, SC.SpoodleRadius * 2), STEEL, Enum.Material.Metal, Enum.PartType.Cylinder)
		local handle = localPart(ctx.folder, "SpoodleHandle", Vector3.new(0.06, 0.06, 1.3), STEEL, Enum.Material.Metal)
		local grip = localPart(ctx.folder, "SpoodleGrip", Vector3.new(0.09, 0.09, 0.45), Color3.fromRGB(200, 30, 30), Enum.Material.Plastic)

		local cells = table.create(SC.Rings * SC.Sectors, 0)
		local cellPos = {}
		for ring = 1, SC.Rings do
			for sector = 1, SC.Sectors do
				local rr = (ring - 0.5) / SC.Rings * sauceR
				local a = (sector - 0.5) / SC.Sectors * math.pi * 2
				table.insert(cellPos, Vector2.new(math.cos(a) * rr, math.sin(a) * rr))
			end
		end
		local rim = 0
		local splats = 0
		local lastSplat = Vector2.new(1e9, 0)
		local sr = SC.SpoodleRadius
		ctx.track(RunService.RenderStepped:Connect(function(dt)
			local hit, x, z = ws:pointer(0.15)
			if not hit then
				return
			end
			local r = math.sqrt(x * x + z * z)
			if r > R + 0.6 then
				local k = (R + 0.6) / r
				x, z, r = x * k, z * k, R + 0.6
			end
			local p = ws:at(x, 0.16, z)
			bowl.CFrame = CFrame.new(p) * Pizza3D.FLAT
			local handleEnd = p + ws.toWorker * 0.9 + Vector3.new(0, 0.7, 0)
			handle.CFrame = CFrame.lookAt((p + handleEnd) / 2, handleEnd)
			grip.CFrame = CFrame.lookAt(handleEnd, handleEnd + (handleEnd - p).Unit)
			if not holding() then
				return
			end
			local amount = SC.PourRate * dt
			-- Whatever part of the spoodle hangs past the sauce line puts sauce on the rim.
			local over = if r > R + sr then 1 else math.clamp((r + sr - sauceR) / (2 * sr), 0, 1)
			rim += amount * over
			if over < 1 then
				local here = Vector2.new(x, z)
				for i, c in cellPos do
					if (c - here).Magnitude <= sr then
						cells[i] += amount * (1 - over)
					end
				end
			end
			local here = Vector2.new(x, z)
			if (here - lastSplat).Magnitude > 0.08 and r < R + 0.1 and splats < 400 then
				lastSplat = here
				splats += 1
				pizza:addSauce(x, z, sr)
			end
		end))
		doneBtn.Activated:Connect(function()
			Minigames3D.Close()
			finish({ size = size, sauce = { cells = cells, rim = rim } })
		end)
	end

	-- Step 1: which skin to sauce (go by the tickets).
	sizeTiles(body, if type(data.skins) == "table" then data.skins else {}, true, spread)
end

---------------------------------------------------------------------------
-- Cheese (make-line): hold to pour; the pour speeds up the longer you hold.
-- The portion's on the job aid card, not the screen.
---------------------------------------------------------------------------
local function cheese(data: any, finish: Finish, cancel: Cancel)
	local ctx = open(data, cancel)
	if not ctx then
		return
	end
	local ws, body, holding = ctx.ws, ctx.body, ctx.holding
	hideShared(data.visual, ctx.cleanup)
	local spec = if type(data.spec) == "table" then data.spec else { size = data.size }
	local pizza = Pizza3D.fromSpec(ws.frame * CFrame.new(0, 0.06, 0), spec, ctx.folder)
	local R = (Config.PizzaDiameter[spec.size] or 2.4) / 2
	local target = Config.CheesePortion[spec.size] or 6
	local rng = Random.new()

	sizeChip(body, tostring(spec.size), 1)
	-- The scale's read-out (ounces poured; the portion is on the cheese card).
	local readout = Ui.box(C.Ink, { Size = UDim2.fromOffset(140, 44), LayoutOrder = 2, Parent = body })
	local scale = Ui.text("0.0 OZ", F.Mono, S.Huge, { TextColor3 = C.Cream, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = readout })
	local doneBtn = actionButton(body, "Done", 3, 130)
	local spaceHeld = false
	bindSpace(function()
		spaceHeld = true
	end, function()
		spaceHeld = false
	end)
	local oz, held, lastShred, swirl, shreds = 0, 0, 0, 0, 0
	ctx.track(RunService.RenderStepped:Connect(function(dt)
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
		scale.Text = string.format("%.1f OZ", oz)
		-- Shreds fall from a spot circling over the pizza.
		lastShred += dt
		if lastShred > 0.025 and shreds < 220 then
			lastShred = 0
			shreds += 1
			local cx, cz = math.cos(swirl) * R * 0.45, math.sin(swirl) * R * 0.45
			local x, z = pizza:randomPoint(rng)
			local shred = localPart(ctx.folder, "Shred", Vector3.new(0.14, 0.03, 0.04), Config.IngredientColors.Cheese, Enum.Material.Sand)
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
-- Toppings (make-line): any toppings, no targets on screen (go by the order
-- screen and the portions card). Then put it on the ready rack, or load it straight away.
---------------------------------------------------------------------------
local function toppings(data: any, finish: Finish, cancel: Cancel)
	local ctx = open(data, cancel)
	if not ctx then
		return
	end
	local ws, body, holding = ctx.ws, ctx.body, ctx.holding
	hideShared(data.visual, ctx.cleanup)
	local spec = if type(data.spec) == "table" then data.spec else { size = data.size }
	local pizza = Pizza3D.fromSpec(ws.frame * CFrame.new(0, 0.06, 0), spec, ctx.folder)
	local R = (Config.PizzaDiameter[spec.size] or 2.4) / 2
	local list: { string } = if type(data.toppings) == "table" then data.toppings else Config.Toppings
	local out = if type(data.out) == "table" then data.out else {}
	local rng = Random.new()
	local counts: { [string]: number } = {}

	sizeChip(body, tostring(spec.size), 1)
	local selected: string? = nil
	for _, name in list do
		if not out[name] then
			selected = name
			break
		end
	end
	-- One tile per bin: its topping and how many are on the pizza (the name
	-- shows while you hover it). Empty bins can't be picked.
	local tiles: { [string]: { button: TextButton, count: TextLabel, stroke: UIStroke } } = {}
	local hovered: string? = nil
	local function refresh()
		for name, tile in tiles do
			local n = pizza:count(name)
			counts[name] = n
			tile.count.Text = if out[name] then "OUT" elseif hovered == name then string.upper(name) else tostring(n)
			tile.count.FontFace = if hovered == name and not out[name] then F.Label else F.Mono
			tile.count.TextSize = if hovered == name and not out[name] then S.Tiny else S.Label
			tile.stroke.Enabled = name == selected
			Ui.setButtonColor(tile.button, if name == selected then Color3.fromRGB(58, 53, 40) else C.Tile)
		end
	end
	for i, name in list do
		local b = Ui.flatButton("", "dark", { Size = UDim2.fromOffset(56, 54), LayoutOrder = 1 + i, Parent = body })
		if out[name] then
			b.BackgroundTransparency = 0.6
		end
		local ico = Icons.make(name, 20, b)
		ico.AnchorPoint = Vector2.new(0.5, 0)
		ico.Position = UDim2.new(0.5, 0, 0, 8)
		local count = Ui.text("0", F.Mono, S.Label, {
			TextColor3 = if out[name] then C.CreamDim else C.Cream,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, -5),
			Size = UDim2.new(1, 0, 0, 18),
			Parent = b,
		})
		local stroke = Ui.new("UIStroke", { Color = C.Gold, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Enabled = false, Parent = b })
		tiles[name] = { button = b, count = count, stroke = stroke }
		b.MouseEnter:Connect(function()
			hovered = name
			refresh()
		end)
		b.MouseLeave:Connect(function()
			if hovered == name then
				hovered = nil
				refresh()
			end
		end)
		b.Activated:Connect(function()
			if not out[name] then
				selected = name
				refresh()
			end
		end)
	end
	local pick = Ui.flatButton("", "ghost", { Size = UDim2.fromOffset(52, 54), LayoutOrder = 20, Parent = body })
	Ui.text("-5", F.Mono, S.Label, { TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 20), Parent = pick })
	Ui.text("PICK OFF", F.Label, S.Tiny, { TextColor3 = C.CreamDim, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 14), Parent = pick })
	pick.Activated:Connect(function()
		if selected then
			pizza:removeTopping(selected, 5)
			refresh()
		end
	end)
	Ui.rule(body, 21)
	local rackBtn = Ui.flatButton("To rack", "ghost", { Size = UDim2.fromOffset(92, 52), LayoutOrder = 22, Parent = body })
	local loadBtn = actionButton(body, "Load", 23, 110)
	loadBtn.Activated:Connect(function()
		Minigames3D.Close()
		if Loading.mode == "Pick" then
			-- It lands on the ready rack first; then we ask which order it's for.
			Loading.AskAfterTopping()
			finish({ counts = counts, load = false })
		else
			finish({ counts = counts, load = true })
		end
	end)
	rackBtn.Activated:Connect(function()
		Minigames3D.Close()
		finish({ counts = counts, load = false })
	end)
	refresh()

	-- A hand-sized scoop of the selected topping follows the pointer.
	local scoop = localPart(ctx.folder, "Scoop", Vector3.new(0.35, 0.12, 0.35), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	local acc = 0
	ctx.track(RunService.RenderStepped:Connect(function(dt)
		local hit, x, z = ws:pointer(0.2)
		local onPizza = hit ~= nil and math.sqrt(x * x + z * z) < R + 0.4
		scoop.Transparency = if onPizza then 0 else 1
		if hit then
			scoop.CFrame = CFrame.new(ws:at(x, 0.55, z))
			scoop.Color = if selected then Config.IngredientColors[selected] or scoop.Color else scoop.Color
		end
		if onPizza and holding() and selected then
			acc += dt
			while acc >= 0.1 do
				acc -= 0.1
				local jx, jz = x + rng:NextNumber(-0.18, 0.18), z + rng:NextNumber(-0.18, 0.18)
				local r = math.sqrt(jx * jx + jz * jz)
				local maxR = R * 0.82
				if r > maxR then
					jx, jz = jx * maxR / r, jz * maxR / r
				end
				pizza:addTopping(selected, jx, jz, rng)
				refresh()
			end
		else
			acc = 0
		end
	end))
end

---------------------------------------------------------------------------
-- Cut & Box: the oven tender clicked a pizza at the oven exit. Click the box
-- to put it in (click another box to move it), pop any bubbles, rock the
-- blade through even cuts, season the crust by tracing it, close the lid.
---------------------------------------------------------------------------
local function cut(data: any, finish: Finish, cancel: Cancel)
	local ctx = open(data, cancel)
	if not ctx then
		return
	end
	local ws, body, cleanup, holding = ctx.ws, ctx.body, ctx.cleanup, ctx.holding
	hideShared(data.visual, cleanup)
	-- The wide view takes in the oven exits and every box; putting it in a box closes in on it.
	ws:resetView()
	table.insert(cleanup, function()
		ws:resetView()
	end)
	local cuts = tonumber(data.cuts) or 4
	local spec = if type(data.spec) == "table" then data.spec else { size = data.size, baked = true }
	local d = Config.PizzaDiameter[spec.size] or 2.4
	local R = d / 2
	local top = 0.12
	local station = data.station :: BasePart
	-- Which pizza this is, at the start of the strip: "#4 LARGE PEPPERONI" or "LARGE EXTRA".
	local title = if data.ticket then string.format("#%s %s %s", tostring(data.ticket), tostring(data.size), tostring(data.pizza)) else tostring(data.size) .. " extra"
	local function titleChip(order: number)
		local chip = Ui.chip(title, C.Cream, C.Ink, { Size = UDim2.fromOffset(0, 28), LayoutOrder = order, Parent = body })
		chip.TextSize = S.Body
	end
	local function note(text: string, order: number)
		Ui.text(string.upper(text), F.Label, S.Body, { TextColor3 = C.CreamDim, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 28), LayoutOrder = order, Parent = body })
	end

	-- The open boxes on the table (from the station art).
	local boxes: { [string]: BasePart } = {}
	local boxParts: { Instance } = {}
	for _, p in station:GetDescendants() do
		if p:IsA("BasePart") and type(p:GetAttribute("BoxSize")) == "string" then
			boxes[p:GetAttribute("BoxSize") :: string] = p
			table.insert(boxParts, p)
		end
	end
	local outline = Instance.new("Highlight")
	outline.FillTransparency = 1
	outline.OutlineColor = Color3.new(1, 1, 1)
	outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	outline.Enabled = false
	outline.Parent = ctx.folder

	-- Our copy of the pizza, lifted off the end of the belt it came from.
	local exitPos = if typeof(data.exitPos) == "Vector3" then data.exitPos else ws:at(-7, 0.4, 0)
	local rot = ws.frame.Rotation
	local pizza = Pizza3D.fromSpec(CFrame.new(exitPos + Vector3.new(0, 0.3, 0)) * rot, spec, ctx.folder)

	local popped = 0
	local angles: { number } = {}
	local chosenBox = ""
	local center = exitPos -- world center of the pizza once it's in its box
	local stage = "box" -- "box" | "cut" | "season" | "close"
	local stepConn: RBXScriptConnection? = nil
	local function newPhase()
		clearBody(body)
		if stepConn then
			stepConn:Disconnect()
			stepConn = nil
		end
		ContextActionService:UnbindAction(ACTION)
	end
	local function rayAt(include: { Instance }): RaycastResult?
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = include
		local ray = Workstation.pointerRay()
		return workspace:Raycast(ray.Origin, ray.Direction * 80, params)
	end
	-- Where the pointer is over the pizza: local (x, z) from its center, and the world point.
	local function overPizza(): (Vector3?, number, number)
		local hit = ws:pointer(center.Y - ws.frame.Position.Y + top)
		if not hit then
			return nil, 0, 0
		end
		local offset = hit - center
		return hit, offset:Dot(ws.right), offset:Dot(ws.toWorker)
	end

	-- Bubbles sit on the pizza; they move with it if it's moved to another box.
	local bubbleData = if type(data.bubbles) == "table" then data.bubbles else {}
	local bubbleParts: { BasePart } = {}
	local function placeBubbles()
		for _, b in bubbleParts do
			b:Destroy()
		end
		table.clear(bubbleParts)
		for i, b in bubbleData do
			if i > #bubbleData - popped then
				break
			end
			local x, z = ((tonumber(b.x) or 0.5) - 0.5) * d * 0.8, ((tonumber(b.y) or 0.5) - 0.5) * d * 0.8
			local bubble = localPart(ctx.folder, "Bubble", Vector3.new(0.26, 0.26, 0.26), Color3.fromRGB(255, 235, 170), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
			bubble.CanQuery = true
			bubble.CFrame = CFrame.new(center + ws.right * x + ws.toWorker * z + Vector3.new(0, top + 0.08, 0))
			table.insert(bubbleParts, bubble)
		end
	end

	-- 4) CLOSE THE LID ------------------------------------------------------
	local function closeLid(season: any)
		newPhase()
		stage = "close"
		note("Closing", 1)
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
		-- Standing on edge (see BOX_FLAT) so the Front-face print reads right way up once shut.
		local lid = localPart(ctx.folder, "BoxLid", Vector3.new(bs, bs, 0.04), Color3.fromRGB(225, 200, 160), Enum.Material.Cardboard)
		local printed = Instance.new("SurfaceGui")
		printed.Face = Enum.NormalId.Front -- the printed outside: face-up once closed
		printed.CanvasSize = Vector2.new(200, 200)
		local brand = Instance.new("TextLabel")
		brand.Size = UDim2.fromScale(1, 1)
		brand.BackgroundColor3 = Color3.fromRGB(205, 168, 118)
		brand.BorderSizePixel = 0
		brand.FontFace = F.Heading
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
		angle.Parent = ctx.folder -- cleaned up with the minigame
		local pizzaShown = true
		local function placeLid()
			lid.CFrame = hinge * CFrame.Angles(math.rad(angle.Value), 0, 0) * CFrame.new(0, 0, -bs / 2) * BOX_FLAT
			-- The pizza (cut lines and toppings stand taller than the box walls) is
			-- shut inside from here on; hide it so nothing pokes through the lid.
			if pizzaShown and angle.Value < 12 then
				pizzaShown = false
				pizza:Destroy()
			end
		end
		placeLid()
		angle.Changed:Connect(placeLid)
		TweenService:Create(angle, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Value = 0 }):Play()
		task.delay(0.9, function()
			if active then
				Minigames3D.Close()
				finish({ angles = angles, popped = popped, box = chosenBox, season = season })
			end
		end)
	end

	-- 3) SEASON: trace the crust with the shaker -------------------------------
	local function seasonPhase()
		newPhase()
		stage = "season"
		note("Crust", 1)
		local status = Ui.text("0%", F.Mono, S.Title, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 28), LayoutOrder = 2, Parent = body })
		Ui.new("UIPadding", { PaddingRight = UDim.new(0, 8), Parent = status })
		local closeBtn = actionButton(body, "Close box", 3, 150)
		local shaker = localPart(ctx.folder, "Shaker", Vector3.new(0.6, 0.3, 0.3), Color3.fromRGB(235, 225, 190), Enum.Material.Plastic, Enum.PartType.Cylinder)
		local capPart = localPart(ctx.folder, "ShakerCap", Vector3.new(0.12, 0.32, 0.32), Color3.fromRGB(200, 40, 40), Enum.Material.Plastic, Enum.PartType.Cylinder)
		local n = Config.Cut.SeasonSectors
		local sectors = table.create(n, false)
		local onTime, offTime, specks, sinceSpeck = 0, 0, 0, 0
		local rng = Random.new()
		stepConn = RunService.RenderStepped:Connect(function(dt)
			local hit, x, z = overPizza()
			if not hit then
				return
			end
			-- Shaker held upside down over the pointer, tipped a little toward you.
			local up = CFrame.new(hit + Vector3.new(0, 0.55, 0)) * rot * CFrame.Angles(math.rad(-15), 0, 0) * CFrame.Angles(0, 0, math.rad(90))
			shaker.CFrame = up
			capPart.CFrame = up * CFrame.new(-0.33, 0, 0)
			if not holding() then
				return
			end
			local r = math.sqrt(x * x + z * z)
			local onCrust = r >= R * 0.8 and r <= R * 1.06
			if onCrust then
				onTime += dt
				local a = (math.atan2(z, x) + math.pi * 2) % (math.pi * 2)
				sectors[math.min(n, math.floor(a / (math.pi * 2) * n) + 1)] = true
			else
				offTime += dt
			end
			sinceSpeck += dt
			if sinceSpeck > 0.03 and specks < 300 then
				sinceSpeck = 0
				specks += 1
				local speck = localPart(ctx.folder, "Seasoning", Vector3.new(0.04, 0.02, 0.04), if rng:NextNumber() < 0.5 then Color3.fromRGB(120, 40, 25) else Color3.fromRGB(70, 110, 50))
				speck.CFrame = CFrame.new(hit + ws.right * rng:NextNumber(-0.06, 0.06) + ws.toWorker * rng:NextNumber(-0.06, 0.06) + Vector3.new(0, 0.02, 0))
			end
			local covered = 0
			for _, s in sectors do
				if s then
					covered += 1
				end
			end
			status.Text = string.format("%d%%", math.floor(covered / n * 100 + 0.5))
		end)
		closeBtn.Activated:Connect(function()
			if stage ~= "season" then
				return
			end
			shaker:Destroy()
			capPart:Destroy()
			closeLid({ sectors = sectors, off = if onTime + offTime > 0 then offTime / (onTime + offTime) else 0 })
		end)
	end

	-- 2) CUT ----------------------------------------------------------------
	local function cutPhase()
		newPhase()
		stage = "cut"
		outline.Enabled = false
		for _, b in bubbleParts do
			b:Destroy()
		end
		table.clear(bubbleParts)
		titleChip(1)
		-- One square per cut, filled as they're made.
		local record = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, Parent = body }, {
			Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		local squares: { Frame } = {}
		for i = 1, cuts do
			squares[i] = Ui.box(C.Tile, { Size = UDim2.fromOffset(14, 14), LayoutOrder = i, Parent = record }, { Ui.new("UIStroke", { Color = C.Line, Thickness = 1 }) })
		end
		local button = actionButton(body, "Cut", 3, 130, KEY_HINT)
		local bladeLen = d * 1.12
		local blade = localPart(ctx.folder, "Rocker", Vector3.new(bladeLen, 0.24, 0.035), STEEL, Enum.Material.Metal)
		blade.Reflectance = 0.25
		local handles = {}
		for _, sx in { -1, 1 } do
			table.insert(handles, { part = localPart(ctx.folder, "Handle", Vector3.new(0.45, 0.13, 0.13), Color3.fromRGB(30, 30, 30), Enum.Material.Plastic, Enum.PartType.Cylinder), side = sx })
		end
		local yaw = 0
		local phase, phaseT, cutYaw = "hover", 0, 0
		stepConn = RunService.RenderStepped:Connect(function(dt)
			local height, roll = 0.55, 0
			if phase == "hover" then
				yaw = (yaw + dt * Config.Cut.SpinSpeed) % 360
			else
				phaseT += dt
				local p = phaseT / Config.Cut.CutTime
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
			task.delay(Config.Cut.CutTime / 2, function()
				if active then
					pizza:addCut(cutYaw)
				end
			end)
			local square = squares[#angles]
			if square then
				square.BackgroundColor3 = C.Cream
			end
			if #angles >= cuts then
				task.delay(Config.Cut.CutTime + 0.25, function()
					if active then
						blade:Destroy()
						for _, h in handles do
							h.part:Destroy()
						end
						seasonPhase()
					end
				end)
			end
		end
		button.Activated:Connect(press)
		bindPress(ctx, press)
	end

	-- 1) BOX IT: click the right box (and another one to move it) --------------
	local function putIn(size: string)
		local box = boxes[size]
		if not box or stage ~= "box" then
			return
		end
		local first = chosenBox == ""
		chosenBox = size
		local landing = box.Position + Vector3.new(0, 0.025 + 0.06, 0)
		center = landing - Vector3.new(0, 0.06, 0)
		ws:closeUp(center)
		TweenService:Create(pizza.crust, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { CFrame = CFrame.new(landing) * rot * Pizza3D.FLAT }):Play()
		placeBubbles()
		if first then
			newPhase()
			-- Wrong box? Clicking another one moves it (the tip says so).
			titleChip(1)
			if #bubbleData > 0 then
				note("Pop the bubbles", 2)
			end
			local start = actionButton(body, "Cut", 3, 130, KEY_HINT)
			start.Activated:Connect(cutPhase)
			bindSpace(cutPhase)
		end
	end
	ctx.track(RunService.RenderStepped:Connect(function()
		if stage ~= "box" then
			return
		end
		local result = rayAt(boxParts)
		outline.Adornee = if result then result.Instance else nil
		outline.Enabled = result ~= nil
	end))
	ctx.track(UserInputService.InputBegan:Connect(function(input, processed)
		if stage ~= "box" or not isPlayClick(input, processed) then
			return
		end
		local bubbleHit = if #bubbleParts > 0 then rayAt(bubbleParts) else nil
		if bubbleHit and bubbleHit.Instance.Name == "Bubble" then
			local hitPart = bubbleHit.Instance :: BasePart
			hitPart.Name = "Popped"
			popped += 1
			local i = table.find(bubbleParts, hitPart)
			if i then
				table.remove(bubbleParts, i)
			end
			TweenService:Create(hitPart, TweenInfo.new(0.15), { Size = Vector3.new(0.05, 0.05, 0.05) }):Play()
			task.delay(0.16, function()
				hitPart:Destroy()
			end)
			return
		end
		local result = rayAt(boxParts)
		local size = result and result.Instance:GetAttribute("BoxSize")
		if type(size) == "string" then
			putIn(size)
		end
	end))
	titleChip(1)
	note("Click a box", 2)
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
