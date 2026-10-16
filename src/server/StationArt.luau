--!strict
-- Detailed visuals for each station, built from parts.
--
-- Convention for every builder: `base` is the station's floor-center (or
-- mount point), with LookVector (-Z) pointing at where the worker stands.
--
-- To use a real model instead, put a Model named after the station kind in
-- ServerStorage/StationModels (e.g. "Oven", "DoughTable", "MakeLine"). Set its pivot to the bottom
-- center with the front facing the pivot's LookVector; it replaces the
-- generated art everywhere, franchises included.

local ServerStorage = game:GetService("ServerStorage")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local StationArt = {}

local STEEL = Color3.fromRGB(196, 200, 206)
local STEEL_DARK = Color3.fromRGB(120, 124, 130)
local BLACK = Color3.fromRGB(25, 25, 28)
local WOOD = Color3.fromRGB(160, 115, 70)
local DOUGH = Config.IngredientColors.Dough

type Opts = { shape: Enum.PartType?, transparency: number?, collide: boolean?, name: string?, reflect: number? }

local function P(parent: Instance, base: CFrame, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, opts: Opts?): Part
	local p = Instance.new("Part")
	p.Name = (opts and opts.name) or "Detail"
	p.Anchored = true
	if opts and opts.shape then
		p.Shape = opts.shape
	end
	p.Size = size
	p.CFrame = base * offset
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Transparency = (opts and opts.transparency) or 0
	p.Reflectance = (opts and opts.reflect) or 0
	-- Small details shouldn't snag players; big bodies stay solid.
	local collide = if opts and opts.collide ~= nil then opts.collide else (size.X * size.Y * size.Z > 2)
	p.CanCollide = collide
	p.CanTouch = false
	p.CastShadow = size.Magnitude > 1
	p.Parent = parent
	return p
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

-- Upright cylinder (Roblox cylinders run along X).
local function up(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.pi / 2)
end

