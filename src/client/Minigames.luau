--!strict
-- Station minigame UIs. Each reports raw inputs; the server scores them.
-- Register and Supply are 2D panels here (the register's shows over the
-- first-person view of the counter while you're stationed there); the pizza
-- stations (Dough, Make-Line, Cut & Box) are in-world 3D minigames in Minigames3D.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Ui = require(script.Parent.Ui)
local Minigames3D = require(script.Parent.Minigames3D)
local T = Ui.Theme

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

local function selectGroup(buttons: { [string]: TextButton }, chosen: string)
	for key, b in buttons do
		b.BackgroundColor3 = if key == chosen then T.Good else T.Card
	end
end

---------------------------------------------------------------------------
-- Register: listen to the customer, ring in every pizza (orders can be big).
---------------------------------------------------------------------------
local function register(data: any, finish: Finish, cancel: Cancel)
	local phone = data.phone == true
	local _, body = open(if phone then "Phone Order" else "Register", 640, if phone then 720 else 540, cancel)

	local speech = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 70), BackgroundColor3 = Color3.new(1, 1, 1), Parent = body }, { Ui.corner(12), Ui.pad(8) })
	Ui.label((if phone then "Caller: " else "Customer: ") .. '"' .. tostring(data.line) .. '"', {
		Size = UDim2.fromScale(1, 1),
		TextColor3 = Color3.fromRGB(30, 30, 30),
		TextWrapped = true,
		MaxText = 20,
		Parent = speech,
	})

	local chosen: { pizza: string?, size: string?, house: number? } = {}
	local cart: { { pizza: string, size: string } } = {}
	local y = 80

	local function sectionLabel(text: string, atY: number)
		Ui.label(text, { Position = UDim2.fromOffset(0, atY), Size = UDim2.new(1, 0, 0, 20), TextColor3 = T.Muted, TextXAlignment = Enum.TextXAlignment.Left, MaxText = 15, Parent = body })
	end

	sectionLabel("PIZZA", y)
	local pizzaRow = Ui.new("Frame", { Position = UDim2.fromOffset(0, y + 22), Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, Parent = body }, {
		Ui.new("UIGridLayout", { CellSize = UDim2.new(0.2, -6, 1, 0), CellPadding = UDim2.fromOffset(6, 0) }),
	})
	local pizzaButtons = {}
	for _, name in Config.PizzaOrder do
		local b = Ui.button(name, T.Card, { Parent = pizzaRow, MaxText = 17 })
		pizzaButtons[name] = b
		b.Activated:Connect(function()
			chosen.pizza = name
			selectGroup(pizzaButtons, name)
		end)
	end
	y += 74

	sectionLabel("SIZE", y)
	local sizeRow = Ui.new("Frame", { Position = UDim2.fromOffset(0, y + 22), Size = UDim2.new(0.62, 0, 0, 44), BackgroundTransparency = 1, Parent = body }, {
		Ui.new("UIGridLayout", { CellSize = UDim2.new(1 / 3, -6, 1, 0), CellPadding = UDim2.fromOffset(6, 0) }),
	})
	local sizeButtons = {}
	for _, size in Config.Sizes do
		local b = Ui.button(size, T.Card, { Parent = sizeRow, MaxText = 17 })
		sizeButtons[size] = b
		b.Activated:Connect(function()
			chosen.size = size
			selectGroup(sizeButtons, size)
		end)
	end
	local add1 = Ui.button("+1", T.Accent2, { Position = UDim2.new(0.64, 0, 0, y + 22), Size = UDim2.new(0.17, 0, 0, 44), TextColor3 = Color3.fromRGB(30, 30, 30), Parent = body })
	local add5 = Ui.button("+5", T.Accent2, { Position = UDim2.new(0.83, 0, 0, y + 22), Size = UDim2.new(0.17, 0, 0, 44), TextColor3 = Color3.fromRGB(30, 30, 30), Parent = body })
	y += 74

	sectionLabel("ORDER  (tap a line to remove one)", y)
	local list = Ui.new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, y + 22),
		Size = UDim2.new(1, 0, 0, 120),
		BackgroundColor3 = T.Card,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = body,
	}, { Ui.corner(8), Ui.pad(6), Ui.new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }) })
	y += 150

	local function renderCart()
		for _, c in list:GetChildren() do
			if c:IsA("TextButton") or c:IsA("TextLabel") then
				c:Destroy()
			end
		end
		local order, counts = {}, {}
		for _, it in cart do
			local key = it.size .. " " .. it.pizza
			if not counts[key] then
				counts[key] = 0
				table.insert(order, { key = key, item = it })
			end
			counts[key] += 1
		end
		if #order == 0 then
			Ui.label("Nothing rung in yet.", { Size = UDim2.new(1, 0, 0, 26), TextColor3 = T.Muted, MaxText = 16, Parent = list })
		end
		for i, entry in order do
			local b = Ui.button(string.format("%d x %s", counts[entry.key], entry.key), T.Panel, { Size = UDim2.new(1, 0, 0, 30), LayoutOrder = i, MaxText = 16, Parent = list })
			b.Activated:Connect(function()
				for j = #cart, 1, -1 do
					if cart[j].size .. " " .. cart[j].pizza == entry.key then
						table.remove(cart, j)
						break
					end
				end
				renderCart()
			end)
		end
	end
	local function add(n: number)
		if not chosen.pizza or not chosen.size then
			return
		end
		for _ = 1, n do
			if #cart < 40 then
				table.insert(cart, { pizza = chosen.pizza :: string, size = chosen.size :: string })
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
		sectionLabel("DELIVER TO HOUSE #", y)
		local grid = Ui.new("Frame", { Position = UDim2.fromOffset(0, y + 22), Size = UDim2.new(1, 0, 0, 150), BackgroundTransparency = 1, Parent = body }, {
			Ui.new("UIGridLayout", { CellSize = UDim2.new(1 / 6, -6, 0, 44), CellPadding = UDim2.fromOffset(6, 6) }),
		})
		local houseButtons = {}
		for i = 1, (tonumber(data.houses) or 16) do
			local b = Ui.button(tostring(i), T.Card, { Parent = grid, MaxText = 18 })
			houseButtons[tostring(i)] = b
			b.Activated:Connect(function()
				chosen.house = i
				selectGroup(houseButtons, tostring(i))
			end)
		end
	end

	local submit = Ui.button("Send to Kitchen", T.Accent, { Position = UDim2.new(0, 0, 1, -48), Size = UDim2.new(1, 0, 0, 48), Parent = body })
	submit.Activated:Connect(function()
		if #cart == 0 or (phone and not chosen.house) then
			submit.Text = if #cart == 0 then "Ring in at least one pizza!" else "Pick the house number!"
			task.delay(1.2, function()
				submit.Text = "Send to Kitchen"
			end)
			return
		end
		Minigames.Close()
		finish({ items = cart, house = chosen.house })
	end)
