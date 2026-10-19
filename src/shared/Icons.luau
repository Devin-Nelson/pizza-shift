--!strict
-- Flat icons drawn from GUI frames (no uploaded images), for the HUD and the
-- in-world screens. Every shape is placed in scale units inside a square
-- holder, so an icon draws the same at any size.
--
--   Icons.make("sauce", 18, parent)        -- an 18 px sauce icon
--   Icons.make("chevron", 12, parent, { color = Style.Color.CreamDim, dir = "right" })

local Style = require(script.Parent.Style)

local Icons = {}

local C = Style.Color

export type Opts = { color: Color3?, dir: string?, text: string?, [string]: any }

local function shape(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, round: number?, rotation: number?): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(x + w / 2, y + h / 2)
	f.Size = UDim2.fromScale(w, h)
	f.BackgroundColor3 = color
	f.Rotation = rotation or 0
	if round then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(round, 0)
		c.Parent = f
	end
	f.Parent = parent
	return f
end

-- A ring: transparent centre, coloured stroke `thickness` px wide (`round`
-- 0.5 = circle, 0 = square outline).
local function ring(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, thickness: number, round: number?): Frame
	local f = shape(parent, x, y, w, h, color, round or 0.5)
	f.BackgroundTransparency = 1
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = f
	return f
end

