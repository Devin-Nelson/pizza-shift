--!strict
-- Staying at a station between jobs. The server puts you at a station
-- (Remotes.StationMode) and hands you each job there as soon as one is waiting
-- (StartMinigame). In between, a slim strip at the bottom shows what the
-- station is waiting for (Remotes.StationStatus). You leave with the Exit
-- button or by jumping (Space / gamepad A: the user, 2026-10-24), or step to
-- another station with the edge arrows (WorkHud) without walking.
-- The first visit to a station shows its tip card (StationTips).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Style = require(ReplicatedStorage.Shared.Style)
local StationTips = require(script.Parent.StationTips)
local Ui = require(script.Parent.Ui)
local Workstation = require(script.Parent.Workstation)

local StationMode = {}

local current: { name: string, part: BasePart, ws: Workstation.Workstation }? = nil
local status = ""
local idle: { dock: Frame, text: TextLabel }? = nil
local isMinigameOpen: () -> boolean = function()
	return false
end
local closeMinigame: () -> () = function() end
local JUMP_OFF = "PizzaStationJumpOff"

local function hideIdle()
	if idle then
		idle.dock:Destroy()
		idle = nil
	end
end

-- Leaves locally (the server has already taken us off, or is about to).
function StationMode.Leave()
	ContextActionService:UnbindAction(JUMP_OFF)
	hideIdle()
	StationTips.Hide()
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

-- The idle strip: just what the station is waiting for, in one line.
local function showIdle()
	local c = current
	if idle or not c then
		return
	end
	local strip, row = Ui.strip()
	strip.Size = UDim2.fromOffset(0, 40)
	row.Size = UDim2.fromOffset(0, 37)
	local text = Ui.text(status, Style.Font.Label, Style.Size.Body, {
		TextColor3 = Style.Color.CreamDim,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 37),
		Parent = row,
	})
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = text })
	idle = { dock = strip, text = text }
end

-- True while a job (minigame) is open at the station.
function StationMode.Busy(): boolean
	return isMinigameOpen()
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
	StationTips.Hide()
	local ws = Workstation.enter(part)
	if not ws then
		Workstation.restore()
		Remotes.LeaveStation:FireServer()
		return nil
	end
	current = { name = name, part = part, ws = ws }
	-- Jumping takes you off the station, and the key is swallowed here so your
	-- character doesn't actually jump (the user, 2026-10-24).
	ContextActionService:BindActionAtPriority(JUMP_OFF, function(_, state)
		if state == Enum.UserInputState.Begin then
			task.defer(StationMode.Exit)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
	StationTips.Show(name)
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
