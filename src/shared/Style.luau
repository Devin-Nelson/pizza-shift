--!strict
-- The "store systems" look, shared by the HUD (client) and the in-world
-- screens (server): the HUD reads like the store's own POS / kitchen-screen
-- software. Flat, squared, brand charcoal / red / cream; Oswald for labels
-- (always uppercase), Roboto Mono for numbers and timers, Roboto for the rare
-- line of body text. Colours come from Config.Brand.

local Config = require(script.Parent.Config)

local Style = {}

local B = Config.Brand
Style.Color = {
	Panel = B.Charcoal,
	Tile = B.Charcoal2,
	Line = B.Line,
	Red = B.Red,
	RedDark = B.RedDark,
	Cream = B.Cream,
	CreamDim = B.CreamDim,
	Gold = B.Gold,
	Green = B.Green,
	Ink = B.Ink,
	Rule = B.Rule,
	White = Color3.new(1, 1, 1),
}

local function family(font: Enum.Font): string
	return Font.fromEnum(font).Family
end
local OSWALD = family(Enum.Font.Oswald)
local MONO = family(Enum.Font.RobotoMono)
local ROBOTO = family(Enum.Font.Roboto)

Style.Font = {
	Label = Font.new(OSWALD, Enum.FontWeight.Medium),
	LabelBold = Font.new(OSWALD, Enum.FontWeight.SemiBold),
	Heading = Font.new(OSWALD, Enum.FontWeight.Bold),
	Mono = Font.new(MONO, Enum.FontWeight.Bold),
	Body = Font.new(ROBOTO, Enum.FontWeight.Regular),
	BodyBold = Font.new(ROBOTO, Enum.FontWeight.Bold),
}

-- Text sizes at the reference resolution (Config.UiReference).
Style.Size = {
	Tiny = 11,
	Small = 12,
	Body = 14,
	Label = 15,
	Big = 18,
	Title = 20,
	Huge = 26,
}

-- Ticket header colour by how long the order has been waiting (seconds).
function Style.ticketColor(ageSeconds: number): (Color3, Color3)
	if ageSeconds < Config.TicketAge.Fresh then
		return Style.Color.Green, Style.Color.White
	elseif ageSeconds < Config.TicketAge.Aging then
		return Style.Color.Gold, Style.Color.Ink
	end
	return Style.Color.Red, Style.Color.White
end

-- "4:05" from seconds.
function Style.clock(seconds: number): string
	seconds = math.max(0, seconds)
	return string.format("%d:%02d", seconds // 60, math.floor(seconds % 60))
end

return Style