local function surfaceText(part: BasePart, face: Enum.NormalId, text: string, color: Color3, bg: Color3?, font: Enum.Font?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundColor3 = bg or Color3.new(0, 0, 0)
	tl.BackgroundTransparency = if bg then 0 else 1
	tl.BorderSizePixel = 0
	tl.Font = font or Enum.Font.GothamBlack
	tl.TextScaled = true
	tl.TextColor3 = color
	tl.Text = text
	tl.Parent = gui
	gui.Parent = part
	return tl
end

local function steelTable(parent: Instance, base: CFrame, w: number, d: number, h: number)
	P(parent, base, Vector3.new(w, 0.3, d), at(0, h - 0.15, 0), STEEL, Enum.Material.Metal, { reflect = 0.1 })
	-- Rolled front edge
	P(parent, base, Vector3.new(w, 0.5, 0.1), at(0, h - 0.25, -d / 2 - 0.05), STEEL, Enum.Material.Metal)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			P(parent, base, Vector3.new(0.3, h - 0.3, 0.3), up(sx * (w / 2 - 0.3), (h - 0.3) / 2, sz * (d / 2 - 0.3)), STEEL_DARK, Enum.Material.Metal, { shape = Enum.PartType.Cylinder, collide = true })
			P(parent, base, Vector3.new(0.15, 0.45, 0.45), up(sx * (w / 2 - 0.3), 0.07, sz * (d / 2 - 0.3)), BLACK, Enum.Material.Rubber, { shape = Enum.PartType.Cylinder })
		end
	end
	P(parent, base, Vector3.new(w - 0.6, 0.15, d - 0.6), at(0, 0.9, 0), STEEL, Enum.Material.DiamondPlate)
end

local function crate(parent: Instance, base: CFrame, offset: CFrame, ingredient: string)
	P(parent, base, Vector3.new(1.8, 1.4, 1.8), offset * at(0, 0.7, 0), Color3.fromRGB(176, 130, 80), Enum.Material.WoodPlanks, { collide = true })
	P(parent, base, Vector3.new(1.9, 0.15, 1.9), offset * at(0, 1.47, 0), Config.IngredientColors[ingredient] or WOOD, Enum.Material.SmoothPlastic)
	local tag = P(parent, base, Vector3.new(1.2, 0.5, 0.05), offset * at(0, 0.75, -0.93), Color3.fromRGB(245, 240, 225))
	surfaceText(tag, Enum.NormalId.Front, string.upper(ingredient), Color3.fromRGB(40, 30, 20))
end

---------------------------------------------------------------------------

local Builders: { [string]: (Instance, CFrame) -> () } = {}

-- Shared layout for the multi-station pieces, so MapBuilder can put each
-- station's hitbox over the right spot. All values are art-local (worker at -Z).
StationArt.Layout = {
	DoughTable = {
		width = 11,
		depth = 4.8,
		height = 3.4,
		workZ = -1.15, -- both work spots sit near the front edge
		stretchX = -3.0,
		sauceX = 1.9,
		rackX = { -1.35, -4.1 }, -- rack 1 nearest the sauce spot
		rackZ = 1.25,
		rackWidth = 2.6,
		rackDepth = 2.2,
		slotSpacing = 0.2,
		bucketX = 2.3,
		bucketZ = 1.4,
		screensX = 4.3,
		screensZ = -0.9,
	},
	MakeLine = {
		width = 13,
		boardZ = -1.05,
		boardTop = 3.445,
		saucedQueueX = -4.875,
		cheeseX = -1.625,
		cheesedQueueX = 1.625,
		toppingsX = 4.875, -- next to the oven entrance
	},
}

-- POS terminal on a cash drawer, sitting on the counter. Worker is at -Z.
Builders.Register = function(m, base)
	P(m, base, Vector3.new(2.6, 0.55, 2), at(0, 0.275, 0), Color3.fromRGB(45, 45, 50), Enum.Material.SmoothPlastic, { name = "CashDrawer" })
	P(m, base, Vector3.new(1.6, 0.06, 0.08), at(0, 0.32, -1.02), STEEL_DARK, Enum.Material.Metal) -- drawer seam/handle
	P(m, base, Vector3.new(0.35, 0.9, 0.35), up(0, 1.0, 0.3), STEEL_DARK, Enum.Material.Metal, { shape = Enum.PartType.Cylinder })
	-- Positive X tilt leans the top back, so the screen faces up toward the worker.
	local screen = P(m, base, Vector3.new(2.2, 1.5, 0.15), at(0, 1.75, 0.3) * CFrame.Angles(math.rad(18), 0, 0), BLACK, Enum.Material.Glass, { name = "Screen" })
	-- Mock POS UI on the screen
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.Brightness = 1.5
	gui.CanvasSize = Vector2.new(220, 150)
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(20, 30, 45)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, 0, 0, 22)
	header.BackgroundColor3 = Color3.fromRGB(200, 50, 40)
	header.BorderSizePixel = 0
	header.Font = Enum.Font.GothamBold
	header.TextScaled = true
	header.TextColor3 = Color3.new(1, 1, 1)
	header.Text = "NEW ORDER"
	header.Parent = bg
	local grid = Instance.new("Frame")
	grid.Position = UDim2.fromOffset(6, 28)
	grid.Size = UDim2.new(1, -12, 1, -34)
	grid.BackgroundTransparency = 1
	grid.Parent = bg
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(1 / 3, -4, 0.5, -4)
	layout.CellPadding = UDim2.fromOffset(4, 4)
	layout.Parent = grid
	local tileColors = { Color3.fromRGB(240, 190, 60), Color3.fromRGB(200, 70, 60), Color3.fromRGB(240, 150, 150), Color3.fromRGB(80, 170, 80), Color3.fromRGB(140, 90, 200), Color3.fromRGB(60, 140, 220) }
	for i, name in { "Cheese", "Pepp.", "Hawaii", "Veggie", "Supreme", "PAY" } do
		local tile = Instance.new("TextLabel")
		tile.BackgroundColor3 = tileColors[i]
		tile.BorderSizePixel = 0
		tile.Font = Enum.Font.GothamBold
		tile.TextScaled = true
		tile.TextColor3 = Color3.new(1, 1, 1)
		tile.Text = name
		tile.Parent = grid
	end
	gui.Parent = screen
	-- Receipt printer + paper
	P(m, base, Vector3.new(0.8, 0.5, 0.9), at(1.75, 0.25, 0.2), Color3.fromRGB(60, 60, 65))
	P(m, base, Vector3.new(0.5, 0.02, 0.5), at(1.75, 0.52, -0.1) * CFrame.Angles(math.rad(-30), 0, 0), Color3.new(1, 1, 1))
	-- Customer-facing card reader + display
	P(m, base, Vector3.new(0.45, 0.7, 0.12), at(-1.6, 0.4, 0.85) * CFrame.Angles(math.rad(15), 0, 0), Color3.fromRGB(35, 35, 40))
	-- Leans toward the worker so its Back face tips up toward the customer.
	local disp = P(m, base, Vector3.new(0.9, 0.5, 0.1), at(0, 1.25, 0.65) * CFrame.Angles(math.rad(-10), 0, 0), BLACK, Enum.Material.Glass)
	surfaceText(disp, Enum.NormalId.Back, "$0.00", Color3.fromRGB(90, 255, 120), BLACK, Enum.Font.Code)
	-- Order ticket spike
	P(m, base, Vector3.new(0.05, 0.6, 0.05), at(-1.7, 0.3, -0.5), STEEL, Enum.Material.Metal)
	P(m, base, Vector3.new(0.5, 0.02, 0.4), at(-1.7, 0.15, -0.5), Color3.fromRGB(250, 250, 240))
end

