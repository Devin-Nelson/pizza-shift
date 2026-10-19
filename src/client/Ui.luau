--!strict
-- The UI toolkit, in the "store systems" look (Style.luau): flat, squared,
-- brand charcoal / red / cream, Oswald labels and Roboto Mono numbers.
--
-- Everything builds on Ui.Root: a full-screen frame laid out at
-- Config.UiReference (1280x720) and scaled to the screen by one UIScale, with
-- flat components (text, box, edge, flatButton, iconButton, badge, chip,
-- caption, strip, rule, panel) and fixed text sizes from Style.Size.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Style = require(ReplicatedStorage.Shared.Style)
local Icons = require(ReplicatedStorage.Shared.Icons)

local Ui = {}

local C = Style.Color
Ui.Style = Style
Ui.Icons = Icons

function Ui.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	if inst:IsA("GuiObject") then
		(inst :: GuiObject).BorderSizePixel = 0
	end
	if props then
		for k, v in props do
			if k == "Parent" then
				continue
			end
			(inst :: any)[k] = v
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

---------------------------------------------------------------------------
-- Screen and root
---------------------------------------------------------------------------
local player = Players.LocalPlayer
local screen: ScreenGui = Ui.new("ScreenGui", {
	Name = "GameUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})
Ui.Screen = screen

local root: Frame = Ui.new("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = screen })
local rootScale: UIScale = Ui.new("UIScale", { Parent = root })
Ui.Root = root

-- One scale for everything on Root: the reference layout, fitted to the screen.
local function fitRoot()
	local view = screen.AbsoluteSize
	if view.X <= 0 or view.Y <= 0 then
		return
	end
	local ref = Config.UiReference
	local range = Config.UiScaleRange
	local s = math.clamp(math.min(view.X / ref.X, view.Y / ref.Y), range[1], range[2])
	rootScale.Scale = s
	root.Size = UDim2.fromScale(1 / s, 1 / s)
end
screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitRoot)
fitRoot()

---------------------------------------------------------------------------
-- Flat components (for Root)
---------------------------------------------------------------------------

-- A text label at a fixed size. `font` is a Style.Font face.
function Ui.text(text: string, font: Font, size: number, props: { [string]: any }?): TextLabel
	local base: { [string]: any } = {
		BackgroundTransparency = 1,
		FontFace = font,
		Text = text,
		TextSize = size,
		TextColor3 = C.Cream,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, size + 4),
	}
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	return Ui.new("TextLabel", base)
end

-- A flat panel.
function Ui.box(color: Color3?, props: { [string]: any }?, children: { Instance }?): Frame
	local base: { [string]: any } = { BackgroundColor3 = color or C.Panel }
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	return Ui.new("Frame", base, children)
end

-- A coloured edge bar on one side of `parent` (the brand accent).
function Ui.edge(parent: GuiObject, side: string, px: number, color: Color3?): Frame
	local props: { [string]: any } = { Name = "Edge", BackgroundColor3 = color or C.Red, ZIndex = parent.ZIndex + 1, Parent = parent }
	if side == "top" then
		props.Size = UDim2.new(1, 0, 0, px)
	elseif side == "bottom" then
		props.AnchorPoint = Vector2.new(0, 1)
		props.Position = UDim2.fromScale(0, 1)
		props.Size = UDim2.new(1, 0, 0, px)
	elseif side == "left" then
		props.Size = UDim2.new(0, px, 1, 0)
	else
		props.AnchorPoint = Vector2.new(1, 0)
		props.Position = UDim2.fromScale(1, 0)
		props.Size = UDim2.new(0, px, 1, 0)
	end
	return Ui.new("Frame", props)
end

local function lighten(c: Color3, k: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), k)
end

-- Hover: brighten a little; press: darken. Works for mouse; touch just taps.
local function hover(b: GuiButton, base: () -> Color3, transparentAtRest: boolean?)
	b.AutoButtonColor = false
	b.MouseEnter:Connect(function()
		b.BackgroundColor3 = lighten(base(), 0.08)
		if transparentAtRest then
			b.BackgroundTransparency = 0
		end
	end)
	b.MouseLeave:Connect(function()
		b.BackgroundColor3 = base()
		if transparentAtRest then
			b.BackgroundTransparency = 1
		end
	end)
end

