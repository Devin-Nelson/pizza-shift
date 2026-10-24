--!strict
-- Pizza box blanks (the user's reference, 2026-10-24: a die-cut sheet measured
-- on a 400 px base; tools/blender/pizzabox.py mirrors this, keep the two in
-- step). The base's front corners are cut off on a diagonal (43 across, 103
-- back), the side walls stand beside the rest; a full-width back wall with a
-- tab at each end; a front wall between the cuts; the lid on the back wall,
-- its front corners creased on the same diagonal (each corner tucks under the
-- lid, leaving the lid's corner cut like the base's); the lid's side flaps,
-- each with a front piece on a crease that swings in along the cut corner,
-- its end tucking behind the front; a tuck along the lid's front with an ear
-- tab at each end. Everything scales with the box (the wall is 61 / 400 of
-- the width, as on the reference). Brown kraft inside, the printed white
-- board outside (Config.BoxPrint).
-- The server lays each stack's top blank flat (StationArt), the cut
-- minigame folds its own copy, and ShopService builds shut boxes for the
-- carryout rack from the same panels.
--
-- Frames: the root is the base's top surface (the board's inside face) at
-- its centre, -Z the box's front, Y up. Each panel hangs off a hinge (its
-- frame's X axis) and lies along its frame's +Z; folding turns +Z toward +Y
-- (the inside). Panels are rectangles (`rect` x0, x1, z0, z1) or right
-- triangles (`tri`: the right-angle corner, then the other two), in their
-- own frame.

local PizzaBox = {}

PizzaBox.WallShare = 61 / 400 -- the wall's height as a share of the box's width
PizzaBox.Thick = 0.025 -- the board
PizzaBox.Time = 1.6 -- seconds for the whole fold

local CUT_W, CUT_D = 43 / 400, 103 / 400 -- the front corner cut, as shares of the width / depth
local UPPER_PAST = 41 / 61 -- the corner piece runs past the lid's front by this much of a wall
local CUT_ANGLE = math.deg(math.atan2(CUT_W, CUT_D)) -- the cut corner's angle off the side

export type Kind = { w: number, d: number, h: number }

export type Panel = {
	name: string,
	parent: number?, -- index into the list (nil: the base)
	hinge: CFrame, -- in the parent's frame
	fold: number, -- degrees when the box is shut
	from: number, -- seconds into the fold when it starts turning
	to: number, -- and when it's done
	rect: { number }?,
	tri: { Vector2 }?,
	print: string?, -- Config.BoxPrint image on its outside ("LidMain" | "LidFront" | "Band")
	hidden: boolean?, -- inside a shut box (left out of shut boxes)
}

local T = PizzaBox.Thick

-- A pizza box `bs` across (Config.BoxSize).
function PizzaBox.pizza(bs: number): Kind
	return { w = bs, d = bs, h = PizzaBox.WallShare * bs }
end

local function yaw(deg: number): CFrame
	return CFrame.Angles(0, math.rad(deg), 0)
end