-- The dough table, modeled on a real store's: a long stainless table with two
-- 15-slot pizza-screen racks standing on it (back left), a sauce bucket with a
-- spoodle (back right), a stack of spare screens, and two work spots along the
-- front: stretching (left) and saucing (right), kept apart so they don't get in
-- each other's way. SkinSlot_<n> markers sit where a screen rests in the racks
-- (rack 1 top to bottom, then rack 2); ShopService puts each skin in its slot.
Builders.DoughTable = function(m, base)
	local L = StationArt.Layout.DoughTable
	local w, d, h = L.width, L.depth, L.height
	steelTable(m, base, w, d, h)

	-- Cornmeal dusting at the stretch spot, a few drips at the sauce spot
	P(m, base, Vector3.new(0.02, 2.6, 2.6), up(L.stretchX, h + 0.01, L.workZ), Color3.fromRGB(235, 195, 110), Enum.Material.Sand, { shape = Enum.PartType.Cylinder, collide = false })
	for _, drip in { { 1.3, -0.5, 0.3 }, { -1.1, 0.7, 0.18 } } do
		P(m, base, Vector3.new(0.02, drip[3], drip[3]), up(L.sauceX + drip[1], h + 0.01, L.workZ + drip[2]), Config.IngredientColors.Sauce, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder, collide = false })
	end

	-- Two chrome pizza-screen racks standing on the table: floor frame, side
	-- frames, and a pair of front-to-back rails per slot with a short inward hook
	-- at the front. Screens slide in from the front (-Z).
	local CHROME = Color3.fromRGB(215, 218, 222)
	local wire = 0.05
	local RW, RD = L.rackWidth, L.rackDepth
	local slotCount = Config.Dough.SlotsPerRack
	local topRail = h + 0.2 + (slotCount - 1) * L.slotSpacing
	local slot = 0
	for r = 1, Config.Dough.Racks do
		local cx, cz = L.rackX[r], L.rackZ
		local front, back = cz - RD / 2 + 0.06, cz + RD / 2 - 0.04
		local function bar(size: Vector3, offset: CFrame)
			P(m, base, size, offset, CHROME, Enum.Material.Metal, { reflect = 0.25, collide = false })
		end
		for _, sx in { -1, 1 } do
			bar(Vector3.new(wire, wire, RD), at(cx + sx * RW / 2, h + 0.03, cz))
		end
		for _, z in { cz - RD / 2, cz + RD / 2 } do
			bar(Vector3.new(RW, wire, wire), at(cx, h + 0.03, z))
		end
		for _, sx in { -1, 1 } do
			local x = cx + sx * RW / 2
			local mid = cz + 0.1
			bar(Vector3.new(wire, topRail - h + 0.15, wire), at(x, (h + topRail + 0.15) / 2, back))
			bar(Vector3.new(wire, topRail - h + 0.15, wire), at(x, (h + topRail + 0.15) / 2, mid))
			bar(Vector3.new(wire, wire, back - mid), at(x, topRail + 0.15, (back + mid) / 2))
			bar(Vector3.new(wire, 0.8, wire), at(x, h + 0.35, cz - 0.25) * CFrame.Angles(math.rad(-30), 0, 0))
			for i = 1, slotCount do
				local y = topRail - (i - 1) * L.slotSpacing
				bar(Vector3.new(wire, wire, back - front), at(x, y, (front + back) / 2))
				bar(Vector3.new(0.25, wire, wire), at(x - sx * 0.125, y, front))
			end
		end
		P(m, base, Vector3.new(RW, topRail - h + 0.2, RD), at(cx, (h + topRail + 0.2) / 2, cz), CHROME, nil, { name = "RackBounds", transparency = 1, collide = true })
		for i = 1, slotCount do
			slot += 1
			P(m, base, Vector3.new(0.1, 0.1, 0.1), at(cx, topRail - (i - 1) * L.slotSpacing + wire / 2, cz), CHROME, nil, { name = "SkinSlot_" .. slot, transparency = 1, collide = false })
		end
	end

	-- Sauce bucket (clear tub of sauce, red lid set aside) with a spoodle in front of it
	local bx, bz = L.bucketX, L.bucketZ
	P(m, base, Vector3.new(1.5, 1.45, 1.45), up(bx, h + 0.75, bz), Color3.fromRGB(235, 240, 245), Enum.Material.Glass, { shape = Enum.PartType.Cylinder, transparency = 0.45, name = "SauceBucket" })
	P(m, base, Vector3.new(1.1, 1.32, 1.32), up(bx, h + 0.6, bz), Config.IngredientColors.Sauce, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder, collide = false })
	P(m, base, Vector3.new(0.06, 1.5, 1.5), up(bx + 1.7, h + 0.03, bz + 0.1), Color3.fromRGB(200, 30, 30), Enum.Material.Plastic, { shape = Enum.PartType.Cylinder, collide = false })
	P(m, base, Vector3.new(0.1, 0.5, 0.5), up(bx - 0.5, h + 0.05, bz - 1.0), STEEL, Enum.Material.Metal, { shape = Enum.PartType.Cylinder, collide = false })
	P(m, base, Vector3.new(0.9, 0.05, 0.07), at(bx + 0.2, h + 0.06, bz - 1.0), STEEL, Enum.Material.Metal, { collide = false })
	P(m, base, Vector3.new(0.5, 0.1, 0.12), at(bx + 0.85, h + 0.07, bz - 1.0), Color3.fromRGB(200, 30, 30), Enum.Material.Plastic, { collide = false })

	-- Spare screens stacked on the table, and a tray of dough balls at the far end
	for i = 0, 9 do
		P(m, base, Vector3.new(0.025, 2.5, 2.5), up(L.screensX, h + 0.03 + i * 0.04, L.screensZ), STEEL_DARK, Enum.Material.DiamondPlate, { shape = Enum.PartType.Cylinder, collide = false })
	end
	P(m, base, Vector3.new(1.1, 0.3, 1.8), at(-w / 2 + 0.65, h + 0.15, L.workZ), Color3.fromRGB(235, 235, 230), Enum.Material.Plastic, { name = "DoughTray" })
	for j = 0, 1 do
		P(m, base, Vector3.new(0.55, 0.55, 0.55), at(-w / 2 + 0.65, h + 0.45, L.workZ - 0.45 + j * 0.9), DOUGH, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Ball, collide = false })
	end
	-- Cart of proofed dough trays under the table
	for i = 0, 3 do
		P(m, base, Vector3.new(4.2, 0.35, 2.8), at(L.stretchX, 1.15 + i * 0.38, 0), Color3.fromRGB(225, 225, 220), Enum.Material.Plastic, { collide = i == 0 })
	end
end

