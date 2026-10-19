--!strict
-- First-visit tips: the first time you work a station, a printed job card
-- (left side, clear of the work) says how it works in a few short steps. On
-- screen everything else is short labels. "Got it" closes it for good (saved
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
		"Ring in every pizza: pick the pizza and size, then +1 or +5.",
		"Phone orders need the house number. Then send it to the kitchen.",
	},
	Dough = {
		"Pick a size. Skins go on the racks for the saucers.",
		"Press when the marker is in the green. The zone jumps after every press.",
		"Yellow and misses leave the skin small and lopsided.",
	},
	Sauce = {
		"Pick a skin off the racks.",
		"Hold and spread the sauce out to the 3/4\" line.",
		"Keep the rim clean, then press Done.",
	},
	Cheese = {
		"Hold to pour. It speeds up the longer you hold.",
		"Portion it by the cheese card, within 10%.",
		"Press Done when it's right.",
	},
	Toppings = {
		"Pick a topping, then hold on the pizza to drop it.",
		"Portions are on the card. -5 picks some back off.",
		"Load sends it to the oven; To Rack puts it on the ready rack.",
	},
	Load = {
		"Click a pizza on the ready rack to load it into the next oven slot.",
		"Auto-match or pick the order yourself: switch it on the Stations bar.",
	},
	CutTable = {
		"Click a pizza as it comes out of an oven, before it falls off.",
		"Click the right box. Pop any bubbles.",
		"Rock the blade through even cuts, season the crust, close the lid.",
	},
	DeliveryRack = {
		"Pick an order from the tickets.",
		"Grab the bag, drive to the house and walk it to the door. Faster, bigger tip.",
	},
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
	local root = Ui.box(C.Cream, {
		Name = "Tip",
		Position = UDim2.fromOffset(10, 170),
		Size = UDim2.fromOffset(300, 0),
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
