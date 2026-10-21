--!strict
-- Detailed visuals for each station, built from parts.
--
-- Convention for every builder: `base` is the station's floor-center (or
-- mount point), with LookVector (-Z) pointing at where the worker stands.
--
-- To use a real model instead, put a Model named after the station kind in
-- ServerStorage/StationModels (e.g. "Oven", "StretchTable", "MakeLine"). Set its pivot to the bottom
-- center with the front facing the pivot's LookVector; it replaces the
-- generated art everywhere, franchises included.

local AssetService = game:GetService("AssetService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Style = require(game:GetService("ReplicatedStorage").Shared.Style)
local PizzaBox = require(game:GetService("ReplicatedStorage").Shared.PizzaBox)
local MeshBank = require(script.Parent.MeshBank)

local StationArt = {}

local STEEL = Color3.fromRGB(196, 200, 206)
local STEEL_DARK = Color3.fromRGB(120, 124, 130)
local STAINLESS = Color3.fromRGB(140, 145, 152) -- big Metal meshes: STEEL blows out white under the store's lights
local SAUCE_TUB = Color3.fromRGB(160, 38, 26) -- sauce in the tub, darker than on a pizza
local GRIP_RED = Color3.fromRGB(200, 35, 35) -- spoodle grips (the user's photo)
-- Foods on the makeline rail that aren't on the menu (yet): shown, not clickable.
local SHOW_FOOD = {
	Onions = Color3.fromRGB(240, 236, 222),
	Chicken = Color3.fromRGB(196, 146, 92), -- grilled, so it isn't mistaken for mushrooms
	Sausage = Color3.fromRGB(125, 95, 80),
	Pasta = Color3.fromRGB(240, 208, 130),
	Wings = Color3.fromRGB(200, 120, 60),
	SuperCakes = Color3.fromRGB(72, 40, 26),
}
-- Foods in the makeline's pans that look different raw: shredded mozzarella is
-- paler than melted (and not the pineapple's yellow).
local PAN_FOOD = { Cheese = Color3.fromRGB(245, 232, 180) }
local BLACK = Color3.fromRGB(25, 25, 28)
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

-- A solid steel triangle from the floor to height h over art-local points a,
-- b, c (y ignored): two WedgePart right triangles, split at the foot of the
-- altitude onto the longest side.
local function triangleSlab(parent: Instance, base: CFrame, a: Vector3, b: Vector3, c: Vector3, h: number)
	if (c - b).Magnitude > (b - a).Magnitude and (c - b).Magnitude >= (a - c).Magnitude then
		a, b, c = b, c, a
	elseif (a - c).Magnitude > (b - a).Magnitude then
		a, b, c = c, a, b
	end
	local along = (b - a).Unit
	local foot = a + along * (c - a):Dot(along)
	local alt = c - foot
	for _, far in { a, b } do
		local leg = far - foot
		if leg.Magnitude > 0.001 then
			-- the right angle at the foot: local -Z runs to `far`, +Y to c, X is vertical
			local zAxis, yAxis = -leg.Unit, alt.Unit
			local wedge = Instance.new("WedgePart")
			wedge.Name = "CornerTop"
			wedge.Anchored = true
			wedge.Size = Vector3.new(h, alt.Magnitude, leg.Magnitude)
			wedge.CFrame = base * CFrame.fromMatrix(foot + leg / 2 + alt / 2 + Vector3.new(0, h / 2, 0), yAxis:Cross(zAxis), yAxis, zAxis)
			wedge.Color = STEEL
			wedge.Material = Enum.Material.Metal
			wedge.TopSurface = Enum.SurfaceType.Smooth
			wedge.BottomSurface = Enum.SurfaceType.Smooth
			wedge.CanTouch = false
			wedge.Parent = parent
		end
	end
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

-- Blender meshes (MeshBank): a MeshPart template per mesh id, loaded once per
-- server (CreateMeshPartAsync yields); false = it failed to load.
local templates: { [number]: MeshPart | false } = {}
local loading: { [number]: boolean } = {}

local function template(id: number): MeshPart?
	while loading[id] do
		task.wait()
	end
	if templates[id] == nil then
		loading[id] = true
		local ok, part = pcall(AssetService.CreateMeshPartAsync, AssetService, "rbxassetid://" .. id, { CollisionFidelity = Enum.CollisionFidelity.Box })
		templates[id] = if ok then part else false
		loading[id] = nil
		if not ok then
			warn(`StationArt: mesh {id} didn't load ({part}), using the code-built art`)
		end
	end
	return templates[id] or nil
end

-- Starts loading every station mesh at once (at server start), so the first
-- store to open doesn't wait on them one by one.
function StationArt.Preload()
	for _, bank in MeshBank do
		for _, mesh in bank.meshes do
			task.spawn(template, mesh.id)
		end
	end
end

-- The station's meshes by name once all are loaded, or nil (none uploaded yet,
-- or one failed: the station then gets its code-built art).
local function stationMeshes(kind: string): { [string]: MeshBank.Mesh }?
	local bank = MeshBank[kind]
	if not bank then
		return nil
	end
	for _, mesh in bank.meshes do
		if not template(mesh.id) then
			return nil
		end
	end
	return bank.meshes
end

-- Roblox's importer turns an uploaded glTF model 180 degrees about Y.
local IMPORT_TURN = CFrame.Angles(0, math.pi, 0)

-- A copy of a loaded mesh at `scale` times its size, its bounding-box centre at `offset`.
local function M(parent: Instance, base: CFrame, mesh: MeshBank.Mesh, offset: CFrame, color: Color3, material: Enum.Material, opts: Opts?, scale: number?): MeshPart
	local p = (templates[mesh.id] :: MeshPart):Clone()
	p.Name = (opts and opts.name) or "Detail"
	p.Anchored = true
	p.Size = mesh.size * (scale or 1)
	p.CFrame = base * offset * IMPORT_TURN
	p.Color = color
	p.Material = material
	p.Reflectance = (opts and opts.reflect) or 0
	p.Transparency = (opts and opts.transparency) or 0
	p.CanCollide = (opts and opts.collide) or false
	p.CanTouch = false
	p.Parent = parent
	return p
end

---------------------------------------------------------------------------

local Builders: { [string]: (Instance, CFrame) -> () } = {}

-- Shared layout for the multi-station pieces, so MapBuilder can put each
-- station's hitbox over the right spot. All values are art-local (worker at -Z).
StationArt.Layout = {
	-- Stretch table along the dough show glass: the dough trays at the far end
	-- (short side along the table), then the cornmeal where skins are stretched.
	StretchTable = {
		width = 12.7,
		depth = 4.4,
		height = 3.4,
		workX = 3.8, -- the stretch spot, in the cornmeal
		workZ = -0.6,
		trayZ = 0.45,
		trayWidth = 2.25, -- along the table
		trayDepth = 3.25, -- across it
		-- `rows`: balls per row along the tray's long side, staggered like the
		-- user's photos (a single row sits centred between the pairs).
		trays = {
			Small = { x = -5.0, ball = 0.6, rows = { 1, 2, 1, 2, 1, 2, 1 } },
			Medium = { x = -2.6, ball = 0.74, rows = { 2, 1, 2, 1, 2 } },
			Large = { x = -0.2, ball = 0.92, rows = { 2, 2, 2 } },
		},
	},
	-- The sauce corner (user, 2026-10-20, from their photos): separate tables
	-- pushed together, their connecting ends the same size. The trapezoid corner
	-- table along the angled lobby wall (`corner`: art-local corners, front then
	-- back at the stretch table, back then front at the sauce table; its front
	-- parallel to its back) and the sauce table, its front flush with the
	-- makeline's. The two skin racks side by side on the corner table (`racks`:
	-- art-local centres and turn in degrees; `rackLift` raises their slots so the
	-- Sauce minigame's spoodle passes under them), the sauce tub in the back
	-- corner against the makeline (`tub`), the saucing spot right in front of it.
	-- All from tools/blender/sauce_table.py (its [layout] printout).
	SauceTable = {
		width = 5.664,
		depth = 4.7,
		height = 3.4,
		workX = 1.582,
		workZ = -1.101,
		racks = { { x = -5.371, z = -2.462, yaw = -46.89 }, { x = -3.663, z = -0.637, yaw = -46.89 } },
		rackLift = 0.35,
		rackWidth = 2.6,
		rackDepth = 2.2,
		slotSpacing = 0.2,
		corner = { Vector3.new(-3.768, 0, -3.35), Vector3.new(-8.168, 0, -3.35), Vector3.new(-2.832, 0, 2.35), Vector3.new(-2.832, 0, -2.35) },
		tub = Vector3.new(1.982, 0, 1.44),
	},
	MakeLine = {
		width = 13.6, -- four sections: a door, two drawer columns, a door (the user)
		depth = 4.7, -- front face at z -1.8
		grateDepth = 2.9, -- a Large is 2.4 across (2.55 on its screen): room to spare front and back
		boardZ = -0.3, -- center of the grate (where pizzas sit), just behind the front lip
		boardTop = 3.4, -- flush with the sauce and stretch tables
		-- The user's order (2026-10-20): Cheese first, where the sauced pizza is
		-- pushed over from the sauce table (-X), in front of the cheese pan; then
		-- Toppings, centred on the topping pans (tools/blender/makeline.py's
		-- [layout]). Pizzas waiting for a step sit on its spot (the worker's
		-- screen hides the others while they work).
		saucedQueueX = -4.45,
		cheeseX = -4.45,
		cheesedQueueX = -0.487,
		toppingsX = -0.487,
	},
	-- The ready rack (the user, 2026-10-20): a square table at the makeline's
	-- end, as deep as the line, the rack at its back (tools/blender/ready_rack.py's
	-- [layout]); screens hold Large pizzas, slots spaced for topped pizzas.
	ReadyRack = { width = 4.7, depth = 4.7, height = 3.4, rackX = 0, rackZ = 0.915, rackWidth = 2.6, rackDepth = 2.2, slotSpacing = 0.3 },
	-- Three stacked conveyor ovens, running along Z: in at +Z (the make-line
	-- end), out at -Z (LookVector: toward the oven tender at the cut table).
	Oven = {
		belt = 13.6, -- belt length (about 9 ft), entrance extension + bake chamber + exit extension
		chamber = 7.6,
		width = 6.6,
		lanes = { -1.4, 1.4 }, -- two pizzas side by side; the -X lane is each oven's first slot
		decks = { 5.1, 3.2, 1.3 }, -- belt heights: top (slots 1-2), middle (3-4), bottom (5-6)
	},
	-- The carryout rack across the cut table's far end (the user, 2026-10-21;
	-- tools/blender/carryout_rack.py): `tiers` are the box tiers' surfaces (the
	-- table top, level with the cut table's, and two heated shelves), two stacks
	-- a tier at `slotsX`; `nextTo`: its centre from the cut table's, along the
	-- cut table's length. Its -Z faces the cut table, +Z the carryout side.
	CarryoutRack = { length = 6.3, depth = 3.0, tiers = { 3.2, 4.55, 5.9 }, slotsX = { -1.55, 1.55 }, nextTo = 7.95 },
	-- Cut table behind the oven exits (the ovens are off its +X end), the oven
	-- tender on its long side facing the carryout counter.
	CutTable = {
		width = 12.8,
		depth = 6.3,
		height = 3.2,
		-- tools/blender/cut_table.py's [layout]: each stack's tray (its top
		-- blank's base panel) centre, at the stack's top; the trough's rockers.
		trays = { Small = Vector3.new(4.878, 3.68, -1.628), Medium = Vector3.new(1.812, 3.74, -1.456), Large = Vector3.new(-2.246, 3.8, -1.285) },
		rockers = { Vector3.new(-0.271, 2.8, -0.8), Vector3.new(0.009, 2.8, -0.8) },
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
-- `first`; returns the next number. `wires` false: only the bounds and markers
-- (the rack itself is a mesh). `lift` raises every slot; `yaw` (degrees) turns
-- the rack about its centre.
local CHROME = Color3.fromRGB(215, 218, 222)
local RACK_LEDGE = 0.75 -- a Small screen is 0.89 in radius
local function screenRack(m: Instance, base: CFrame, cx: number, cz: number, rw: number, rd: number, h: number, slots: number, spacing: number, prefix: string, first: number, wires: boolean?, lift: number?, yaw: number?): number
	if yaw then
		base = base * CFrame.new(cx, 0, cz) * CFrame.Angles(0, math.rad(yaw), 0)
		cx, cz = 0, 0
	end
	local wire = 0.05
	local topRail = h + 0.2 + (lift or 0) + (slots - 1) * spacing
	local front, back = cz - rd / 2 + 0.06, cz + rd / 2 - 0.04
	local function bar(size: Vector3, offset: CFrame)
		if wires ~= false then
			P(m, base, size, offset, CHROME, Enum.Material.Metal, { reflect = 0.25, collide = false })
		end
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
			-- a ledge just inside a Small screen's edge (every size rests on it), tied to the side frame
			local y = topRail - (i - 1) * spacing
			bar(Vector3.new(wire, wire, back - front), at(cx + sx * RACK_LEDGE, y, (front + back) / 2))
			bar(Vector3.new(rw / 2 - RACK_LEDGE, wire, wire), at(cx + sx * (rw / 2 + RACK_LEDGE) / 2, y, front))
			bar(Vector3.new(rw / 2 - RACK_LEDGE, wire, wire), at(cx + sx * (rw / 2 + RACK_LEDGE) / 2, y, back))
		end
	end
	P(m, base, Vector3.new(rw, topRail - h + 0.2, rd), at(cx, (h + topRail + 0.2) / 2, cz), CHROME, nil, { name = "RackBounds", transparency = 1, collide = true })
	for i = 1, slots do
		P(m, base, Vector3.new(0.1, 0.1, 0.1), at(cx, topRail - (i - 1) * spacing + wire / 2, cz), CHROME, nil, { name = prefix .. (first + i - 1), transparency = 1, collide = false })
	end
	return first + slots
end

local CORNMEAL = Color3.fromRGB(236, 196, 92)

-- Cornmeal scattered around (cx, cz) the way it ends up after a rush: patches
-- and swirls, each a hair higher than the last so none z-fight. Kept inside
-- the w x d top.
local function cornmealDust(m: Instance, base: CFrame, rng: Random, w: number, d: number, h: number, cx: number, cz: number, spread: number, n: number, layer: number)
	for i = 1, n do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = spread * math.sqrt(rng:NextNumber())
		local x, z = cx + math.cos(a) * r, cz + math.sin(a) * r
		if math.abs(x) > w / 2 - 0.2 or math.abs(z) > d / 2 - 0.2 then
			continue
		end
		local y = h + 0.005 + (layer + i) * 0.0015
		local tint = CORNMEAL:Lerp(Color3.fromRGB(245, 215, 130), rng:NextNumber(0, 0.6))
		if rng:NextNumber() < 0.6 then
			local sz = rng:NextNumber(0.25, 1.0)
			P(m, base, Vector3.new(0.01, sz, sz * rng:NextNumber(0.5, 1)), up(x, y, z) * CFrame.Angles(rng:NextNumber(0, math.pi), 0, 0), tint, Enum.Material.Sand, { shape = Enum.PartType.Cylinder, collide = false })
		else
			P(m, base, Vector3.new(rng:NextNumber(0.5, 1.4), 0.01, rng:NextNumber(0.1, 0.22)), at(x, y, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), tint, Enum.Material.Sand, { collide = false })
		end
	end
end

-- The stretch table along the dough show glass, after the user's store map:
-- a tray of proofed dough balls per size at the far end (Config.Dough.TrayBalls
-- each, in rows across the tray), more trays on dollies underneath, and the
-- cornmeal where a ball is pressed out and stretched. Each ball is a
-- `DoughBall` part with Size + Index: ShopService hides the ones used up (the
-- highest numbers first) and the Stretch minigame picks one by clicking.
-- Blender meshes when they load (MeshBank), else built from parts.
local STRETCH_MESH = { -- extras in the mesh version, as in tools/blender/stretch_table.py
	trayFloor = 0.03,
	dollies = { -4.85, -2.5, -0.15 },
	dollyZ = 0.1,
	dollyTop = 0.32,
	stack = 7,
	pitch = 0.345,
	binFill = CFrame.new(3.8, 1.95, 0),
	binFillSize = Vector3.new(2.08, 0.02, 2.95),
	dustZ = -0.15,
	dustSize = 4,
}
Builders.StretchTable = function(m, base)
	local L = StationArt.Layout.StretchTable
	local w, d, h = L.width, L.depth, L.height
	local TRAY = Color3.fromRGB(45, 125, 215)
	local tw, td = L.trayWidth, L.trayDepth
	local S = STRETCH_MESH
	local mesh = stationMeshes("StretchTable")
	if mesh then
		M(m, base, mesh.Steel, CFrame.new(mesh.Steel.at), STAINLESS, Enum.Material.Metal, { collide = true, name = "Table" })
		M(m, base, mesh.Rubber, CFrame.new(mesh.Rubber.at), BLACK, Enum.Material.Rubber)
		M(m, base, mesh.Dollies, CFrame.new(mesh.Dollies.at), Color3.fromRGB(62, 64, 70), Enum.Material.Plastic)
		M(m, base, mesh.Bin, CFrame.new(mesh.Bin.at), Color3.fromRGB(235, 232, 225), Enum.Material.Plastic, { name = "CornmealBin" })
	else
		steelTable(m, base, w, d, h)
	end
	for _, size in Config.Sizes do
		local t = L.trays[size]
		-- Walls tagged with the size: the Stretch minigame lights the tray to use.
		local walls = {}
		if mesh then
			table.insert(walls, M(m, base, mesh.Tray, at(t.x, h + mesh.Tray.size.Y / 2, L.trayZ), TRAY, Enum.Material.Plastic, { name = "DoughTrayWall" }))
		else
			P(m, base, Vector3.new(tw, 0.06, td), at(t.x, h + 0.03, L.trayZ), TRAY, Enum.Material.Plastic, { name = "DoughTray_" .. size })
			for _, sx in { -1, 1 } do
				table.insert(walls, P(m, base, Vector3.new(0.06, 0.32, td), at(t.x + sx * (tw / 2 - 0.03), h + 0.16, L.trayZ), TRAY, Enum.Material.Plastic, { collide = false, name = "DoughTrayWall" }))
			end
			for _, sz in { -1, 1 } do
				table.insert(walls, P(m, base, Vector3.new(tw, 0.32, 0.06), at(t.x, h + 0.16, L.trayZ + sz * (td / 2 - 0.03)), TRAY, Enum.Material.Plastic, { collide = false, name = "DoughTrayWall" }))
			end
		end
		for _, wall in walls do
			wall:SetAttribute("Size", size)
		end
		local n = 0
		for r, count in t.rows do
			-- Rows spread between the end walls (row 1 nearest the stretcher), clear of them.
			local bz = L.trayZ - td / 2 + 0.1 + t.ball / 2 + (r - 1) * (td - t.ball - 0.2) / math.max(#t.rows - 1, 1)
			for c = 1, count do
				n += 1
				local bx = t.x + (if count == 1 then 0 else (c - 1.5) * (tw / 2))
				local ball: BasePart
				if mesh then
					-- One of three proofed lumps, each turned its own way.
					local lump = mesh["Ball" .. (n - 1) % 3 + 1]
					local s = t.ball / lump.size.X
					ball = M(m, base, lump, at(bx, h + S.trayFloor + lump.size.Y * s / 2, bz) * CFrame.Angles(0, math.rad(n * 77), 0), DOUGH, Enum.Material.SmoothPlastic, { name = "DoughBall" }, s)
				else
					-- A proofed ball is a soft dome: a sphere mesh squashed to 60% height.
					ball = P(m, base, Vector3.new(t.ball, t.ball * 0.6, t.ball), at(bx, h + 0.06 + t.ball * 0.3, bz), DOUGH, Enum.Material.SmoothPlastic, { name = "DoughBall", collide = false })
					local sphere = Instance.new("SpecialMesh")
					sphere.MeshType = Enum.MeshType.Sphere
					sphere.Parent = ball
				end
				ball:SetAttribute("Size", size)
				ball:SetAttribute("Index", n)
			end
		end
		assert(n == Config.Dough.TrayBalls[size], size .. " tray layout doesn't match Config.Dough.TrayBalls")
		-- The size on the tray's front wall, facing the stretcher
		local sizeTag = P(m, base, Vector3.new(0.5, 0.2, 0.03), at(t.x, h + 0.2, L.trayZ - td / 2 - 0.02), Color3.new(1, 1, 1), nil, { collide = false })
		surfaceText(sizeTag, Enum.NormalId.Front, string.sub(size, 1, 1), Config.Brand.Red)
	end
	if mesh then
		-- Dollies of full trays under the table, cornmeal in the bin, and a dusting
		-- over the stretch spot (an image on an invisible part).
		for _, x in S.dollies do
			for k = 0, S.stack - 1 do
				M(m, base, mesh.Tray, at(x, S.dollyTop + k * S.pitch + mesh.Tray.size.Y / 2, S.dollyZ), TRAY, Enum.Material.Plastic, { name = "Tray" })
			end
		end
		P(m, base, S.binFillSize, S.binFill, CORNMEAL, Enum.Material.Sand, { collide = false })
		local dust = P(m, base, Vector3.new(S.dustSize, 0.01, S.dustSize), at(L.workX, h + 0.005, S.dustZ), CORNMEAL, nil, { transparency = 1, collide = false, name = "CornmealDust" })
		local decal = Instance.new("Decal")
		decal.Face = Enum.NormalId.Top
		decal.Texture = "rbxassetid://" .. MeshBank.StretchTable.images.Dust
		decal.Parent = dust
		return
	end
	-- Dollies of full trays under the table
	for k = 0, 2 do
		for i = 0, 3 do
			P(m, base, Vector3.new(tw, 0.32, td), at(-5.0 + k * 2.4, 0.5 + i * 0.34, L.trayZ - 0.2), TRAY, Enum.Material.Plastic, { collide = i == 0 })
		end
	end
	-- Cornmeal over the stretch spot and the far end, a bin of it below
	local rng = Random.new(3)
	cornmealDust(m, base, rng, w, d, h, L.workX, L.workZ, 1.9, 26, 0)
	cornmealDust(m, base, rng, w, d, h, L.workX + 1.2, L.workZ + 1.2, 1.2, 8, 40)
	P(m, base, Vector3.new(2.6, 1.6, 2.6), at(L.workX, 1.0 + 0.8, 0.3), Color3.fromRGB(235, 232, 225), Enum.Material.Plastic, { name = "CornmealBin" })
	P(m, base, Vector3.new(2.4, 0.05, 2.4), at(L.workX, 2.61, 0.3), CORNMEAL, Enum.Material.Sand, { collide = false })
end

-- The sauce station in the corner where the stretch table turns into the
-- makeline (the user's store map): the saucing spot at the front, two
-- pizza-screen racks of stretched skins behind it (SkinSlot_<n>, rack 1 top to
-- bottom, then rack 2; ShopService puts each skin in its slot), and a corner
-- piece whose far edge follows the angled lobby wall, where the sauce buckets
-- stand with the spoodles. Blender meshes when they load (MeshBank, after the
-- user's photos: a refrigerated work table, two tall wire screen racks, one
-- clear sauce tub left of the racks with its spoodle, drips), else parts.
Builders.SauceTable = function(m, base)
	local L = StationArt.Layout.SauceTable
	local w, d, h = L.width, L.depth, L.height
	local mesh = stationMeshes("SauceTable")
	if mesh then
		M(m, base, mesh.Steel, CFrame.new(mesh.Steel.at), STAINLESS, Enum.Material.Metal, { collide = true, name = "Table" })
		M(m, base, mesh.Rubber, CFrame.new(mesh.Rubber.at), BLACK, Enum.Material.Rubber)
		M(m, base, mesh.Racks, CFrame.new(mesh.Racks.at), CHROME, Enum.Material.Metal, { name = "Racks" })
		M(m, base, mesh.Tubs, CFrame.new(mesh.Tubs.at), Color3.fromRGB(235, 235, 230), Enum.Material.SmoothPlastic, { name = "SauceBucket", transparency = 0.6 })
		M(m, base, mesh.Sauce, CFrame.new(mesh.Sauce.at), SAUCE_TUB, Enum.Material.SmoothPlastic)
		M(m, base, mesh.Grips, CFrame.new(mesh.Grips.at), GRIP_RED, Enum.Material.Plastic)
		-- The spoodle the Sauce minigame holds (the client clones it; pivot = the cup's centre).
		if not ReplicatedStorage:FindFirstChild("Spoodle") then
			local spoodle = Instance.new("Model")
			spoodle.Name = "Spoodle"
			for _, part in { M(spoodle, CFrame.identity, mesh.Spoodle, CFrame.new(mesh.Spoodle.at), STEEL, Enum.Material.Metal), M(spoodle, CFrame.identity, mesh.SpoodleGrip, CFrame.new(mesh.SpoodleGrip.at), GRIP_RED, Enum.Material.Plastic) } do
				part.CanQuery = false
			end
			spoodle.WorldPivot = CFrame.identity
			spoodle.Parent = ReplicatedStorage
		end
		local slot = 1
		for r = 1, Config.Dough.Racks do
			slot = screenRack(m, base, L.racks[r].x, L.racks[r].z, L.rackWidth, L.rackDepth, h, Config.Dough.SlotsPerRack, L.slotSpacing, "SkinSlot_", slot, false, L.rackLift, L.racks[r].yaw)
		end
		return
	end
	steelTable(m, base, w, d, h)
	-- The corner table: its trapezoid as two solid triangles.
	local c = L.corner
	triangleSlab(m, base, c[1], c[2], c[3], h)
	triangleSlab(m, base, c[1], c[3], c[4], h)
	-- The sauce tub in the back corner against the makeline, its spoodle in it
	local tx, tz = L.tub.X, L.tub.Z
	P(m, base, Vector3.new(1.4, 1.9, 1.9), up(tx, h + 0.7, tz), Color3.fromRGB(235, 232, 225), Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder, transparency = 0.25, name = "SauceBucket" })
	P(m, base, Vector3.new(0.05, 1.8, 1.8), up(tx, h + 0.98, tz), SAUCE_TUB, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder, collide = false })
	P(m, base, Vector3.new(0.08, 1.3, 0.08), at(tx - 0.15, h + 1.4, tz - 0.3) * CFrame.Angles(math.rad(60), 0, 0), STEEL, Enum.Material.Metal, { collide = false })
	P(m, base, Vector3.new(0.17, 0.04, 0.7), at(tx - 0.2, h + 1.62, tz - 1.1) * CFrame.Angles(math.rad(-25), 0, 0), GRIP_RED, Enum.Material.Plastic, { collide = false })
	-- A few drips at the saucing spot
	for _, drip in { { -1.3, -0.45, 0.3 }, { -1.0, 0.85, 0.18 } } do
		P(m, base, Vector3.new(0.02, drip[3], drip[3]), up(L.workX + drip[1], h + 0.01, L.workZ + drip[2]), Config.IngredientColors.Sauce, Enum.Material.SmoothPlastic, { shape = Enum.PartType.Cylinder, collide = false })
	end
	-- The skin racks
	local slot = 1
	for r = 1, Config.Dough.Racks do
		slot = screenRack(m, base, L.racks[r].x, L.racks[r].z, L.rackWidth, L.rackDepth, h, Config.Dough.SlotsPerRack, L.slotSpacing, "SkinSlot_", slot, nil, L.rackLift, L.racks[r].yaw)
	end
end

-- Refrigerated make-line, after the user's photos: a stainless cabinet with
-- doors at the ends and a bank of drawers between, a wire grate work surface
-- along the front where pizzas sit on their way down the line, a row of small
-- black topping pans set into the rail behind it, and a sloped stainless
-- canopy over the pans. The grate is split into four zones, oven side last:
-- sauced pizzas waiting (SaucedQueue marker), the cheese spot, cheesed pizzas
-- waiting (CheesedQueue marker), and the toppings spot. Finished pizzas go on
-- the ready rack, a separate table at the oven end. (Portions are in the
-- stations' tip cards; there are no job aid cards.) Blender meshes when they
-- load (MeshBank), else parts; the scales and queue markers are parts either way.
Builders.MakeLine = function(m, base)
	local L = StationArt.Layout.MakeLine
	local w, depth, top = L.width, L.depth, L.boardTop
	local front = -1.8 -- the cabinet's front face (the makers stand in front of it)
	local back = front + depth
	local mid = (front + back) / 2
	local gd = L.grateDepth
	local mesh = stationMeshes("MakeLine")
	if mesh then
		-- The Blender makeline (tools/blender/makeline.py): cabinet, rolled edge,
		-- grate, rail, pans and canopy; each food its own mesh in its pan (the
		-- toppings are the clickable Pan_<topping>s).
		M(m, base, mesh.Steel, CFrame.new(mesh.Steel.at), STAINLESS, Enum.Material.Metal, { collide = true, name = "Cabinet" })
		M(m, base, mesh.Dark, CFrame.new(mesh.Dark.at), Color3.fromRGB(40, 41, 45), Enum.Material.Metal)
		M(m, base, mesh.Pans, CFrame.new(mesh.Pans.at), Color3.fromRGB(28, 28, 30), Enum.Material.SmoothPlastic, { name = "Pans" })
		for key, food in mesh do
			local ing = string.match(key, "^Food_(.+)$")
			if ing then
				local pan = M(m, base, food, CFrame.new(food.at), PAN_FOOD[ing] or Config.IngredientColors[ing] or SHOW_FOOD[ing] or DOUGH, Enum.Material.SmoothPlastic, { name = "Pan_" .. ing })
				if table.find(Config.Toppings, ing) then
					pan:SetAttribute("Topping", ing)
				end
			end
		end
	else
		P(m, base, Vector3.new(w, 0.4, depth - 0.2), at(0, 0.2, mid + 0.1), BLACK, Enum.Material.SmoothPlastic) -- kick plate
		P(m, base, Vector3.new(w, 2.8, depth), at(0, 1.8, mid), STEEL, Enum.Material.Metal, { name = "Cabinet", reflect = 0.05 })
		-- Front: a door at each end, two drawers in each column between
		local PANEL = Color3.fromRGB(206, 210, 216)
		local sections = 4
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
		P(m, base, Vector3.new(w - 0.3, 0.2, gd + 0.1), at(0, top - 0.17, L.boardZ), Color3.fromRGB(45, 46, 50), Enum.Material.Metal, { name = "Well", collide = true })
		local rods = math.floor(gd / 0.125)
		for i = 0, rods do
			P(m, base, Vector3.new(w - 0.3, 0.035, 0.035), at(0, top - 0.0175, L.boardZ - gd / 2 + i * gd / rods), STEEL, Enum.Material.Metal, { reflect = 0.2, collide = false })
		end
		for i = 0, 10 do
			P(m, base, Vector3.new(0.05, 0.05, gd - 0.05), at(-w / 2 + 0.3 + i * (w - 0.6) / 10, top - 0.06, L.boardZ), STEEL_DARK, Enum.Material.Metal, { collide = false })
		end
		P(m, base, Vector3.new(w, 0.3, 0.08), at(0, top - 0.1, front - 0.04), STEEL, Enum.Material.Metal, { name = "FrontLip" })
	end
	-- Portion scales at the cheese and toppings spots: a flat plate the pizza
	-- sits on and a read-out standing to the maker's right (the tip card is on
	-- the left of the screen), tipped back toward
	-- the maker (`Scale` = the station; the client writes the weight on it
	-- while they work).
	for _, spot in { { id = "Cheese", x = L.cheeseX }, { id = "Toppings", x = L.toppingsX } } do
		P(m, base, Vector3.new(2.7, 0.03, 2.7), at(spot.x, top + 0.015, L.boardZ), STEEL, Enum.Material.Metal, { name = "ScalePlate", collide = false, reflect = 0.2 })
		P(m, base, Vector3.new(0.06, 0.3, 0.06), at(spot.x - 1.75, top + 0.15, L.boardZ - 0.95), STEEL_DARK, Enum.Material.Metal, { collide = false })
		local display = P(m, base, Vector3.new(1.0, 0.5, 0.1), at(spot.x - 1.75, top + 0.42, L.boardZ - 0.95) * CFrame.Angles(math.rad(40), 0, 0), BLACK, Enum.Material.SmoothPlastic, { name = "ScaleDisplay", collide = false })
		display:SetAttribute("Scale", spot.id)
		surfaceText(display, Enum.NormalId.Front, "0.00 OZ", Color3.fromRGB(120, 255, 140), Color3.fromRGB(12, 20, 14), Enum.Font.Code)
	end
	if not mesh then
		-- Pan rail behind the grate: one long row of small black pans. Cheese by
		-- the cheese spot, the toppings in front of the toppings spot, where the
		-- maker clicks one to pick it up (`Topping` attribute).
		local railFront = L.boardZ + gd / 2 + 0.05
		local railZ = railFront + 0.65
		local railTop = top + 0.25
		P(m, base, Vector3.new(w, railTop - 3.2, 1.3), at(0, (3.2 + railTop) / 2, railZ), STEEL, Enum.Material.Metal, { name = "Rail" })
		local fills = { "Cheese", "Cheese", "Cheese", "Pepperoni", "Ham", "Pineapple", "Peppers", "Mushrooms", "Olives", "", "", "" }
		local count = #fills
		local pw = (w - 0.6) / count
		for i, ing in fills do
			local x = -w / 2 + 0.3 + pw * (i - 0.5)
			P(m, base, Vector3.new(pw - 0.08, 0.06, 0.95), at(x, railTop + 0.01, railZ), Color3.fromRGB(28, 28, 30), Enum.Material.SmoothPlastic, { collide = false })
			local color = Config.IngredientColors[ing]
			if color then
				local fill = P(m, base, Vector3.new(pw - 0.2, 0.05, 0.8), at(x, railTop + 0.02, railZ), color, if ing == "Cheese" or ing == "Pineapple" then Enum.Material.Sand else Enum.Material.SmoothPlastic, { collide = false, name = "Pan_" .. ing })
				if table.find(Config.Toppings, ing) then
					fill:SetAttribute("Topping", ing)
				end
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
	end
	-- Where waiting pizzas sit (ShopService lines them up here)
	P(m, base, Vector3.new(0.1, 0.1, 0.1), at(L.saucedQueueX, top, L.boardZ), BLACK, nil, { name = "SaucedQueue", transparency = 1, collide = false })
	P(m, base, Vector3.new(0.1, 0.1, 0.1), at(L.cheesedQueueX, top, L.boardZ), BLACK, nil, { name = "CheesedQueue", transparency = 1, collide = false })
end

-- The ready rack: a square stainless table at the makeline's end with the
-- dough racks' 15-screen rack at its back. Finished pizzas wait on its screens
-- (Config.ReadyRack.Slots of them, ReadySlot_<n> markers, top first) until
-- someone loads them. Blender meshes when they load (MeshBank), else parts.
Builders.ReadyRack = function(m, base)
	local L = StationArt.Layout.ReadyRack
	local mesh = stationMeshes("ReadyRack")
	if mesh then
		M(m, base, mesh.Steel, CFrame.new(mesh.Steel.at), STAINLESS, Enum.Material.Metal, { collide = true, name = "Table" })
		M(m, base, mesh.Rubber, CFrame.new(mesh.Rubber.at), BLACK, Enum.Material.Rubber)
		M(m, base, mesh.Racks, CFrame.new(mesh.Racks.at), CHROME, Enum.Material.Metal, { name = "Racks" })
	else
		steelTable(m, base, L.width, L.depth, L.height)
		local tag = P(m, base, Vector3.new(2.0, 0.32, 0.04), at(0, L.height - 0.25, -L.depth / 2 - 0.08), BLACK, nil, { collide = false })
		surfaceText(tag, Enum.NormalId.Front, "READY TO LOAD", Color3.fromRGB(255, 190, 60), BLACK)
	end
	screenRack(m, base, L.rackX, L.rackZ, L.rackWidth, L.rackDepth, L.height, Config.ReadyRack.Slots, L.slotSpacing, "ReadySlot_", 1, if mesh then false else nil)
end

-- Three stacked conveyor ovens, after the user's photo (2026-10-21). Pizzas
-- ride in at +Z (the make-line end) and out at -Z, toward the oven tender at
-- the cut table (LookVector = the exit end), two side by side per oven. Blender
-- meshes when they load (tools/blender/ovens.py: one painted front per oven
-- with a window to watch the pizzas ride through, stainless housings round the
-- conveyor at both ends, the hood with its baffle filters over the belt ends,
-- the painted enclosure up to the ceiling), else parts. Either way: the belts
-- (a wire Texture) and, with the meshes, the pulleys at their ends, tagged
-- OvenBelt / OvenPulley so the client runs them at the lanes' speed
-- (client/OvenBelts); a dim lamp in each chamber; the slot markers; the slot
-- numbers over each lane's mouth at both ends (the user, 2026-10-21).
-- Slots 1-2 are the top oven, 3-4 the middle, 5-6 the bottom; in each oven the
-- -X lane comes first. Markers per slot: OvenIn_<n> / OvenOut_<n> (a pizza's
-- center at the start and end of its lane) and OvenMouthIn_<n> /
-- OvenMouthOut_<n> (where the lane enters and leaves the bake chamber).
local GLASS = Color3.fromRGB(40, 40, 46)
local BELT_TOP, PULLEY_R = 0.05, 0.12 -- over the deck height; as in tools/blender/ovens.py
local HOUSING_END = 5.13 -- the conveyor housings' end faces (ZH1 in tools/blender/ovens.py)

Builders.Oven = function(m, base)
	local L = StationArt.Layout.Oven
	local W, B, C = L.width, L.belt, L.chamber
	local speed = (B - 2.6) / Config.Oven.BakeTime -- a lane's length (OvenIn to OvenOut) over the bake time, as ShopService moves pizzas
	local mesh = stationMeshes("Oven")
	if mesh then
		M(m, base, mesh.Body, CFrame.new(mesh.Body.at), STAINLESS, Enum.Material.Metal, { collide = true, name = "Body" })
		M(m, base, mesh.Paint, CFrame.new(mesh.Paint.at), STAINLESS, Enum.Material.Metal, { name = "OvenPaint" }) -- StationArt.PaintOven colours it
		M(m, base, mesh.Conveyor, CFrame.new(mesh.Conveyor.at), Color3.fromRGB(160, 164, 170), Enum.Material.Metal)
		M(m, base, mesh.Hood, CFrame.new(mesh.Hood.at), STAINLESS, Enum.Material.Metal, { name = "Hood" })
		M(m, base, mesh.Filters, CFrame.new(mesh.Filters.at), STEEL, Enum.Material.Metal)
		M(m, base, mesh.Dark, CFrame.new(mesh.Dark.at), BLACK, Enum.Material.SmoothPlastic)
		M(m, base, mesh.Glass, CFrame.new(mesh.Glass.at), GLASS, Enum.Material.SmoothPlastic, { name = "Window", transparency = 0.6 })
		M(m, base, mesh.Labels, CFrame.new(mesh.Labels.at), Color3.fromRGB(235, 110, 30), Enum.Material.SmoothPlastic)
		M(m, base, mesh.Rubber, CFrame.new(mesh.Rubber.at), BLACK, Enum.Material.Rubber)
		for _, y in L.decks do
			for _, sz in { -1, 1 } do
				local pulley = M(m, base, mesh.Pulley, CFrame.new(0, y + BELT_TOP - PULLEY_R, sz * (B / 2 - PULLEY_R)) * CFrame.new(mesh.Pulley.at), Color3.fromRGB(175, 178, 184), Enum.Material.Metal, { name = "Pulley" })
				pulley:SetAttribute("Base", pulley.CFrame)
				pulley:SetAttribute("Spin", speed / PULLEY_R)
				CollectionService:AddTag(pulley, "OvenPulley")
			end
		end
	else
		local bottom = L.decks[#L.decks] - 0.175
		-- Stand on casters
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				P(m, base, Vector3.new(0.4, bottom - 0.35, 0.4), at(sx * (W / 2 - 0.4), 0.35 + (bottom - 0.35) / 2, sz * (C / 2 - 0.4)), STEEL_DARK, Enum.Material.Metal, { collide = true })
				P(m, base, Vector3.new(0.18, 0.32, 0.32), at(sx * (W / 2 - 0.4), 0.16, sz * (C / 2 - 0.4)), BLACK, Enum.Material.Rubber, { shape = Enum.PartType.Cylinder })
			end
		end
		for _, y in L.decks do
			local y0, y1 = y - 0.175, y + 1.375 -- the chamber's floor and roof
			local hgt = y1 - y0
			-- Shell: floor (under the belt), roof, and the back wall with vent slots.
			P(m, base, Vector3.new(W, 0.12, C), at(0, y0 + 0.06, 0), STEEL, Enum.Material.Metal, { name = "DeckFloor", collide = true })
			P(m, base, Vector3.new(W, 0.125, C), at(0, y1 - 0.0625, 0), STEEL, Enum.Material.Metal, { name = "DeckRoof", reflect = 0.08, collide = true })
			P(m, base, Vector3.new(0.1, hgt, C), at(W / 2 - 0.05, (y0 + y1) / 2, 0), STEEL, Enum.Material.Metal, { name = "DeckBack", collide = true })
			for row = 0, 1 do
				for k = 0, math.floor((C - 2.4) / 1.1) do
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
			for _, sx in { -1, 1 } do
				P(m, base, Vector3.new(0.12, 0.25, B), at(sx * (W / 2 - 0.35), y + 0.05, 0), STEEL_DARK, Enum.Material.Metal, { collide = false })
			end
		end
		-- Exhaust hood + duct to the roof
		local top = L.decks[1] + 1.375
		P(m, base, Vector3.new(W + 1.5, 1, C + 3), at(0, top + 0.9, 0), STEEL, Enum.Material.Metal, { name = "Hood" })
		P(m, base, Vector3.new(2.2, 14 - top, 2.2), at(0, top + 1.4 + (14 - top) / 2, 0), STEEL, Enum.Material.Metal, { name = "Duct" })
	end
	local mouthFace = if mesh then HOUSING_END else C / 2 + 0.05 -- the face over the mouths: the housings' ends, or the chamber's bezels
	for i, y in L.decks do
		-- The belt: its wire a Texture top and bottom (clear between the wires), between the pulleys.
		local belt = P(m, base, Vector3.new(W - 0.8, 0.03, B - 4 * PULLEY_R), at(0, y + BELT_TOP - 0.015, 0), BLACK, nil, { name = "Belt", transparency = 1, collide = false })
		for _, face in { Enum.NormalId.Top, Enum.NormalId.Bottom } do
			local wire = Instance.new("Texture")
			wire.Texture = "rbxassetid://" .. MeshBank.Oven.images.Belt
			wire.Face = face
			wire.StudsPerTileU, wire.StudsPerTileV = 0.3, 0.3
			wire.Parent = belt
		end
		belt:SetAttribute("BeltSpeed", speed)
		CollectionService:AddTag(belt, "OvenBelt")
		-- A dim, plain interior light so the window isn't just dark.
		local lamp = P(m, base, Vector3.new(0.2, 0.05, 0.2), at(0, y + 1.175, 0), BLACK, nil, { transparency = 1, collide = false })
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 238, 215)
		light.Brightness = 0.5
		light.Range = 5
		light.Parent = lamp
		for j, lx in L.lanes do
			local slot = (i - 1) * #L.lanes + j
			local function mark(name: string, z: number)
				P(m, base, Vector3.new(0.1, 0.1, 0.1), at(lx, y + 0.11, z), BLACK, nil, { name = name .. slot, transparency = 1, collide = false })
			end
			mark("OvenIn_", B / 2 - 1.3)
			mark("OvenMouthIn_", C / 2)
			mark("OvenMouthOut_", -C / 2)
			mark("OvenOut_", -B / 2 + 1.3)
			-- Slot numbers over the lane's mouth at both ends, matching: the exit's
			-- face the tender (-Z), the entrance's face the loader (+Z).
			local outTag = P(m, base, Vector3.new(0.6, 0.4, 0.05), at(lx, y + 0.92, -mouthFace - 0.025), Color3.new(1, 1, 1), nil, { collide = false })
			surfaceText(outTag, Enum.NormalId.Front, tostring(slot), Config.Brand.Red)
			local inTag = P(m, base, Vector3.new(0.6, 0.4, 0.05), at(lx, y + 0.92, mouthFace + 0.025), Color3.new(1, 1, 1), nil, { collide = false })
			surfaceText(inTag, Enum.NormalId.Back, tostring(slot), Config.Brand.Red)
		end
	end
end

-- Cut table, after the user's photos (2026-10-21): a stainless table on
-- casters behind the oven exits, the oven tender on its long side (-Z) facing
-- the carryout counter. Blender meshes when they load (tools/blender/cut_table.py:
-- the table, a stack of unfolded boxes per size, the rocker trough, the
-- clear counter (no seasoning insert: the user, 2026-10-21); sides, once on the menu, go in the Small
-- boxes), else a plain table and stacks. Parts either way: the top blank of
-- each stack (Blank_<Size>, a Model of PizzaBox panels, each with BoxSize: the
-- cut minigame cuts the pizza on it, then folds it into the box), the size
-- tags, and CutLanding, where a pulled pizza waits while someone works it.
local CARDBOARD = Color3.fromRGB(205, 168, 118)

Builders.CutTable = function(m, base)
	local L = StationArt.Layout.CutTable
	local h, w, d = L.height, L.width, L.depth
	local mesh = stationMeshes("CutTable")
	if mesh then
		M(m, base, mesh.Steel, CFrame.new(mesh.Steel.at), STAINLESS, Enum.Material.Metal, { collide = true, name = "Table" })
		M(m, base, mesh.Dark, CFrame.new(mesh.Dark.at), BLACK, Enum.Material.SmoothPlastic)
		M(m, base, mesh.Cardboard, CFrame.new(mesh.Cardboard.at), CARDBOARD, Enum.Material.Cardboard)
		M(m, base, mesh.Blanks, CFrame.new(mesh.Blanks.at), CARDBOARD, Enum.Material.Cardboard, { name = "BoxStacks" })
		for _, r in L.rockers do
			local cf = CFrame.new(r) * CFrame.Angles(0, math.rad(90), 0)
			M(m, base, mesh.Rocker, cf * CFrame.new(mesh.Rocker.at), STEEL, Enum.Material.Metal)
			M(m, base, mesh.RockerGrips, cf * CFrame.new(mesh.RockerGrips.at), BLACK, Enum.Material.SmoothPlastic)
		end
		-- The cut minigame's own rocker (the client clones it; pivot = the edge's lowest point).
		if not ReplicatedStorage:FindFirstChild("Rocker") then
			local rocker = Instance.new("Model")
			rocker.Name = "Rocker"
			for _, part in { M(rocker, CFrame.identity, mesh.Rocker, CFrame.new(mesh.Rocker.at), STEEL, Enum.Material.Metal), M(rocker, CFrame.identity, mesh.RockerGrips, CFrame.new(mesh.RockerGrips.at), BLACK, Enum.Material.SmoothPlastic) } do
				part.CanQuery = false
			end
			rocker.WorldPivot = CFrame.identity
			rocker.Parent = ReplicatedStorage
		end
	else
		steelTable(m, base, w, d, h)
		for size, t in L.trays do
			local kind = PizzaBox.pizza(Config.BoxSize[size])
			local bw, bd = PizzaBox.blankSize(kind)
			local below = t.Y - h - PizzaBox.Thick
			P(m, base, Vector3.new(bw, below, bd), at(t.X, h + below / 2, t.Z - PizzaBox.trayFromFront(kind) + bd / 2), CARDBOARD, Enum.Material.Cardboard, { collide = false })
		end
	end
	-- The top blank of each stack, lying flat on it; its size on the front edge below.
	for size, t in L.trays do
		local blank = Instance.new("Model")
		blank.Name = "Blank_" .. size
		local panels = PizzaBox.panels(PizzaBox.pizza(Config.BoxSize[size]))
		for i, cf in PizzaBox.pose(panels, base * CFrame.new(t), 0) do
			local panel = P(blank, CFrame.identity, PizzaBox.size(panels[i]), cf, CARDBOARD, Enum.Material.Cardboard, { collide = false, name = panels[i].name })
			panel:SetAttribute("BoxSize", size)
		end
		blank.Parent = m
		local tag = P(m, base, Vector3.new(0.5, 0.11, 0.02), at(t.X, h - 0.075, -d / 2 - 0.011), Color3.new(1, 1, 1), nil, { collide = false })
		surfaceText(tag, Enum.NormalId.Front, string.sub(size, 1, 1), Config.Brand.Red)
	end
	local lt = L.trays.Large
	P(m, base, Vector3.new(0.1, 0.1, 0.1), at(lt.X, lt.Y + 0.08, lt.Z), BLACK, nil, { name = "CutLanding", transparency = 1, collide = false })
end

-- The carryout rack (tools/blender/carryout_rack.py): a stainless table with
-- heated shelves over it, across the cut table's far end. Blender meshes when
-- they load, else plain parts. Either way the CarryoutSlot_<n> markers, where
-- ShopService stacks a waiting order's boxes (tier by tier, -X first). Nothing
-- in it takes clicks: ShopService puts its own hitbox over it.
Builders.CarryoutRack = function(m, base)
	local L = StationArt.Layout.CarryoutRack
	local top = L.tiers[#L.tiers] + 1.35 -- the heated canopy
	local mesh = stationMeshes("CarryoutRack")
	if mesh then
		M(m, base, mesh.Steel, CFrame.new(mesh.Steel.at), STAINLESS, Enum.Material.Metal, { collide = true, name = "Rack" })
		M(m, base, mesh.Dark, CFrame.new(mesh.Dark.at), BLACK, Enum.Material.SmoothPlastic)
	else
		P(m, base, Vector3.new(L.length, 0.1, L.depth), at(0, L.tiers[1] - 0.05, 0), STAINLESS, Enum.Material.Metal, { collide = true, name = "Rack" })
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				P(m, base, Vector3.new(0.12, L.tiers[1] - 0.1, 0.12), at(sx * (L.length / 2 - 0.12), (L.tiers[1] - 0.1) / 2, sz * (L.depth / 2 - 0.12)), STAINLESS, Enum.Material.Metal)
			end
			P(m, base, Vector3.new(0.05, top - L.tiers[1], L.depth - 0.1), at(sx * (L.length / 2 - 0.025), (L.tiers[1] + top) / 2, 0), STAINLESS, Enum.Material.Metal)
		end
		for i = 2, #L.tiers do
			P(m, base, Vector3.new(L.length - 0.1, 0.08, L.depth - 0.1), at(0, L.tiers[i] - 0.04, 0), STAINLESS, Enum.Material.Metal)
		end
		P(m, base, Vector3.new(L.length, 0.14, L.depth - 0.1), at(0, top + 0.07, 0), STAINLESS, Enum.Material.Metal)
	end
	local n = 0
	for _, y in L.tiers do
		for _, x in L.slotsX do
			n += 1
			P(m, base, Vector3.new(0.1, 0.1, 0.1), at(x, y, 0), BLACK, nil, { name = "CarryoutSlot_" .. n, transparency = 1, collide = false })
		end
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanQuery = false
		end
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

-- A pizza screen for a `size` pizza (its diameter plus the rim, so the skin
-- fits it exactly), centred at `cf` lying flat: the Blender screen with its wire
-- mesh texture once the sauce corner's meshes have loaded, else a plain disc.
local SCREEN_RIM = 0.06
function StationArt.Screen(size: string, cf: CFrame): BasePart
	local d = (Config.PizzaDiameter[size] or 2.4) + SCREEN_RIM
	local bank = MeshBank.SauceTable
	local mesh = bank and bank.meshes.Screen
	local part: BasePart
	if mesh and templates[mesh.id] then
		local p = (templates[mesh.id] :: MeshPart):Clone()
		p.Size = Vector3.new(d, mesh.size.Y, d)
		p.CFrame = cf * CFrame.new(mesh.at) * IMPORT_TURN
		p.TextureID = "rbxassetid://" .. bank.images.Screen
		p.Material = Enum.Material.Metal
		part = p
	else
		part = Instance.new("Part")
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(0.03, d, d)
		part.CFrame = cf * CFrame.Angles(0, 0, math.pi / 2)
		part.Color = SCREEN
		part.Material = Enum.Material.DiamondPlate
	end
	part.Name = "Screen"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

-- Builds art for `kind` under `parent`, preferring a custom model if one exists.
-- Paints the oven under `root` (a Config.OvenPaints name; an unknown one gets
-- the first, silver). The code-built oven has no paint: it stays stainless.
function StationArt.PaintOven(root: Instance, name: string)
	local part = root:FindFirstChild("OvenPaint", true)
	if not part or not part:IsA("BasePart") then
		return
	end
	local paint = Config.OvenPaints[1]
	for _, p in Config.OvenPaints do
		if p.name == name then
			paint = p
		end
	end
	part.Color = paint.color
	part.Material = if paint.metal then Enum.Material.Metal else Enum.Material.SmoothPlastic
	part.Reflectance = if paint.metal then 0 else 0.05
end

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