-- Refrigerated make-line: cabinet, cutting board along the front, ingredient
-- pans on the rail, open lid. The board is split into four zones, oven side
-- last: sauced pizzas waiting (SaucedQueue marker), the cheese spot, cheesed
-- pizzas waiting (CheesedQueue marker), and the toppings spot by the oven.
Builders.MakeLine = function(m, base)
	local L = StationArt.Layout.MakeLine
	local w = L.width
	P(m, base, Vector3.new(w, 0.4, 3.4), at(0, 0.2, 0.1), BLACK, Enum.Material.SmoothPlastic) -- kick plate
	P(m, base, Vector3.new(w, 2.8, 3.6), at(0, 1.8, 0), STEEL, Enum.Material.Metal, { name = "Cabinet", reflect = 0.05 })
	for i, zone in { L.saucedQueueX, L.cheeseX, L.cheesedQueueX, L.toppingsX } do
		P(m, base, Vector3.new(3.0, 2.2, 0.08), at(zone, 1.75, -1.84), Color3.fromRGB(210, 214, 220), Enum.Material.Metal, { name = "Door" .. i })
		P(m, base, Vector3.new(2.2, 0.15, 0.2), at(zone, 2.65, -1.95), STEEL_DARK, Enum.Material.Metal)
	end
	-- Cutting board along the front, with faint lines between the four zones
	P(m, base, Vector3.new(w, 0.25, 1.5), at(0, L.boardTop - 0.125, L.boardZ), Color3.fromRGB(240, 240, 235), Enum.Material.Plastic, { name = "CuttingBoard" })
	for _, x in { (L.saucedQueueX + L.cheeseX) / 2, (L.cheeseX + L.cheesedQueueX) / 2, (L.cheesedQueueX + L.toppingsX) / 2 } do
		P(m, base, Vector3.new(0.04, 0.01, 1.5), at(x, L.boardTop + 0.005, L.boardZ), Color3.fromRGB(200, 200, 195), Enum.Material.SmoothPlastic, { collide = false })
	end
	-- Raised rail with ingredient pans (2 rows x 4)
	P(m, base, Vector3.new(w, 0.7, 2.1), at(0, 3.55, 0.75), STEEL, Enum.Material.Metal, { name = "Rail" })
	local pans = { "Cheese", "Pepperoni", "Ham", "Pineapple", "Peppers", "Mushrooms", "Olives", "Sauce" }
	for i, ing in pans do
		local col = (i - 1) % 4
		local row = math.floor((i - 1) / 4)
		local x = -4.5 + col * 3
		local z = 0.25 + row * 1.0
		P(m, base, Vector3.new(2.7, 0.1, 0.85), at(x, 3.88, z), STEEL_DARK, Enum.Material.Metal)
		P(m, base, Vector3.new(2.5, 0.08, 0.7), at(x, 3.92, z), Config.IngredientColors[ing], if ing == "Cheese" or ing == "Pineapple" then Enum.Material.Sand else Enum.Material.SmoothPlastic, { collide = false })
	end
	-- Open lid behind the rail
	P(m, base, Vector3.new(w, 1.4, 0.12), at(0, 4.4, 1.95) * CFrame.Angles(math.rad(-20), 0, 0), STEEL, Enum.Material.Metal)
	-- Where waiting pizzas sit (ShopService lines them up here)
	P(m, base, Vector3.new(0.1, 0.1, 0.1), at(L.saucedQueueX, L.boardTop, L.boardZ), BLACK, nil, { name = "SaucedQueue", transparency = 1, collide = false })
	P(m, base, Vector3.new(0.1, 0.1, 0.1), at(L.cheesedQueueX, L.boardTop, L.boardZ), BLACK, nil, { name = "CheesedQueue", transparency = 1, collide = false })
end
-- Double-stacked conveyor oven. Pizzas ride in at -X and out at +X; the
-- ConveyorIn / ConveyorOut markers tell ShopService where the belt starts and ends.
Builders.Oven = function(m, base)
	local L, D = 9, 4.4
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			P(m, base, Vector3.new(0.4, 2.5, 0.4), at(sx * (L / 2 - 0.4), 1.25, sz * (D / 2 - 0.4)), STEEL_DARK, Enum.Material.Metal, { collide = true })
			P(m, base, Vector3.new(0.3, 0.5, 0.5), up(sx * (L / 2 - 0.4), 0.15, sz * (D / 2 - 0.4)), BLACK, Enum.Material.Rubber, { shape = Enum.PartType.Cylinder })
		end
	end
	P(m, base, Vector3.new(L, 0.3, D), at(0, 2.65, 0), STEEL_DARK, Enum.Material.Metal, { name = "Frame" })
	local function deck(y0: number, temp: string)
		P(m, base, Vector3.new(L, 2.2, D), at(0, y0 + 1.1, 0), STEEL, Enum.Material.Metal, { name = "Deck", reflect = 0.08 })
		local panel = P(m, base, Vector3.new(2.2, 1.3, 0.12), at(L / 2 - 1.5, y0 + 1.15, -D / 2 - 0.06), BLACK, Enum.Material.Glass)
		surfaceText(panel, Enum.NormalId.Front, temp .. "\nBELT 6:30", Color3.fromRGB(255, 130, 60), BLACK, Enum.Font.Code)
		-- Peek window into the bake chamber
		P(m, base, Vector3.new(L - 4, 0.45, 0.06), at(-1.1, y0 + 1.45, -D / 2 - 0.03), Color3.fromRGB(255, 120, 40), Enum.Material.Neon, { collide = false })
		-- Glowing belt openings at both ends
		for _, sx in { -1, 1 } do
			P(m, base, Vector3.new(0.06, 0.6, D - 0.8), at(sx * (L / 2 + 0.03), y0 + 0.5, 0), Color3.fromRGB(255, 110, 30), Enum.Material.Neon, { collide = false })
		end
		-- Wire belt running through, sticking out both ends
		P(m, base, Vector3.new(L + 5, 0.1, D - 0.8), at(0, y0 + 0.2, 0), Color3.fromRGB(90, 90, 95), Enum.Material.DiamondPlate, { collide = false, name = "Belt" })
		for _, sz in { -1, 1 } do
			P(m, base, Vector3.new(L + 5, 0.25, 0.12), at(0, y0 + 0.25, sz * (D / 2 - 0.35)), STEEL_DARK, Enum.Material.Metal, { collide = false })
		end
	end
	deck(2.8, "475 F")
	deck(5.1, "470 F")
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 140, 70)
	light.Range = 10
	light.Brightness = 1
	light.Parent = P(m, base, Vector3.new(0.2, 0.2, 0.2), at(0, 4, -D / 2 - 0.5), BLACK, Enum.Material.SmoothPlastic, { transparency = 1, collide = false })
	-- Exhaust hood + duct to the roof
	P(m, base, Vector3.new(L + 3, 1, D + 1.5), at(0, 8.3, 0), STEEL, Enum.Material.Metal, { name = "Hood" })
	P(m, base, Vector3.new(L + 2.6, 0.4, 0.08), at(0, 7.95, -(D + 1.5) / 2 - 0.04), Color3.fromRGB(70, 70, 75), Enum.Material.DiamondPlate)
	P(m, base, Vector3.new(2.2, 6, 2.2), at(0, 11.8, 0.6), STEEL, Enum.Material.Metal, { name = "Duct" })
	-- Belt markers
	P(m, base, Vector3.new(0.2, 0.2, 0.2), at(-(L / 2 + 2.2), 3.25, 0), BLACK, Enum.Material.SmoothPlastic, { name = "ConveyorIn", transparency = 1, collide = false })
	P(m, base, Vector3.new(0.2, 0.2, 0.2), at(L / 2 + 2.2, 3.25, 0), BLACK, Enum.Material.SmoothPlastic, { name = "ConveyorOut", transparency = 1, collide = false })
