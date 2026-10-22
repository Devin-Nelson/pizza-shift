--!strict
-- First-visit tips: the first time you work a station, a printed job card
-- (left side, clear of the work) says how it works in a few short steps, with
-- its portions (made from Config, so they're always current). There are no
-- job aid cards in the world; this is the reference. On screen everything
-- else is short labels. "Got it" closes it for good (saved
-- server-side via Remotes.TipSeen, read back from the TipsSeen attribute);
-- Help on the Stations bar brings it back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Style = require(ReplicatedStorage.Shared.Style)
local Ui = require(script.Parent.Ui)

local StationTips = {}

local C = Style.Color
local player = Players.LocalPlayer

local TIPS: { [string]: { string } } = {
	Register = {
		"Listen to the customer or caller.",
		"Ring in every pizza: pick up to 3 toppings (none for cheese) and the size, then +1 or +5.",
		"Phone orders need the house number. Then send it to the kitchen.",
	},
	Dough = {
		"Click a dough ball in its tray: the lit tray is the size the top ticket needs (any tray when you stay here to prep).",
		"Press when the marker is in the green. The zone jumps after every press.",
		"Yellow and misses leave the skin small and lopsided.",
		"You follow each pizza to its next step. Pick a station on the Stations bar to stay there; Follow brings you back.",
	},
	Sauce = {
		"The top ticket's skin is laid out for you (pick one when you stay here).",
		"Hold and spread the sauce out to the 3/4\" line.",
		"Keep the rim clean, then press Done.",
	},
	Cheese = {
		"Hold to pour. It speeds up the longer you hold.",
		"Watch the scale on the make-line. Portion it by the chart below, within 10%.",
		"Press Done when it's right.",
	},
	Toppings = {
		"Each topping is on its own line of the ticket.",
		"Click a pan on the rail to pick a topping up, then hold on the pizza.",
		"The scale shows what's on: pepperoni and ham in pieces, the rest in ounces.",
		"Portions are below, within 10%. -5 picks some back off.",
		"Load sends it to the oven; To Rack puts it on the ready rack.",
	},
	Load = {
		"Click a pizza on the ready rack to load it into the next oven slot.",
		"Auto-match or pick the order yourself: switch it on the Stations bar.",
	},
	CutTable = {
		"Click a pizza as it comes out of an oven, before it falls off.",
		"Click the right box. Pop any bubbles.",
		"Rock the blade through even cuts, then close the lid.",
	},
	DeliveryRack = {
		"Pick an order from the tickets: it waits on the delivery rack in a bag with its number.",
		"Grab the bag, drive to the house and walk it to the door. Faster, bigger tip.",
	},
}

-- Each station's reference chart, in lines of fixed-width text.
local function pad(text: string, width: number): string
	return text .. string.rep(" ", math.max(1, width - #text))
end
local REFS: { [string]: () -> { string } } = {
	Sauce = function()
		return { string.format("Sauce line: %g\" in from the edge, every size.", Config.Sauce.BorderInches) }
	end,
	Cheese = function()
		local lines = {}
		for _, size in Config.Sizes do
			table.insert(lines, pad(string.upper(size), 8) .. Config.PortionText("Cheese", Config.CheesePortion[size]))
		end
		return lines
	end,
	Toppings = function()
		local head = pad("1 / 2-3 top", 12)
		for _, size in Config.Sizes do
			head ..= pad(string.upper(string.sub(size, 1, 1)), 10)
		end
		local lines = { head }
		for _, topping in Config.Toppings do
			local line = pad(string.upper(topping), 12)
			for _, size in Config.Sizes do
				line ..= pad(string.format("%g/%g", Config.PortionFor(topping, size, 1), Config.PortionFor(topping, size, 2)), 10)
			end
			table.insert(lines, line .. (if Config.CountedToppings[topping] then "pcs" else "oz"))
		end
		return lines
	end,
	CutTable = function()
		local lines = {}
		for _, size in Config.Sizes do
			table.insert(lines, pad(string.upper(size), 8) .. Config.Cut.Slices[size] .. " slices")
		end
		return lines
	end,
}

local card: Frame? = nil
local seenNow: { [string]: boolean } = {} -- closed this session (before the save round-trips)

local function seen(id: string): boolean
	if seenNow[id] then
		return true
	end
	local list = player:GetAttribute("TipsSeen")
	if type(list) ~= "string" then
		return false
	end
	for entry in string.gmatch(list, "[^,]+") do
		if entry == id then
			return true
		end
	end
	return false
end

function StationTips.Has(id: string): boolean
	return TIPS[id] ~= nil
end

function StationTips.Hide()
	if card then
		card:Destroy()
		card = nil
	end
end

-- Shows a station's tip if it hasn't been seen (or always, with `again`).
function StationTips.Show(id: string, again: boolean?)
	local steps = TIPS[id]
	if not steps or (seen(id) and not again) then
		return
	end
	StationTips.Hide()
	local info = Config.StationInfo(id)
	local ref = REFS[id]
	local root = Ui.box(C.Cream, {
		Name = "Tip",
		Position = UDim2.fromOffset(10, 170),
		Size = UDim2.fromOffset(if ref then 360 else 300, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = Ui.Root,
	}, {
		Ui.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	card = root
	local head = Ui.box(C.Red, { Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 0, Parent = root })
	Ui.text(string.upper(if info then info.label else id), Style.Font.Heading, Style.Size.Big, { TextColor3 = C.White, Position = UDim2.fromOffset(12, 0), Size = UDim2.fromScale(0.6, 1), Parent = head })
	Ui.text(if again then "HOW IT WORKS" else "FIRST TIME HERE", Style.Font.Label, Style.Size.Tiny, {
		TextColor3 = C.White,
		TextTransparency = 0.15,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 0),
		Size = UDim2.fromScale(0.4, 1),
		Parent = head,
	})
	for i, step in steps do
		local row = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = i, Parent = root }, {
			Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }),
		})
		if i > 1 then
			Ui.box(C.Rule, { Size = UDim2.new(1, 24, 0, 1), Position = UDim2.fromOffset(-12, -8), Parent = row })
		end
		local num = Ui.box(C.Panel, { Size = UDim2.fromOffset(20, 20), Parent = row })
		Ui.text(tostring(i), Style.Font.Mono, Style.Size.Small, { TextColor3 = C.Cream, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = num })
		Ui.text(step, Style.Font.Body, Style.Size.Body, {
			TextColor3 = C.Ink,
			TextWrapped = true,
			Position = UDim2.fromOffset(30, 0),
			Size = UDim2.new(1, -30, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = row,
		})
	end
	if ref then
		local block = Ui.box(C.Panel, { Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 50, Parent = root }, {
			Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }),
		})
		Ui.text(table.concat(ref(), "\n"), Style.Font.Mono, Style.Size.Small, {
			TextColor3 = C.Cream,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = block,
		})
	end
	local foot = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 46), LayoutOrder = 100, Parent = root })
	Ui.text("Help on the Stations bar reopens this", Style.Font.Body, Style.Size.Small, {
		TextColor3 = Color3.fromRGB(122, 114, 102),
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -130, 1, 0),
		TextWrapped = true,
		Parent = foot,
	})
	local ok = Ui.flatButton("Got it", "dark", {
		BackgroundColor3 = C.Panel,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(96, 32),
		Parent = foot,
	})
	ok.Activated:Connect(function()
		StationTips.Hide()
		if not seen(id) then
			seenNow[id] = true
			Remotes.TipSeen:FireServer(id)
		end
	end)
end

return StationTips
