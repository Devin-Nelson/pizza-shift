--!strict
-- Staying at a station between jobs. The server puts you at a station
-- (Remotes.StationMode) and hands you each job there as soon as one is waiting
-- (StartMinigame). In between, a strip at the bottom shows what the station is
-- waiting for (Remotes.StationStatus). You leave with Exit / X, or hop to
-- another station from the HUD rail (WorkHud) without walking.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Ui = require(script.Parent.Ui)
local Workstation = require(script.Parent.Workstation)
local T = Ui.Theme

local StationMode = {}

local current: { name: string, part: BasePart, ws: Workstation.Workstation }? = nil
local status = ""
local idle: { dock: Frame, text: TextLabel }? = nil
local isMinigameOpen: () -> boolean = function()
	return false
end
local closeMinigame: () -> () = function() end

-- What to do while a station waits, where it isn't just "the next one loads by itself".
local HINTS: { [string]: string } = {
	Toppings = "The next pizza loads by itself. Load It sends a finished pizza straight to the oven; To Rack puts it on the ready rack.",
	Load = "Click a pizza on the ready rack to load it into the next free oven slot.",
	CutTable = "Click a pizza at an oven exit to pull it before it falls off. Click a card to read it.",
	DeliveryRack = "Pick an order from the heat rack list on the right to take it out.",
}

local function label(id: string): string
	local info = Config.StationInfo(id)
	return if info then info.label else id
end

local function hideIdle()
	if idle then
		idle.dock:Destroy()
		idle = nil
	end
end

-- Leaves locally (the server has already taken us off, or is about to).
function StationMode.Leave()
	hideIdle()
	local c = current
	if c then
		current = nil
		c.ws:leave(false)
	end
end

-- Step away from the station: tell the server, put down the minigame, leave.
function StationMode.Exit()
	if current then
		Remotes.LeaveStation:FireServer()
	end
	closeMinigame()
	StationMode.Leave()
end

local function showIdle()
	local c = current
	if idle or not c then
		return
	end
	local dock, body, close = Ui.dock(label(c.name), 150)
	close.Activated:Connect(StationMode.Exit)
	local text = Ui.label(status, { Size = UDim2.new(1, -170, 0, 44), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, MaxText = 22, Parent = body })
	local hint = HINTS[c.name] or "Stay here and the next one loads by itself. Switch stations from the list on the left."
	Ui.label(hint, {
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, -170, 0, 34),
		TextColor3 = T.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		MaxText = 15,
		Parent = body,
	})
	local exit = Ui.button("Exit Station", Color3.fromRGB(90, 70, 70), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 24), Size = UDim2.fromOffset(160, 56), Parent = body })
	exit.Activated:Connect(StationMode.Exit)
	idle = { dock = dock, text = text }
end

-- The id of the station we're at, if any.
function StationMode.Current(): string?
	return if current then current.name else nil
end

function StationMode.Workstation(): Workstation.Workstation?
	return if current then current.ws else nil
end

-- Puts us at a station (gliding over from the one we're at, if any).
function StationMode.Enter(name: string, part: BasePart): Workstation.Workstation?
	local c = current
	if c and c.part == part then
		return c.ws
	end
	hideIdle()
	closeMinigame()
	if c then
		current = nil
		c.ws:leave(true)
	end
	status = "..."
	local ws = Workstation.enter(part)
	if not ws then
		Workstation.restore()
		Remotes.LeaveStation:FireServer()
		return nil
	end
	current = { name = name, part = part, ws = ws }
	return ws
end

-- The workstation for a job the server just started at `part` (entering it if
-- we somehow aren't there yet).
function StationMode.Ensure(part: any): Workstation.Workstation?
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return StationMode.Workstation()
	end
	local c = current
	if c and c.part == part then
		return c.ws
	end
	local name = part:GetAttribute("Station")
	return StationMode.Enter(if type(name) == "string" then name else part.Name, part)
end

function StationMode.Init(minigameOpen: () -> boolean, closeOpenMinigame: () -> ())
	isMinigameOpen = minigameOpen
	closeMinigame = closeOpenMinigame
	Remotes.StationMode.OnClientEvent:Connect(function(name: string?, part: BasePart?)
		if type(name) == "string" and typeof(part) == "Instance" and part:IsA("BasePart") then
			StationMode.Enter(name, part)
		else
			closeMinigame()
			StationMode.Leave()
		end
	end)
	Remotes.StationStatus.OnClientEvent:Connect(function(text: string)
		status = tostring(text)
		if idle then
			idle.text.Text = status
		end
	end)
	-- The idle strip shows whenever we're at a station with no job open.
	local wasOpen = false
	RunService.Heartbeat:Connect(function()
		local open = isMinigameOpen()
		if wasOpen and not open then
			-- Just finished one; the server sends the real status if nothing's next.
			status = "Checking for the next one..."
		end
		wasOpen = open
		local want = current ~= nil and not open
		if want and not idle then
			showIdle()
		elseif not want and idle then
			hideIdle()
		end
	end)
end

return StationMode