end

-- Cut table at the oven exit, modeled on a real chain's cut station: a long
-- stainless table with pizza boxes folded open flat (tray in front, lid lying
-- open behind it), squeeze bottles, a rocker blade in its holder, and a label
-- printer. The oven belt discharges onto the left (-X) end.
-- Box_<Size> parts carry BoxSize + WallHeight; Lid_<Size> carries OpenAngle so
-- the cut minigame can swing the same lid shut.
local BOX_WALL = 0.2

-- Lid hinged at the back of the tray; angle 0 = closed over the box, 180 = flat behind.
local function lidCFrame(boxCenter: CFrame, bs: number, angle: number): CFrame
	return boxCenter * CFrame.new(0, BOX_WALL - 0.025, bs / 2) * CFrame.Angles(math.rad(angle), 0, 0) * CFrame.new(0, 0, -bs / 2)
end

Builders.CutTable = function(m, base)
	local h, w, d = 3.2, 10, 5.6
	steelTable(m, base, w, d, h)
	local cardboard = Color3.fromRGB(205, 168, 118)
	local inside = Color3.fromRGB(225, 200, 160)

	-- Open boxes, small to large from the oven side, front edges lined up at the cutter's edge.
	local x = -4.2
	local frontEdge = -d / 2 + 0.2
	for _, size in Config.Sizes do
		local bs = Config.BoxSize[size]
		local cx = x + bs / 2
		x += bs + 0.2
		local cz = frontEdge + bs / 2
		local boxBase = P(m, base, Vector3.new(bs, 0.05, bs), at(cx, h + 0.025, cz), inside, Enum.Material.Cardboard, { name = "Box_" .. size })
		boxBase:SetAttribute("BoxSize", size)
		boxBase:SetAttribute("WallHeight", BOX_WALL)
		for _, side in { { 0, -1 }, { 1, 0 }, { -1, 0 } } do
			P(m, base, Vector3.new(if side[1] ~= 0 then 0.04 else bs, BOX_WALL, if side[2] ~= 0 then 0.04 else bs), at(cx + side[1] * bs / 2, h + BOX_WALL / 2, cz + side[2] * bs / 2), cardboard, Enum.Material.Cardboard, { collide = false })
		end
		-- Lid lying open behind the tray, sloping from the hinge down to the table.
		local openAngle = 180 + math.deg(math.asin(math.clamp((BOX_WALL - 0.03) / bs, 0, 1)))
		local lid = P(m, base, Vector3.new(bs, 0.04, bs), lidCFrame(at(cx, h + 0.025, cz), bs, openAngle), inside, Enum.Material.Cardboard, { collide = false, name = "Lid_" .. size })
		lid:SetAttribute("OpenAngle", openAngle)
		-- Printed outside of the lid (faces down while open, up once closed).
		surfaceText(lid, Enum.NormalId.Top, (string.upper(Config.GameName):gsub(" ", "\n")), Config.Brand.Red, cardboard)
		-- Size printed on the tray's front edge
		local tag = P(m, base, Vector3.new(0.45, 0.16, 0.03), at(cx, h + 0.1, frontEdge - 0.03), Color3.new(1, 1, 1))
		surfaceText(tag, Enum.NormalId.Front, string.sub(size, 1, 1), Config.Brand.Red)
	end

	-- Right end: rocker blade standing in a stainless holder, squeeze bottles, label printer.
	P(m, base, Vector3.new(1.0, 0.9, 0.5), at(4.3, h + 0.45, 1.6), STEEL, Enum.Material.Metal, { name = "BladeHolder", reflect = 0.15 })
	P(m, base, Vector3.new(0.05, 0.6, 2.4), at(4.3, h + 1.05, 1.6) * CFrame.Angles(0, math.rad(90), 0), STEEL, Enum.Material.Metal, { reflect = 0.3 })
	for _, sx in { -1, 1 } do
		P(m, base, Vector3.new(0.18, 0.5, 0.18), up(4.3 + sx * 1.3, h + 1.15, 1.6), BLACK, Enum.Material.Plastic, { shape = Enum.PartType.Cylinder })
	end
	for i, zOff in { 0.2, 0.55 } do
		P(m, base, Vector3.new(0.75, 0.32, 0.32), up(3.75 + i * 0.05, h + 0.375, zOff), Color3.fromRGB(245, 200, 40), Enum.Material.Plastic, { shape = Enum.PartType.Cylinder, collide = false })
		P(m, base, Vector3.new(0.2, 0.18, 0.18), up(3.75 + i * 0.05, h + 0.85, zOff), Color3.new(1, 1, 1), Enum.Material.Plastic, { shape = Enum.PartType.Cylinder, collide = false })
		P(m, base, Vector3.new(0.2, 0.05, 0.05), up(3.75 + i * 0.05, h + 1.03, zOff), Color3.new(1, 1, 1), Enum.Material.Plastic, { shape = Enum.PartType.Cylinder, collide = false })
	end
	P(m, base, Vector3.new(0.9, 0.55, 0.9), at(4.35, h + 0.275, -1.6), Color3.fromRGB(28, 28, 32), Enum.Material.SmoothPlastic, { name = "LabelPrinter" })
	P(m, base, Vector3.new(0.6, 0.02, 0.35), at(4.35, h + 0.56, -2.0) * CFrame.Angles(math.rad(-20), 0, 0), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, { collide = false })
	-- A few flat boxes ready to fold, by the printer
	for j = 0, 3 do
		P(m, base, Vector3.new(1.2, 0.05, 1.2), at(4.3, h + 0.03 + j * 0.055, -0.35), cardboard, Enum.Material.Cardboard, { collide = false })
	end

	-- Under the table: white storage bins and a tall stack of flat boxes
	for i, bx in { -3.2, -0.8 } do
		P(m, base, Vector3.new(2.0, 1.1, d - 1.2), at(bx, 1.55, 0), Color3.fromRGB(240, 240, 238), Enum.Material.Plastic, { name = "Bin" .. i })
	end
	for j = 0, 9 do
		P(m, base, Vector3.new(2.4, 0.05, 2.4), at(2.6, 1.03 + j * 0.055, 0), cardboard, Enum.Material.Cardboard, { collide = false })
	end