-- Kinds: "primary" (red, the one main action), "dark" (tile), "ghost"
-- (outlined), "key" (a station key on a charcoal bar).
function Ui.flatButton(text: string, kind: string, props: { [string]: any }?): TextButton
	local bg = if kind == "primary" then C.Red elseif kind == "dark" then C.Tile elseif kind == "key" then C.Panel else C.Panel
	local base: { [string]: any } = {
		BackgroundColor3 = bg,
		BackgroundTransparency = if kind == "ghost" then 1 else 0,
		FontFace = Style.Font.LabelBold,
		Text = string.upper(text),
		TextSize = Style.Size.Label,
		TextColor3 = if kind == "primary" then C.White else C.Cream,
		Size = UDim2.fromOffset(110, 40),
	}
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	local b: TextButton = Ui.new("TextButton", base)
	b:SetAttribute("BaseColor", base.BackgroundColor3)
	if kind == "primary" then
		Ui.edge(b, "bottom", 3, C.RedDark)
	elseif kind == "ghost" then
		Ui.new("UIStroke", { Color = C.Line, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b })
	end
	hover(b, function()
		local c = b:GetAttribute("BaseColor")
		return if typeof(c) == "Color3" then c else bg
	end, kind == "ghost")
	return b
end

-- Changes a flat button's resting colour (e.g. the selected key).
function Ui.setButtonColor(b: GuiButton, color: Color3)
	b:SetAttribute("BaseColor", color)
	b.BackgroundColor3 = color
end

-- A square button holding one icon.
function Ui.iconButton(icon: string, size: number, props: { [string]: any }?, iconOpts: Icons.Opts?): TextButton
	local base: { [string]: any } = { Size = UDim2.fromOffset(size, size), Text = "" }
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	local b = Ui.flatButton("", "ghost", base)
	local ico = Icons.make(icon, math.floor(size * 0.46), b, iconOpts)
	ico.AnchorPoint = Vector2.new(0.5, 0.5)
	ico.Position = UDim2.fromScale(0.5, 0.5)
	return b
end

-- A small gold count (waiting jobs and the like).
function Ui.badge(text: string, props: { [string]: any }?): TextLabel
	local base: { [string]: any } = {
		BackgroundColor3 = C.Gold,
		FontFace = Style.Font.Mono,
		Text = text,
		TextSize = Style.Size.Small,
		TextColor3 = C.Ink,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(18, 18),
	}
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	local l: TextLabel = Ui.new("TextLabel", base)
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), Parent = l })
	return l
end

-- A label on a coloured block (sizes, grades, OPEN).
function Ui.chip(text: string, bg: Color3, fg: Color3?, props: { [string]: any }?): TextLabel
	local base: { [string]: any } = {
		BackgroundColor3 = bg,
		FontFace = Style.Font.LabelBold,
		Text = string.upper(text),
		TextSize = Style.Size.Small,
		TextColor3 = fg or C.White,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
	}
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	local l: TextLabel = Ui.new("TextLabel", base)
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = l })
	return l
end

-- Modal panel centred on screen (on Root, so it scales with the HUD), with a
-- red top bar, a heading and a close button. Returns (root, body, close).
function Ui.panel(title: string, width: number, height: number): (Frame, Frame, TextButton)
	local panel = Ui.new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = C.Panel,
		ZIndex = 5,
		Parent = root,
	})
	Ui.edge(panel, "top", 4, C.Red)
	-- Taller than the reference screen allows? Shrink it to fit.
	local ref = Config.UiReference
	local fit = math.min(1, (ref.Y - 60) / height, (ref.X - 40) / width)
	if fit < 1 then
		Ui.new("UIScale", { Scale = fit, Parent = panel })
	end
	Ui.text(string.upper(title), Style.Font.Heading, Style.Size.Title, { Position = UDim2.fromOffset(16, 14), Size = UDim2.new(1, -70, 0, 26), TextTruncate = Enum.TextTruncate.AtEnd, Parent = panel })
	local close = Ui.iconButton("close", 32, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 12), Parent = panel })
	local body = Ui.new("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(16, 56),
		Size = UDim2.new(1, -32, 1, -72),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	return panel, body, close
end

-- A small uppercase caption over a group of controls.
function Ui.caption(text: string, props: { [string]: any }?): TextLabel
	local base: { [string]: any } = { TextColor3 = C.CreamDim, Size = UDim2.new(1, 0, 0, 16) }
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	return Ui.text(string.upper(text), Style.Font.Label, Style.Size.Small, base)
end

-- The work strip: controls for the job at hand, docked bottom centre on Root
-- and only as wide as its controls. It's named "Dock" so the Stations bar
-- can step it aside. Returns (strip, row); put controls in `row`, a
-- horizontal list centred vertically.
Ui.STRIP_H = 68

-- Keeps `wrapper` exactly as wide as `inner` (an auto-sized row), in Root
-- units. Wrappers that carry full-width edge bars can't auto-size themselves:
-- the bar's width would feed back into the wrapper's.
function Ui.fitWidth(wrapper: GuiObject, inner: GuiObject)
	local function sync()
		local h = wrapper.Size.Y.Offset
		wrapper.Size = UDim2.fromOffset(math.ceil(inner.AbsoluteSize.X / rootScale.Scale), h)
	end
	inner:GetPropertyChangedSignal("AbsoluteSize"):Connect(sync)
	task.defer(sync)
end

function Ui.strip(): (Frame, Frame)
	local strip = Ui.box(C.Panel, {
		Name = "Dock",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.fromOffset(200, Ui.STRIP_H),
		Parent = root,
	})
	Ui.edge(strip, "top", 3, C.Red)
	local row = Ui.new("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 3),
		Size = UDim2.fromOffset(0, Ui.STRIP_H - 3),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = strip,
	}, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }),
	})
	Ui.fitWidth(strip, row)
	return strip, row
