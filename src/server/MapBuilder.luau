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
-- traced from a real store's map): a narrow, deep store, 42 x 84 studs at
-- 1.5 studs per foot. Front (entrance) faces +Z of `origin`. An L-shaped
-- lobby (tables along the front, booths down the left side, restrooms off the
-- side hall); the carryout counter facing the side lobby; production as an L
-- behind the dough show glass (stretch table along the side, sauce in the
-- angled corner, makeline along the front wall) with the ovens right behind
-- the makers, the cut table at the oven exits, dispatch behind it; walk-in,
-- restrooms, office and dish area in back. Returns the Model.
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

	local FACE_FRONT = CFrame.Angles(0, math.pi, 0) -- worker toward the shop front (+Z)
	local FACE_RIGHT = CFrame.Angles(0, -math.pi / 2, 0) -- worker toward +X
	local FACE_LEFT = CFrame.Angles(0, math.pi / 2, 0) -- worker toward -X

	local HW, HD, h = 21, 42, 14 -- half width, half depth, wall height
	local wallColor = Color3.fromRGB(236, 230, 220)
	local tile = Color3.fromRGB(246, 246, 243) -- white subway tile on the walls the public sees
	local glass = Color3.fromRGB(160, 205, 235)
	local steel = Color3.fromRGB(196, 200, 206)
	local wood = Color3.fromRGB(150, 108, 70)
	local glassProps = { Transparency = 0.55, Material = Enum.Material.Glass, CanCollide = true }

	-- Floors: red quarry tile in the kitchen, wood-look planks in the L-shaped lobby.
	box("Floor", -HW, HW, 0, 1, -HD, HD, Color3.fromRGB(150, 62, 48), Enum.Material.CeramicTiles)
	box("LobbyFloor", -HW, HW, 1, 1.05, 28.9, HD, wood, Enum.Material.WoodPlanks, { CanCollide = false })
	box("LobbyFloor", -HW, -10.6, 1, 1.05, -19.2, 28.9, wood, Enum.Material.WoodPlanks, { CanCollide = false })
	box("LobbyFloor", -10.6, -8.4, 1, 1.05, 9.9, 28.9, wood, Enum.Material.WoodPlanks, { CanCollide = false }) -- in front of the dough show glass
	box("LobbyFloor", -8.4, -2.4, 1, 1.05, 23.2, 28.9, wood, Enum.Material.WoodPlanks, { CanCollide = false }) -- the angled corner (the kitchen half is under the sauce table)
	box("Mat", -20.3, -15.7, 1.05, 1.1, 38.5, 41.6, BRAND.Charcoal, Enum.Material.Carpet, { CanCollide = false })

	-- Outside walls, back door, storefront with a door at each front corner.
	for _, sx in { -1, 1 } do
		box("WallSide", sx * HW - 0.5, sx * HW + 0.5, 1, 1 + h, -HD, HD, wallColor, Enum.Material.Plaster)
		box("WallStripe", sx * HW - 0.55, sx * HW + 0.55, 1, 3, -HD, HD, BRAND.Charcoal)
	end
	box("WallBack", -HW, -3.6, 1, 1 + h, -HD - 0.5, -HD + 0.5, wallColor, Enum.Material.Plaster)
	box("WallBack", 1.6, HW, 1, 1 + h, -HD - 0.5, -HD + 0.5, wallColor, Enum.Material.Plaster)
	box("Lintel", -3.6, 1.6, 9, 1 + h, -HD - 0.5, -HD + 0.5, wallColor, Enum.Material.Plaster)
	local driverSign = part({ Name = "DriverDoorSign", Size = Vector3.new(6, 1, 0.1), CFrame = at(-1, 9.6, -HD + 0.6), Color = Color3.fromRGB(46, 160, 90), Parent = decor })
	screenText(driverSign, Enum.NormalId.Back, "DRIVERS - CARS OUT BACK", Color3.new(1, 1, 1))
	box("KneeWall", -15.5, 15.5, 1, 3, HD - 0.5, HD + 0.5, BRAND.Charcoal)
	box("Storefront", -15.5, 15.5, 3, 11, HD - 0.2, HD + 0.2, glass, nil, glassProps)
	for _, sx in { -1, 1 } do
		box("DoorFrame", sx * 15.5 - 0.3, sx * 15.5 + 0.3, 1, 11, HD - 0.4, HD + 0.4, BRAND.Charcoal, Enum.Material.Metal)
		box("DoorFrame", sx * 20.5 - 0.3, sx * HW, 1, 11, HD - 0.4, HD + 0.4, BRAND.Charcoal, Enum.Material.Metal)
		box("Transom", sx * 15.5, sx * 20.5, 9.6, 11, HD - 0.2, HD + 0.2, glass, nil, glassProps)
		part({ Name = "Awning", Size = Vector3.new(15, 0.3, 3.4), CFrame = at(sx * 7.75, 11.6, HD + 1.5) * CFrame.Angles(math.rad(-18), 0, 0), Color = BRAND.Red, Material = Enum.Material.Fabric, Parent = decor })
	end
	box("Header", -HW, HW, 11, 1 + h, HD - 0.5, HD + 0.5, BRAND.Red)
	box("Roof", -HW - 0.5, HW + 0.5, 1 + h, 2 + h, -HD - 0.5, HD + 0.5, Color3.fromRGB(70, 70, 75))
	box("Parapet", -HW - 0.5, HW + 0.5, 1 + h, 3.5 + h, HD, HD + 0.5, BRAND.Red)
	-- Brand sign on the header: round logo + name
	part({ Name = "Logo", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 4.4, 4.4), CFrame = at(-14, 15.6, HD + 0.9) * CFrame.Angles(0, math.pi / 2, 0), Color = BRAND.Cream, Parent = decor })
	part({ Name = "LogoSlice", Size = Vector3.new(2.1, 2.1, 0.2), CFrame = at(-14, 15.6, HD + 1.15) * CFrame.Angles(0, 0, math.rad(45)), Color = BRAND.Gold, Parent = decor })
	part({ Name = "LogoPepperoni", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 0.7, 0.7), CFrame = at(-14, 15.7, HD + 1.3) * CFrame.Angles(0, math.pi / 2, 0), Color = BRAND.Red, Parent = decor })
	local sign = part({ Name = "Sign", Size = Vector3.new(24, 3.4, 0.4), CFrame = at(3, 15.6, HD + 0.9), Color = BRAND.Red, Parent = decor })
	local signText = screenText(sign, Enum.NormalId.Back, string.upper(shopName), Color3.new(1, 1, 1), nil, Enum.Font.FredokaOne, Vector2.new(720, 100))
	signText.Name = "ShopName"
	local service = part({ Name = "ServiceSign", Size = Vector3.new(11, 1.2, 0.1), CFrame = at(0, 10.5, HD + 0.3), Color = BRAND.Charcoal, Parent = decor })
	screenText(service, Enum.NormalId.Back, "CARRYOUT  |  DELIVERY", BRAND.Gold)

	-- Ceiling light panels
	for _, pos in { Vector2.new(-15, 34), Vector2.new(2, 35), Vector2.new(14, 35), Vector2.new(-15, 14), Vector2.new(-15, -6), Vector2.new(0, 21), Vector2.new(12, 22), Vector2.new(-2, 9), Vector2.new(9, 3), Vector2.new(7, -9), Vector2.new(-1, -22), Vector2.new(-12, -33), Vector2.new(10, -34) } do
		local panel = part({ Name = "LightPanel", Size = Vector3.new(6, 0.2, 3), CFrame = at(pos.X, h + 0.85, pos.Y), Color = Color3.fromRGB(255, 252, 240), Material = Enum.Material.Neon, CanCollide = false, Parent = decor })
		local light = Instance.new("SurfaceLight")
		light.Face = Enum.NormalId.Bottom
		light.Range = 16
		light.Brightness = 1.2
		light.Angle = 120
		light.Color = Color3.fromRGB(255, 245, 225)
		light.Parent = panel
	end

	-- === Lobby ===
	-- Carryout counter facing the side lobby: the register, a second POS, the
	-- carryout warmer at its back end, menu boards hanging above.
	box("Counter", -10.6, -6.8, 1, 5, -3.6, 9.9, BRAND.Charcoal)
	box("CounterFace", -10.65, -10.6, 2.8, 4, -3.6, 9.9, BRAND.Red)
	box("CounterTop", -10.8, -6.6, 5, 5.4, -3.8, 10.1, Color3.fromRGB(235, 235, 232), Enum.Material.Marble)
	StationArt.Build("Register", decor, at(-8.2, 5.4, 3.0) * FACE_RIGHT)
	local menuItems = {
		{ "PIZZAS", "Build your own:\nsize + up to 3\ntoppings" },
		{ "SIZES", string.format("Small $%d\nMedium $%d\nLarge $%d", Config.SizePrice.Small, Config.SizePrice.Medium, Config.SizePrice.Large) },
		{ "TOPPINGS", table.concat(Config.Toppings, "\n") },
	}
	for i, item in menuItems do
		local board = part({ Name = "MenuScreen" .. i, Size = Vector3.new(0.3, 3.6, 4.2), CFrame = at(-11.2, 12.2, 9.4 - (i - 1) * 4.5), Color = Color3.fromRGB(15, 15, 18), Parent = decor })
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
	local orderHere = part({ Name = "OrderHere", Size = Vector3.new(0.1, 0.9, 4), CFrame = at(-11.2, 9.6, 7.4), Color = BRAND.Red, Parent = decor })
	screenText(orderHere, Enum.NormalId.Left, "ORDER HERE", Color3.new(1, 1, 1))
	-- Kitchen wall behind the counter's end, with the staff door
	box("StaffWall", -11, -10.4, 1, 1 + h, -9.9, -8.6, tile, Enum.Material.Plaster)
	box("StaffWall", -11, -10.4, 1, 1 + h, -5.4, -3.6, tile, Enum.Material.Plaster)
	box("StaffWall", -11, -10.4, 9, 1 + h, -8.6, -5.4, tile, Enum.Material.Plaster)

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

	-- Booths down the side lobby's left wall, tables along the front
	local booth = Color3.fromRGB(190, 45, 40)
	local tableTop = Color3.fromRGB(120, 85, 55)
	for _, z0 in { 1.5, 10.5, 19.5 } do
		box("BoothSeat", -HW + 0.5, -17.6, 1, 2.8, z0, z0 + 5.5, booth, Enum.Material.Fabric)
		box("BoothBack", -HW + 0.5, -19.6, 2.8, 5.6, z0, z0 + 5.5, booth, Enum.Material.Fabric)
		box("BoothTable", -17.4, -14.8, 3.4, 3.7, z0 + 1.4, z0 + 4.1, tableTop, Enum.Material.Wood)
		box("TableLeg", -16.3, -15.9, 1, 3.4, z0 + 2.55, z0 + 2.95, BRAND.Charcoal, Enum.Material.Metal)
	end
	for _, t in { Vector2.new(-3, 33.5), Vector2.new(6, 33.5), Vector2.new(13, 38.5) } do
		box("LobbyTable", t.X - 1.4, t.X + 1.4, 3.4, 3.7, t.Y - 1.4, t.Y + 1.4, tableTop, Enum.Material.Wood)
		box("TableLeg", t.X - 0.2, t.X + 0.2, 1, 3.4, t.Y - 0.2, t.Y + 0.2, BRAND.Charcoal, Enum.Material.Metal)
		for _, sx in { -1, 1 } do
			box("Chair", t.X + sx * 2.2 - 0.7, t.X + sx * 2.2 + 0.7, 1, 2.6, t.Y - 0.7, t.Y + 0.7, booth, Enum.Material.Plastic)
		end
	end
	-- Drink cooler on the right wall of the front lobby
	box("DrinkCooler", HW - 2.9, HW - 0.5, 1, 8, 29.5, 33.5, BRAND.Red)
	box("CoolerGlass", HW - 2.95, HW - 2.85, 1.8, 7.2, 29.8, 33.2, glass, nil, { Transparency = 0.5, Material = Enum.Material.Glass })
	for row = 0, 3 do
		for col = 0, 4 do
			local c = ({ Color3.fromRGB(200, 30, 30), Color3.fromRGB(30, 120, 200), Color3.fromRGB(240, 200, 40), Color3.fromRGB(60, 170, 70) })[row + 1]
			part({ Name = "Bottle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.0, 0.45, 0.45), CFrame = at(HW - 2.4, 2.7 + row * 1.3, 30.2 + col * 0.7) * CFrame.Angles(0, 0, math.pi / 2), Color = c, Material = Enum.Material.Glass, CanCollide = false, Parent = decor })
		end
	end
	box("BenchSeat", 3, 13, 2.5, 3.1, 39.8, 41.6, Color3.fromRGB(150, 105, 65), Enum.Material.WoodPlanks)
	box("BenchBase", 3.3, 12.7, 1, 2.5, 40.0, 41.4, BRAND.Charcoal)

	-- === Dough show walls ===
	-- Low wall (42") with sneeze-guard glass beside the stretch table, an angled
	-- piece at the corner, and the high wall (54") with glass behind the makeline.
	box("LowWall", -8.7, -8.1, 1, 5, 9.9, 23.2, tile, Enum.Material.Plaster)
	box("WallCap", -8.8, -8.0, 5, 5.15, 9.8, 23.3, Color3.fromRGB(235, 235, 232), Enum.Material.Marble)
	box("SneezeGuard", -8.46, -8.34, 5.15, 7.15, 9.9, 23.2, glass, nil, { Transparency = 0.6, Material = Enum.Material.Glass })
	box("HighWall", -2.4, HW, 1, 6.1, 28.3, 28.9, tile, Enum.Material.Plaster)
	box("WallCap", -2.4, HW, 6.1, 6.25, 28.2, 29.0, Color3.fromRGB(235, 235, 232), Enum.Material.Marble)
	box("SneezeGuard", -2.4, HW, 6.25, 7.75, 28.54, 28.66, glass, nil, { Transparency = 0.6, Material = Enum.Material.Glass })
	local dx, dz = 6.0, 5.7 -- the angled corner wall, from (-8.4, 23.2) to (-2.4, 28.9)
	local corner = at(-5.4, 0, 26.05) * CFrame.Angles(0, -math.atan2(dz, dx), 0)
	local span = math.sqrt(dx * dx + dz * dz)
	part({ Name = "CornerWall", Size = Vector3.new(span + 0.6, 5.1, 0.6), CFrame = corner * CFrame.new(0, 3.55, 0), Color = tile, Material = Enum.Material.Plaster, Parent = decor })
	part({ Name = "CornerCap", Size = Vector3.new(span + 0.6, 0.15, 0.8), CFrame = corner * CFrame.new(0, 6.18, 0), Color = Color3.fromRGB(235, 235, 232), Material = Enum.Material.Marble, Parent = decor })
	part({ Name = "CornerGlass", Size = Vector3.new(span, 1.5, 0.12), CFrame = corner * CFrame.new(0, 7.0, 0), Color = glass, Material = Enum.Material.Glass, Transparency = 0.6, Parent = decor })
	box("DoughStep", -10.2, -8.8, 1, 1.7, 14, 18, Color3.fromRGB(240, 200, 40), Enum.Material.DiamondPlate)
	local stepSign = part({ Name = "DoughShowSign", Size = Vector3.new(0.1, 1.2, 3.6), CFrame = at(-8.75, 3.6, 16), Color = BRAND.Red, Parent = decor })
	screenText(stepSign, Enum.NormalId.Left, "STEP UP - DOUGH SHOW", Color3.new(1, 1, 1))

	-- === Kitchen ===
	-- Kitchen display (KDS) hung over the makeline, facing the makers (ShopService writes to it)
	local kds = part({ Name = "TicketBoard", Size = Vector3.new(15, 3, 0.3), CFrame = at(11.9, 9.6, 27.8), Color = Color3.fromRGB(10, 10, 12), Parent = decor })
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
	for _, x in { 5.4, 18.4 } do
		box("KdsMount", x - 0.1, x + 0.1, 11.1, 1 + h, 27.7, 27.9, Color3.fromRGB(60, 60, 60), Enum.Material.Metal)
	end
	-- Dough monitor hung over the stretch table, facing the stretcher
	local doughMonitor = part({ Name = "DoughMonitor", Size = Vector3.new(0.2, 2.2, 3.6), CFrame = at(-7.4, 10, 18.5), Color = Color3.fromRGB(10, 10, 12), Parent = decor })
	screenText(doughMonitor, Enum.NormalId.Right, "DOUGH\nS  M  L", Color3.fromRGB(120, 255, 140), Color3.fromRGB(12, 16, 22), Enum.Font.Code)
	box("MonitorMount", -7.5, -7.3, 11.1, 1 + h, 18.4, 18.6, Color3.fromRGB(60, 60, 60), Enum.Material.Metal)

	-- Three stacked conveyor ovens right behind the makers, conveying toward the
	-- back (not a station: pizzas ride through on their own).
	StationArt.Build("Oven", decor, at(8.55, 1, 13.1))

	-- Box storage along the right wall by the ovens, a window further back
	for i = 0, 3 do
		box("BoxShelf", HW - 3.2, HW - 0.5, 1.3 + i * 2.4, 1.45 + i * 2.4, 4.5, 15.5, steel, Enum.Material.DiamondPlate)
		for j = 0, 3 do
			box("FlatBoxes", HW - 3.0, HW - 0.7, 1.45 + i * 2.4, 2.5 + i * 2.4, 4.9 + j * 2.6, 6.9 + j * 2.6, Color3.fromRGB(205, 168, 118), Enum.Material.Cardboard, { CanCollide = false })
		end
	end
	box("Window", HW - 0.6, HW + 0.6, 4, 9, -6.3, -0.9, glass, nil, glassProps)

	-- Dispatch zone behind the oven tender: a second heat rack and the bag cabinet
	StationArt.Build("DeliveryRack", decor, at(1.9, 1, -10.4) * FACE_FRONT)
	box("BagCabinet", 11.6, 14.0, 1, 6, -12.2, -9.6, Color3.fromRGB(150, 25, 30), Enum.Material.Fabric)
	local bagSign = part({ Name = "BagSign", Size = Vector3.new(2.4, 0.8, 0.1), CFrame = at(12.8, 6.6, -9.5), Color = BRAND.Charcoal, Parent = decor })
	screenText(bagSign, Enum.NormalId.Back, "HOT BAGS", BRAND.Gold)

	-- Walk-in cooler: the Fridge station is its front's right end (door + stock
	-- tablet), clear of the heat racks.
	local walkIn = Color3.fromRGB(205, 210, 216)
	box("WalkIn", 5.75, 14, 1, 11, -28.4, -13.2, walkIn, Enum.Material.Metal)
	box("WalkIn", 14, HW - 0.5, 1, 11, -28.4, -17.2, walkIn, Enum.Material.Metal)
	box("WalkIn", 20, HW - 0.5, 1, 11, -17.2, -13.2, walkIn, Enum.Material.Metal)
	box("HandSink", 2.9, 5.0, 3.0, 3.6, -14.6, -12.4, steel, Enum.Material.Metal)
	box("HandSinkBase", 3.4, 4.5, 1, 3.0, -14.2, -12.8, steel, Enum.Material.Metal)

	-- Restrooms and the office off the side hall
	local function wall(name: string, x0: number, x1: number, z0: number, z1: number)
		box(name, x0, x1, 1, 11, z0, z1, wallColor, Enum.Material.Plaster)
	end
	-- Women's: x -21..-10.2, z -26.2..-19.2, door to the hall
	wall("RestroomWall", -HW, -17.5, -19.4, -19.0)
	wall("RestroomWall", -15.0, -10.2, -19.4, -19.0)
	wall("RestroomWall", -10.4, -10.0, -26.2, -19.0)
	wall("RestroomWall", -HW, -10.0, -26.4, -26.0)
	-- Men's: x -13.8..-4.3, z -18.9..-9.9, door to the hall
	wall("RestroomWall", -13.8, -4.3, -10.1, -9.7)
	wall("RestroomWall", -13.8, -4.3, -18.9, -18.5)
	wall("RestroomWall", -14.0, -13.6, -18.9, -16.0)
	wall("RestroomWall", -14.0, -13.6, -13.5, -9.9)
	wall("RestroomWall", -4.5, -4.1, -18.9, -9.9)
	for _, r in { { -15.6, -22.7, "WOMEN" }, { -9.0, -14.4, "MEN" } } do
		box("Toilet", r[1] - 0.6, r[1] + 0.6, 1, 2.6, r[2] - 2.5, r[2] - 1.0, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
		box("Sink", r[1] + 1.4, r[1] + 2.8, 3.4, 3.8, r[2] + 1.0, r[2] + 2.2, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	end
	local womenSign = part({ Name = "RestroomSign", Size = Vector3.new(1.6, 1.6, 0.1), CFrame = at(-16.25, 8.6, -18.9), Color = Color3.fromRGB(40, 90, 160), Parent = decor })
	screenText(womenSign, Enum.NormalId.Back, "WOMEN", Color3.new(1, 1, 1))
	local menSign = part({ Name = "RestroomSign", Size = Vector3.new(0.1, 1.6, 1.6), CFrame = at(-14.1, 8.6, -14.75), Color = Color3.fromRGB(40, 90, 160), Parent = decor })
	screenText(menSign, Enum.NormalId.Left, "MEN", Color3.new(1, 1, 1))
	-- Office: x -10.2..-4.3, z -26.2..-19.6, door to the kitchen
	wall("OfficeWall", -10.2, -4.3, -19.8, -19.4)
	wall("OfficeWall", -4.5, -4.1, -26.2, -24.5)
	wall("OfficeWall", -4.5, -4.1, -22.0, -19.6)
	wall("OfficeWall", -10.2, -4.1, -26.4, -26.0)
	box("Desk", -9.6, -6.4, 3.4, 3.7, -25.8, -24.0, Color3.fromRGB(110, 80, 55), Enum.Material.Wood)
	box("DeskBody", -9.6, -8.4, 1, 3.4, -25.8, -24.0, Color3.fromRGB(90, 65, 45), Enum.Material.Wood)
	box("OfficeChair", -8.4, -7.2, 1, 3.0, -23.6, -22.4, Color3.fromRGB(190, 40, 35), Enum.Material.Fabric)
	box("Monitor", -8.6, -7.0, 3.7, 4.8, -25.7, -25.6, Color3.fromRGB(15, 15, 18))
	-- Sales board on the restroom block's kitchen side: today's/this week's sales vs. forecast (ShopService writes to it)
	local salesBoard = part({ Name = "SalesBoard", Size = Vector3.new(0.15, 3.6, 6), CFrame = at(-3.95, 6.5, -14.4), Color = Color3.fromRGB(12, 16, 22), Parent = decor })
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

	-- Back of house: 3-compartment sink, dish rack, prep table, mop sink, dry
	-- storage, tray storage, back storage.
	box("SinkBody", -17.4, -7.0, 1, 4.2, -28.4, -26.6, steel, Enum.Material.Metal)
	for i = 0, 2 do
		box("SinkBasin", -16.9 + i * 3.4, -14.1 + i * 3.4, 4.15, 4.25, -28.2, -26.8, Color3.fromRGB(120, 160, 190), Enum.Material.Glass, { Transparency = 0.3, CanCollide = false })
	end
	box("Splash", -17.4, -7.0, 4.2, 6.0, -26.7, -26.55, steel, Enum.Material.Metal)
	for i = 0, 3 do
		box("DishRack", -20.6, -17.6, 1.3 + i * 2.2, 1.45 + i * 2.2, -35.0, -30.9, steel, Enum.Material.DiamondPlate)
	end
	box("PrepTable", -13.3, -6.5, 3.2, 3.5, -34.8, -32.9, steel, Enum.Material.Metal)
	box("PrepTableBase", -13.0, -6.8, 1, 3.2, -34.6, -33.1, Color3.fromRGB(150, 154, 160), Enum.Material.Metal, { Transparency = 0.2 })
	box("MopSink", -20.6, -17.0, 1, 2.6, -41.6, -38.4, Color3.fromRGB(200, 200, 200), Enum.Material.Concrete)
	box("WaterHeater", -20.4, -18.2, 1, 7, -37.8, -35.8, Color3.fromRGB(225, 225, 220), Enum.Material.Metal)
	for i = 0, 3 do
		box("DryShelf", 2.9, 5.6, 1.3 + i * 2.2, 1.45 + i * 2.2, -28.1, -24.0, steel, Enum.Material.DiamondPlate)
		box("Cases", 3.1, 5.4, 1.45 + i * 2.2, 2.6 + i * 2.2, -27.8, -24.3, Color3.fromRGB(180, 140, 90), Enum.Material.Cardboard, { CanCollide = false })
	end
	for k = 0, 5 do
		for i = 0, 5 do
			box("TrayStack", 3.4 + k * 2.9, 5.8 + k * 2.9, 1 + i * 0.36, 1.34 + i * 0.36, -41.0, -38.0, Color3.fromRGB(45, 125, 215), Enum.Material.Plastic)
		end
	end
	for i = 0, 3 do
		box("BackStorage", 12.4, HW - 0.5, 1.3 + i * 2.2, 1.45 + i * 2.2, -35.0, -32.2, steel, Enum.Material.DiamondPlate)
		box("Cases", 12.8, HW - 0.8, 1.45 + i * 2.2, 2.4 + i * 2.2, -34.7, -32.5, Color3.fromRGB(230, 205, 120), Enum.Material.Cardboard, { CanCollide = false })
	end

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

	-- Carryout counter: the register, and the carryout warmer facing the side lobby.
	station("Register", at(-8.2, 5.4, 7.4) * FACE_RIGHT, Vector3.new(3, 2, 2), "Take Order", "Register", nil, Vector3.new(0, 0, 0))
	station("Pickup", at(-8.7, 5.4, -0.9) * FACE_LEFT, Vector3.new(6, 1, 3), "Carryout", "Carryout")
	-- The production L: stretch table and sauce corner (their stations are
	-- hitboxes over the work spots from StationArt.Layout), makeline, ready rack.
	local ST, SL, ML = StationArt.Layout.StretchTable, StationArt.Layout.SauceTable, StationArt.Layout.MakeLine
	local stretchCF = at(-5.4, 1, 16.25) * FACE_RIGHT
	local sauceCF = at(0.1, 1, 24.95)
	local makeCF = at(11.9, 1, 25.4)
	StationArt.Build("StretchTable", decor, stretchCF)
	StationArt.Build("SauceTable", decor, sauceCF)
	StationArt.Build("MakeLine", decor, makeCF)
	station("Dough", stretchCF * CFrame.new(ST.workX, 0, 0), Vector3.new(3, 4, 3.6), "Stretch Dough", "Stretch Table", nil, Vector3.new(0, ST.height, ST.workZ))
	station("Sauce", sauceCF * CFrame.new(SL.workX, 0, 0), Vector3.new(3, 4, 3.6), "Sauce", "Sauce Station", nil, Vector3.new(0, SL.height, SL.workZ))
	local makeWork = Vector3.new(0, ML.boardTop, ML.boardZ)
	station("Cheese", makeCF * CFrame.new(ML.cheeseX, 0, 0), Vector3.new(3, 4, 3.6), "Cheese", "Make-Line", nil, makeWork)
	station("Toppings", makeCF * CFrame.new(ML.toppingsX, 0, 0), Vector3.new(3, 4, 3.6), "Toppings", "Make-Line", nil, makeWork)
	-- The ready rack beside the oven entrance: the topper turns around to load.
	local RR = StationArt.Layout.ReadyRack
	StationArt.Build("ReadyRack", decor, at(15.3, 1, 18.4) * FACE_FRONT)
	station("Load", at(15.3, 1, 18.4) * FACE_FRONT, Vector3.new(RR.width, 8, RR.depth), "Load Oven", "Ready Rack", nil, Vector3.new(0, RR.height + 2.3, 0.1 - RR.rackDepth / 2))
	-- Cut table behind the oven exits; the oven tender faces the carryout counter.
	local CT = StationArt.Layout.CutTable
	station("CutTable", at(3.1, 1, 1.5) * FACE_RIGHT, Vector3.new(CT.width, 4, CT.depth), "Cut & Box", "Cut Table", nil, Vector3.new(1.2, CT.height, -0.3))
	station("DeliveryRack", at(8.1, 1, -10.4) * FACE_FRONT, Vector3.new(6, 7, 2.2), "Heat Rack", "Heat Rack", nil, Vector3.new(0, 3.6, -1.1))
	station("Fridge", at(17, 1, -15.2) * FACE_FRONT, Vector3.new(6, 10, 4), "Check Stock", "Walk-in Cooler")

	-- === Lot out back ===
	part({ Name = "ParkingLot", Size = Vector3.new(36, 0.2, 28), CFrame = at(0, 0.1, -62), Color = Color3.fromRGB(55, 55, 60), Material = Enum.Material.Asphalt, CanCollide = false, Parent = decor })
	part({ Name = "BackApron", Size = Vector3.new(12, 0.2, 6), CFrame = at(-1, 0.1, -45), Color = Color3.fromRGB(120, 120, 125), Material = Enum.Material.Concrete, CanCollide = false, Parent = decor })
	for i = 0, 4 do
		part({ Name = "Stripe", Size = Vector3.new(0.4, 0.05, 10), CFrame = at(-16 + i * 8, 0.22, -66), Color = Color3.new(1, 1, 1), CanCollide = false, Parent = decor })
	end
	for i = 1, 4 do
		spot(spots, "Parking" .. i, at(-12 + (i - 1) * 8, 2, -66))
	end
	local lotSign = part({ Name = "LotSign", Size = Vector3.new(8, 1.6, 0.3), CFrame = at(0, 5, -75.8), Color = Color3.fromRGB(46, 160, 90), Parent = decor })
	screenText(lotSign, Enum.NormalId.Back, "DELIVERY PARKING ONLY", Color3.new(1, 1, 1))
	part({ Name = "LotSignPost", Size = Vector3.new(0.3, 4.4, 0.3), CFrame = at(0, 2.2, -75.8), Color = Color3.fromRGB(90, 90, 95), Material = Enum.Material.Metal, Parent = decor })

	-- Customer path: in at the front-left door, up the side lobby to the
	-- register, wait by the carryout warmer, out the same door.
	spot(spots, "CustomerSpawn", at(-13, 3, 38))
	spot(spots, "Queue1", at(-12.8, 3, 7.4))
	spot(spots, "Queue2", at(-12.8, 3, 11.0))
	spot(spots, "Queue3", at(-12.8, 3, 14.6))
	spot(spots, "Wait1", at(-13.0, 3, 0.4))
	spot(spots, "Wait2", at(-13.6, 3, -3.0))
	spot(spots, "Wait3", at(-12.6, 3, -6.4))
	spot(spots, "Exit", at(-17.5, 3, 47))

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
	local base = part({ Name = "Base", Size = Vector3.new(60, 0.4, 136), CFrame = cf * CFrame.new(0, 0.2, -16), Color = Color3.fromRGB(140, 120, 90), Material = Enum.Material.Ground, Parent = model })
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
	road("LotDriveway", Vector3.new(22, 0.2, 16), Vector3.new(29, 0.18, -62))
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
