--!strict
-- Loading finished pizzas from the ready rack into the oven, and the player's
-- order-matching setting (Config.MatchModes, tentative while we see which
-- plays better): "Auto" lets the server match each pizza to an order; "Pick"
-- asks which order it's for, from the orders still waiting on that size.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Ui = require(script.Parent.Ui)
local T = Ui.Theme

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
	local root, body, close = Ui.panel(string.format("Load this %s: which order?", size), 480, 130 + math.min(rows, 6) * 52)
	picker = root
	close.Activated:Connect(closePicker)
	local list = Ui.new("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -50),
		BackgroundTransparency = 1,
		ScrollBarThickness = 5,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = body,
	}, { Ui.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
	for i, e in eligible do
		local o = e.order
		local where = if o.delivery then "DELIVERY #" .. tostring(o.house) else "CARRYOUT"
		local b = Ui.button(string.format("#%d  %s  -  needs %s", o.id, where, table.concat(e.names, ", ")), T.Card, { Size = UDim2.new(1, -6, 0, 46), LayoutOrder = i, MaxText = 16 })
		b.Parent = list
		b.Activated:Connect(function()
			closePicker()
			Remotes.LoadPizza:FireServer(pieId, o.id)
		end)
	end
	if #eligible == 0 then
		Ui.label(string.format("No order is waiting on a %s right now.", size), { Size = UDim2.new(1, 0, 0, 40), TextColor3 = T.Muted, MaxText = 16, Parent = list })
	end
	local extra = Ui.button("Load it with no order (extra)", Color3.fromRGB(90, 70, 70), { Position = UDim2.new(0, 0, 1, -44), Size = UDim2.new(1, 0, 0, 44), MaxText = 16, Parent = body })
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
