--!strict
-- Creates (server) or fetches (client) the RemoteEvents used by the game.

local RunService = game:GetService("RunService")

local NAMES = {
	"Notify", -- server -> client: (text, color?, pay?) pay = { grade, what, coins, xp, quality } shows as a pay slip
	"StartMinigame", -- server -> client: (kind, token, data)
	"MinigameResult", -- client -> server: (token, payload)
	"CancelMinigame", -- both ways: (token)
	"UseStation", -- client -> server: (stationId, pickId?) prompts, HUD bar / rail; pickId = a pizza (follow, oven exit) or an order (heat rack)
	"LeaveStation", -- client -> server: step away from the station you're at
	"StationMode", -- server -> client: (stationId, stationPart) you're now at this station; (nil) you left it
	"StationStatus", -- server -> client: (text) what the station you're at is waiting for
	"LoadPizza", -- client -> server: (pieId, orderId?) load a ready pizza (orderId: the picked order; 0 = as an extra; nil = auto-match)
	"StepDone", -- server -> client: (info) a station step finished; offer to follow the pizza
	"QueueUpdate", -- server -> client: (snapshot) open orders + rack counts for the queue panel
	"OpenStorePicker", -- server -> client: (lots, focusLotId?) every lot: { id, owner?, count, max, mine, owned }
	"RequestStores", -- client -> server: HUD "Stores" button
	"ChooseStore", -- client -> server: (lotId | nil) open or join the store on that lot; nil = leave yours
	"RequestStaff", -- client -> server: HUD "Staff" button
	"OpenStaffMenu", -- server -> client: (info) your store's hired staff, what's for hire, the roll
	"HireStaff", -- client -> server: (kind) owner hires a Config.Staff kind
	"AssignStaff", -- client -> server: (memberId, stationId) owner moves a team member / toggles a manager's station
	"ScheduleStaff", -- client -> server: (memberId, shift, on) owner puts a team member on or off a shift
	"GrantStaff", -- client -> server: (kind) Studio only, until the staff roll exists: the owner gets a manager
	"DeliveryTarget", -- server -> client: (doorPart | nil, seconds for the timer)
	"TipSeen", -- client -> server: (stationId) the player closed that station's first-visit tip
}

local folder: Folder
if RunService:IsServer() then
	local existing = script.Parent:FindFirstChild("RemoteEvents")
	if existing then
		folder = existing :: Folder
	else
		folder = Instance.new("Folder")
		folder.Name = "RemoteEvents"
		folder.Parent = script.Parent
	end
	for _, name in NAMES do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = script.Parent:WaitForChild("RemoteEvents") :: Folder
end

local Remotes: { [string]: RemoteEvent } = {}
for _, name in NAMES do
	Remotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