end

-- A thin vertical rule between groups of controls in a strip.
function Ui.rule(parent: Instance, order: number): Frame
	return Ui.box(C.Line, { Size = UDim2.fromOffset(1, 40), LayoutOrder = order, Parent = parent })
end

---------------------------------------------------------------------------
-- Toasts: slips that slide in under the clock (top right), clear of the work
---------------------------------------------------------------------------
local toastHolder = Ui.new("Frame", {
	Name = "Toasts",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 44),
	Size = UDim2.fromOffset(460, 320),
	BackgroundTransparency = 1,
	Parent = root,
}, {
	Ui.new("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
})
Ui.Toasts = toastHolder
local toastOrder = 0

local function fadeOut(frame: GuiObject, after: number)
	task.delay(after, function()
		if not frame.Parent then
			return
		end
		local info = TweenInfo.new(0.35)
		for _, d in frame:GetDescendants() do
			if d:IsA("TextLabel") then
				TweenService:Create(d, info, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
			elseif d:IsA("Frame") then
				TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
			end
		end
		TweenService:Create(frame, info, { BackgroundTransparency = 1 }):Play()
		task.wait(0.4)
		frame:Destroy()
	end)
end

local function keepFew()
	-- Keep at most 4 on screen: drop the oldest.
	local toasts = {}
	for _, c in toastHolder:GetChildren() do
		if c:IsA("Frame") then
			table.insert(toasts, c)
		end
	end
	if #toasts > 4 then
		table.sort(toasts, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		toasts[1]:Destroy()
	end
end

local function slip(): Frame
	toastOrder += 1
	local frame = Ui.new("Frame", {
		BackgroundColor3 = C.Cream,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 26),
		LayoutOrder = toastOrder,
		Parent = toastHolder,
	}, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	return frame
end

local function slipText(parent: Frame, text: string, font: Font, color: Color3, order: number): TextLabel
	local l = Ui.text(text, font, Style.Size.Body, {
		TextColor3 = color,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 26),
		TextWrapped = true,
		LayoutOrder = order,
		Parent = parent,
	})
	Ui.new("UISizeConstraint", { MaxSize = Vector2.new(420, 200), Parent = l })
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), Parent = l })
	return l
end

-- A plain message. `color` marks the slip's edge (gold by default).
function Ui.toast(text: string, color: Color3?)
	local frame = slip()
	Ui.new("Frame", { BackgroundColor3 = color or C.Gold, Size = UDim2.fromOffset(5, 26), LayoutOrder = 0, Parent = frame })
	slipText(frame, text, Style.Font.Label, C.Ink, 1)
	keepFew()
	fadeOut(frame, 3.5)
end

-- A pay slip: grade tag, what was done, coins and XP.
function Ui.payToast(grade: string, what: string, coins: number, xp: number, gradeColor: Color3?)
	local frame = slip()
	local tag = Ui.chip(grade, gradeColor or C.Green, C.White, { Size = UDim2.fromOffset(0, 26), LayoutOrder = 0, Parent = frame })
	tag.TextSize = Style.Size.Body
	slipText(frame, string.upper(what), Style.Font.Label, C.Ink, 1)
	local pay = Ui.new("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26), LayoutOrder = 2, Parent = frame }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }),
		Ui.new("UIPadding", { PaddingRight = UDim.new(0, 8) }),
	})
	Icons.make("coin", 12, pay).LayoutOrder = 1
	Ui.text(string.format("+%d", coins), Style.Font.Mono, Style.Size.Body, { TextColor3 = C.Ink, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26), LayoutOrder = 2, Parent = pay })
	Ui.text(string.format("+%d XP", xp), Style.Font.Mono, Style.Size.Body, { TextColor3 = C.Ink, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26), LayoutOrder = 3, Parent = pay })
	keepFew()
	fadeOut(frame, 3.5)
end

return Ui