end

-- Chrome wire shelving stacked with pizza boxes and insulated delivery bags.
Builders.DeliveryRack = function(m, base)
	local w, d, h = 6, 2.2, 7
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			P(m, base, Vector3.new(h, 0.18, 0.18), up(sx * (w / 2 - 0.1), h / 2, sz * (d / 2 - 0.1)), Color3.fromRGB(215, 218, 222), Enum.Material.Metal, { shape = Enum.PartType.Cylinder, reflect = 0.2, collide = true })
		end
	end
	local shelfY = { 0.5, 2.4, 4.3, 6.2 }
	for _, y in shelfY do
		P(m, base, Vector3.new(w, 0.1, d), at(0, y, 0), Color3.fromRGB(205, 208, 212), Enum.Material.DiamondPlate, { collide = true })
	end
	local boxColor = Color3.fromRGB(205, 168, 118)
	local function boxStack(x: number, y: number, n: number)
		for i = 0, n - 1 do
			local b = P(m, base, Vector3.new(1.9, 0.32, 1.9), at(x, y + 0.16 + i * 0.33, 0), boxColor, Enum.Material.Cardboard, { collide = false })
			if i == n - 1 then
				surfaceText(b, Enum.NormalId.Top, (string.upper(Config.GameName):gsub(" ", "\n")), Color3.fromRGB(200, 40, 30))
			end
		end
	end
	boxStack(-1.5, 0.55, 5)
	boxStack(1.5, 0.55, 4)
	-- Insulated delivery bags
	for i, x in { -1.5, 1.5 } do
		local bag = P(m, base, Vector3.new(2.6, 1.0, 2.0), at(x, 2.95, 0), Color3.fromRGB(190, 30, 35), Enum.Material.Fabric, { name = "Bag" .. i })
		P(m, base, Vector3.new(2.62, 0.08, 2.02), at(x, 3.3, 0), Color3.fromRGB(30, 30, 30), Enum.Material.Fabric, { collide = false }) -- zipper
		P(m, base, Vector3.new(1.0, 0.1, 0.25), at(x, 3.5, 0), Color3.fromRGB(30, 30, 30), Enum.Material.Fabric, { collide = false }) -- handle
		surfaceText(bag, Enum.NormalId.Front, "HOT", Color3.new(1, 1, 1))
	end
	boxStack(-1.5, 4.35, 2)
	boxStack(1.5, 4.35, 3)
	boxStack(0, 6.25, 6)
	-- Heat lamp over the top
	P(m, base, Vector3.new(w, 0.3, 1.2), at(0, h + 0.2, -0.3), STEEL, Enum.Material.Metal)
	local lamp = P(m, base, Vector3.new(w - 0.4, 0.05, 0.5), at(0, h + 0.03, -0.3), Color3.fromRGB(255, 130, 60), Enum.Material.Neon, { collide = false })
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Color = Color3.fromRGB(255, 160, 90)
	light.Range = 10
	light.Brightness = 1.5
	light.Parent = lamp
	-- Routing screen above the rack
	P(m, base, Vector3.new(0.15, 1.0, 0.15), at(0, h + 0.85, 0.3), STEEL_DARK, Enum.Material.Metal)
	local screen = P(m, base, Vector3.new(2.6, 1.4, 0.12), at(0, h + 1.9, 0.3), BLACK, Enum.Material.Glass, { name = "RoutingScreen" })
	surfaceText(screen, Enum.NormalId.Front, "ROUTING\nGrab a bag, hit the road", Color3.fromRGB(120, 230, 255), Color3.fromRGB(15, 22, 32), Enum.Font.Code)