-- A thin bar from (x1, y1) to (x2, y2) in scale units, `width` scale thick
-- (relative to the icon's width).
local function bar(parent: Instance, x1: number, y1: number, x2: number, y2: number, width: number, color: Color3): Frame
	local dx, dy = x2 - x1, y2 - y1
	local len = math.sqrt(dx * dx + dy * dy)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale((x1 + x2) / 2, (y1 + y2) / 2)
	f.Size = UDim2.fromScale(len, width)
	f.Rotation = math.deg(math.atan2(dy, dx))
	f.BackgroundColor3 = color
	f.Parent = parent
	return f
end

local DRAW: { [string]: (holder: Frame, size: number, o: Opts) -> () } = {}

DRAW.register = function(h, _, o)
	shape(h, 0.05, 0.12, 0.9, 0.76, o.color or C.Cream, 0.12)
	shape(h, 0.18, 0.24, 0.64, 0.26, C.Panel)
end
DRAW.dough = function(h)
	shape(h, 0.06, 0.06, 0.88, 0.88, Color3.fromRGB(234, 220, 184), 0.5)
	shape(h, 0.36, 0.3, 0.12, 0.12, Color3.fromRGB(205, 180, 120), 0.5)
	shape(h, 0.56, 0.5, 0.1, 0.1, Color3.fromRGB(205, 180, 120), 0.5)
end
DRAW.sauce = function(h)
	shape(h, 0.04, 0.04, 0.92, 0.92, C.Cream, 0.5)
	shape(h, 0.2, 0.2, 0.6, 0.6, Color3.fromRGB(200, 50, 42), 0.5)
end
DRAW.cheese = function(h)
	shape(h, 0.04, 0.04, 0.92, 0.92, Color3.fromRGB(243, 211, 107), 0.5)
	for _, p in { { 0.28, 0.3 }, { 0.56, 0.38 }, { 0.36, 0.6 } } do
		shape(h, p[1], p[2], 0.16, 0.16, Color3.fromRGB(255, 243, 196), 0.5)
	end
end
DRAW.toppings = function(h)
	shape(h, 0.04, 0.04, 0.92, 0.92, Color3.fromRGB(243, 211, 107), 0.5)
	for _, p in { { 0.2, 0.24 }, { 0.54, 0.3 }, { 0.34, 0.56 } } do
		shape(h, p[1], p[2], 0.26, 0.26, Color3.fromRGB(181, 40, 31), 0.5)
	end
end
DRAW.oven = function(h)
	shape(h, 0.04, 0.1, 0.92, 0.8, Color3.fromRGB(185, 190, 199))
	shape(h, 0.16, 0.42, 0.68, 0.2, C.Ink)
end
DRAW.box = function(h)
	shape(h, 0.04, 0.1, 0.92, 0.8, Color3.fromRGB(217, 185, 138))
	shape(h, 0.04, 0.36, 0.92, 0.1, Color3.fromRGB(168, 134, 90))
end
DRAW.rack = function(h, _, o)
	local col = o.color or Color3.fromRGB(185, 190, 199)
	ring(h, 0.1, 0.06, 0.8, 0.88, col, 2, 0)
	shape(h, 0.22, 0.34, 0.56, 0.1, col)
	shape(h, 0.22, 0.58, 0.56, 0.1, col)
end
DRAW.truck = function(h, _, o)
	shape(h, 0, 0.18, 0.64, 0.52, o.color or C.Cream)
	shape(h, 0.66, 0.36, 0.34, 0.34, C.CreamDim)
	shape(h, 0.1, 0.68, 0.22, 0.22, C.Ink, 0.5)
	shape(h, 0.66, 0.68, 0.22, 0.22, C.Ink, 0.5)
end
DRAW.aid = function(h, _, o)
	shape(h, 0.14, 0.04, 0.72, 0.92, o.color or C.CreamDim)
	for i = 0, 2 do
		shape(h, 0.26, 0.24 + i * 0.2, 0.48, 0.08, C.Panel)
	end
end
DRAW.help = function(h, size, o)
	local col = o.color or C.CreamDim
	ring(h, 0.06, 0.06, 0.88, 0.88, col, math.max(1, math.floor(size / 10)))
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.FontFace = Style.Font.Heading
	t.Text = "?"
	t.TextColor3 = col
	t.TextSize = math.floor(size * 0.66)
	t.Parent = h
end
DRAW.close = function(h, size, o)
	local col = o.color or C.Cream
	local w = math.max(2, size * 0.14) / size
	bar(h, 0.12, 0.12, 0.88, 0.88, w, col)
	bar(h, 0.12, 0.88, 0.88, 0.12, w, col)
end
DRAW.chevron = function(h, size, o)
	local col = o.color or C.CreamDim
	local w = math.max(2, size * 0.16) / size
	local dir = o.dir or "right"
	local pts = {
		right = { 0.3, 0.12, 0.72, 0.5, 0.3, 0.88 },
		left = { 0.7, 0.12, 0.28, 0.5, 0.7, 0.88 },
		up = { 0.12, 0.7, 0.5, 0.28, 0.88, 0.7 },
		down = { 0.12, 0.3, 0.5, 0.72, 0.88, 0.3 },
	}
	local p = pts[dir] or pts.right
	bar(h, p[1], p[2], p[3], p[4], w, col)
	bar(h, p[3], p[4], p[5], p[6], w, col)
end
DRAW.grid = function(h, _, o)
	local col = o.color or C.Cream
	for _, p in { { 0, 0 }, { 0.56, 0 }, { 0, 0.56 }, { 0.56, 0.56 } } do
		shape(h, p[1], p[2], 0.44, 0.44, col)
	end
end
DRAW.check = function(h, size, o)
	local col = o.color or C.White
	local w = math.max(2, size * 0.16) / size
	bar(h, 0.14, 0.52, 0.4, 0.76, w, col)
	bar(h, 0.38, 0.76, 0.88, 0.24, w, col)
end
DRAW.exit = function(h, size, o)
	DRAW.close(h, size, o)
end
DRAW.coin = function(h, size)
	local f = shape(h, 0.04, 0.04, 0.92, 0.92, C.Gold, 0.5)
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(224, 160, 36)
	s.Thickness = math.max(1, math.floor(size / 7))
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = f
end
-- Toppings (what the bins hold)
DRAW.Pepperoni = function(h, size)
	local f = shape(h, 0.08, 0.08, 0.84, 0.84, Color3.fromRGB(181, 40, 31), 0.5)
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(143, 29, 23)
	s.Thickness = math.max(1, math.floor(size / 8))
	s.Parent = f
end
DRAW.Ham = function(h)
	shape(h, 0.14, 0.14, 0.72, 0.72, Color3.fromRGB(233, 160, 168), nil, 8)
end
DRAW.Pineapple = function(h)
	shape(h, 0.2, 0.2, 0.6, 0.6, Color3.fromRGB(244, 210, 76), nil, 45)
end
DRAW.Peppers = function(h, size)
	ring(h, 0.12, 0.12, 0.76, 0.76, Color3.fromRGB(60, 154, 63), math.max(2, math.floor(size / 5)))
end
DRAW.Mushrooms = function(h)
	shape(h, 0.38, 0.4, 0.24, 0.44, Color3.fromRGB(231, 214, 186))
	shape(h, 0.08, 0.12, 0.84, 0.5, Color3.fromRGB(201, 173, 134), 0.5)
end
DRAW.Olives = function(h, size)
	ring(h, 0.14, 0.14, 0.72, 0.72, Color3.fromRGB(42, 42, 42), math.max(2, math.floor(size / 4.5)))
end

function Icons.has(name: string): boolean
	return DRAW[name] ~= nil
end

-- A square holder `size` px across with the icon drawn in it.
function Icons.make(name: string, size: number, parent: Instance?, opts: Opts?): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Icon_" .. name
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = UDim2.fromOffset(size, size)
	local draw = DRAW[name]
	if draw then
		draw(holder, size, opts or {})
	end
	if parent then
		holder.Parent = parent
	end
	return holder
end

return Icons
