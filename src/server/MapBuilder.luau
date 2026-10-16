--!strict
-- Builds the whole map from code so the place file needs no manual building.
-- Swap pieces for real models later; everything gameplay-related is found by
-- name/attribute, not by look.
--
-- Store layout follows a delivery-first pizza chain ("open kitchen"): a small
-- carryout lobby, a make-line facing the customers behind the counter, a
-- conveyor oven feeding a cut table, a heat rack by the driver door, and a
-- parking lot out back for delivery cars.

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
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
	tl.Font = Enum.Font.FredokaOne
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
	tl.Font = font or Enum.Font.GothamBlack
	tl.TextScaled = true
	tl.TextColor3 = color
	tl.Text = text
	tl.Parent = gui
	gui.Parent = target
	return tl
end

-- Builds one store. Front (entrance) faces +Z of `origin`. Returns the Model.
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

	local wallColor = Color3.fromRGB(236, 230, 220)
	local glass = Color3.fromRGB(160, 205, 235)
	local h = 14

	-- Floors: light tile lobby, red quarry tile kitchen.
	part({ Name = "Floor", Size = Vector3.new(60, 1, 50), CFrame = at(0, 0.5, 0), Color = Color3.fromRGB(150, 62, 48), Material = Enum.Material.CeramicTiles, Parent = decor })
	part({ Name = "LobbyFloor", Size = Vector3.new(60, 0.05, 12.5), CFrame = at(0, 1.02, 18.75), Color = Color3.fromRGB(225, 222, 215), Material = Enum.Material.CeramicTiles, Parent = decor })
	part({ Name = "Mat", Size = Vector3.new(10, 0.06, 4), CFrame = at(0, 1.05, 22.5), Color = BRAND.Charcoal, Material = Enum.Material.Carpet, Parent = decor })

	-- Side walls with a charcoal base stripe
	for _, sx in { -1, 1 } do
		part({ Name = "WallSide", Size = Vector3.new(1, h, 50), CFrame = at(sx * 30, 1 + h / 2, 0), Color = wallColor, Material = Enum.Material.Plaster, Parent = decor })
		part({ Name = "WallStripe", Size = Vector3.new(1.1, 2, 50), CFrame = at(sx * 30, 2, 0), Color = BRAND.Charcoal, Parent = decor })
	end
	-- Back wall with a receiving door (x -14..-6) and a driver door (x 16..24).
	for _, seg in { { -22, 16 }, { 5, 22 }, { 27, 6 } } do
		part({ Name = "WallBack", Size = Vector3.new(seg[2], h, 1), CFrame = at(seg[1], 1 + h / 2, -25), Color = wallColor, Material = Enum.Material.Plaster, Parent = decor })
	end
	for _, x in { -10, 20 } do
		part({ Name = "Lintel", Size = Vector3.new(8, 4, 1), CFrame = at(x, h - 1, -25), Color = wallColor, Material = Enum.Material.Plaster, Parent = decor })
	end
	local driverSign = part({ Name = "DriverDoorSign", Size = Vector3.new(6, 1, 0.1), CFrame = at(20, 9.6, -24.4), Color = Color3.fromRGB(46, 160, 90), Parent = decor })
	screenText(driverSign, Enum.NormalId.Back, "DRIVERS - CARS OUT BACK", Color3.new(1, 1, 1))

	-- Storefront: knee walls, big glass, brand header band. Entrance gap x -6..6.
	for _, sx in { -1, 1 } do
		part({ Name = "KneeWall", Size = Vector3.new(24, 2, 1), CFrame = at(sx * 18, 2, 25), Color = BRAND.Charcoal, Parent = decor })
		part({ Name = "Storefront", Size = Vector3.new(24, 8, 0.4), CFrame = at(sx * 18, 7, 25), Color = glass, Transparency = 0.55, Material = Enum.Material.Glass, Parent = decor })
		part({ Name = "DoorPost", Size = Vector3.new(0.6, 10, 0.8), CFrame = at(sx * 6, 6, 25), Color = BRAND.Charcoal, Material = Enum.Material.Metal, Parent = decor })
		-- Awning over each window
		part({ Name = "Awning", Size = Vector3.new(22, 0.3, 3.4), CFrame = at(sx * 18, 11.6, 26.5) * CFrame.Angles(math.rad(-18), 0, 0), Color = BRAND.Red, Material = Enum.Material.Fabric, Parent = decor })
	end
	part({ Name = "Header", Size = Vector3.new(60, 4, 1), CFrame = at(0, 13, 25), Color = BRAND.Red, Parent = decor })
	part({ Name = "Roof", Size = Vector3.new(62, 1, 52), CFrame = at(0, 1 + h + 0.5, 0), Color = Color3.fromRGB(70, 70, 75), Parent = decor })
	part({ Name = "Parapet", Size = Vector3.new(62, 2.5, 1), CFrame = at(0, 17.2, 25.2), Color = BRAND.Red, Parent = decor })

	-- Brand sign on the header: round logo + name
	part({ Name = "Logo", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 5, 5), CFrame = at(-15, 15.5, 26) * CFrame.Angles(0, math.pi / 2, 0), Color = BRAND.Cream, Parent = decor })
	part({ Name = "LogoSlice", Size = Vector3.new(2.4, 2.4, 0.2), CFrame = at(-15, 15.5, 26.25) * CFrame.Angles(0, 0, math.rad(45)), Color = BRAND.Gold, Parent = decor })
	part({ Name = "LogoPepperoni", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 0.8, 0.8), CFrame = at(-15, 15.6, 26.4) * CFrame.Angles(0, math.pi / 2, 0), Color = BRAND.Red, Parent = decor })
	local sign = part({ Name = "Sign", Size = Vector3.new(24, 3.4, 0.4), CFrame = at(2, 15.5, 25.9), Color = BRAND.Red, Parent = decor })
	local signText = screenText(sign, Enum.NormalId.Back, string.upper(shopName), Color3.new(1, 1, 1), nil, Enum.Font.FredokaOne, Vector2.new(720, 100))
	signText.Name = "ShopName"
	local service = part({ Name = "ServiceSign", Size = Vector3.new(11, 1.2, 0.1), CFrame = at(0, 10.5, 25.3), Color = BRAND.Charcoal, Parent = decor })
	screenText(service, Enum.NormalId.Back, "CARRYOUT  |  DELIVERY", BRAND.Gold)

	-- Ceiling light panels
	for _, pos in { Vector2.new(-15, 18), Vector2.new(10, 18), Vector2.new(-15, 2), Vector2.new(5, 2), Vector2.new(20, -8), Vector2.new(-15, -15), Vector2.new(10, -15) } do
		local panel = part({ Name = "LightPanel", Size = Vector3.new(6, 0.2, 3), CFrame = at(pos.X, 14.85, pos.Y), Color = Color3.fromRGB(255, 252, 240), Material = Enum.Material.Neon, CanCollide = false, Parent = decor })
		local light = Instance.new("SurfaceLight")
		light.Face = Enum.NormalId.Bottom
		light.Range = 16
		light.Brightness = 1.2
		light.Angle = 120
		light.Color = Color3.fromRGB(255, 245, 225)
		light.Parent = panel
	end

	-- === Lobby ===
	-- Front counter (customers +Z side) with staff gap at x 14..18, then a half wall.
	part({ Name = "Counter", Size = Vector3.new(44, 4, 3), CFrame = at(-8, 3, 12), Color = BRAND.Charcoal, Parent = decor })
	part({ Name = "CounterFace", Size = Vector3.new(44, 1.2, 0.1), CFrame = at(-8, 3.4, 13.55), Color = BRAND.Red, Parent = decor })
	part({ Name = "CounterTop", Size = Vector3.new(44, 0.4, 3.4), CFrame = at(-8, 5.2, 12), Color = Color3.fromRGB(235, 235, 232), Material = Enum.Material.Marble, Parent = decor })
	part({ Name = "HalfWall", Size = Vector3.new(12, 4.5, 1), CFrame = at(24, 3.25, 12), Color = BRAND.Charcoal, Parent = decor })
	-- Second (decorative) POS at the counter
	StationArt.Build("Register", decor, at(-16, 5.4, 12))

	-- Digital menu boards over the counter, facing the lobby
	local menuItems = {
		{ "PIZZAS", "Cheese  Pepperoni\nHawaiian  Veggie\nSupreme" },
		{ "SIZES", string.format("Small $%d\nMedium $%d\nLarge $%d", Config.SizePrice.Small, Config.SizePrice.Medium, Config.SizePrice.Large) },
		{ "DEAL", "Any 2 Mediums\n$9.99 each\nCarryout only" },
	}
	for i, item in menuItems do
		local x = -24 + (i - 1) * 8
		local board = part({ Name = "MenuScreen" .. i, Size = Vector3.new(7.2, 4, 0.3), CFrame = at(x, 12.6, 11.2), Color = Color3.fromRGB(15, 15, 18), Parent = decor })
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Back
		gui.CanvasSize = Vector2.new(360, 200)
		gui.LightInfluence = 0
		local bg = Instance.new("Frame")
		bg.Size = UDim2.fromScale(1, 1)
		bg.BackgroundColor3 = if i == 3 then BRAND.Red else BRAND.Charcoal
		bg.BorderSizePixel = 0
		bg.Parent = gui
		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, 0, 0, 50)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.FredokaOne
		title.TextScaled = true
		title.TextColor3 = BRAND.Gold
		title.Text = item[1]
		title.Parent = bg
		local body = Instance.new("TextLabel")
		body.Position = UDim2.fromOffset(10, 55)
		body.Size = UDim2.new(1, -20, 1, -65)
		body.BackgroundTransparency = 1
		body.Font = Enum.Font.GothamBold
		body.TextScaled = true
		body.TextColor3 = Color3.new(1, 1, 1)
		body.Text = item[2]
		body.Parent = bg
		gui.Parent = board
	end
	local orderHere = part({ Name = "OrderHere", Size = Vector3.new(4, 0.9, 0.1), CFrame = at(-6, 10.1, 12.2), Color = BRAND.Red, Parent = decor })
	screenText(orderHere, Enum.NormalId.Back, "ORDER HERE", Color3.new(1, 1, 1))

	-- Order tracker TV on the lobby wall (ShopService writes to it)
	local tracker = part({ Name = "TrackerScreen", Size = Vector3.new(0.3, 4.4, 8), CFrame = at(-29.3, 8.5, 18.5), Color = Color3.fromRGB(10, 10, 12), Parent = decor })
	local trackerGui = Instance.new("SurfaceGui")
	trackerGui.Name = "Tracker"
	trackerGui.Face = Enum.NormalId.Right
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

	-- Waiting bench under the window
	part({ Name = "BenchSeat", Size = Vector3.new(12, 0.6, 2), CFrame = at(-21, 2.8, 22.8), Color = Color3.fromRGB(150, 105, 65), Material = Enum.Material.WoodPlanks, Parent = decor })
	part({ Name = "BenchBase", Size = Vector3.new(11.5, 1.6, 1.6), CFrame = at(-21, 1.8, 22.8), Color = BRAND.Charcoal, Parent = decor })
	-- Drink cooler on the right lobby wall
	part({ Name = "DrinkCooler", Size = Vector3.new(2.4, 7, 4), CFrame = at(28.6, 4.5, 19), Color = BRAND.Red, Parent = decor })
	part({ Name = "CoolerGlass", Size = Vector3.new(0.1, 5.4, 3.4), CFrame = at(27.35, 4.6, 19), Color = glass, Transparency = 0.5, Material = Enum.Material.Glass, Parent = decor })
	for row = 0, 3 do
		for col = 0, 4 do
			local c = ({ Color3.fromRGB(200, 30, 30), Color3.fromRGB(30, 120, 200), Color3.fromRGB(240, 200, 40), Color3.fromRGB(60, 170, 70) })[row + 1]
			part({ Name = "Bottle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.0, 0.45, 0.45), CFrame = at(27.9, 2.7 + row * 1.3, 17.6 + col * 0.7) * CFrame.Angles(0, 0, math.pi / 2), Color = c, Material = Enum.Material.Glass, CanCollide = false, Parent = decor })
		end
	end

	-- === Kitchen ===
	-- Kitchen display (KDS) over the make-line, facing the makers (ShopService writes to it)
	local kds = part({ Name = "TicketBoard", Size = Vector3.new(16, 3, 0.3), CFrame = at(-8, 9.6, 6.2), Color = Color3.fromRGB(10, 10, 12), Parent = decor })
	local kdsGui = Instance.new("SurfaceGui")
	kdsGui.Name = "Tickets"
	kdsGui.Face = Enum.NormalId.Front -- Front is -Z: toward the makers
	kdsGui.CanvasSize = Vector2.new(800, 150)
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
	for _, x in { -15, -1 } do
		part({ Name = "KdsMount", Size = Vector3.new(0.2, 4, 0.2), CFrame = at(x, 13, 6.2), Color = Color3.fromRGB(60, 60, 60), Material = Enum.Material.Metal, Parent = decor })
	end

	-- Conveyor oven (not a station: pizzas ride through it automatically)
	StationArt.Build("Oven", decor, at(7, 1, 4))

	-- 3-compartment sink on the back wall
	local sinkBase = at(-22, 1, -23.2) * CFrame.Angles(0, math.pi, 0)
	part({ Name = "SinkBody", Size = Vector3.new(10, 3.2, 2.6), CFrame = sinkBase * CFrame.new(0, 1.6, 0), Color = Color3.fromRGB(196, 200, 206), Material = Enum.Material.Metal, Parent = decor })
	for i = -1, 1 do
		part({ Name = "SinkBasin", Size = Vector3.new(2.8, 0.1, 2), CFrame = sinkBase * CFrame.new(i * 3.1, 3.1, 0), Color = Color3.fromRGB(120, 160, 190), Material = Enum.Material.Glass, Transparency = 0.3, CanCollide = false, Parent = decor })
		part({ Name = "Faucet", Size = Vector3.new(0.2, 1.4, 0.2), CFrame = sinkBase * CFrame.new(i * 3.1, 3.9, 1.1), Color = Color3.fromRGB(150, 150, 155), Material = Enum.Material.Metal, Parent = decor })
	end
	part({ Name = "Splash", Size = Vector3.new(10, 2, 0.15), CFrame = sinkBase * CFrame.new(0, 4.2, 1.3), Color = Color3.fromRGB(196, 200, 206), Material = Enum.Material.Metal, Parent = decor })
	-- Manager desk in the back office
	part({ Name = "Desk", Size = Vector3.new(5, 0.3, 2.4), CFrame = at(10, 3.6, -22.8), Color = Color3.fromRGB(110, 80, 55), Material = Enum.Material.Wood, Parent = decor })
	part({ Name = "DeskBody", Size = Vector3.new(1.6, 2.4, 2.2), CFrame = at(11.6, 2.25, -22.8), Color = Color3.fromRGB(90, 65, 45), Material = Enum.Material.Wood, Parent = decor })
	part({ Name = "Monitor", Size = Vector3.new(2, 1.3, 0.12), CFrame = at(9.5, 4.6, -23.6), Color = Color3.fromRGB(15, 15, 18), Parent = decor })
	-- Sales board: today's/this week's sales vs. forecast (ShopService writes to it)
	local salesBoard = part({ Name = "SalesBoard", Size = Vector3.new(6, 3.6, 0.15), CFrame = at(-2, 6.5, -24.4), Color = Color3.fromRGB(12, 16, 22), Parent = decor })
	local salesGui = Instance.new("SurfaceGui")
	salesGui.Name = "Sales"
	salesGui.Face = Enum.NormalId.Back -- faces into the store (+Z)
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
	-- Dry storage shelf
	for i = 0, 3 do
		part({ Name = "DryShelf", Size = Vector3.new(8, 0.15, 2), CFrame = at(-21, 1.5 + i * 2.2, -6), Color = Color3.fromRGB(205, 208, 212), Material = Enum.Material.DiamondPlate, Parent = decor })
		for j = -1, 1 do
			part({ Name = "Case", Size = Vector3.new(2, 1.4, 1.6), CFrame = at(-21 + j * 2.5, 2.3 + i * 2.2, -6), Color = Color3.fromRGB(180, 140, 90), Material = Enum.Material.Cardboard, CanCollide = false, Parent = decor })
		end
	end
	for _, x in { -25, -17 } do
		for _, z in { -7, -5 } do
			part({ Name = "ShelfPost", Size = Vector3.new(0.15, 9, 0.15), CFrame = at(x, 5.5, z), Color = Color3.fromRGB(215, 218, 222), Material = Enum.Material.Metal, Parent = decor })
		end
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
			-- Where the 3D pizza sits during this station's minigame (art-local, on the work surface).
			p:SetAttribute("PizzaAt", pizzaAt)
		end
		prompt(p, action, title)
		if kind == "Register" then
			-- Clocking in and out happens at the order-taking station (F), alongside taking orders (E).
			local clock = prompt(p, "Clock In / Out", "Register")
			clock.Name = "ClockPrompt"
			clock.KeyboardKeyCode = Enum.KeyCode.F
			clock.GamepadKeyCode = Enum.KeyCode.ButtonY
			clock.UIOffset = Vector2.new(0, 72)
		end
		StationArt.Build(kind, p, art)
		return p
	end

	local FACE_FRONT = CFrame.Angles(0, math.pi, 0) -- worker toward the shop front (+Z)
	local FACE_RIGHT = CFrame.Angles(0, -math.pi / 2, 0) -- worker toward +X
	local FACE_LEFT = CFrame.Angles(0, math.pi / 2, 0) -- worker toward -X

	-- Front counter: register and the carryout warmer (faces the lobby).
	station("Register", at(-6, 5.4, 12), Vector3.new(3, 2, 2), "Take Order", "Register")
	station("Pickup", at(10, 5.4, 12) * FACE_FRONT, Vector3.new(6, 1, 3), "Carryout", "Carryout")
	-- Dough table (stretch + sauce, with the screen racks on it) and the make-line
	-- (cheese + toppings), one long row facing the lobby. Makers stand on the
	-- kitchen side (-Z). Each piece is built once as decor; its stations are
	-- hitboxes placed over the work spots from StationArt.Layout.
	local DT, ML = StationArt.Layout.DoughTable, StationArt.Layout.MakeLine
	local doughX, makeX = -20.5, -7.5
	StationArt.Build("DoughTable", decor, at(doughX, 1, 4))
	StationArt.Build("MakeLine", decor, at(makeX, 1, 4))
	local doughWork = Vector3.new(0, DT.height, DT.workZ)
	local makeWork = Vector3.new(0, ML.boardTop, ML.boardZ)
	station("Dough", at(doughX + DT.stretchX, 1, 4), Vector3.new(3, 4, 3.6), "Stretch Dough", "Dough Table", nil, doughWork)
	station("Sauce", at(doughX + DT.sauceX, 1, 4), Vector3.new(3, 4, 3.6), "Sauce", "Dough Table", nil, doughWork)
	station("Cheese", at(makeX + ML.cheeseX, 1, 4), Vector3.new(3, 4, 3.6), "Cheese", "Make-Line", nil, makeWork)
	station("Toppings", at(makeX + ML.toppingsX, 1, 4), Vector3.new(3, 4, 3.6), "Toppings", "Make-Line", nil, makeWork)
	station("CutTable", at(18.7, 1, 4), Vector3.new(10, 4, 5.6), "Cut & Box", "Cut Table", nil, Vector3.new(-0.6, 3.2, -1.5))
	station("DeliveryRack", at(28.3, 1, -4) * FACE_LEFT, Vector3.new(6, 7, 2.2), "Grab Delivery", "Heat Rack")
	station("Fridge", at(-27.4, 1, -12) * FACE_RIGHT, Vector3.new(6, 10, 4), "Check Stock", "Walk-in Cooler")
	station("SupplyTruck", at(-10, 0, -30) * FACE_FRONT, Vector3.new(8, 4, 3), "Unload Truck", "Supply Truck", CFrame.new(0, 2, -1.5))

	-- === Lot out back ===
	part({ Name = "ParkingLot", Size = Vector3.new(36, 0.2, 28), CFrame = at(17, 0.1, -42), Color = Color3.fromRGB(55, 55, 60), Material = Enum.Material.Asphalt, CanCollide = false, Parent = decor })
	part({ Name = "LoadingPad", Size = Vector3.new(14, 0.2, 24), CFrame = at(-10, 0.1, -38), Color = Color3.fromRGB(120, 120, 125), Material = Enum.Material.Concrete, CanCollide = false, Parent = decor })
	for i = 0, 4 do
		part({ Name = "Stripe", Size = Vector3.new(0.4, 0.05, 10), CFrame = at(3 + i * 8, 0.22, -46), Color = Color3.new(1, 1, 1), CanCollide = false, Parent = decor })
	end
	for i = 1, 4 do
		spot(spots, "Parking" .. i, at(7 + (i - 1) * 8, 2, -46))
	end
	local lotSign = part({ Name = "LotSign", Size = Vector3.new(8, 1.6, 0.3), CFrame = at(17, 5, -55.8), Color = Color3.fromRGB(46, 160, 90), Parent = decor })
	screenText(lotSign, Enum.NormalId.Back, "DELIVERY PARKING ONLY", Color3.new(1, 1, 1))
	part({ Name = "LotSignPost", Size = Vector3.new(0.3, 4.4, 0.3), CFrame = at(17, 2.2, -55.8), Color = Color3.fromRGB(90, 90, 95), Material = Enum.Material.Metal, Parent = decor })

	-- Customer path
	spot(spots, "CustomerSpawn", at(0, 3, 45))
	spot(spots, "Queue1", at(-7, 3, 15.5))
	spot(spots, "Queue2", at(-7, 3, 19))
	spot(spots, "Queue3", at(-7, 3, 22.5))
	spot(spots, "Wait1", at(6, 3, 16.5))
	spot(spots, "Wait2", at(11, 3, 19.5))
	spot(spots, "Wait3", at(3, 3, 20.5))
	spot(spots, "Exit", at(0, 3, 60))

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
	local base = part({ Name = "Base", Size = Vector3.new(84, 0.4, 100), CFrame = cf * CFrame.new(2, 0.2, -18), Color = Color3.fromRGB(140, 120, 90), Material = Enum.Material.Ground, Parent = model })
	local signPost = part({ Name = "ForSale", Size = Vector3.new(10, 6, 0.5), CFrame = cf * CFrame.new(0, 5, 30), Color = Color3.fromRGB(255, 255, 255), Parent = model })
	prompt(signPost, "Franchise Info", "Lot #" .. id)
	label(signPost, "FRANCHISE LOT\nOpen your own store!", 5, UDim2.fromOffset(220, 60))
	model.Parent = parent
	return base
end

export type World = {
	hq: Model,
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

	-- Roads: Main Street (neighborhood), an avenue east of the HQ, a back
	-- street past the franchise lots, and a driveway from the HQ lot.
	local roadColor = Color3.fromRGB(55, 55, 60)
	local function road(name: string, size: Vector3, pos: Vector3)
		part({ Name = name, Size = size, CFrame = CFrame.new(pos), Color = roadColor, Material = Enum.Material.Asphalt, CanCollide = false, Parent = map })
	end
	road("MainStreet", Vector3.new(920, 0.2, 26), Vector3.new(0, 0.1, 190))
	-- Overlapping road surfaces sit at distinct heights so they don't z-fight.
	road("Avenue", Vector3.new(26, 0.2, 360), Vector3.new(52, 0.14, 15))
	road("BackStreet", Vector3.new(300, 0.2, 24), Vector3.new(-85, 0.1, -130))
	road("LotDriveway", Vector3.new(18, 0.2, 16), Vector3.new(42, 0.18, -42))
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

	local hq = MapBuilder.BuildShop(CFrame.new(0, 0, 0), Config.GameName, shops)
	hq.Name = "HQ"

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

	-- Franchise lots north of the HQ.
	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = workspace
	local plots = {}
	for i, x in { -195, -95, 5, 105 } do
		local cf = CFrame.new(x, 0, -200)
		local model = buildPlot(i, cf, plotsFolder).Parent :: Model
		table.insert(plots, { id = i, cframe = cf, model = model })
	end

	-- Trees, kept off roads, houses, lots and the HQ.
	local rng = Random.new(7)
	for _ = 1, 90 do
		local x = rng:NextNumber(-580, 580)
		local z = rng:NextNumber(-580, 580)
		local clear = (math.abs(z - 190) < 80) -- Main Street + houses
			or (math.abs(x - 52) < 25 and z > -170 and z < 200) -- Avenue
			or (math.abs(z + 130) < 20 and x > -240 and x < 70) -- Back Street
			or (z > -280 and z < -140 and x > -250 and x < 160) -- franchise lots
			or (x > -45 and x < 70 and z > -70 and z < 90) -- HQ + lot
		if not clear then
			part({ Name = "Trunk", Size = Vector3.new(2, 10, 2), CFrame = CFrame.new(x, 5, z), Color = Color3.fromRGB(100, 70, 40), Material = Enum.Material.Wood, Parent = map })
			part({ Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.new(12, 12, 12), CFrame = CFrame.new(x, 13, z), Color = Color3.fromRGB(50, 130, 50), Material = Enum.Material.Grass, Parent = map })
		end
	end

	return { hq = hq, houses = houses, plots = plots }
end

return MapBuilder
