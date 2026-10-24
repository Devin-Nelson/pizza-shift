--!strict
-- The game's UI look, shared by the HUD (client) and the in-world screens
-- (server). Bright, simple and kid friendly (the user, 2026-10-24, after the
-- station arrows): tomato, sun and mint on a friendly deep purple, rounded
-- corners (Ui rounds buttons, chips, panels and the work strip), Fredoka One
-- for labels and headings (always uppercase), Roboto Mono for numbers and
-- timers, Gotham for body text. The store's own colours (signs, soffits)
-- stay Config.Brand.

local Config = require(script.Parent.Config)

local Style = {}

local B = Config.Brand
Style.Color = {
	Panel = Color3.fromRGB(43, 36, 64),
	Tile = Color3.fromRGB(60, 51, 90),
	Line = Color3.fromRGB(86, 76, 122),
	Red = Color3.fromRGB(255, 75, 62),
	RedDark = Color3.fromRGB(205, 50, 40),
	Cream = Color3.fromRGB(255, 248, 236),
	CreamDim = Color3.fromRGB(208, 200, 228),
	Gold = Color3.fromRGB(255, 201, 60),
	Green = Color3.fromRGB(40, 190, 105),
	Ink = Color3.fromRGB(31, 27, 46),
	Rule = B.Rule,
	White = Color3.new(1, 1, 1),
}
-- Corner radius (px at the reference size) for rounded pieces.
Style.Round = 10

local function family(font: Enum.Font): string
	return Font.fromEnum(font).Family
end
local MONO = family(Enum.Font.RobotoMono)
local GOTHAM = family(Enum.Font.Gotham)
local FREDOKA = Font.fromEnum(Enum.Font.FredokaOne)

Style.Font = {
	Label = FREDOKA,
	LabelBold = FREDOKA,
	Heading = FREDOKA,
	Mono = Font.new(MONO, Enum.FontWeight.Bold),
	Body = Font.new(GOTHAM, Enum.FontWeight.Medium),
	BodyBold = Font.new(GOTHAM, Enum.FontWeight.Bold),
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