-- A hinge along p0 -> p1 (x, z points in the parent's frame), its +Z toward
-- `side`, and a function taking parent points into it.
local function line(p0: Vector2, p1: Vector2, side: Vector2): (CFrame, (Vector2) -> Vector2)
	local dir = (p1 - p0).Unit
	local normal = Vector2.new(-dir.Y, dir.X) -- X x Y
	if (side - p0):Dot(normal) < 0 then
		return line(p1, p0, side)
	end
	local cf = CFrame.fromMatrix(Vector3.new(p0.X, 0, p0.Y), Vector3.new(dir.X, 0, dir.Y), Vector3.yAxis)
	return cf, function(q: Vector2): Vector2
		local r = q - p0
		return Vector2.new(r:Dot(dir), r:Dot(normal))
	end
end

function PizzaBox.panels(k: Kind): { Panel }
	local w, d, h = k.w, k.d, k.h
	local cw, cd = CUT_W * w, CUT_D * d
	local list: { Panel } = {}
	local function add(p: { [string]: any }): number
		p.hinge = p.hinge or CFrame.identity
		p.fold = p.fold or 0
		p.from = p.from or 0
		p.to = p.to or 0
		table.insert(list, p :: any)
		return #list
	end
	local base = add({ name = "Base", rect = { -w / 2, w / 2, -d / 2 + cd, d / 2 } })
	add({ name = "BaseFront", parent = base, rect = { -w / 2 + cw, w / 2 - cw, -d / 2, -d / 2 + cd } })
	for _, s in { 1, -1 } do
		add({ name = "BaseCorner", parent = base, tri = { Vector2.new(s * (w / 2 - cw), -d / 2 + cd), Vector2.new(s * w / 2, -d / 2 + cd), Vector2.new(s * (w / 2 - cw), -d / 2) } })
		-- Side walls beside the uncut part only (panel x = -s * the base's z).
		local x0, x1 = if s == 1 then -d / 2 else -d / 2 + cd, if s == 1 then d / 2 - cd else d / 2
		add({ name = "Side", parent = base, hinge = CFrame.new(s * w / 2, 0, 0) * yaw(s * 90), fold = 90, from = 0, to = 0.3, rect = { x0, x1, 0, h } })
	end
	add({ name = "Front", parent = base, hinge = CFrame.new(0, 0, -d / 2) * yaw(180), fold = 90, from = 0.2, to = 0.5, rect = { -(w / 2 - cw), w / 2 - cw, 0, h } })
	local back = add({ name = "Back", parent = base, hinge = CFrame.new(0, 0, d / 2), fold = 90, from = 0.2, to = 0.5, rect = { -w / 2, w / 2, 0, h } })
	for _, s in { 1, -1 } do
		-- End tabs: they fold in against the side walls (panel x = -s * the wall's z).
		local x0, x1 = if s == 1 then -(h - 0.02) else 0.02, if s == 1 then -0.02 else h - 0.02
		add({ name = "BackTab", parent = back, hinge = CFrame.new(s * (w / 2 - T), 0, 0) * yaw(s * 90), fold = 90, from = 0.45, to = 0.65, rect = { x0, x1, 0, 0.95 * h }, hidden = true })
	end
	local lid = add({ name = "Lid", parent = back, hinge = CFrame.new(0, 0, h), fold = 90, from = 0.85, to = 1.35, rect = { -w / 2 - T, w / 2 + T, 0, d - cd }, print = "LidMain" })
	add({ name = "LidFront", parent = lid, rect = { -(w / 2 - cw), w / 2 - cw, d - cd, d }, print = "LidFront" })
	local tuck = add({ name = "Tuck", parent = lid, hinge = CFrame.new(0, 0, d - 2 * T), fold = 90, from = 1.15, to = 1.5, rect = { -(w / 2 - cw), w / 2 - cw, 0, h }, hidden = true })
	for _, s in { 1, -1 } do
		-- The lid's side flap behind the crease (panel x = -s * the lid's z).
		local x0, x1 = if s == 1 then -(d - cd) else 0, if s == 1 then 0 else d - cd
		local side = add({ name = "LidSide", parent = lid, hinge = CFrame.new(s * (w / 2 + T), 0, 0) * yaw(s * 90), fold = 90, from = 0.95, to = 1.25, rect = { x0, x1, 0, h }, print = "Band" })
		-- Its front piece, on the crease across the flap's front end: with the
		-- flap down it swings in along the cut corner, and its end (past the
		-- cut corner) tucks in behind the front wall.
		local fx = -s * (d - cd)
		local hinge2, into2 = line(Vector2.new(fx, 0), Vector2.new(fx, h), Vector2.new(fx - s, 0))
		local ea, eb = into2(Vector2.new(fx, 0)).X, into2(Vector2.new(fx, h)).X
		local ex0, ex1 = math.min(ea, eb), math.max(ea, eb)
		local cut = math.sqrt(cw * cw + cd * cd)
		local flap = add({ name = "CornerFlap", parent = side, hinge = hinge2, fold = CUT_ANGLE, from = 1.15, to = 1.4, rect = { ex0, ex1, 0, cut } })
		add({ name = "CornerTip", parent = flap, hinge = CFrame.new(0, 0, cut), fold = 100 - CUT_ANGLE, from = 1.25, to = 1.45, rect = { ex0, ex1, 0, cd + UPPER_PAST * h - cut }, hidden = true })
		-- The lid's front corner, creased on the diagonal: it tucks under the lid.
		local p0, p1, apex = Vector2.new(s * (w / 2 - cw), d), Vector2.new(s * w / 2, d - cd), Vector2.new(s * w / 2, d)
		local hinge, into = line(p0, p1, apex)
		add({ name = "LidCorner", parent = lid, hinge = hinge, fold = 180, from = 1.0, to = 1.3, tri = { into(apex), into(p0), into(p1) }, hidden = true })
		-- The lid inside the crease stays: its corner ends up cut like the base's.
		add({ name = "LidInner", parent = lid, tri = { Vector2.new(s * (w / 2 - cw), d - cd), Vector2.new(s * w / 2, d - cd), Vector2.new(s * (w / 2 - cw), d) } })
		-- Ear tabs on the tuck's ends (panel x = -s * the tuck's z).
		local ex, ey = if s == 1 then -h else 0, if s == 1 then 0 else h
		add({ name = "Ear", parent = tuck, hinge = CFrame.new(s * (w / 2 - cw), 0, 0) * yaw(s * 90), fold = 90, from = 1.25, to = 1.5, rect = { ex, ey, 0, 0.9 * cw }, hidden = true })
	end
	return list
end

-- The flat blank's width and depth: base and lid plus the walls round them.
function PizzaBox.blankSize(k: Kind): (number, number)
	return k.w + 2 * k.h, 2 * k.d + 3 * k.h
end

-- How far the base's centre sits behind the blank's front edge (the front wall's).
function PizzaBox.trayFromFront(k: Kind): number
	return k.d / 2 + k.h
end

-- A shut box's height (the lid's outside).
function PizzaBox.height(k: Kind): number
	return k.h + T
end

local function ease(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Each panel's hinge frame at `t` seconds into the fold (0 = flat), for a
-- box whose root is `root`.
function PizzaBox.frames(panels: { Panel }, root: CFrame, t: number): { CFrame }
	local out: { CFrame } = {}
	for i, p in panels do
		local parent = p.parent
		if not parent then
			out[i] = root
		else
			local angle = p.fold * ease((t - p.from) / math.max(p.to - p.from, 1e-3))
			out[i] = out[parent] * p.hinge * CFrame.Angles(math.rad(-angle), 0, 0)
		end
	end
	return out
end

export type Piece = { size: Vector3, offset: CFrame, wedge: boolean, face: Enum.NormalId }

-- A slab of a panel's board from y0 down `thick` (in its frame): its part's
-- size and placement, and which face is on the outside.
function PizzaBox.slab(p: Panel, y0: number, thick: number): Piece
	local r = p.rect
	if r then
		return { size = Vector3.new(r[2] - r[1], thick, r[4] - r[3]), offset = CFrame.new((r[1] + r[2]) / 2, y0 - thick / 2, (r[3] + r[4]) / 2), wedge = false, face = Enum.NormalId.Bottom }
	end
	-- A WedgePart: its right angle at its bottom back, so +Y runs along one leg and -Z along the other.
	local t = p.tri :: { Vector2 }
	local corner, a, b = t[1], t[2], t[3]
	local u, v = a - corner, b - corner
	local yw = Vector3.new(u.X, 0, u.Y).Unit
	local zw = -Vector3.new(v.X, 0, v.Y).Unit
	local xw = yw:Cross(zw)
	local c = corner + u / 2 + v / 2
	return { size = Vector3.new(thick, u.Magnitude, v.Magnitude), offset = CFrame.fromMatrix(Vector3.new(c.X, y0 - thick / 2, c.Y), xw, yw), wedge = true, face = if xw.Y < 0 then Enum.NormalId.Right else Enum.NormalId.Left }
end

export type Built = { part: BasePart, panel: number, offset: CFrame }

-- Parts for a box under `parent`: each panel a kraft inside layer and a white
-- outside layer carrying its print (`prints`: image ids by Panel.print).
-- `shut`: just the outside layer of what shows on a shut box.
function PizzaBox.build(panels: { Panel }, parent: Instance, kraft: Color3, board: Color3, prints: { [string]: number }, shut: boolean?): { Built }
	local out: { Built } = {}
	for i, p in panels do
		if shut and p.hidden then
			continue
		end
		for _, layer in (if shut then { "out" } else { "in", "out" }) do
			local outside = layer == "out"
			local piece = PizzaBox.slab(p, if outside and not shut then -T / 2 else 0, if shut then T else T / 2)
			local part: BasePart = if piece.wedge then Instance.new("WedgePart") else Instance.new("Part")
			part.Name = p.name
			part.Size = piece.size
			part.Color = if outside then board else kraft
			part.Material = Enum.Material.SmoothPlastic
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CastShadow = false
			local image = if outside and p.print then prints[p.print] else nil
			if image and not piece.wedge then
				-- Laid on the outside face, turned to read from the box's front when shut.
				local gui = Instance.new("SurfaceGui")
				gui.Face = piece.face
				gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
				gui.PixelsPerStud = 100
				local label = Instance.new("ImageLabel")
				label.AnchorPoint = Vector2.new(0.5, 0.5)
				label.Position = UDim2.fromScale(0.5, 0.5)
				label.Size = UDim2.fromOffset(piece.size.Z * 100, piece.size.X * 100)
				label.Rotation = 90
				label.BackgroundTransparency = 1
				label.ScaleType = Enum.ScaleType.Stretch
				label.Image = "rbxassetid://" .. image
				label.Parent = gui
				gui.Parent = part
			end
			part.Parent = parent
			table.insert(out, { part = part, panel = i, offset = piece.offset })
		end
	end
	return out
end

-- Puts a built box's parts where its panels are at `t` seconds into the fold.
function PizzaBox.place(built: { Built }, panels: { Panel }, root: CFrame, t: number)
	local frames = PizzaBox.frames(panels, root, t)
	for _, b in built do
		b.part.CFrame = frames[b.panel] * b.offset
	end
end

return PizzaBox
