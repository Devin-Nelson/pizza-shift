--!strict
-- Creates (server) or fetches (client) the RemoteEvents used by the game.

local RunService = game:GetService("RunService")

local NAMES = {
	"Notify", -- server -> client: (text, color?)
	"StartMinigame", -- server -> client: (kind, token, data)
	"MinigameResult", -- client -> server: (token, payload)
	"CancelMinigame", -- both ways: (token)
	"ChooseJob", -- client -> server: (jobName | nil)
	"OpenJobMenu", -- server -> client: (shopName)
	"RequestTimeClock", -- client -> server: HUD "Clock In" button (nearest store)
	"UseStation", -- client -> server: (stationId, ticketId?) HUD station bar / queue / "what next?"
	"StepDone", -- server -> client: (info) a station step finished; offer what to do next
	"QueueUpdate", -- server -> client: (snapshot) open orders + rack counts for the queue panel
	"BuyFranchise", -- client -> server: (requested shop name)
	"OpenFranchiseMenu", -- server -> client: (info)
	"DeliveryTarget", -- server -> client: (doorPart | nil, seconds for the timer)
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
