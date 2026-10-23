--!strict
-- Builds the whole map from code so the place file needs no manual building.
-- Swap pieces for real models later; everything gameplay-related is found by
-- name/attribute, not by look.
--
-- Store layout follows a real delivery-first store's map (`docs/floorplan.svg`):
-- an L-shaped lobby, production behind dough show glass, ovens behind the
-- makers feeding the cut table, dispatch by the back door, and a parking lot
-- out back for delivery cars.

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Style = require(game:GetService("ReplicatedStorage").Shared.Style)
local StationArt = require(script.Parent.StationArt)

local MapBuilder = {}

local BRAND = Config.Brand

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	-- Shape first: changing Shape can resize the part, so Size must come after.
	if props.Shape then
		p.Shape = props.Shape
	end
	for key, value in props do
		if key ~= "Parent" and key ~= "Shape" then
			(p :: any)[key] = value
		end
	end
	p.Parent = props.Parent
	return p
end

local function label(adornee: BasePart, text: string, offsetY: number, size: UDim2?): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = size or UDim2.fromOffset(200, 50)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 80
	gui.LightInfluence = 0
	local tl = Instance.new("TextLabel")
	tl.Name = "Text"
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.FontFace = Style.Font.Heading
	tl.TextScaled = true
	tl.TextColor3 = Color3.new(1, 1, 1)
	tl.TextStrokeTransparency = 0.3
	tl.Text = text
	tl.Parent = gui
	gui.Adornee = adornee
	gui.Parent = adornee
	return gui
end

local function prompt(parentPart: BasePart, action: string, object: string, holdTime: number?): ProximityPrompt
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = action
	pp.ObjectText = object
	pp.HoldDuration = holdTime or 0
	pp.MaxActivationDistance = 8
	pp.RequiresLineOfSight = false
	pp.Parent = parentPart
	return pp
end

local function spot(parent: Instance, name: string, cf: CFrame)
	part({
		Name = name,
		Size = Vector3.new(2, 1, 2),
		CFrame = cf,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		Parent = parent,
	})
end