end

-- Glass pass-through carryout warmer on the counter. Front faces the customers.
-- Finished carryout boxes are set on its bottom shelf (hitbox center - 0.05).
Builders.Pickup = function(m, base)
	local w, d, h = 5.6, 2.6, 3.0
	P(m, base, Vector3.new(w, 0.25, d), at(0, 0.125, 0), STEEL, Enum.Material.Metal, { name = "Base", reflect = 0.1 })
	P(m, base, Vector3.new(w, 0.4, d), at(0, h - 0.2, 0), STEEL, Enum.Material.Metal, { name = "Top" })
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			P(m, base, Vector3.new(0.2, h, 0.2), at(sx * (w / 2 - 0.1), h / 2, sz * (d / 2 - 0.1)), STEEL_DARK, Enum.Material.Metal)
		end
		P(m, base, Vector3.new(0.08, h - 0.65, d - 0.2), at(sx * (w / 2 - 0.05), h / 2 - 0.08, 0), Color3.fromRGB(200, 230, 255), Enum.Material.Glass, { transparency = 0.65 })
	end
	for _, sz in { -1, 1 } do
		P(m, base, Vector3.new(w - 0.4, h - 0.65, 0.06), at(0, h / 2 - 0.08, sz * (d / 2 - 0.05)), Color3.fromRGB(200, 230, 255), Enum.Material.Glass, { transparency = 0.7, collide = true })
	end
	P(m, base, Vector3.new(w - 0.3, 0.08, d - 0.3), at(0, 1.5, 0), Color3.fromRGB(180, 182, 186), Enum.Material.DiamondPlate, { collide = false })
	local glow = P(m, base, Vector3.new(w - 0.6, 0.05, 0.3), at(0, h - 0.43, 0), Color3.fromRGB(255, 200, 140), Enum.Material.Neon, { collide = false })
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 190, 120)
	light.Range = 5
	light.Brightness = 1.5
	light.Parent = glow
	-- A couple of waiting boxes on the top shelf
	for i, x in { -1.4, 1.3 } do
		for j = 0, i do
			P(m, base, Vector3.new(1.8, 0.32, 1.8), at(x, 1.7 + j * 0.33, 0), Color3.fromRGB(205, 168, 118), Enum.Material.Cardboard, { collide = false })
		end
	end
	local sign = P(m, base, Vector3.new(3.4, 0.7, 0.1), at(0, h + 0.4, -d / 2 + 0.2), Config.Brand.Red)
	surfaceText(sign, Enum.NormalId.Front, "CARRYOUT", Color3.new(1, 1, 1))
end

-- Walk-in cooler front with a stock tablet. The tablet's SurfaceGui is the stock board.
Builders.Fridge = function(m, base)
	P(m, base, Vector3.new(6, 10, 4), at(0, 5, 0), Color3.fromRGB(205, 210, 216), Enum.Material.Metal, { name = "Body", reflect = 0.05 })
	P(m, base, Vector3.new(6, 0.4, 0.1), at(0, 0.2, -2.05), BLACK)
	P(m, base, Vector3.new(6, 0.7, 0.1), at(0, 9.55, -2.05), Color3.fromRGB(60, 62, 66), Enum.Material.DiamondPlate) -- condenser grille
	-- Door
	P(m, base, Vector3.new(3.4, 7.8, 0.2), at(-1.1, 4.1, -2.1), Color3.fromRGB(222, 226, 230), Enum.Material.Metal, { name = "Door" })
	P(m, base, Vector3.new(1.3, 1.5, 0.06), at(-1.1, 6.3, -2.22), Color3.fromRGB(170, 210, 240), Enum.Material.Glass, { transparency = 0.3 })
	P(m, base, Vector3.new(0.3, 1.8, 0.35), at(0.25, 4.2, -2.35), Color3.fromRGB(70, 70, 75), Enum.Material.Metal) -- handle
	for _, y in { 1.5, 6.8 } do
		P(m, base, Vector3.new(0.25, 0.7, 0.3), at(-2.75, y, -2.25), STEEL_DARK, Enum.Material.Metal) -- hinges
	end
	-- Temperature readout
	local temp = P(m, base, Vector3.new(1.1, 0.55, 0.06), at(1.9, 8.2, -2.04), BLACK, Enum.Material.Glass)
	surfaceText(temp, Enum.NormalId.Front, "36°F", Color3.fromRGB(90, 230, 255), BLACK, Enum.Font.Code)
	-- Stock tablet
	local tablet = P(m, base, Vector3.new(1.9, 3.4, 0.08), at(1.9, 5.4, -2.04), BLACK, Enum.Material.Glass, { name = "StockTablet" })
	local gui = Instance.new("SurfaceGui")
	gui.Name = "StockBoard"
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.CanvasSize = Vector2.new(190, 340)
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundColor3 = Color3.fromRGB(18, 24, 32)
	text.BorderSizePixel = 0
	text.Font = Enum.Font.Code
	text.TextSize = 17
	text.TextColor3 = Color3.fromRGB(200, 255, 210)
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.Text = ""
	text.Parent = gui
	gui.Parent = tablet
end

