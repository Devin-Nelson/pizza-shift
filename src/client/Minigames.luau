--!strict
-- Station minigame UIs. Each reports raw inputs; the server scores them.
-- The Register is a 2D panel here (it shows over the
-- first-person view of the counter while you're stationed there); the pizza
-- stations (Dough, Make-Line, Cut & Box) are in-world 3D minigames in Minigames3D.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Style = require(ReplicatedStorage.Shared.Style)
local Ui = require(script.Parent.Ui)
local Minigames3D = require(script.Parent.Minigames3D)

local C = Style.Color
local F = Style.Font
local S = Style.Size

local Minigames = {}

type Finish = (payload: any) -> ()
type Cancel = () -> ()

local active: { root: Frame, cleanup: { () -> () } }? = nil

function Minigames.Close()
	Minigames3D.Close()
	if not active then
		return
	end
	local a = active
	active = nil
	for _, fn in a.cleanup do
		pcall(fn)
	end
	a.root:Destroy()
end

function Minigames.IsOpen(): boolean
	return active ~= nil or Minigames3D.IsOpen()
end

local function open(title: string, w: number, h: number, cancel: Cancel): (Frame, Frame, { () -> () })
	Minigames.Close()
	local root, body, close = Ui.panel(title, w, h)
	local cleanup = {}
	active = { root = root, cleanup = cleanup }
	close.Activated:Connect(function()
		Minigames.Close()
		cancel()
	end)
	return root, body, cleanup
end

-- Marks the chosen key of a group (red) and resets the others.
local function selectGroup(buttons: { [string]: TextButton }, chosen: string)
	for key, b in buttons do
		Ui.setButtonColor(b, if key == chosen then C.Red else C.Tile)
	end
end

-- A row of equal keys across `parent` at `y`.
local function keyRow(parent: Instance, y: number, height: number, width: UDim, labels: { string }, onPick: (string) -> ()): { [string]: TextButton }
	local row = Ui.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, y), Size = UDim2.new(width.Scale, width.Offset, 0, height), Parent = parent }, {
		Ui.new("UIGridLayout", { CellSize = UDim2.new(1 / #labels, -6, 1, 0), CellPadding = UDim2.fromOffset(6, 0), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local buttons = {}
	for i, label in labels do
		local b = Ui.flatButton(label, "dark", { LayoutOrder = i, Parent = row })
		buttons[label] = b
		b.Activated:Connect(function()
			onPick(label)
		end)
	end
	return buttons
end

---------------------------------------------------------------------------
-- Register: listen to the customer, ring in every pizza (orders can be big).
-- Laid out like the store's POS touchscreen.
---------------------------------------------------------------------------
local function register(data: any, finish: Finish, cancel: Cancel)
	local phone = data.phone == true
	local _, body = open(if phone then "Phone order" else "Register", 640, if phone then 574 else 468, cancel)

	-- What they said, on a slip.
	local speech = Ui.box(C.Cream, { Size = UDim2.new(1, 0, 0, 56), Parent = body })
	local who = Ui.chip(if phone then "Caller" else "Customer", C.Panel, C.Cream, { Position = UDim2.fromOffset(10, 8), Parent = speech })
	who.TextSize = S.Small
	Ui.text('"' .. tostring(data.line) .. '"', F.Body, S.Label, {
		TextColor3 = C.Ink,
		TextWrapped = true,
		Position = UDim2.fromOffset(10, 28),
		Size = UDim2.new(1, -20, 0, 24),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = speech,
	})

	local chosen: { size: string?, house: number? } = {}
	local toppings: { [string]: boolean } = {} -- the toppings keys that are on
	local cart: { { size: string, toppings: { string } } } = {}

	-- Toppings toggle on and off, up to Config.MaxToppings (none = a cheese pizza).
	Ui.caption(string.format("Toppings  -  up to %d, none for cheese", Config.MaxToppings), { Position = UDim2.fromOffset(0, 66), Parent = body })
	local toppingButtons: { [string]: TextButton } = {}
	local function showToppings()
		for name, b in toppingButtons do
			Ui.setButtonColor(b, if toppings[name] then C.Red else C.Tile)
		end
	end
	toppingButtons = keyRow(body, 84, 44, UDim.new(1, 6), Config.Toppings, function(name)
		local on = 0
		for _ in toppings do
			on += 1
		end
		if toppings[name] then
			toppings[name] = nil
		elseif on < Config.MaxToppings then
			toppings[name] = true
		end
		showToppings()
	end)
	local function picked(): { string }
		local list = {}
		for _, t in Config.Toppings do
			if toppings[t] then
				table.insert(list, t)
			end
		end
		return list
	end
	local function key(it: { size: string, toppings: { string } }): string
		return it.size .. " " .. (if #it.toppings > 0 then table.concat(it.toppings, " & ") else "cheese")
	end

	Ui.caption("Size", { Position = UDim2.fromOffset(0, 138), Parent = body })
	local sizeButtons: { [string]: TextButton } = {}
	sizeButtons = keyRow(body, 156, 44, UDim.new(0.62, 6), Config.Sizes, function(size)
		chosen.size = size
		selectGroup(sizeButtons, size)
	end)
	local add1 = Ui.flatButton("+1", "dark", { Position = UDim2.new(0.64, 0, 0, 156), Size = UDim2.new(0.17, 0, 0, 44), BackgroundColor3 = C.Gold, TextColor3 = C.Ink, TextSize = S.Big, Parent = body })
	local add5 = Ui.flatButton("+5", "dark", { Position = UDim2.new(0.83, 0, 0, 156), Size = UDim2.new(0.17, 0, 0, 44), BackgroundColor3 = C.Gold, TextColor3 = C.Ink, TextSize = S.Big, Parent = body })

	Ui.caption("Order  -  tap a line to take one off", { Position = UDim2.fromOffset(0, 210), Parent = body })
	local list = Ui.new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 228),
		Size = UDim2.new(1, 0, 0, 110),
		BackgroundColor3 = C.Cream,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = C.Line,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = body,
	}, { Ui.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }) })

	local function renderCart()
		for _, c in list:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local order, counts = {}, {}
		for _, it in cart do
			local k = key(it)
			if not counts[k] then
				counts[k] = 0
				table.insert(order, { key = k, item = it })
			end
			counts[k] += 1
		end
		if #order == 0 then
			Ui.text("Nothing rung in yet.", F.Body, S.Body, { TextColor3 = Color3.fromRGB(139, 132, 120), Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 0, 30), Parent = list })
		end
		for i, entry in order do
			local row = Ui.new("TextButton", { BackgroundColor3 = C.Cream, AutoButtonColor = true, Text = "", Size = UDim2.new(1, 0, 0, 28), LayoutOrder = i, Parent = list })
			Ui.box(C.Rule, { Size = UDim2.new(1, 0, 0, 1), Parent = row })
			Ui.text(string.format("%d  x  %s", counts[entry.key], string.upper(entry.key)), F.Label, S.Label, { TextColor3 = C.Ink, Position = UDim2.fromOffset(10, 1), Size = UDim2.new(1, -40, 1, -1), Parent = row })
			local x = Ui.Icons.make("close", 10, row, { color = C.Ink })
			x.AnchorPoint = Vector2.new(1, 0.5)
			x.Position = UDim2.new(1, -12, 0.5, 0)
			row.Activated:Connect(function()
				for j = #cart, 1, -1 do
					if key(cart[j]) == entry.key then
						table.remove(cart, j)
						break
					end
				end
				renderCart()
			end)
		end
	end
	local function add(n: number)
		if not chosen.size then
			return
		end
		for _ = 1, n do
			if #cart < 40 then
				table.insert(cart, { size = chosen.size :: string, toppings = picked() })
			end
		end
		renderCart()
	end
	add1.Activated:Connect(function()
		add(1)
	end)
	add5.Activated:Connect(function()
		add(5)
	end)
	renderCart()

	if phone then
		Ui.caption("Deliver to house #", { Position = UDim2.fromOffset(0, 348), Parent = body })
		local grid = Ui.new("Frame", { Position = UDim2.fromOffset(0, 366), Size = UDim2.new(1, 0, 0, 78), BackgroundTransparency = 1, Parent = body }, {
			Ui.new("UIGridLayout", { CellSize = UDim2.new(1 / 8, -6, 0, 36), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		local houseButtons: { [string]: TextButton } = {}
		for i = 1, (tonumber(data.houses) or 16) do
			local b = Ui.flatButton(tostring(i), "dark", { LayoutOrder = i, Parent = grid })
			b.FontFace = F.Mono
			houseButtons[tostring(i)] = b
			b.Activated:Connect(function()
				chosen.house = i
				selectGroup(houseButtons, tostring(i))
			end)
		end
	end

	local submit = Ui.flatButton("Send to kitchen", "primary", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 48), TextSize = S.Big, Parent = body })
	submit.Activated:Connect(function()
		if #cart == 0 or (phone and not chosen.house) then
			submit.Text = if #cart == 0 then "RING IN AT LEAST ONE PIZZA" else "PICK THE HOUSE NUMBER"
			task.delay(1.2, function()
				submit.Text = "SEND TO KITCHEN"
			end)
			return
		end
		Minigames.Close()
		finish({ items = cart, house = chosen.house })
	end)
end

local HANDLERS: { [string]: (any, Finish, Cancel) -> () } = {
	Register = register,
}

function Minigames.Start(kind: string, data: any, finish: Finish, cancel: Cancel)
	Minigames.Close()
	if Minigames3D.Handles(kind) then
		Minigames3D.Start(kind, data, finish, cancel)
		return
	end
	local handler = HANDLERS[kind]
	if handler then
		handler(data or {}, finish, cancel)
	end
end

return Minigames
