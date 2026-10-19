--!strict
-- Loading finished pizzas from the ready rack into the oven, and the player's
-- order-matching setting (Config.MatchModes, tentative while we see which
-- plays better): "Auto" lets the server match each pizza to an order; "Pick"
-- asks which order it's for, from the orders still waiting on that size.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Style = require(ReplicatedStorage.Shared.Style)
local Ui = require(script.Parent.Ui)

local C = Style.Color

local Loading = {}

Loading.mode = "Auto"

local snapshot: any = nil
local picker: Frame? = nil
local askAfterTopping = false

local function closePicker()
	if picker then
		picker:Destroy()
		picker = nil
	end
end

-- Pick mode: which order is this pizza for?
local function openPicker(pieId: number, size: string)
	closePicker()
	local eligible = {}
	for _, o in (if snapshot then snapshot.orders else {}) do
		local need, names = 0, {}
		for _, item in o.items do
			if not item.loaded and item.size == size then
				need += 1
				table.insert(names, item.pizza)
			end
		end
		if need > 0 then
			table.insert(eligible, { order = o, names = names })
		end
	end
	local rows = math.max(#eligible, 1)
	local root, body, close = Ui.panel(string.format("Load this %s: which order?", size), 480, 128 + math.min(rows, 6) * 52)
	picker = root
	close.Activated:Connect(closePicker)
	local list = Ui.new("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -54),
		BackgroundTransparency = 1,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = C.Line,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = body,
	}, { Ui.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
	-- One row per order still waiting on this size: the order like a ticket
	-- header, then what it needs.
	for i, e in eligible do
		local o = e.order
		local b = Ui.flatButton("", "dark", { Size = UDim2.new(1, -6, 0, 46), LayoutOrder = i, Parent = list })
		local bg, fg = Style.ticketColor(tonumber(o.age) or 0)
		local head = Ui.chip(string.format("#%d %s", o.id, if o.delivery then "Delivery" else "Carryout"), bg, fg, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 10, 0.5, 0),
			Size = UDim2.fromOffset(0, 26),
			Parent = b,
		})
		head.TextSize = Style.Size.Body
		Ui.text(string.upper("Needs " .. table.concat(e.names, ", ")), Style.Font.Label, Style.Size.Body, {
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.AtEnd,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.new(1, -170, 0, 20),
			Parent = b,
		})
		b.Activated:Connect(function()
			closePicker()
			Remotes.LoadPizza:FireServer(pieId, o.id)
		end)
	end
	if #eligible == 0 then
		Ui.text(string.format("No order is waiting on a %s right now.", size), Style.Font.Body, Style.Size.Body, { TextColor3 = C.CreamDim, Size = UDim2.new(1, 0, 0, 40), Parent = list })
	end
	local extra = Ui.flatButton("Load as an extra", "ghost", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 44), Parent = body })
	extra.Activated:Connect(function()
		closePicker()
		Remotes.LoadPizza:FireServer(pieId, 0) -- 0 = no order: bake it as an extra
	end)
end

function Loading.SetMode(mode: string)
	Loading.mode = mode
	closePicker()
end

-- Load a pizza from the ready rack (asks which order first in Pick mode).
function Loading.Load(pieId: number, size: string)
	if Loading.mode == "Pick" then
		openPicker(pieId, size)
	else
		Remotes.LoadPizza:FireServer(pieId)
	end
end

-- The toppings minigame's "Load It" in Pick mode: ask which order as soon
-- as the pizza is on the ready rack.
function Loading.AskAfterTopping()
	askAfterTopping = true
end

function Loading.Close()
	closePicker()
end

function Loading.Init()
	Remotes.QueueUpdate.OnClientEvent:Connect(function(snap: any)
		snapshot = snap
	end)
	Remotes.StepDone.OnClientEvent:Connect(function(info: any)
		if askAfterTopping and type(info) == "table" and info.station == "Toppings" and type(info.pieId) == "number" then
			askAfterTopping = false
			openPicker(info.pieId, tostring(info.size))
		end
	end)
end

return Loading