-- Box truck backed up to the loading door, liftgate down with crates.
-- Local origin is the liftgate edge; the truck extends away from the worker (+Z).
Builders.SupplyTruck = function(m, base)
	local white = Color3.fromRGB(240, 240, 238)
	local cab = Color3.fromRGB(35, 110, 190)
	local cargo = P(m, base, Vector3.new(8, 7.5, 11), at(0, 5.25, 5.5), white, Enum.Material.SmoothPlastic, { name = "Cargo" })
	surfaceText(cargo, Enum.NormalId.Left, "FRESH SUPPLY CO.", cab)
	surfaceText(cargo, Enum.NormalId.Right, "FRESH SUPPLY CO.", cab)
	P(m, base, Vector3.new(8.05, 0.6, 11.05), at(0, 2.2, 5.5), cab, Enum.Material.SmoothPlastic, { collide = false }) -- stripe
	P(m, base, Vector3.new(7, 0.8, 16), at(0, 1.2, 8), Color3.fromRGB(40, 40, 44), Enum.Material.Metal, { name = "Chassis" })
	-- Cab
	P(m, base, Vector3.new(8, 5, 4.5), at(0, 4.0, 13.25), cab, Enum.Material.SmoothPlastic, { name = "Cab" })
	P(m, base, Vector3.new(8, 2.2, 1.2), at(0, 2.6, 16.1), cab, Enum.Material.SmoothPlastic)
	P(m, base, Vector3.new(7, 2, 0.1), at(0, 5.0, 15.52), Color3.fromRGB(140, 190, 230), Enum.Material.Glass, { transparency = 0.25 })
	for _, sx in { -1, 1 } do
		P(m, base, Vector3.new(0.06, 1.8, 2.2), at(sx * 4.02, 5.0, 13.6), Color3.fromRGB(140, 190, 230), Enum.Material.Glass, { transparency = 0.25 })
		P(m, base, Vector3.new(0.6, 0.9, 0.1), at(sx * 4.4, 5.2, 15.0), BLACK) -- mirror
		P(m, base, Vector3.new(1.0, 0.6, 0.1), at(sx * 3.0, 2.8, 16.72), Color3.fromRGB(255, 250, 220), Enum.Material.Neon) -- headlight
		P(m, base, Vector3.new(0.6, 1.0, 0.1), at(sx * 3.5, 2.6, -0.06), Color3.fromRGB(220, 30, 30), Enum.Material.Neon) -- tail light
	end
	P(m, base, Vector3.new(4, 1.3, 0.06), at(0, 2.7, 16.72), Color3.fromRGB(30, 30, 32), Enum.Material.DiamondPlate) -- grille
	P(m, base, Vector3.new(8.2, 0.6, 0.6), at(0, 1.3, 16.9), Color3.fromRGB(70, 70, 74), Enum.Material.Metal) -- bumper
	-- Wheels (cylinders already run along X = the axle)
	for _, z in { 2.5, 4.4, 13.0 } do
		for _, sx in { -1, 1 } do
			P(m, base, Vector3.new(1.0, 3, 3), at(sx * 3.7, 1.5, z), Color3.fromRGB(25, 25, 25), Enum.Material.Rubber, { shape = Enum.PartType.Cylinder, collide = true })
			P(m, base, Vector3.new(1.05, 1.6, 1.6), at(sx * 3.7, 1.5, z), Color3.fromRGB(170, 172, 176), Enum.Material.Metal, { shape = Enum.PartType.Cylinder })
		end
	end
	-- Open rear: dark interior, rolled-up door, lowered liftgate
	P(m, base, Vector3.new(7.4, 6.8, 0.1), at(0, 5.15, -0.06), Color3.fromRGB(30, 30, 34), Enum.Material.SmoothPlastic, { collide = false })
	P(m, base, Vector3.new(7.6, 1.0, 0.5), at(0, 8.4, -0.2), Color3.fromRGB(215, 215, 215), Enum.Material.DiamondPlate)
	P(m, base, Vector3.new(7.4, 0.25, 2.8), at(0, 0.125, -1.5), Color3.fromRGB(150, 152, 156), Enum.Material.DiamondPlate, { name = "Liftgate", collide = true })
	crate(m, base, at(-2.2, 0.25, -1.5), "Cheese")
	crate(m, base, at(0, 0.25, -1.5), "Pepperoni")
	crate(m, base, at(2.2, 0.25, -1.6), "Peppers")
	crate(m, base, at(-2.2, 1.75, -1.5), "Dough")
	crate(m, base, at(5.6, 0, -1.2), "Sauce")
	crate(m, base, at(5.6, 1.5, -1.2), "Mushrooms")
	-- Hand truck
	P(m, base, Vector3.new(0.15, 4, 0.15), CFrame.new(-5.2, 2, -1.2) * CFrame.Angles(math.rad(-10), 0, 0), Color3.fromRGB(200, 40, 40), Enum.Material.Metal, { collide = false })
	P(m, base, Vector3.new(0.15, 4, 0.15), CFrame.new(-6.2, 2, -1.2) * CFrame.Angles(math.rad(-10), 0, 0), Color3.fromRGB(200, 40, 40), Enum.Material.Metal, { collide = false })
	P(m, base, Vector3.new(1.4, 0.1, 0.8), at(-5.7, 0.1, -1.6), STEEL_DARK, Enum.Material.Metal, { collide = false })
	P(m, base, Vector3.new(0.3, 0.8, 0.8), at(-5.7, 0.4, -0.6), BLACK, Enum.Material.Rubber, { shape = Enum.PartType.Cylinder, collide = false })
end

-- Builds art for `kind` under `parent`, preferring a custom model if one exists.
function StationArt.Build(kind: string, parent: Instance, base: CFrame)
	local folder = ServerStorage:FindFirstChild("StationModels")
	local custom = folder and folder:FindFirstChild(kind)
	if custom and custom:IsA("Model") then
		local clone = custom:Clone()
		clone:PivotTo(base)
		for _, d in clone:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		clone.Name = "Art"
		clone.Parent = parent
		return
	end
	local builder = Builders[kind]
	if builder then
		local art = Instance.new("Model")
		art.Name = "Art"
		builder(art, base)
		art.Parent = parent
	end
end

return StationArt