-- SurfaceGui text helper for signs and screens.
local function screenText(target: BasePart, face: Enum.NormalId, text: string, color: Color3, bg: Color3?, font: Enum.Font?, canvas: Vector2?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.LightInfluence = 0
	if canvas then
		gui.CanvasSize = canvas
	else
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
	end
	local tl = Instance.new("TextLabel")
	tl.Name = "Text"
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundColor3 = bg or Color3.new(0, 0, 0)
	tl.BackgroundTransparency = if bg then 0 else 1
	tl.BorderSizePixel = 0
	tl.FontFace = if font == Enum.Font.Code then Style.Font.Mono else Style.Font.Heading
	tl.TextScaled = true
	tl.TextColor3 = color
	tl.Text = text
	tl.Parent = gui
	gui.Parent = target
	return tl
end

-- Builds one store, after the user's floor plan v4.1 (`docs/floorplan.svg`,
-- traced from a real store's map), widened after their playtest for roomier
-- walkways: 48 x 90 studs (x -24..24, z -48..42). Front (entrance) faces +Z of `origin`. An L-shaped
-- lobby (no furniture for now), open to the kitchen past the counter's end;
-- the carryout counter facing the side lobby; production as an L
-- behind the dough show glass (stretch table along the side, sauce in the
-- angled corner, makeline along the front wall) with the ovens right behind
-- the makers, the cut table at the oven exits, dispatch behind it; walk-in,
-- office and dish area in back (no restrooms). Returns the Model.
function MapBuilder.BuildShop(origin: CFrame, shopName: string, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "Shop"
	local stations = Instance.new("Folder")
	stations.Name = "Stations"
	stations.Parent = model
	local spots = Instance.new("Folder")
	spots.Name = "Spots"
	spots.Parent = model
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = model

	local function at(x: number, y: number, z: number): CFrame
		return origin * CFrame.new(x, y, z)
	end
	-- A block from (x0, y0, z0) to (x1, y1, z1), shop-local.
	local function box(name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, material: Enum.Material?, extra: { [string]: any }?): Part
		local props: { [string]: any } = {
			Name = name,
			Size = Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)),
			CFrame = at((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
			Color = color,
			Material = material or Enum.Material.SmoothPlastic,
			Parent = decor,
		}
		for k, v in extra or {} do
			props[k] = v
		end
		return part(props)
	end

	local FACE_RIGHT = CFrame.Angles(0, -math.pi / 2, 0) -- worker toward +X
	local FACE_LEFT = CFrame.Angles(0, math.pi / 2, 0) -- worker toward -X

	local HW, FRONT, BACK, h = 24, 42, -48, 14 -- half width, front and back walls, wall height
	local wallColor = Color3.fromRGB(242, 242, 238) -- white tile inside (brick outside, see Finishes)
	local tile = Color3.fromRGB(246, 246, 243) -- white subway tile on the walls the public sees
	local glass = Color3.fromRGB(160, 205, 235)
	local steel = Color3.fromRGB(196, 200, 206)
	local wood = Color3.fromRGB(150, 108, 70)
	local glassProps = { Transparency = 0.55, Material = Enum.Material.Glass, CanCollide = true }
	-- The front of house moved toward the ovens by the ready rack's width when
	-- the Load station went (the user, 2026-10-23): the carryout counter, the
	-- stretch table, the sauce corner, the makeline and the walls, signs and
	-- lobby edge that go with them. Everything else stays put.
	local S = 4.7

	-- Floors: red quarry tile in the kitchen, wood-look planks in the L-shaped lobby.
	box("Floor", -HW, HW, 0, 1, BACK, FRONT, Color3.fromRGB(128, 66, 52), Enum.Material.CeramicTiles)
	box("LobbyFloor", -HW, HW, 1, 1.05, 28.9, FRONT, wood, Enum.Material.WoodPlanks, { CanCollide = false })
	box("LobbyFloor", -HW, -8.4 + S, 1, 1.05, -9.9, 28.9, wood, Enum.Material.WoodPlanks, { CanCollide = false }) -- the side lobby, up to the counter and the dough show glass
	box("LobbyFloor", -8.4 + S, -2.4 + S, 1, 1.05, 23.2, 28.9, wood, Enum.Material.WoodPlanks, { CanCollide = false }) -- the angled corner (the kitchen half is under the sauce table)
	box("Mat", -23.3, -18.7, 1.05, 1.1, 38.5, 41.6, BRAND.Charcoal, Enum.Material.Carpet, { CanCollide = false })

	-- Outside walls, back door, storefront with a door at each front corner.
	for _, sx in { -1, 1 } do
		box("WallSide", sx * HW - 0.5, sx * HW + 0.5, 1, 1 + h, BACK, FRONT, wallColor, Enum.Material.CeramicTiles)
		box("WallStripe", sx * HW - 0.55, sx * HW + 0.55, 1, 3, BACK, FRONT, BRAND.Charcoal)
	end
	box("WallBack", -HW, -3.6, 1, 1 + h, BACK - 0.5, BACK + 0.5, wallColor, Enum.Material.CeramicTiles)
	box("WallBack", 1.6, HW, 1, 1 + h, BACK - 0.5, BACK + 0.5, wallColor, Enum.Material.CeramicTiles)
	box("Lintel", -3.6, 1.6, 9, 1 + h, BACK - 0.5, BACK + 0.5, wallColor, Enum.Material.Plaster)
	local driverSign = part({ Name = "DriverDoorSign", Size = Vector3.new(6, 1, 0.1), CFrame = at(-1, 9.6, BACK + 0.6), Color = Color3.fromRGB(46, 160, 90), Parent = decor })
	screenText(driverSign, Enum.NormalId.Back, "DRIVERS - CARS OUT BACK", Color3.new(1, 1, 1))
	box("KneeWall", -18.5, 18.5, 1, 3, FRONT - 0.5, FRONT + 0.5, BRAND.Charcoal)
	box("Storefront", -18.5, 18.5, 3, 11, FRONT - 0.2, FRONT + 0.2, glass, nil, glassProps)
	for _, sx in { -1, 1 } do
		box("DoorFrame", sx * 18.5 - 0.3, sx * 18.5 + 0.3, 1, 11, FRONT - 0.4, FRONT + 0.4, BRAND.Charcoal, Enum.Material.Metal)
		box("DoorFrame", sx * 23.5 - 0.3, sx * HW, 1, 11, FRONT - 0.4, FRONT + 0.4, BRAND.Charcoal, Enum.Material.Metal)
		box("Transom", sx * 18.5, sx * 23.5, 9.6, 11, FRONT - 0.2, FRONT + 0.2, glass, nil, glassProps)
		part({ Name = "Awning", Size = Vector3.new(18, 0.3, 3.4), CFrame = at(sx * 9.25, 11.6, FRONT + 1.5) * CFrame.Angles(math.rad(-18), 0, 0), Color = BRAND.Red, Material = Enum.Material.Fabric, Parent = decor })
	end
	box("Header", -HW, HW, 11, 1 + h, FRONT - 0.5, FRONT + 0.5, BRAND.Red)
	box("Roof", -HW - 0.5, HW + 0.5, 1 + h, 2 + h, BACK - 0.5, FRONT + 0.5, Color3.fromRGB(70, 70, 75))
	box("Parapet", -HW - 0.5, HW + 0.5, 1 + h, 3.5 + h, FRONT, FRONT + 0.5, BRAND.Red)
	-- Brand sign on the header: round logo + name
	part({ Name = "Logo", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 4.4, 4.4), CFrame = at(-14, 15.6, FRONT + 0.9) * CFrame.Angles(0, math.pi / 2, 0), Color = BRAND.Cream, Parent = decor })
	part({ Name = "LogoSlice", Size = Vector3.new(2.1, 2.1, 0.2), CFrame = at(-14, 15.6, FRONT + 1.15) * CFrame.Angles(0, 0, math.rad(45)), Color = BRAND.Gold, Parent = decor })
	part({ Name = "LogoPepperoni", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 0.7, 0.7), CFrame = at(-14, 15.7, FRONT + 1.3) * CFrame.Angles(0, math.pi / 2, 0), Color = BRAND.Red, Parent = decor })
	local sign = part({ Name = "Sign", Size = Vector3.new(24, 3.4, 0.4), CFrame = at(3, 15.6, FRONT + 0.9), Color = BRAND.Red, Parent = decor })
	local signText = screenText(sign, Enum.NormalId.Back, string.upper(shopName), Color3.new(1, 1, 1), nil, Enum.Font.FredokaOne, Vector2.new(720, 100))
	signText.Name = "ShopName"
	local service = part({ Name = "ServiceSign", Size = Vector3.new(11, 1.2, 0.1), CFrame = at(0, 10.5, FRONT + 0.3), Color = BRAND.Charcoal, Parent = decor })
	screenText(service, Enum.NormalId.Back, "CARRYOUT  |  DELIVERY", BRAND.Gold)

	-- Light panels in the drop ceiling: warm over the lobby, neutral white in the
	-- kitchen; with Future lighting they cast soft shadows.
	for _, pos in { Vector2.new(-16, 34), Vector2.new(2, 35), Vector2.new(16, 35), Vector2.new(-17, 14), Vector2.new(-17, -3), Vector2.new(0, 21), Vector2.new(13, 21), Vector2.new(-2, 8), Vector2.new(10, 1), Vector2.new(7, -11), Vector2.new(-1, -25), Vector2.new(-14, -30), Vector2.new(-14, -16), Vector2.new(12, -40), Vector2.new(-10, -42) } do
		local lobby = pos.Y > 28.9 or (pos.X < -8.4 + S and pos.Y > -9.9)
		local panel = part({ Name = "LightPanel", Size = Vector3.new(6, 0.2, 3), CFrame = at(pos.X, h + 0.38, pos.Y), Color = Color3.fromRGB(255, 252, 240), Material = Enum.Material.Neon, CanCollide = false, Parent = decor })
		local light = Instance.new("SurfaceLight")
		light.Face = Enum.NormalId.Bottom
		light.Range = 18
		light.Brightness = if lobby then 1.1 else 1.5
		light.Angle = 120
		light.Shadows = true
		light.Color = if lobby then Color3.fromRGB(255, 226, 190) else Color3.fromRGB(255, 248, 236)
		light.Parent = panel
	end

	-- === Lobby ===
	-- Carryout counter facing the side lobby: the register (the ordering screen),
	-- a second POS, menu boards hanging above (no carryout warmer: orders wait
	-- on the carryout rack by the oven, the user, 2026-10-23). Its face is in
	-- line with the dough show's low wall beside the slap table (the user,
	-- 2026-10-21: "even with the slap table"). Code-built until the user picks
	-- a design for the new counter.
	box("Counter", -8.6 + S, -4.8 + S, 1, 5, -3.6, 9.9, BRAND.Charcoal)
	box("CounterFace", -8.65 + S, -8.6 + S, 2.8, 4, -3.6, 9.9, BRAND.Red)
	box("CounterTop", -8.8 + S, -4.6 + S, 5, 5.4, -3.8, 9.8, Color3.fromRGB(235, 235, 232), Enum.Material.Marble)
	StationArt.Build("Register", decor, at(-6.2 + S, 5.4, 3.0) * FACE_RIGHT)
	local menuItems = {
		{ "PIZZAS", "Build your own:\nsize + up to 3\ntoppings" },
		{ "SIZES", (string.gsub(table.concat(Config.Sizes, "\n"), "%a+", function(size)
			return string.format("%s $%d", size, Config.SizePrice[size])
		end)) },
		{ "TOPPINGS", table.concat(Config.Toppings, "\n") },
	}
	for i, item in menuItems do
		local board = part({ Name = "MenuScreen" .. i, Size = Vector3.new(0.3, 3.6, 4.2), CFrame = at(-9.2 + S, 10.7, 9.4 - (i - 1) * 4.5), Color = Color3.fromRGB(15, 15, 18), Parent = decor })
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Left -- -X: the side lobby
		gui.CanvasSize = Vector2.new(360, 300)
		gui.LightInfluence = 0
		local bg = Instance.new("Frame")
		bg.Size = UDim2.fromScale(1, 1)
		bg.BackgroundColor3 = if i == 1 then BRAND.Red else BRAND.Charcoal
		bg.BorderSizePixel = 0
		bg.Parent = gui
		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, 0, 0, 60)
		title.BackgroundTransparency = 1
		title.FontFace = Style.Font.Heading
		title.TextScaled = true
		title.TextColor3 = BRAND.Gold
		title.Text = item[1]
		title.Parent = bg
		local body = Instance.new("TextLabel")
		body.Position = UDim2.fromOffset(12, 66)
		body.Size = UDim2.new(1, -24, 1, -78)
		body.BackgroundTransparency = 1
		body.FontFace = Style.Font.LabelBold
		body.TextScaled = true
		body.TextColor3 = Color3.new(1, 1, 1)
		body.Text = item[2]
		body.Parent = bg
		gui.Parent = board
	end
	local orderHere = part({ Name = "OrderHere", Size = Vector3.new(0.1, 0.9, 4), CFrame = at(-9.2 + S, 9.6, 7.4), Color = BRAND.Red, Parent = decor })
	screenText(orderHere, Enum.NormalId.Left, "ORDER HERE", Color3.new(1, 1, 1))
	-- The side lobby's back wall. Past the counter's end the lobby is open to the
	-- kitchen (the user, 2026-10-23: no wall or staff door there).
	box("LobbyBackWall", -HW, -8.4 + S, 1, 1 + h, -10.3, -9.9, tile, Enum.Material.CeramicTiles)

	-- Order tracker TV on the right lobby wall (ShopService writes to it)
	local tracker = part({ Name = "TrackerScreen", Size = Vector3.new(0.3, 4.4, 8), CFrame = at(HW - 0.65, 9.5, 35), Color = Color3.fromRGB(10, 10, 12), Parent = decor })
	local trackerGui = Instance.new("SurfaceGui")
	trackerGui.Name = "Tracker"
	trackerGui.Face = Enum.NormalId.Left
	trackerGui.CanvasSize = Vector2.new(640, 352)
	trackerGui.LightInfluence = 0
	local trackerText = Instance.new("TextLabel")
	trackerText.Name = "Text"
	trackerText.Size = UDim2.fromScale(1, 1)
	trackerText.BackgroundColor3 = Color3.fromRGB(16, 20, 28)
	trackerText.BorderSizePixel = 0
	trackerText.Font = Enum.Font.GothamBold
	trackerText.TextSize = 22
	trackerText.RichText = true
	trackerText.TextColor3 = Color3.new(1, 1, 1)
	trackerText.TextXAlignment = Enum.TextXAlignment.Left
	trackerText.TextYAlignment = Enum.TextYAlignment.Top
	trackerText.Text = "ORDER TRACKER"
	trackerText.Parent = trackerGui
	trackerGui.Parent = tracker

	-- No lobby furniture for now (the user, 2026-10-23: booths, tables, chairs,
	-- the drink cooler, bench, plants and pendant lamps go; 3D models or
	-- existing assets come later).

	-- === Dough show walls ===
	-- Low wall (42") with sneeze-guard glass beside the stretch table, an angled
	-- piece at the corner, and the high wall (54") with glass behind the makeline.
	box("LowWall", -8.7 + S, -8.1 + S, 1, 5, 9.9, 23.2, tile, Enum.Material.CeramicTiles)
	box("WallCap", -8.8 + S, -8.0 + S, 5, 5.15, 9.8, 23.3, Color3.fromRGB(235, 235, 232), Enum.Material.Marble)
	box("SneezeGuard", -8.46 + S, -8.34 + S, 5.15, 7.15, 9.9, 23.2, glass, nil, { Transparency = 0.6, Material = Enum.Material.Glass })
	box("HighWall", -2.4 + S, HW, 1, 6.1, 28.3, 28.9, tile, Enum.Material.CeramicTiles)
	box("WallCap", -2.4 + S, HW, 6.1, 6.25, 28.2, 29.0, Color3.fromRGB(235, 235, 232), Enum.Material.Marble)
	box("SneezeGuard", -2.4 + S, HW, 6.25, 7.75, 28.54, 28.66, glass, nil, { Transparency = 0.6, Material = Enum.Material.Glass })
	local dx, dz = 6.0, 5.7 -- the angled corner wall, from (-8.4, 23.2) to (-2.4, 28.9), moved by S
	local corner = at(-5.4 + S, 0, 26.05) * CFrame.Angles(0, -math.atan2(dz, dx), 0)
	local span = math.sqrt(dx * dx + dz * dz)
	part({ Name = "CornerWall", Size = Vector3.new(span + 0.6, 5.1, 0.6), CFrame = corner * CFrame.new(0, 3.55, 0), Color = tile, Material = Enum.Material.CeramicTiles, Parent = decor })
	part({ Name = "CornerCap", Size = Vector3.new(span + 0.6, 0.15, 0.8), CFrame = corner * CFrame.new(0, 6.18, 0), Color = Color3.fromRGB(235, 235, 232), Material = Enum.Material.Marble, Parent = decor })
	part({ Name = "CornerGlass", Size = Vector3.new(span, 1.5, 0.12), CFrame = corner * CFrame.new(0, 7.0, 0), Color = glass, Material = Enum.Material.Glass, Transparency = 0.6, Parent = decor })
	box("DoughStep", -10.2 + S, -8.8 + S, 1, 1.7, 14, 18, Color3.fromRGB(240, 200, 40), Enum.Material.DiamondPlate)
	local stepSign = part({ Name = "DoughShowSign", Size = Vector3.new(0.1, 1.2, 3.6), CFrame = at(-8.75 + S, 3.6, 16), Color = BRAND.Red, Parent = decor })
	screenText(stepSign, Enum.NormalId.Left, "STEP UP - DOUGH SHOW", Color3.new(1, 1, 1))

	-- === Kitchen ===
	-- Kitchen display (KDS) hung over the makeline, facing the makers (ShopService writes to it)
	local kds = part({ Name = "TicketBoard", Size = Vector3.new(15, 3, 0.3), CFrame = at(10.2 + S, 9.6, 27.8), Color = Color3.fromRGB(10, 10, 12), Parent = decor })
	local kdsGui = Instance.new("SurfaceGui")
	kdsGui.Name = "Tickets"
	kdsGui.Face = Enum.NormalId.Front -- Front is -Z: toward the makers
	kdsGui.CanvasSize = Vector2.new(1000, 200)
	kdsGui.LightInfluence = 0
	local kdsText = Instance.new("TextLabel")
	kdsText.Name = "Text"
	kdsText.Size = UDim2.fromScale(1, 1)
	kdsText.BackgroundColor3 = Color3.fromRGB(12, 16, 22)
	kdsText.BorderSizePixel = 0
	kdsText.Font = Enum.Font.Code
	kdsText.TextSize = 17
	kdsText.TextColor3 = Color3.fromRGB(120, 255, 140)
	kdsText.TextXAlignment = Enum.TextXAlignment.Left
	kdsText.TextYAlignment = Enum.TextYAlignment.Top
	kdsText.Text = "NO ORDERS"
	kdsText.Parent = kdsGui
	kdsGui.Parent = kds
	for _, x in { 5.4 + S, 18.4 + S } do
		box("KdsMount", x - 0.1, x + 0.1, 11.1, 1 + h, 27.7, 27.9, Color3.fromRGB(60, 60, 60), Enum.Material.Metal)
	end
	-- Dough monitor hung over the stretch table, facing the stretcher
	local doughMonitor = part({ Name = "DoughMonitor", Size = Vector3.new(0.2, 2.2, 3.6), CFrame = at(-7.4 + S, 10, 18.5), Color = Color3.fromRGB(10, 10, 12), Parent = decor })
	screenText(doughMonitor, Enum.NormalId.Right, "DOUGH\nM  L", Color3.fromRGB(120, 255, 140), Color3.fromRGB(12, 16, 22), Enum.Font.Code)
	box("MonitorMount", -7.5 + S, -7.3 + S, 11.1, 1 + h, 18.4, 18.6, Color3.fromRGB(60, 60, 60), Enum.Material.Metal)

	-- Three stacked conveyor ovens behind the makers, conveying toward the back
	-- (not a station: pizzas ride through on their own), their backs to the
	-- right wall with a small gap, too narrow to walk (the user, 2026-10-21:
	-- the hood's edge 0.2 from the wall, the body's back 0.8).
	StationArt.Build("Oven", decor, at(19.35, 1, 10.1))
	-- The owner paints the ovens here, at their front (StoreService; only the owner sees it).
	local paintSpot = part({ Name = "OvenPaintSpot", Size = Vector3.new(1, 1, 1), CFrame = at(15.65, 4, 10.1), Transparency = 1, CanCollide = false, CanQuery = false, Parent = decor })
	prompt(paintSpot, "Paint", "Oven", 0.5):SetAttribute("OwnerOnly", true)

	-- A window on the right wall past the cut table
	box("Window", HW - 0.6, HW + 0.6, 4, 9, -9.3, -3.9, glass, nil, glassProps)

	-- Walk-in cooler against the back wall in the right-hand corner (the user,
	-- 2026-10-21: all the way back, for room), its door (the Fridge station:
	-- door + stock tablet, in a notch) on its left side facing the prep table.
	local walkIn = Color3.fromRGB(205, 210, 216)
	local WI_X, WI_Z0, WI_Z1, DOOR_Z = 5.75, BACK + 0.5, BACK + 15.7, BACK + 11.7 -- its left side, back, front; the door's centre
	box("WalkIn", WI_X + 4, HW - 0.5, 1, 11, WI_Z0, WI_Z1, walkIn, Enum.Material.Metal)
	box("WalkIn", WI_X, WI_X + 4, 1, 11, WI_Z0, DOOR_Z - 3, walkIn, Enum.Material.Metal)
	box("WalkIn", WI_X, WI_X + 4, 1, 11, DOOR_Z + 3, WI_Z1, walkIn, Enum.Material.Metal)
	box("HandSink", 2.9, 5.0, 3.0, 3.6, -17.6, -15.4, steel, Enum.Material.Metal)
	box("HandSinkBase", 3.4, 4.5, 1, 3.0, -17.2, -15.8, steel, Enum.Material.Metal)

	-- Back of house where the restrooms were (the user dropped them): the
	-- office in the back-left corner, the 3-compartment sink on the left wall,
	-- dish rack, prep table, mop sink and water heater, dry storage along the
	-- back (the back storage shelf and the dough tray stacks went, 2026-10-21).
	local function wall(name: string, x0: number, x1: number, z0: number, z1: number)
		box(name, x0, x1, 1, 11, z0, z1, wallColor, Enum.Material.Plaster)
	end
	wall("OfficeWall", -14.2, -13.8, -22.4, -18.0)
	wall("OfficeWall", -14.2, -13.8, -15.5, -10.3)
	wall("OfficeWall", -HW, -13.8, -22.6, -22.2)
	box("Desk", -23.4, -20.2, 3.4, 3.7, -21.8, -19.6, Color3.fromRGB(110, 80, 55), Enum.Material.Wood)
	box("DeskBody", -23.4, -22.2, 1, 3.4, -21.8, -19.6, Color3.fromRGB(90, 65, 45), Enum.Material.Wood)
	box("OfficeChair", -20.0, -18.8, 1, 3.0, -21.0, -19.8, Color3.fromRGB(190, 40, 35), Enum.Material.Fabric)
	box("Monitor", -23.3, -23.2, 3.7, 4.8, -21.4, -19.8, Color3.fromRGB(15, 15, 18))
	box("Safe", -23.4, -21.8, 1, 3.2, -12.4, -10.8, Color3.fromRGB(60, 62, 66), Enum.Material.Metal)
	-- Sales board on the office's kitchen side: today's/this week's sales vs. forecast (ShopService writes to it)
	local salesBoard = part({ Name = "SalesBoard", Size = Vector3.new(0.15, 3.6, 5), CFrame = at(-13.65, 6.5, -12.9), Color = Color3.fromRGB(12, 16, 22), Parent = decor })
	local salesGui = Instance.new("SurfaceGui")
	salesGui.Name = "Sales"
	salesGui.Face = Enum.NormalId.Right -- faces into the kitchen (+X)
	salesGui.CanvasSize = Vector2.new(600, 360)
	salesGui.LightInfluence = 0
	local salesText = Instance.new("TextLabel")
	salesText.Name = "Text"
	salesText.Size = UDim2.fromScale(1, 1)
	salesText.BackgroundColor3 = Color3.fromRGB(12, 16, 22)
	salesText.BorderSizePixel = 0
	salesText.Font = Enum.Font.Code
	salesText.TextSize = 24
	salesText.TextColor3 = Color3.fromRGB(120, 255, 140)
	salesText.TextXAlignment = Enum.TextXAlignment.Left
	salesText.TextYAlignment = Enum.TextYAlignment.Top
	salesText.Text = "SALES"
	local salesPad = Instance.new("UIPadding")
	salesPad.PaddingLeft = UDim.new(0, 14)
	salesPad.PaddingTop = UDim.new(0, 12)
	salesPad.Parent = salesText
	salesText.Parent = salesGui
	salesGui.Parent = salesBoard

	box("SinkBody", -HW + 0.5, -21.7, 1, 4.2, -38.4, -27.6, steel, Enum.Material.Metal)
	for i = 0, 2 do
		box("SinkBasin", -HW + 0.7, -21.9, 4.15, 4.25, -38.0 + i * 3.5, -35.2 + i * 3.5, Color3.fromRGB(120, 160, 190), Enum.Material.Glass, { Transparency = 0.3, CanCollide = false })
	end
	box("Splash", -HW + 0.5, -HW + 0.65, 4.2, 6.0, -38.4, -27.6, steel, Enum.Material.Metal)
	for i = 0, 3 do
		box("DishRack", -HW + 0.5, -20.6, 1.3 + i * 2.2, 1.45 + i * 2.2, -46.6, -41.6, steel, Enum.Material.DiamondPlate)
	end
	box("PrepTable", -16.0, -8.0, 3.2, 3.5, -32.0, -30.0, steel, Enum.Material.Metal)
	box("PrepTableBase", -15.7, -8.3, 1, 3.2, -31.8, -30.2, Color3.fromRGB(150, 154, 160), Enum.Material.Metal, { Transparency = 0.2 })
	box("MopSink", -18.6, -15.0, 1, 2.6, BACK + 0.5, BACK + 3.7, Color3.fromRGB(200, 200, 200), Enum.Material.Concrete)
	box("WaterHeater", -14.2, -12.0, 1, 7, BACK + 0.6, BACK + 2.8, Color3.fromRGB(225, 225, 220), Enum.Material.Metal)
	for i = 0, 3 do
		box("DryShelf", -10.8, -5.2, 1.3 + i * 2.2, 1.45 + i * 2.2, BACK + 0.5, BACK + 3.0, steel, Enum.Material.DiamondPlate)
		box("Cases", -10.5, -5.5, 1.45 + i * 2.2, 2.6 + i * 2.2, BACK + 0.7, BACK + 2.8, Color3.fromRGB(180, 140, 90), Enum.Material.Cardboard, { CanCollide = false })
	end

	-- === Finishes and decor (the look pass) ===
	-- Brick outside, a drop ceiling inside, red brand soffits like the user's
	-- counter photos ("ORDER" over the carryout counter, the dough show sign over
	-- the makeline wall), a chalk wall down the side lobby (the reference map's
	-- "chalk wall & trimming"), posters, pendant lamps, plants, a sidewalk and an
	-- OPEN sign. Built from parts and SurfaceGuis: no uploads.
	local brick = Color3.fromRGB(150, 82, 62)
	for _, sx in { -1, 1 } do
		box("Cladding", sx * (HW + 0.5), sx * (HW + 0.85), 1, 1 + h, BACK - 0.85, FRONT - 0.5, brick, Enum.Material.Brick)
		box("Plinth", sx * (HW + 0.5), sx * (HW + 0.95), 0, 2, BACK - 0.95, FRONT - 0.5, Color3.fromRGB(95, 95, 98), Enum.Material.Slate)
	end
	box("Cladding", -HW - 0.85, -3.6, 1, 1 + h, BACK - 0.85, BACK - 0.5, brick, Enum.Material.Brick)
	box("Cladding", 1.6, HW + 0.85, 1, 1 + h, BACK - 0.85, BACK - 0.5, brick, Enum.Material.Brick)
	box("Cladding", -3.6, 1.6, 9, 1 + h, BACK - 0.85, BACK - 0.5, brick, Enum.Material.Brick)
	-- Drop ceiling with its T-bar grid (the light panels sit in it)
	box("Ceiling", -HW + 0.5, HW - 0.5, h + 0.4, h + 0.6, BACK + 0.5, FRONT - 0.5, Color3.fromRGB(236, 236, 230), Enum.Material.SmoothPlastic, { CanCollide = false })
	local grid = Color3.fromRGB(200, 200, 196)
	for x = -HW + 4, HW - 4, 4 do
		box("CeilingGrid", x - 0.06, x + 0.06, h + 0.35, h + 0.4, BACK + 0.5, FRONT - 0.5, grid, Enum.Material.Metal, { CanCollide = false })
	end
	for z = BACK + 4, FRONT - 4, 4 do
		box("CeilingGrid", -HW + 0.5, HW - 0.5, h + 0.35, h + 0.4, z - 0.06, z + 0.06, grid, Enum.Material.Metal, { CanCollide = false })
	end
	-- The ORDER soffit over the carryout counter and dough show (side lobby),
	-- with recessed lights in its underside.
	local soffitY = 12.6
	box("OrderSoffit", -13.2 + S, -8.4 + S, soffitY, h + 0.4, -4.4, 23.4, BRAND.Red, Enum.Material.SmoothPlastic, { CanCollide = false })
	box("SoffitTrim", -13.25 + S, -13.15 + S, soffitY - 0.12, soffitY + 0.06, -4.4, 23.4, BRAND.Charcoal, Enum.Material.Metal, { CanCollide = false })
	local orderSign = part({ Name = "OrderSign", Size = Vector3.new(0.1, 1.5, 12), CFrame = at(-13.26 + S, soffitY + 0.9, 3.5), Color = BRAND.Red, Transparency = 1, CanCollide = false, Parent = decor })
	screenText(orderSign, Enum.NormalId.Left, "ORDER", Color3.new(1, 1, 1), nil, Enum.Font.FredokaOne)
	local doughSign = part({ Name = "DoughShowHeader", Size = Vector3.new(0.1, 1.2, 11), CFrame = at(-13.26 + S, soffitY + 0.9, 17), Color = BRAND.Red, Transparency = 1, CanCollide = false, Parent = decor })
	screenText(doughSign, Enum.NormalId.Left, "FRESH DOUGH, MADE HERE", BRAND.Gold, nil, Enum.Font.FredokaOne)
	local function downlight(x: number, z: number, color: Color3)
		local can = part({ Name = "Downlight", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06, 0.7, 0.7), CFrame = at(x, soffitY - 0.03, z) * CFrame.Angles(0, 0, math.pi / 2), Color = Color3.fromRGB(255, 244, 222), Material = Enum.Material.Neon, CanCollide = false, Parent = decor })
		local beam = Instance.new("SpotLight")
		beam.Face = Enum.NormalId.Left -- the cylinder's -X end points down after the roll
		beam.Angle = 75
		beam.Range = 14
		beam.Brightness = 1.6
		beam.Color = color
		beam.Parent = can
	end
	for z = -2, 22, 4 do
		downlight(-8.8 + S, z, Color3.fromRGB(255, 220, 180))
	end
	-- The dough show soffit along the makeline wall, facing the front lobby
	box("MakelineSoffit", -2.4 + S, HW - 0.5, soffitY, h + 0.4, 28.9, 31.2, BRAND.Red, Enum.Material.SmoothPlastic, { CanCollide = false })
	box("SoffitTrim", -2.4 + S, HW - 0.5, soffitY - 0.12, soffitY + 0.06, 31.15, 31.25, BRAND.Charcoal, Enum.Material.Metal, { CanCollide = false })
	local makeSign = part({ Name = "MakelineSign", Size = Vector3.new(19, 1.4, 0.1), CFrame = at((-2.4 + S + HW - 0.5) / 2, soffitY + 0.9, 31.26), Color = BRAND.Red, Transparency = 1, CanCollide = false, Parent = decor })
	screenText(makeSign, Enum.NormalId.Back, "HAND-TOSSED  \u{2022}  FRESH DOUGH  \u{2022}  BAKED TO ORDER", Color3.new(1, 1, 1), nil, Enum.Font.FredokaOne)
	for x = 4, 22, 4.5 do
		downlight(x, 30.05, Color3.fromRGB(255, 220, 180))
	end
	-- Hanging dough show sign on the glass (photo: a red banner over the trays)
	local banner = part({ Name = "DoughBanner", Size = Vector3.new(0.12, 1.3, 4.4), CFrame = at(-8.75 + S, 7.7, 19.2), Color = BRAND.Red, Parent = decor })
	screenText(banner, Enum.NormalId.Left, "HAND-TOSSED\nFRESH DOUGH", Color3.new(1, 1, 1), BRAND.Red, Enum.Font.FredokaOne)
	-- Chalk wall down the side lobby, framed in wood
	local chalk = part({ Name = "ChalkWall", Size = Vector3.new(0.12, 6.4, 37.4), CFrame = at(-HW + 0.56, 9.1, 9.5), Color = Color3.fromRGB(38, 40, 40), Material = Enum.Material.Slate, Parent = decor })
	for _, y in { 5.85, 12.35 } do
		box("ChalkTrim", -HW + 0.5, -HW + 0.75, y - 0.12, y + 0.12, -9.3, 28.3, Color3.fromRGB(120, 82, 52), Enum.Material.Wood)
	end
	local chalkGui = Instance.new("SurfaceGui")
	chalkGui.Face = Enum.NormalId.Right -- +X: into the lobby
	chalkGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	chalkGui.PixelsPerStud = 40
	chalkGui.LightInfluence = 0.6
	local chalkWhite = Color3.fromRGB(236, 232, 222)
	local marker = Font.new("rbxasset://fonts/families/PermanentMarker.json")
	local hand = Font.new("rbxasset://fonts/families/IndieFlower.json", Enum.FontWeight.Bold)
	local function chalkText(text: string, font: Font, x: number, y: number, w: number, hgt: number, color: Color3?)
		local tl = Instance.new("TextLabel")
		tl.BackgroundTransparency = 1
		tl.Position = UDim2.fromScale(x, y)
		tl.Size = UDim2.fromScale(w, hgt)
		tl.FontFace = font
		tl.TextScaled = true
		tl.TextColor3 = color or chalkWhite
		tl.TextTransparency = 0.08
		tl.Text = text
		tl.Parent = chalkGui
	end
	-- (The wall runs from the back of the side lobby, left on the gui, to the front.)
	chalkText(string.upper(shopName), marker, 0.05, 0.12, 0.27, 0.42, Config.Brand.Gold)
	chalkText("hand-tossed, fresh, every single pie", hand, 0.05, 0.56, 0.27, 0.22)
	chalkText("Stretched by hand.\nSauced to the line.\nBaked in two minutes.", hand, 0.4, 0.12, 0.22, 0.72)
	chalkText("WATCH THE DOUGH SHOW!", marker, 0.68, 0.2, 0.28, 0.3, Config.Brand.Red:Lerp(Color3.new(1, 1, 1), 0.35))
	chalkText("step up to the glass", hand, 0.68, 0.55, 0.28, 0.2)
	-- A chalk pizza: crust ring, sauce, pepperoni dots
	local pizzaArt = Instance.new("Frame")
	pizzaArt.BackgroundTransparency = 1
	pizzaArt.AnchorPoint = Vector2.new(0.5, 0.5)
	pizzaArt.Position = UDim2.fromScale(0.355, 0.5)
	pizzaArt.Size = UDim2.fromScale(0.07, 0.7)
	pizzaArt.Parent = chalkGui
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.Parent = pizzaArt
	local function ring(scale: number, color: Color3, thick: number, fillT: number, x: number, y: number)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(x, y)
		f.Size = UDim2.fromScale(scale, scale)
		f.BackgroundColor3 = color
		f.BackgroundTransparency = fillT
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = f
		local stroke = Instance.new("UIStroke")
		stroke.Color = color
		stroke.Thickness = thick
		stroke.Parent = f
		f.Parent = pizzaArt
	end
	ring(1, chalkWhite, 4, 1, 0.5, 0.5)
	ring(0.8, Color3.fromRGB(220, 110, 90), 2, 0.75, 0.5, 0.5)
	for _, d in { { 0.35, 0.35 }, { 0.65, 0.4 }, { 0.45, 0.65 }, { 0.68, 0.66 }, { 0.32, 0.6 } } do
		ring(0.14, Color3.fromRGB(220, 110, 90), 2, 0.2, d[1], d[2])
	end
	chalkGui.Parent = chalk

	-- Posters by the front door (left wall of the front lobby)
	local function poster(z: number, headline: string, sub: string)
		local board = part({ Name = "Poster", Size = Vector3.new(0.1, 4.6, 3.4), CFrame = at(-HW + 0.56, 7.4, z), Color = BRAND.Red, Parent = decor })
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Right
		gui.CanvasSize = Vector2.new(340, 460)
		gui.LightInfluence = 0.8
		local bg = Instance.new("Frame")
		bg.Size = UDim2.fromScale(1, 1)
		bg.BackgroundColor3 = BRAND.Red
		bg.BorderSizePixel = 0
		bg.Parent = gui
		local function disc(size: number, x: number, y: number, color: Color3)
			local f = Instance.new("Frame")
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.Position = UDim2.fromOffset(x, y)
			f.Size = UDim2.fromOffset(size, size)
			f.BackgroundColor3 = color
			f.BorderSizePixel = 0
			local round = Instance.new("UICorner")
			round.CornerRadius = UDim.new(0.5, 0)
			round.Parent = f
			f.Parent = bg
		end
		disc(250, 170, 300, Color3.fromRGB(214, 160, 92)) -- crust
		disc(214, 170, 300, Color3.fromRGB(196, 44, 34)) -- sauce
		disc(190, 170, 300, Color3.fromRGB(250, 214, 120)) -- cheese
		for _, d in { { 120, 250 }, { 205, 255 }, { 150, 330 }, { 225, 335 }, { 175, 290 }, { 110, 310 } } do
			disc(34, d[1], d[2], Color3.fromRGB(165, 35, 35))
		end
		local head = Instance.new("TextLabel")
		head.BackgroundTransparency = 1
		head.Position = UDim2.fromOffset(16, 18)
		head.Size = UDim2.fromOffset(308, 110)
		head.FontFace = Style.Font.Heading
		head.TextScaled = true
		head.TextColor3 = Color3.new(1, 1, 1)
		head.Text = headline
		head.Parent = bg
		local subLabel = Instance.new("TextLabel")
		subLabel.BackgroundTransparency = 1
		subLabel.Position = UDim2.fromOffset(16, 128)
		subLabel.Size = UDim2.fromOffset(308, 36)
		subLabel.FontFace = Style.Font.LabelBold
		subLabel.TextScaled = true
		subLabel.TextColor3 = BRAND.Gold
		subLabel.Text = sub
		subLabel.Parent = bg
		gui.Parent = board
	end
	poster(32.5, "BUILD\nYOUR OWN", "Any size, up to 3 toppings")
	poster(37.5, "FRESH\nDOUGH DAILY", "Stretched by hand, right here")

	-- Outside: a sidewalk with a curb, lit door frames, an OPEN sign in the window
	box("Sidewalk", -HW - 3, HW + 3, 0, 1, FRONT + 0.5, FRONT + 9, Color3.fromRGB(176, 176, 170), Enum.Material.Concrete)
	box("Curb", -HW - 3, HW + 3, 0, 1.15, FRONT + 9, FRONT + 9.6, Color3.fromRGB(150, 150, 146), Enum.Material.Concrete)
	for _, x in { -18.5, 18.5 } do
		local sconce = part({ Name = "Sconce", Size = Vector3.new(0.5, 0.9, 0.4), CFrame = at(x, 9.2, FRONT + 0.7), Color = Color3.fromRGB(255, 230, 180), Material = Enum.Material.Neon, CanCollide = false, Parent = decor })
		local lamp = Instance.new("PointLight")
		lamp.Range = 14
		lamp.Brightness = 1.2
		lamp.Color = Color3.fromRGB(255, 210, 160)
		lamp.Parent = sconce
	end
	local openSign = part({ Name = "OpenSign", Size = Vector3.new(3.2, 1.2, 0.1), CFrame = at(12, 7.2, FRONT - 0.5), Color = Color3.fromRGB(20, 20, 24), Transparency = 1, CanCollide = false, Parent = decor })
	screenText(openSign, Enum.NormalId.Back, "OPEN", Color3.fromRGB(255, 70, 60), nil, Enum.Font.FredokaOne)

	-- === Stations ===
	-- Each station is an invisible hitbox (prompt + "Station" attribute, which is
	-- all gameplay code looks at) with StationArt detail parented under it.
	-- `art` is the floor-center of the art with LookVector toward the worker.
	local function station(kind: string, art: CFrame, size: Vector3, action: string, title: string, hitOffset: CFrame?, pizzaAt: Vector3?): Part
		local p = part({
			Name = kind,
			Size = size,
			CFrame = art * (hitOffset or CFrame.new(0, size.Y / 2, 0)),
			Transparency = 1,
			CanCollide = false,
			CanTouch = false,
			Parent = stations,
		})
		p:SetAttribute("Station", kind)
		if pizzaAt then
			-- The station's work spot (art-local, on the work surface): where the 3D
			-- pizza sits during its minigame, and what the station camera aims at.
			p:SetAttribute("PizzaAt", pizzaAt)
		end
		prompt(p, action, title)
		StationArt.Build(kind, p, art)
		return p
	end

	-- Carryout counter: the register (the ordering screen) facing the side lobby.
	station("Register", at(-6.2 + S, 5.4, 7.4) * FACE_RIGHT, Vector3.new(3, 2, 2), "Take Order", "Register", nil, Vector3.new(0, 0, 0))
	-- The production L: stretch table and sauce corner (their stations are
	-- hitboxes over the work spots from StationArt.Layout), makeline. (No
	-- ready rack or Load station for now: StationArt's ReadyRack and the Load
	-- code stay for a store builder.)
	local ST, SL, ML = StationArt.Layout.StretchTable, StationArt.Layout.SauceTable, StationArt.Layout.MakeLine
	local stretchCF = at(-5.4 + S, 1, 16.25) * FACE_RIGHT
	local sauceCF = at(0.568 + S, 1, 25.95) -- the sauce table: from the corner table (x -2.264 + S) to the makeline, front flush with it (z 23.6)
	local makeCF = at(10.2 + S, 1, 25.4) -- from the sauce table (x 3.4 + S) to x 17 + S
	StationArt.Build("StretchTable", decor, stretchCF)
	StationArt.Build("SauceTable", decor, sauceCF)
	StationArt.Build("MakeLine", decor, makeCF)
	station("Dough", stretchCF * CFrame.new(ST.workX, 0, 0), Vector3.new(3, 4, 3.6), "Stretch Dough", "Stretch Table", nil, Vector3.new(0, ST.height, ST.workZ))
	station("Sauce", sauceCF * CFrame.new(SL.workX, 0, 0), Vector3.new(3, 4, 3.6), "Sauce", "Sauce Station", nil, Vector3.new(0, SL.height, SL.workZ))
	local makeWork = Vector3.new(0, ML.boardTop, ML.boardZ)
	station("Cheese", makeCF * CFrame.new(ML.cheeseX, 0, 0), Vector3.new(3, 4, 3.6), "Cheese", "Make-Line", nil, makeWork)
	station("Toppings", makeCF * CFrame.new(ML.toppingsX, 0, 0), Vector3.new(3, 4, 3.6), "Toppings", "Make-Line", nil, makeWork)
	-- Cut table behind the oven exits; the oven tender faces the carryout counter.
	local CT = StationArt.Layout.CutTable
	-- (The user's bigger table, 2026-10-21, moved toward the right wall with the
	-- ovens the same day: the same place relative to their exits.)
	local cutCF = at(12.65, 1, -3.4) * FACE_RIGHT
	-- The carryout rack across its far end (the user, 2026-10-21), facing it:
	-- finished carryout orders wait there for their customers (ShopService).
	StationArt.Build("CarryoutRack", decor, cutCF * CFrame.new(-StationArt.Layout.CarryoutRack.nextTo, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0))
	station("CutTable", cutCF, Vector3.new(CT.width, 4, CT.depth), "Cut & Box", "Cut Table", nil, Vector3.new(3.1, CT.height, -1.55))
	-- Dispatch (the user, 2026-10-21, spot C on their plan): along the right wall
	-- past the carryout rack, drivers facing it; the delivery ready rack beside it
	-- toward the walk-in, each waiting order's hot bag on it (ShopService).
	local DP, HR = StationArt.Layout.Dispatch, StationArt.Layout.CarryoutRack
	station("DeliveryRack", at(HW - 0.6 - DP.depth / 2, 1, -17.7) * FACE_LEFT, Vector3.new(DP.length, 7, DP.depth), "Dispatch", "Dispatch", nil, Vector3.new(2.9, 4.4, 0))
	StationArt.Build("DeliveryReadyRack", decor, at(HW - 0.6 - HR.depth / 2, 1, -17.7 - DP.length / 2 - 0.15 - HR.length / 2) * FACE_LEFT)
	station("Fridge", at(WI_X + 2, 1, DOOR_Z) * FACE_LEFT, Vector3.new(6, 10, 4), "Check Stock", "Walk-in Cooler") -- in the walk-in's door notch

	-- === Lot out back ===
	part({ Name = "ParkingLot", Size = Vector3.new(36, 0.2, 28), CFrame = at(0, 0.1, -68), Color = Color3.fromRGB(55, 55, 60), Material = Enum.Material.Asphalt, CanCollide = false, Parent = decor })
	part({ Name = "BackApron", Size = Vector3.new(12, 0.2, 6), CFrame = at(-1, 0.1, BACK - 3), Color = Color3.fromRGB(120, 120, 125), Material = Enum.Material.Concrete, CanCollide = false, Parent = decor })
	for i = 0, 4 do
		part({ Name = "Stripe", Size = Vector3.new(0.4, 0.05, 10), CFrame = at(-16 + i * 8, 0.22, -72), Color = Color3.new(1, 1, 1), CanCollide = false, Parent = decor })
	end
	for i = 1, 4 do
		spot(spots, "Parking" .. i, at(-12 + (i - 1) * 8, 2, -72))
	end
	local lotSign = part({ Name = "LotSign", Size = Vector3.new(8, 1.6, 0.3), CFrame = at(0, 5, -81.8), Color = Color3.fromRGB(46, 160, 90), Parent = decor })
	screenText(lotSign, Enum.NormalId.Back, "DELIVERY PARKING ONLY", Color3.new(1, 1, 1))
	part({ Name = "LotSignPost", Size = Vector3.new(0.3, 4.4, 0.3), CFrame = at(0, 2.2, -81.8), Color = Color3.fromRGB(90, 90, 95), Material = Enum.Material.Metal, Parent = decor })

	-- Customer path: in at the front-left door, into the line for the ordering
	-- screen (the register: Queue1 in front of it, the line running back toward
	-- the door), then into the waiting line beside it along the counter (Wait1,
	-- the line running toward the back), out the same door (the user,
	-- 2026-10-23). ShopService puts the k-th in a line k - 1 steps of
	-- Queue2 - Queue1 (Wait2 - Wait1) from the first.
	spot(spots, "CustomerSpawn", at(-16, 3, 38))
	spot(spots, "Queue1", at(-6.2 + S - 4.2, 3, 7.4))
	spot(spots, "Queue2", at(-6.2 + S - 4.2, 3, 10.2))
	spot(spots, "Wait1", at(-6.2 + S - 5.4, 3, 4.0))
	spot(spots, "Wait2", at(-6.2 + S - 5.4, 3, 1.5))
	spot(spots, "Exit", at(-21, 3, 47))

	model.PrimaryPart = (decor:FindFirstChild("Floor") :: Part)
	model.Parent = parent
	return model
end

local function buildHouse(id: number, cf: CFrame, parent: Instance): Part
	local model = Instance.new("Model")
	model.Name = "House" .. id
	local colors = {
		Color3.fromRGB(180, 210, 240),
		Color3.fromRGB(240, 210, 180),
		Color3.fromRGB(200, 240, 200),
		Color3.fromRGB(240, 200, 220),
		Color3.fromRGB(230, 230, 180),
		Color3.fromRGB(220, 220, 225),
	}
	local color = colors[(id - 1) % #colors + 1]
	part({ Name = "Body", Size = Vector3.new(24, 12, 20), CFrame = cf * CFrame.new(0, 6, 0), Color = color, Material = Enum.Material.Plaster, Parent = model })
	-- Gabled roof: two wedges back to back, ridge running along the street.
	-- A WedgePart's vertical face is at +Z and its slope faces -Z.
	for _, side in { 1, -1 } do
		local wedge = Instance.new("WedgePart")
		wedge.Name = "Roof"
		wedge.Anchored = true
		wedge.Size = Vector3.new(26, 5, 11.5)
		wedge.CFrame = cf * CFrame.new(0, 14.5, side * 5.75) * (if side == 1 then CFrame.Angles(0, math.pi, 0) else CFrame.new())
		wedge.Color = Color3.fromRGB(110, 60, 50)
		wedge.Material = Enum.Material.RoofShingles
		wedge.Parent = model
	end
	for _, sx in { -1, 1 } do
		part({ Name = "Window", Size = Vector3.new(4, 3.5, 0.2), CFrame = cf * CFrame.new(sx * 7, 6.5, 10.05), Color = Color3.fromRGB(160, 205, 235), Material = Enum.Material.Glass, Transparency = 0.3, Parent = model })
		part({ Name = "Shutter", Size = Vector3.new(1, 3.7, 0.15), CFrame = cf * CFrame.new(sx * 7 + sx * 2.6, 6.5, 10.1), Color = Color3.fromRGB(60, 70, 90), Parent = model })
	end
	local door = part({ Name = "Door", Size = Vector3.new(4, 7, 0.6), CFrame = cf * CFrame.new(0, 4.5, 10.2), Color = Color3.fromRGB(100, 60, 30), Material = Enum.Material.Wood, Parent = model })
	door:SetAttribute("HouseId", id)
	prompt(door, "Deliver Pizza", "House #" .. id)
	label(door, "#" .. id, 5, UDim2.fromOffset(60, 30))
	part({ Name = "Porch", Size = Vector3.new(8, 1, 4), CFrame = cf * CFrame.new(0, 0.5, 12), Color = Color3.fromRGB(170, 170, 170), Material = Enum.Material.Concrete, Parent = model })
	local lamp = part({ Name = "PorchLight", Size = Vector3.new(0.5, 0.8, 0.5), CFrame = cf * CFrame.new(2.8, 7, 10.4), Color = Color3.fromRGB(255, 230, 160), Material = Enum.Material.Neon, Parent = model })
	local light = Instance.new("PointLight")
	light.Range = 10
	light.Color = Color3.fromRGB(255, 220, 160)
	light.Parent = lamp
	local plaque = part({ Name = "Number", Size = Vector3.new(1.6, 1, 0.1), CFrame = cf * CFrame.new(-3, 7, 10.25), Color = Color3.fromRGB(30, 30, 35), Parent = model })
	screenText(plaque, Enum.NormalId.Back, tostring(id), Color3.new(1, 1, 1))
	part({ Name = "Path", Size = Vector3.new(4, 0.2, 14), CFrame = cf * CFrame.new(0, 0.1, 21), Color = Color3.fromRGB(180, 180, 180), Material = Enum.Material.Concrete, CanCollide = false, Parent = model })
	part({ Name = "Driveway", Size = Vector3.new(8, 0.2, 18), CFrame = cf * CFrame.new(16, 0.1, 19), Color = Color3.fromRGB(140, 140, 145), Material = Enum.Material.Concrete, CanCollide = false, Parent = model })
	-- Mailbox with the house number
	part({ Name = "MailPost", Size = Vector3.new(0.3, 3.5, 0.3), CFrame = cf * CFrame.new(-4, 1.75, 27), Color = Color3.fromRGB(80, 60, 40), Material = Enum.Material.Wood, Parent = model })
	local box = part({ Name = "Mailbox", Size = Vector3.new(1, 1, 1.8), CFrame = cf * CFrame.new(-4, 3.8, 27), Color = Color3.fromRGB(40, 40, 45), Material = Enum.Material.Metal, Parent = model })
	screenText(box, Enum.NormalId.Right, tostring(id), Color3.new(1, 1, 1))
	screenText(box, Enum.NormalId.Left, tostring(id), Color3.new(1, 1, 1))
	model.Parent = parent
	return door
end

local function buildPlot(id: number, cf: CFrame, parent: Instance): Part
	local model = Instance.new("Model")
	model.Name = "Plot" .. id
	local base = part({ Name = "Base", Size = Vector3.new(66, 0.4, 142), CFrame = cf * CFrame.new(0, 0.2, -19), Color = Color3.fromRGB(140, 120, 90), Material = Enum.Material.Ground, Parent = model })
	local signPost = part({ Name = "ForSale", Size = Vector3.new(10, 6, 0.5), CFrame = cf * CFrame.new(0, 5, 48), Color = Color3.fromRGB(255, 255, 255), Parent = model })
	prompt(signPost, "Stores", "Lot #" .. id)
	label(signPost, "STORE LOT #" .. id .. "\nOpen your own store!", 5, UDim2.fromOffset(220, 60))
	model.Parent = parent
	return base
end

export type World = {
	houses: { Part },
	plots: { { id: number, cframe: CFrame, model: Model } },
}

function MapBuilder.Build(): World
	-- Studio's default Baseplate sits exactly at our ground height and z-fights
	-- with the grass; remove it (and its stock SpawnLocation) if they're still there.
	for _, child in workspace:GetChildren() do
		if (child.Name == "Baseplate" and child:IsA("BasePart")) or child:IsA("SpawnLocation") then
			child:Destroy()
		end
	end

	local map = Instance.new("Folder")
	map.Name = "Map"
	map.Parent = workspace

	part({ Name = "Ground", Size = Vector3.new(1200, 2, 1200), CFrame = CFrame.new(0, -1, 0), Color = Color3.fromRGB(90, 160, 70), Material = Enum.Material.Grass, Parent = map })

	-- Roads: Main Street (neighborhood), an avenue east of lot 1, a back
	-- street past the other lots, and a driveway from lot 1's parking.
	local roadColor = Color3.fromRGB(55, 55, 60)
	local function road(name: string, size: Vector3, pos: Vector3)
		part({ Name = name, Size = size, CFrame = CFrame.new(pos), Color = roadColor, Material = Enum.Material.Asphalt, CanCollide = false, Parent = map })
	end
	road("MainStreet", Vector3.new(920, 0.2, 26), Vector3.new(0, 0.1, 190))
	-- Overlapping road surfaces sit at distinct heights so they don't z-fight.
	road("Avenue", Vector3.new(26, 0.2, 360), Vector3.new(52, 0.14, 15))
	road("BackStreet", Vector3.new(300, 0.2, 24), Vector3.new(-85, 0.1, -130))
	road("LotDriveway", Vector3.new(22, 0.2, 16), Vector3.new(29, 0.18, -68))
	road("FrontStreet", Vector3.new(120, 0.2, 20), Vector3.new(0, 0.22, 75))
	-- Center line on Main Street
	for x = -440, 440, 20 do
		part({ Name = "LaneDash", Size = Vector3.new(8, 0.05, 0.5), CFrame = CFrame.new(x, 0.21, 190), Color = Color3.fromRGB(255, 210, 60), CanCollide = false, Parent = map })
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(22, 0.5, 55)
	spawn.Color = Config.Brand.Gold
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Duration = 0
	spawn.Parent = map

	local shops = Instance.new("Folder")
	shops.Name = "Shops"
	shops.Parent = workspace

	-- Delivery neighborhood along Main Street.
	local housesFolder = Instance.new("Folder")
	housesFolder.Name = "Houses"
	housesFolder.Parent = workspace
	local houses = {}
	local xs = { -400, -300, -200, -100, 100, 200, 300, 400 }
	local id = 0
	for _, x in xs do
		id += 1
		-- North side of Main Street, doors facing the street (+Z).
		table.insert(houses, buildHouse(id, CFrame.new(x, 0, 140), housesFolder))
	end
	for _, x in xs do
		id += 1
		-- South side, rotated to face the street (-Z).
		table.insert(houses, buildHouse(id, CFrame.new(x, 0, 240) * CFrame.Angles(0, math.pi, 0), housesFolder))
	end

	-- Store lots: lot 1 on the old HQ site by the spawn, lots 2-5 up north.
	-- Stores are built on them as players open them (StoreService).
	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = workspace
	local plots = {}
	local sites = { CFrame.new(0, 0, 0) }
	for _, x in { -195, -95, 5, 105 } do
		table.insert(sites, CFrame.new(x, 0, -200))
	end
	for i, cf in sites do
		local model = buildPlot(i, cf, plotsFolder).Parent :: Model
		table.insert(plots, { id = i, cframe = cf, model = model })
	end

	-- Trees, kept off roads, houses and lots.
	local rng = Random.new(7)
	for _ = 1, 90 do
		local x = rng:NextNumber(-580, 580)
		local z = rng:NextNumber(-580, 580)
		local clear = (math.abs(z - 190) < 80) -- Main Street + houses
			or (math.abs(x - 52) < 25 and z > -170 and z < 200) -- Avenue
			or (math.abs(z + 130) < 20 and x > -240 and x < 70) -- Back Street
			or (z > -300 and z < -140 and x > -250 and x < 160) -- lots 2-5
			or (x > -45 and x < 70 and z > -95 and z < 90) -- lot 1 + its parking
		if not clear then
			part({ Name = "Trunk", Size = Vector3.new(2, 10, 2), CFrame = CFrame.new(x, 5, z), Color = Color3.fromRGB(100, 70, 40), Material = Enum.Material.Wood, Parent = map })
			part({ Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.new(12, 12, 12), CFrame = CFrame.new(x, 13, z), Color = Color3.fromRGB(50, 130, 50), Material = Enum.Material.Grass, Parent = map })
		end
	end

	return { houses = houses, plots = plots }
end

return MapBuilder