end

---------------------------------------------------------------------------
-- Supply: shelve each crate on the right shelf (shelves reshuffle).
---------------------------------------------------------------------------
local function supply(data: any, finish: Finish, cancel: Cancel)
	local crates: { string } = data.crates or {}
	local shelves: { string } = table.clone(data.shelves or Config.Ingredients)
	local _, body = open("Unload the Truck", 580, 470, cancel)

	local status = Ui.label("", { Size = UDim2.new(1, 0, 0, 24), TextColor3 = T.Muted, MaxText = 18, Parent = body })
	local crate = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 30), Size = UDim2.fromOffset(240, 90), BackgroundColor3 = Color3.fromRGB(150, 105, 60), Parent = body }, { Ui.corner(6), Ui.stroke(Color3.fromRGB(90, 60, 30), 4) })
	local swatch = Ui.new("Frame", { Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(20, 70), Parent = crate }, { Ui.corner(4) })
	local crateLabel = Ui.label("", { Position = UDim2.fromOffset(40, 10), Size = UDim2.new(1, -50, 1, -20), Font = T.Title, Parent = crate })

	local grid = Ui.new("Frame", { Position = UDim2.fromOffset(0, 136), Size = UDim2.new(1, 0, 1, -136), BackgroundTransparency = 1, Parent = body }, {
		Ui.new("UIGridLayout", { CellSize = UDim2.new(1 / 3, -8, 0, 70), CellPadding = UDim2.fromOffset(8, 8) }),
	})
	local answers: { string } = {}
	local index = 1
	local rng = Random.new()

	local function shuffle(list: { string })
		for i = #list, 2, -1 do
			local j = rng:NextInteger(1, i)
			list[i], list[j] = list[j], list[i]
		end
	end

	local function render()
		local current = crates[index]
		status.Text = string.format("Crate %d of %d - put it on the matching shelf", index, #crates)
		crateLabel.Text = string.upper(current or "")
		swatch.BackgroundColor3 = Config.IngredientColors[current] or Color3.new(1, 1, 1)
		grid:ClearAllChildren()
		Ui.new("UIGridLayout", { CellSize = UDim2.new(1 / 3, -8, 0, 70), CellPadding = UDim2.fromOffset(8, 8), Parent = grid })
		shuffle(shelves)
		for _, ing in shelves do
			local b = Ui.button(ing, T.Card, { Parent = grid, MaxText = 18 })
			b.Activated:Connect(function()
				answers[index] = ing
				index += 1
				if index > #crates then
					Minigames.Close()
					finish({ answers = answers })
				else
					render()
				end
			end)
		end
	end
	render()
end

local HANDLERS: { [string]: (any, Finish, Cancel) -> () } = {
	Register = register,
	Supply = supply,
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
