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
local Style = require(game:GetService("ReplicatedStorage").Shared.Style)

local StationArt = {}

local STEEL = Color3.fromRGB(196, 200, 206)
local STEEL_DARK = Color3.fromRGB(120, 124, 130)
local BLACK = Color3.fromRGB(25, 25, 28)
local WOOD = Color3.fromRGB(160, 115, 70)
local SCREEN = Color3.fromRGB(58, 58, 62) -- pizza screens, dark from use (as in the user's photos)
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
	tl.FontFace = if font == Enum.Font.Code then Style.Font.Mono else Style.Font.Heading
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
-- Job aids: laminated reference cards propped up at a station, tilted back
-- toward the worker so they show in the station camera. `JobAid` = the
-- station they belong to (clients let you click one to read it up close).
---------------------------------------------------------------------------

local AID_PPS = 200 -- card print resolution (pixels per stud)
local CRUST = Color3.fromRGB(225, 180, 110)

local function guiFrame(parent: Instance, props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for k, v in props do
		(f :: any)[k] = v
	end
	f.Parent = parent
	return f
end

local function guiText(parent: Instance, text: string, props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.FontFace = Style.Font.LabelBold
	t.TextScaled = true
	t.TextColor3 = Style.Color.Ink
	t.Text = text
	for k, v in props do
		if k == "Font" then
			t.FontFace = if v == Enum.Font.Code then Style.Font.Mono else Style.Font.Heading
		else
			(t :: any)[k] = v
		end
	end
	t.Parent = parent
	return t
end

-- A circle `d` px across centered at (x, y) px.
local function guiCircle(parent: Instance, x: number, y: number, d: number, color: Color3, outline: Color3?): Frame
	local c = guiFrame(parent, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(d, d), BackgroundColor3 = color })
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = c
	if outline then
		local s = Instance.new("UIStroke")
		s.Color = outline
		s.Thickness = 3
		s.Parent = c
	end
	return c
end

-- The card: a white plate with a red title band, standing with its bottom
-- edge at `offset` and leaning back. `draw` fills the body (given its size in
-- pixels). Returns the card part.
local AID_TILT = math.rad(55) -- lying back for cards on a work surface, seen from above
local function jobAid(parent: Instance, base: CFrame, offset: CFrame, size: Vector2, stationId: string, title: string, draw: (Frame, Vector2) -> (), tilt: number?): Part
	local lay = tilt or AID_TILT
	local rise, lean = size.Y / 2 * math.cos(lay), size.Y / 2 * math.sin(lay)
	local card = P(parent, base, Vector3.new(size.X, size.Y, 0.05), offset * CFrame.new(0, rise, lean) * CFrame.Angles(lay, 0, 0), Color3.fromRGB(250, 250, 245), Enum.Material.SmoothPlastic, { name = "JobAid", collide = false })
	card:SetAttribute("JobAid", stationId)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front -- toward the worker
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = AID_PPS
	local px = size * AID_PPS
	local bg = guiFrame(gui, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Style.Color.Cream })
	local band = guiFrame(bg, { Size = UDim2.new(1, 0, 0, px.Y * 0.18), BackgroundColor3 = Config.Brand.Red })
	guiText(band, title, { Size = UDim2.fromScale(1, 1), TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBlack })
	local body = guiFrame(bg, { Position = UDim2.fromOffset(0, px.Y * 0.18), Size = UDim2.new(1, 0, 1, -px.Y * 0.18), BackgroundTransparency = 1 })
	draw(body, Vector2.new(px.X, px.Y * 0.82))
	gui.Parent = card
	-- A prop holding up its top edge
	P(parent, base, Vector3.new(0.06, rise * 2, 0.06), offset * CFrame.new(0, rise, lean * 2 + 0.04), STEEL_DARK, Enum.Material.Metal, { collide = false })
	return card
end

-- The sauce line: 3/4" in from the edge on every size.
local function drawSauce(body: Frame, px: Vector2)
	local d = px.Y * 0.8
	local cx = px.X * 0.3
	guiCircle(body, cx, px.Y * 0.5, d, CRUST)
	-- Drawn wider than true scale so the border reads at a glance.
	guiCircle(body, cx, px.Y * 0.5, d * 0.78, Config.IngredientColors.Sauce)
	guiText(body, string.format("%s\" BORDER\nevery size\n\nCover to the line.\nKeep the rim clean.", if Config.Sauce.BorderInches == 0.75 then "3/4" else tostring(Config.Sauce.BorderInches)), {
		Position = UDim2.fromOffset(px.X * 0.56, px.Y * 0.08),
		Size = UDim2.fromOffset(px.X * 0.42, px.Y * 0.84),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
end

-- Cheese portions by size.
local function drawCheese(body: Frame, px: Vector2)
	local lines = {}
	for _, size in Config.Sizes do
		table.insert(lines, string.format("%-7s %g oz", string.upper(size), Config.CheesePortion[size]))
	end
	table.insert(lines, "within 10%")
	guiText(body, table.concat(lines, "\n"), { Position = UDim2.fromOffset(px.X * 0.08, px.Y * 0.06), Size = UDim2.fromOffset(px.X * 0.84, px.Y * 0.88), Font = Enum.Font.Code, TextXAlignment = Enum.TextXAlignment.Left })
end

-- Topping portions: one row per pizza, one column per size.
local function drawPortions(body: Frame, px: Vector2)
	local pizzas = {}
	local totalLines = 0
	for _, name in Config.PizzaOrder do
		local recipe = Config.Recipes[name]
		if recipe and #recipe > 0 then
			table.insert(pizzas, name)
			totalLines += #recipe
		end
	end
	local headH = px.Y * 0.12
	local lineH = (px.Y - headH - px.Y * 0.1) / totalLines
	local colW = { px.X * 0.28, px.X * 0.24, px.X * 0.24, px.X * 0.24 }
	-- One text size for the whole table (scaled-to-fit cells came out uneven).
	local textSize = math.floor(lineH * 0.78)
	local function cell(col: number, y: number, h: number, text: string, face: Font, size: number, color: Color3?)
		local x = 0
		for c = 1, col - 1 do
			x += colW[c]
		end
		guiText(body, text, {
			Position = UDim2.fromOffset(x + 6, y + 2),
			Size = UDim2.fromOffset(colW[col] - 10, h - 2),
			FontFace = face,
			TextScaled = false,
			TextSize = size,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = color or Style.Color.Ink,
		})
	end
	local headSize = math.floor(headH * 0.62)
	cell(1, 0, headH, "PIZZA", Style.Font.Heading, headSize, Config.Brand.Red)
	for i, size in Config.Sizes do
		cell(i + 1, 0, headH, string.upper(size), Style.Font.Heading, headSize, Config.Brand.Red)
	end
	local y = headH
	for _, name in pizzas do
		local recipe = Config.Recipes[name]
		local h = lineH * #recipe
		guiFrame(body, { Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = Color3.fromRGB(200, 200, 195) })
		cell(1, y, h, string.upper(name), Style.Font.LabelBold, textSize)
		for i, size in Config.Sizes do
			local lines = {}
			for _, topping in recipe do
				table.insert(lines, string.format("%s %d", string.upper(string.sub(topping, 1, 4)), Config.PortionFor(topping, size, #recipe)))
			end
			cell(i + 1, y, h, table.concat(lines, "\n"), Style.Font.Mono, textSize)
		end
		y += h
	end
	guiText(body, "Cheese pizza: sauce + cheese only. All portions within 10%.", { Position = UDim2.fromOffset(4, px.Y * 0.9), Size = UDim2.fromOffset(px.X - 8, px.Y * 0.09), TextXAlignment = Enum.TextXAlignment.Left })
end

-- Where to cut: even cuts straight through the middle.
local function drawCuts(body: Frame, px: Vector2)
	local d = px.Y * 0.62
	for i, size in Config.Sizes do
		local slices = Config.Cut.Slices[size]
		local x = px.X * (i - 0.5) / #Config.Sizes
		local y = px.Y * 0.4
		guiCircle(body, x, y, d * Config.PizzaInches[size] / Config.PizzaInches.Large, CRUST)
		local cuts = slices // 2
		for c = 0, cuts - 1 do
			local line = guiFrame(body, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(d * Config.PizzaInches[size] / Config.PizzaInches.Large, 4), BackgroundColor3 = Color3.fromRGB(60, 40, 30) })
			line.Rotation = c * 180 / cuts
		end
		guiText(body, string.format("%s\n%d slices", string.upper(size), slices), { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(x, px.Y * 0.74), Size = UDim2.fromOffset(px.X / #Config.Sizes - 10, px.Y * 0.24) })
	end
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
		stretchX = -1.0,
		sauceX = 2.7,
		rackX = { -1.35, -4.1 }, -- rack 1 right behind the stretch spot
		rackZ = 1.25,
		rackWidth = 2.6,
		rackDepth = 2.2,
		slotSpacing = 0.2,
		cornmealX = -4.1, -- the cornmeal pan, in front of rack 2
		cornmealZ = -1.1,
		tubsX = 3.0, -- sauce tubs against the back, behind the sauce spot
		tubsZ = 1.5,
		screensX = 1.2, -- spare screens, back middle
		screensZ = 1.25,
	},
	MakeLine = {
		width = 17,
		depth = 4.7, -- front face at z -1.8
		grateDepth = 2.9, -- a Large is 2.4 across (2.55 on its screen): room to spare front and back
		boardZ = -0.3, -- center of the grate (where pizzas sit), just behind the front lip
		boardTop = 3.445,
		saucedQueueX = -6.5,
		cheeseX = -2.5,
		cheesedQueueX = 1.5,
		toppingsX = 5.5, -- the oven end (+X)
	},
	-- Ready rack table at the end of the make-line (screens hold Large pizzas;
	-- slots are spaced for topped pizzas).
	ReadyRack = { width = 3.6, depth = 3.2, height = 3.4, rackWidth = 2.9, rackDepth = 2.8, slotSpacing = 0.3 },
	-- Three stacked conveyor ovens, running along Z: in at +Z (the make-line
	-- end), out at -Z (LookVector: toward the oven tender at the cut table).
	Oven = {
		belt = 20, -- belt length, entrance extension + bake chamber + exit extension
		chamber = 11,
		width = 6.6,
		lanes = { -1.4, 1.4 }, -- two pizzas side by side; the -X lane is each oven's first slot
		decks = { 5.1, 3.2, 1.3 }, -- belt heights: top (slots 1-2), middle (3-4), bottom (5-6)
	},
	-- Cut table beside the oven exits (the ovens are off its +X end).
	CutTable = { width = 11, depth = 5.6, height = 3.2 },
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
	bg.BackgroundColor3 = Style.Color.Panel
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, 0, 0, 22)
	header.BackgroundColor3 = Style.Color.Red
	header.BorderSizePixel = 0
	header.FontFace = Style.Font.Heading
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
	for i, name in { "CHEESE", "PEPP", "HAWAII", "VEGGIE", "SUPREME", "SEND" } do
		local tile = Instance.new("TextLabel")
		tile.BackgroundColor3 = if i == 6 then Style.Color.Red else Style.Color.Tile
		tile.BorderSizePixel = 0
		tile.FontFace = Style.Font.LabelBold
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

-- A chrome pizza-screen rack standing on a table top at height `h`: floor
-- frame, side frames, and a pair of front-to-back rails per slot with a short
-- inward hook at the front (screens slide in from -Z). Adds invisible
-- `<prefix><n>` markers where each screen rests, top slot first, numbered from
-- `first`; returns the next number.
local function screenRack(m: Instance, base: CFrame, cx: number, cz: number, rw: number, rd: number, h: number, slots: number, spacing: number, prefix: string, first: number): number
	local CHROME = Color3.fromRGB(215, 218, 222)
	local wire = 0.05
	local topRail = h + 0.2 + (slots - 1) * spacing
	local front, back = cz - rd / 2 + 0.06, cz + rd / 2 - 0.04
	local function bar(size: Vector3, offset: CFrame)
		P(m, base, size, offset, CHROME, Enum.Material.Metal, { reflect = 0.25, collide = false })
	end
	for _, sx in { -1, 1 } do
		bar(Vector3.new(wire, wire, rd), at(cx + sx * rw / 2, h + 0.03, cz))
	end
	for _, z in { cz - rd / 2, cz + rd / 2 } do
		bar(Vector3.new(rw, wire, wire), at(cx, h + 0.03, z))
	end
	for _, sx in { -1, 1 } do
		local x = cx + sx * rw / 2
		local mid = cz + 0.1
		bar(Vector3.new(wire, topRail - h + 0.15, wire), at(x, (h + topRail + 0.15) / 2, back))
		bar(Vector3.new(wire, topRail - h + 0.15, wire), at(x, (h + topRail + 0.15) / 2, mid))
		bar(Vector3.new(wire, wire, back - mid), at(x, topRail + 0.15, (back + mid) / 2))
		bar(Vector3.new(wire, 0.8, wire), at(x, h + 0.35, cz - 0.25) * CFrame.Angles(math.rad(-30), 0, 0))
		for i = 1, slots do
			local y = topRail - (i - 1) * spacing
			bar(Vector3.new(wire, wire, back - front), at(x, y, (front + back) / 2))
			bar(Vector3.new(0.25, wire, wire), at(x - sx * 0.125, y, front))
		end
	end
	P(m, base, Vector3.new(rw, topRail - h + 0.2, rd), at(cx, (h + topRail + 0.2) / 2, cz), CHROME, nil, { name = "RackBounds", transparency = 1, collide = true })
	for i = 1, slots do
		P(m, base, Vector3.new(0.1, 0.1, 0.1), at(cx, topRail - (i - 1) * spacing + wire / 2, cz), CHROME, nil, { name = prefix .. (first + i - 1), transparency = 1, collide = false })
	end
	return first + slots
end

-- The dough table, modeled on the user's photos of a real store's: a long
-- stainless table against a backsplash, two 15-slot pizza-screen racks
-- standing on it in the back corner with stretched skins on dark screens, a
-- big pan of cornmeal in front of them, the stretching spot dusted with
-- cornmeal, and the sauce tubs with the saucing spot at the make-line end.
-- (The photos run left to right toward their make-line; ours runs the other
-- way, so the same order reads mirrored: racks and cornmeal farthest from the
-- make-line, sauce nearest it.) SkinSlot_<n> markers sit where a screen rests
-- in the racks (rack 1 top to bottom, then rack 2); ShopService puts each
-- skin in its slot.
Builders.DoughTable = function(m, base)
	local L = StationArt.Layout.DoughTable
	local w, d, h = L.width, L.depth, L.height
	steelTable(m, base, w, d, h)
	P(m, base, Vector3.new(w, 1.3, 0.08), at(0, h + 0.65, d / 2 - 0.04), STEEL, Enum.Material.Metal, { name = "Backsplash", reflect = 0.1 })

	-- Cornmeal: a big pan of it, and a messy dusting over the stretching spot
	-- (and spilled around the pan) the way it ends up after a rush.
	local CORNMEAL = Color3.fromRGB(236, 196, 92)
	P(m, base, Vector3.new(0.36, 2.3, 2.3), up(L.cornmealX, h + 0.18, L.cornmealZ), Color3.fromRGB(120, 82, 48), Enum.Material.Metal, { shape = Enum.PartType.Cylinder, name = "CornmealPan", collide = true })
	P(m, base, Vector3.new(0.04, 2.1, 2.1), up(L.cornmealX, h + 0.35, L.cornmealZ), CORNMEAL, Enum.Material.Sand, { shape = Enum.PartType.Cylinder, collide = false })
	local rng = Random.new(3)
	local function dust(cx: number, cz: number, spread: number, n: number, layer: number)
		for i = 1, n do
			local a = rng:NextNumber(0, math.pi * 2)
			local r = spread * math.sqrt(rng:NextNumber())
			local x, z = cx + math.cos(a) * r, cz + math.sin(a) * r
			if math.abs(x) > w / 2 - 0.2 or math.abs(z) > d / 2 - 0.2 then
				continue
			end
			local y = h + 0.005 + (layer + i) * 0.0015 -- each patch a hair higher, so none z-fight
			local tint = CORNMEAL:Lerp(Color3.fromRGB(245, 215, 130), rng:NextNumber(0, 0.6))
			if rng:NextNumber() < 0.6 then
				local s = rng:NextNumber(0.25, 1.0)
				P(m, base, Vector3.new(0.01, s, s * rng:NextNumber(0.5, 1)), up(x, y, z) * CFrame.Angles(rng:NextNumber(0, math.pi), 0, 0), tint, Enum.Material.Sand, { shape = Enum.PartType.Cylinder, collide = false })
			else
				-- A swirl where a skin was spun out
				P(m, base, Vector3.new(rng:NextNumber(0.5, 1.4), 0.01, rng:NextNumber(0.1, 0.22)), at(x, y, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), tint, Enum.Material.Sand, { collide = false })
			end
		end
	end
	dust(L.stretchX, L.workZ, 1.5, 22, 0)
	dust(L.cornmealX, L.cornmealZ, 1.6, 8, 30)
	-- A few drips at the sauce spot
	for _, drip in { { 1.3, -0.5, 0.3 }, { -1.1, 0.7, 0.18 } } do
		P(m, base, Vector3.new(0.02, drip[3], drip[3]), up(L.sauceX + drip[1], h + 0.01, L.workZ + drip[2]), Config.IngredientColors.Sauce, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder, collide = false })
	end

	-- Two chrome pizza-screen racks standing on the table (rack 1 top to bottom, then rack 2).
	local slot = 1
	for r = 1, Config.Dough.Racks do
		slot = screenRack(m, base, L.rackX[r], L.rackZ, L.rackWidth, L.rackDepth, h, Config.Dough.SlotsPerRack, L.slotSpacing, "SkinSlot_", slot)
	end

	-- Sauce tubs against the backsplash: two square tubs stacked, the top one
	-- open, a small deli cup in front, and the spoodle lying ready.
	local TUB = Color3.fromRGB(235, 232, 225)
	local tx, tz = L.tubsX, L.tubsZ
	P(m, base, Vector3.new(1.2, 0.9, 1.2), at(tx, h + 0.45, tz), TUB, Enum.Material.SmoothPlastic, { transparency = 0.35, name = "SauceTub" })
	P(m, base, Vector3.new(1.08, 0.8, 1.08), at(tx, h + 0.42, tz), Config.IngredientColors.Sauce, Enum.Material.SmoothPlastic, { collide = false })
	P(m, base, Vector3.new(1.2, 0.85, 1.2), at(tx, h + 1.33, tz), TUB, Enum.Material.SmoothPlastic, { transparency = 0.35, name = "SauceTub" })
	P(m, base, Vector3.new(1.08, 0.7, 1.08), at(tx, h + 1.27, tz), Config.IngredientColors.Sauce, Enum.Material.SmoothPlastic, { collide = false })
	P(m, base, Vector3.new(0.4, 0.5, 0.5), up(tx + 1.0, h + 0.2, tz - 0.9), TUB, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder, transparency = 0.3, collide = false })
	P(m, base, Vector3.new(0.3, 0.44, 0.44), up(tx + 1.0, h + 0.17, tz - 0.9), Color3.fromRGB(215, 90, 50), Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder, collide = false })
	P(m, base, Vector3.new(0.1, 0.5, 0.5), up(tx - 0.4, h + 0.05, tz - 1.15), STEEL, Enum.Material.Metal, { shape = Enum.PartType.Cylinder, collide = false })
	P(m, base, Vector3.new(0.9, 0.05, 0.07), at(tx + 0.3, h + 0.06, tz - 1.15), STEEL, Enum.Material.Metal, { collide = false })
	P(m, base, Vector3.new(0.5, 0.1, 0.12), at(tx + 0.95, h + 0.07, tz - 1.15), Color3.fromRGB(60, 150, 70), Enum.Material.Plastic, { collide = false })
	-- A second spoodle standing in the open tub, green handle up
	P(m, base, Vector3.new(0.08, 1.3, 0.08), at(tx - 0.3, h + 1.6, tz + 0.1) * CFrame.Angles(math.rad(-20), 0, math.rad(15)), STEEL, Enum.Material.Metal, { collide = false })
	P(m, base, Vector3.new(0.11, 0.45, 0.11), at(tx - 0.45, h + 2.25, tz + 0.32) * CFrame.Angles(math.rad(-20), 0, math.rad(15)), Color3.fromRGB(60, 150, 70), Enum.Material.Plastic, { collide = false })

	-- Spare (dark, well-seasoned) screens stacked at the back, and a tray of dough balls at the far end
	for i = 0, 9 do
		P(m, base, Vector3.new(0.025, 2.4, 2.4), up(L.screensX, h + 0.03 + i * 0.04, L.screensZ), SCREEN, Enum.Material.DiamondPlate, { shape = Enum.PartType.Cylinder, collide = false })
	end
	P(m, base, Vector3.new(1.1, 0.3, 1.8), at(w / 2 - 0.65, h + 0.15, 1.3), Color3.fromRGB(45, 125, 215), Enum.Material.Plastic, { name = "DoughTray" }) -- blue dough box
	for j = 0, 1 do
		P(m, base, Vector3.new(0.55, 0.55, 0.55), at(w / 2 - 0.65, h + 0.45, 0.85 + j * 0.9), DOUGH, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Ball, collide = false })
	end
	-- Job aid: the sauce line, past the sauce spot. (No dough sizes card: the user
	-- had it removed; the size buttons show the inches.)
	jobAid(m, base, at(w / 2 - 0.7, h, L.workZ - 0.5), Vector2.new(1.1, 0.95), "Sauce", "SAUCE", drawSauce)
	-- Cart of proofed dough trays under the table
	for i = 0, 3 do
		P(m, base, Vector3.new(4.2, 0.35, 2.8), at(L.stretchX, 1.15 + i * 0.38, 0), Color3.fromRGB(225, 225, 220), Enum.Material.Plastic, { collide = i == 0 })
	end
end

-- Refrigerated make-line, after the user's photos: a stainless cabinet with
-- doors at the ends and a bank of drawers between, a wire grate work surface
-- along the front where pizzas sit on their way down the line, a row of small
-- black topping pans set into the rail behind it, and a sloped stainless
-- canopy over the pans. The grate is split into four zones, oven side last:
-- sauced pizzas waiting (SaucedQueue marker), the cheese spot, cheesed pizzas
-- waiting (CheesedQueue marker), and the toppings spot. Job aids (cheese
-- portions, topping portions) stand on the rail behind their spots, where the
-- station cameras can see them. Finished pizzas go on the ready rack, a
-- separate table at the oven end.
Builders.MakeLine = function(m, base)
	local L = StationArt.Layout.MakeLine
	local w, depth, top = L.width, L.depth, L.boardTop
	local front = -1.8 -- the cabinet's front face (the makers stand in front of it)
	local back = front + depth
	local mid = (front + back) / 2
	P(m, base, Vector3.new(w, 0.4, depth - 0.2), at(0, 0.2, mid + 0.1), BLACK, Enum.Material.SmoothPlastic) -- kick plate
	P(m, base, Vector3.new(w, 2.8, depth), at(0, 1.8, mid), STEEL, Enum.Material.Metal, { name = "Cabinet", reflect = 0.05 })
	-- Front: a door at each end, two drawers in each column between
	local PANEL = Color3.fromRGB(206, 210, 216)
	local sections = 5
	local sw = w / sections
	for k = 1, sections do
		local x = -w / 2 + sw * (k - 0.5)
		if k == 1 or k == sections then
			P(m, base, Vector3.new(sw - 0.16, 2.5, 0.06), at(x, 1.8, front - 0.03), PANEL, Enum.Material.Metal, { name = "Door" })
			-- Recessed pull along the top of the door
			P(m, base, Vector3.new(0.9, 0.14, 0.03), at(x + (if k == 1 then 0.7 else -0.7), 2.8, front - 0.065), BLACK, Enum.Material.SmoothPlastic, { collide = false })
		else
			for _, y in { 2.45, 1.15 } do
				P(m, base, Vector3.new(sw - 0.16, 1.2, 0.06), at(x, y, front - 0.03), PANEL, Enum.Material.Metal, { name = "Drawer" })
				P(m, base, Vector3.new(1.3, 0.09, 0.09), at(x, y + 0.3, front - 0.15), STEEL, Enum.Material.Metal, { reflect = 0.3, collide = false })
				for _, sx in { -1, 1 } do
					P(m, base, Vector3.new(0.08, 0.08, 0.14), at(x + sx * 0.6, y + 0.3, front - 0.1), STEEL, Enum.Material.Metal, { collide = false })
				end
			end
		end
	end
	-- Work surface: a wire grate over a dark well, deep enough for a Large on
	-- its screen with room to spare, with a stainless front lip. Rod tops sit
	-- at boardTop, so pizzas rest on the grate.
	local gd = L.grateDepth
	P(m, base, Vector3.new(w - 0.3, 0.2, gd + 0.1), at(0, top - 0.17, L.boardZ), Color3.fromRGB(45, 46, 50), Enum.Material.Metal, { name = "Well", collide = true })
	local rods = math.floor(gd / 0.125)
	for i = 0, rods do
		P(m, base, Vector3.new(w - 0.3, 0.035, 0.035), at(0, top - 0.0175, L.boardZ - gd / 2 + i * gd / rods), STEEL, Enum.Material.Metal, { reflect = 0.2, collide = false })
	end
	for i = 0, 10 do
		P(m, base, Vector3.new(0.05, 0.05, gd - 0.05), at(-w / 2 + 0.3 + i * (w - 0.6) / 10, top - 0.06, L.boardZ), STEEL_DARK, Enum.Material.Metal, { collide = false })
	end
	P(m, base, Vector3.new(w, 0.3, 0.08), at(0, top - 0.1, front - 0.04), STEEL, Enum.Material.Metal, { name = "FrontLip" })
	-- Pan rail behind the grate: one long row of small black pans
	local railFront = L.boardZ + gd / 2 + 0.05
	local railZ = railFront + 0.65
	local railTop = top + 0.25
	P(m, base, Vector3.new(w, railTop - 3.2, 1.3), at(0, (3.2 + railTop) / 2, railZ), STEEL, Enum.Material.Metal, { name = "Rail" })
	local fills = { "Sauce", "Cheese", "Cheese", "Pepperoni", "Pepperoni", "Ham", "Pineapple", "Peppers", "Mushrooms", "Olives", "Pepperoni", "Cheese", "", "", "" }
	local count = #fills
	local pw = (w - 0.6) / count
	for i, ing in fills do
		local x = -w / 2 + 0.3 + pw * (i - 0.5)
		P(m, base, Vector3.new(pw - 0.08, 0.06, 0.95), at(x, railTop + 0.01, railZ), Color3.fromRGB(28, 28, 30), Enum.Material.SmoothPlastic, { collide = false })
		local color = Config.IngredientColors[ing]
		if color then
			P(m, base, Vector3.new(pw - 0.2, 0.05, 0.8), at(x, railTop + 0.02, railZ), color, if ing == "Cheese" or ing == "Pineapple" then Enum.Material.Sand else Enum.Material.SmoothPlastic, { collide = false })
		end
	end
	-- Sloped stainless canopy over the pans, rising to the back ledge
	local slope = math.rad(-14) -- back edge up
	local canopyZ = railFront + 1.0
	P(m, base, Vector3.new(w, 0.06, 1.6), at(0, top + 1.35, canopyZ) * CFrame.Angles(slope, 0, 0), STEEL, Enum.Material.Metal, { name = "Canopy", reflect = 0.15 })
	P(m, base, Vector3.new(w, 0.22, 0.05), at(0, top + 1.03, railFront + 0.23), STEEL, Enum.Material.Metal, { collide = false })
	for _, sx in { -1, 1 } do
		P(m, base, Vector3.new(0.06, 1.15, 1.6), at(sx * (w / 2 - 0.03), top + 0.85, canopyZ), STEEL, Enum.Material.Metal)
	end
	P(m, base, Vector3.new(w, 0.08, 0.4), at(0, top + 1.55, back - 0.2), STEEL, Enum.Material.Metal, { name = "BackLedge" })
	-- Job aids stand up on the back ledge, on top of the make-line and out of the
	-- way of the work (read them up close with the station rail's Job Aid button).
	jobAid(m, base, at(L.cheeseX, top + 1.6, back - 0.35), Vector2.new(1.4, 1.0), "Cheese", "CHEESE", drawCheese, math.rad(15))
	jobAid(m, base, at(L.toppingsX, top + 1.6, back - 0.35), Vector2.new(2.2, 1.5), "Toppings", "TOPPING PORTIONS", drawPortions, math.rad(15))
	-- Where waiting pizzas sit (ShopService lines them up here)
	P(m, base, Vector3.new(0.1, 0.1, 0.1), at(L.saucedQueueX, top, L.boardZ), BLACK, nil, { name = "SaucedQueue", transparency = 1, collide = false })
	P(m, base, Vector3.new(0.1, 0.1, 0.1), at(L.cheesedQueueX, top, L.boardZ), BLACK, nil, { name = "CheesedQueue", transparency = 1, collide = false })
end

-- The ready rack: a small stainless table at the end of the make-line, by the
-- oven entrance, with a pizza-screen rack on it like the dough racks.
-- Finished pizzas wait on its screens (Config.ReadyRack.Slots of them,
-- ReadySlot_<n> markers, top first) until someone loads them.
Builders.ReadyRack = function(m, base)
	local L = StationArt.Layout.ReadyRack
	steelTable(m, base, L.width, L.depth, L.height)
	screenRack(m, base, 0, 0.1, L.rackWidth, L.rackDepth, L.height, Config.ReadyRack.Slots, L.slotSpacing, "ReadySlot_", 1)
	local tag = P(m, base, Vector3.new(2.0, 0.32, 0.04), at(0, L.height - 0.25, -L.depth / 2 - 0.08), BLACK, nil, { collide = false })
	surfaceText(tag, Enum.NormalId.Front, "READY TO LOAD", Color3.fromRGB(255, 190, 60), BLACK)
end

-- Three stacked stainless conveyor ovens, after the user's photos. Pizzas
-- ride in at +Z (the make-line end) and out at -Z, toward the oven tender at
-- the cut table (LookVector = the exit end), two side by side per oven. Each
-- bake chamber is hollow, with an access door on the kitchen side (-X) whose
-- long window shows the pizzas riding through; vented back, open belt mouths
-- at both ends, a control box by the exit, on casters. Slots 1-2 are the top
-- oven, 3-4 the middle, 5-6 the bottom; in each oven the -X lane comes first.
-- Markers per slot: OvenIn_<n> / OvenOut_<n> (a pizza's center at the start
-- and end of its lane) and OvenMouthIn_<n> / OvenMouthOut_<n> (where the lane
-- enters and leaves the bake chamber).
Builders.Oven = function(m, base)
	local L = StationArt.Layout.Oven
	local W, B, C = L.width, L.belt, L.chamber
	local bottom = L.decks[#L.decks] - 0.175
	-- Stand on casters
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			P(m, base, Vector3.new(0.4, bottom - 0.35, 0.4), at(sx * (W / 2 - 0.4), 0.35 + (bottom - 0.35) / 2, sz * (C / 2 - 0.4)), STEEL_DARK, Enum.Material.Metal, { collide = true })
			P(m, base, Vector3.new(0.18, 0.32, 0.32), at(sx * (W / 2 - 0.4), 0.16, sz * (C / 2 - 0.4)), BLACK, Enum.Material.Rubber, { shape = Enum.PartType.Cylinder })
		end
	end
	local GLASS = Color3.fromRGB(40, 40, 46)
	for i, y in L.decks do
		local y0, y1 = y - 0.175, y + 1.375 -- the chamber's floor and roof
		local hgt = y1 - y0
		-- Shell: floor (under the belt), roof, and the back wall with vent slots.
		P(m, base, Vector3.new(W, 0.12, C), at(0, y0 + 0.06, 0), STEEL, Enum.Material.Metal, { name = "DeckFloor", collide = true })
		P(m, base, Vector3.new(W, 0.125, C), at(0, y1 - 0.0625, 0), STEEL, Enum.Material.Metal, { name = "DeckRoof", reflect = 0.08, collide = true })
		P(m, base, Vector3.new(0.1, hgt, C), at(W / 2 - 0.05, (y0 + y1) / 2, 0), STEEL, Enum.Material.Metal, { name = "DeckBack", collide = true })
		for row = 0, 1 do
			for k = 0, 8 do
				P(m, base, Vector3.new(0.02, 0.05, 0.7), at(W / 2 + 0.01, y0 + 0.45 + row * 0.55, -C / 2 + 1.2 + k * 1.1), BLACK, Enum.Material.SmoothPlastic, { collide = false })
			end
		end
		-- Ends: a bezel over each belt mouth; the mouth itself is open.
		for _, sz in { -1, 1 } do
			P(m, base, Vector3.new(W, hgt - 0.55, 0.1), at(0, y0 + 0.55 + (hgt - 0.55) / 2, sz * (C / 2 - 0.05)), STEEL, Enum.Material.Metal, { collide = true })
		end
		-- Kitchen side: the access door, with a long window to watch the pizzas go by and a handle.
		local fx = -W / 2 + 0.04
		local winBottom, winTop = y + 0.1, y + 0.8
		P(m, base, Vector3.new(0.08, winBottom - y0, C), at(fx, (y0 + winBottom) / 2, 0), STEEL, Enum.Material.Metal, { name = "Door", collide = true })
		P(m, base, Vector3.new(0.08, y1 - winTop, C), at(fx, (winTop + y1) / 2, 0), STEEL, Enum.Material.Metal, { name = "Door", collide = true })
		for _, sz in { -1, 1 } do
			P(m, base, Vector3.new(0.08, winTop - winBottom, 1.0), at(fx, (winBottom + winTop) / 2, sz * (C / 2 - 0.5)), STEEL, Enum.Material.Metal, { collide = true })
		end
		P(m, base, Vector3.new(0.04, winTop - winBottom, C - 2.0), at(fx, (winBottom + winTop) / 2, 0), GLASS, Enum.Material.SmoothPlastic, { name = "Window", transparency = 0.6, collide = true })
		-- Raised steel frame around the window
		for _, wy in { winBottom, winTop } do
			P(m, base, Vector3.new(0.1, 0.07, C - 1.86), at(fx - 0.04, wy, 0), STEEL, Enum.Material.Metal, { reflect = 0.25, collide = false })
		end
		for _, sz in { -1, 1 } do
			P(m, base, Vector3.new(0.1, winTop - winBottom + 0.07, 0.07), at(fx - 0.04, (winBottom + winTop) / 2, sz * (C / 2 - 1.0)), STEEL, Enum.Material.Metal, { reflect = 0.25, collide = false })
		end
		P(m, base, Vector3.new(0.1, 0.1, C - 3.2), at(fx - 0.24, winTop + 0.24, 0), STEEL, Enum.Material.Metal, { name = "Handle", reflect = 0.3, collide = false })
		for _, sz in { -1, 1 } do
			P(m, base, Vector3.new(0.24, 0.07, 0.07), at(fx - 0.12, winTop + 0.24, sz * (C / 2 - 1.7)), STEEL, Enum.Material.Metal, { collide = false })
		end
		-- A dim, plain interior light so the window isn't just dark.
		local lamp = P(m, base, Vector3.new(0.2, 0.05, 0.2), at(0, y1 - 0.2, 0), BLACK, nil, { transparency = 1, collide = false })
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 238, 215)
		light.Brightness = 0.5
		light.Range = 5
		light.Parent = lamp
		-- Control box beside the exit
		local control = P(m, base, Vector3.new(0.9, 1.1, 1.3), at(W / 2 + 0.45, y + 0.5, -C / 2 - 0.9), Color3.fromRGB(232, 232, 228), Enum.Material.SmoothPlastic, { name = "OvenControl", collide = true })
		surfaceText(control, Enum.NormalId.Front, string.format("OVEN CONTROL\n510 F   %d:%02d", Config.Oven.BakeTime // 60, Config.Oven.BakeTime % 60), Color3.fromRGB(40, 40, 46))
		-- Wire belt running through, sticking out both ends, with side rails
		P(m, base, Vector3.new(W - 0.8, 0.1, B), at(0, y, 0), Color3.fromRGB(90, 90, 95), Enum.Material.DiamondPlate, { collide = false, name = "Belt" })
		for _, sx in { -1, 1 } do
			P(m, base, Vector3.new(0.12, 0.25, B), at(sx * (W / 2 - 0.35), y + 0.05, 0), STEEL_DARK, Enum.Material.Metal, { collide = false })
		end
		for j, lx in L.lanes do
			local slot = (i - 1) * #L.lanes + j
			local function mark(name: string, z: number)
				P(m, base, Vector3.new(0.1, 0.1, 0.1), at(lx, y + 0.11, z), BLACK, nil, { name = name .. slot, transparency = 1, collide = false })
			end
			mark("OvenIn_", B / 2 - 1.3)
			mark("OvenMouthIn_", C / 2)
			mark("OvenMouthOut_", -C / 2)
			mark("OvenOut_", -B / 2 + 1.3)
			-- Slot numbers under both belt ends, matching: the exit's face the
			-- tender (-Z), the entrance's face the loader (+Z).
			local outTag = P(m, base, Vector3.new(0.5, 0.22, 0.05), at(lx, y - 0.1, -B / 2 - 0.03), Color3.new(1, 1, 1), nil, { collide = false })
			surfaceText(outTag, Enum.NormalId.Front, tostring(slot), Config.Brand.Red)
			local inTag = P(m, base, Vector3.new(0.5, 0.22, 0.05), at(lx, y - 0.1, B / 2 + 0.03), Color3.new(1, 1, 1), nil, { collide = false })
			surfaceText(inTag, Enum.NormalId.Back, tostring(slot), Config.Brand.Red)
		end
	end
	-- Exhaust hood + duct to the roof
	local top = L.decks[1] + 1.375
	P(m, base, Vector3.new(W + 1.5, 1, C + 3), at(0, top + 0.9, 0), STEEL, Enum.Material.Metal, { name = "Hood" })
	P(m, base, Vector3.new(2.2, 14 - top, 2.2), at(0, top + 1.4 + (14 - top) / 2, 0), STEEL, Enum.Material.Metal, { name = "Duct" })
end

-- Cut table beside the oven exits, modeled on a real chain's cut station: a
-- long stainless table with pizza boxes folded open flat (tray in front, lid
-- lying open behind it), seasoning shakers, a rocker blade in its holder, a
-- label printer, and the cut guide. The ovens are off its +X end.
-- Box_<Size> parts carry BoxSize + WallHeight; Lid_<Size> carries OpenAngle so
-- the cut minigame can swing the same lid shut. CutLanding: where a pizza
-- pulled off the belt sits while someone works it.
local BOX_WALL = 0.2

-- Lid hinged at the back of the tray; angle 0 = closed over the box, 180 = flat behind.
local function lidCFrame(boxCenter: CFrame, bs: number, angle: number): CFrame
	return boxCenter * CFrame.new(0, BOX_WALL - 0.025, bs / 2) * CFrame.Angles(math.rad(angle), 0, 0) * CFrame.new(0, 0, -bs / 2)
end

Builders.CutTable = function(m, base)
	local L = StationArt.Layout.CutTable
	local h, w, d = L.height, L.width, L.depth
	steelTable(m, base, w, d, h)
	local cardboard = Color3.fromRGB(205, 168, 118)
	local inside = Color3.fromRGB(225, 200, 160)

	-- Open boxes, small to large from the oven end, front edges lined up at the cutter's edge.
	local x = w / 2 - 0.8
	local frontEdge = -d / 2 + 0.2
	for _, size in Config.Sizes do
		local bs = Config.BoxSize[size]
		local cx = x - bs / 2
		x -= bs + 0.2
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
		-- Printed outside of the lid (faces down while open).
		surfaceText(lid, Enum.NormalId.Top, (string.upper(Config.GameName):gsub(" ", "\n")), Config.Brand.Red, cardboard)
		-- Size printed on the tray's front edge
		local sizeTag = P(m, base, Vector3.new(0.45, 0.16, 0.03), at(cx, h + 0.1, frontEdge - 0.03), Color3.new(1, 1, 1))
		surfaceText(sizeTag, Enum.NormalId.Front, string.sub(size, 1, 1), Config.Brand.Red)
	end
	-- Where a pulled pizza waits on the table (by the oven end, behind the boxes)
	P(m, base, Vector3.new(0.1, 0.1, 0.1), at(w / 2 - 1.6, h + 0.08, 1.4), BLACK, nil, { name = "CutLanding", transparency = 1, collide = false })

	-- Far end: rocker blade standing in a stainless holder, seasoning shakers, label printer.
	P(m, base, Vector3.new(1.0, 0.9, 0.5), at(-w / 2 + 0.9, h + 0.45, 1.6), STEEL, Enum.Material.Metal, { name = "BladeHolder", reflect = 0.15 })
	P(m, base, Vector3.new(0.05, 0.6, 2.4), at(-w / 2 + 0.9, h + 1.05, 1.6) * CFrame.Angles(0, math.rad(90), 0), STEEL, Enum.Material.Metal, { reflect = 0.3 })
	for _, sx in { -1, 1 } do
		P(m, base, Vector3.new(0.18, 0.5, 0.18), up(-w / 2 + 0.9 + sx * 1.3, h + 1.15, 1.6), BLACK, Enum.Material.Plastic, { shape = Enum.PartType.Cylinder })
	end
	for i, zOff in { 0.2, 0.55 } do
		P(m, base, Vector3.new(0.75, 0.32, 0.32), up(-w / 2 + 0.6 + i * 0.4, h + 0.375, zOff), Color3.fromRGB(230, 215, 170), Enum.Material.Plastic, { shape = Enum.PartType.Cylinder, collide = false })
		P(m, base, Vector3.new(0.12, 0.34, 0.34), up(-w / 2 + 0.6 + i * 0.4, h + 0.78, zOff), Color3.fromRGB(200, 40, 40), Enum.Material.Plastic, { shape = Enum.PartType.Cylinder, collide = false })
	end
	P(m, base, Vector3.new(0.9, 0.55, 0.9), at(-0.6, h + 0.275, 1.9), Color3.fromRGB(28, 28, 32), Enum.Material.SmoothPlastic, { name = "LabelPrinter" })
	-- A few flat boxes ready to fold, behind the box line
	for j = 0, 3 do
		P(m, base, Vector3.new(1.2, 0.05, 1.2), at(0.9, h + 0.03 + j * 0.055, 1.9), cardboard, Enum.Material.Cardboard, { collide = false })
	end
	-- Job aid: the cut guide
	jobAid(m, base, at(-w / 2 + 2.4, h, -0.9), Vector2.new(2.0, 1.3), "CutTable", "CUT GUIDE", drawCuts)

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
