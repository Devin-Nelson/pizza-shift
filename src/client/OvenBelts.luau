--!strict
-- The ovens' conveyors run: each belt's wire Texture scrolls toward the exit
-- and the pulleys at its ends turn, at the speed pizzas ride the lanes
-- (StationArt tags them OvenBelt / OvenPulley with BeltSpeed / Spin). Visual
-- only, client-side; the phase needn't match the server's pizzas, the speed does.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local OvenBelts = {}

local TILE = 0.3 -- studs per tile of the wire (StationArt's StudsPerTileV)
local SCROLL = -1 -- toward the exit (the user saw +1 run the wrong way)

function OvenBelts.start()
	RunService.Heartbeat:Connect(function() -- Heartbeat: RenderStepped stops when Studio isn't rendering
		local t = os.clock()
		for _, belt in CollectionService:GetTagged("OvenBelt") do
			local offset = (SCROLL * t * ((belt:GetAttribute("BeltSpeed") :: number?) or 0)) % TILE
			for _, wire in belt:GetChildren() do
				if wire:IsA("Texture") then
					wire.OffsetStudsV = offset
				end
			end
		end
		for _, pulley in CollectionService:GetTagged("OvenPulley") do
			local base = pulley:GetAttribute("Base")
			if pulley:IsA("BasePart") and typeof(base) == "CFrame" then
				-- Base includes the mesh import's half turn, which flips the axle: + turns the top toward the exit.
				pulley.CFrame = base * CFrame.Angles((t * ((pulley:GetAttribute("Spin") :: number?) or 0)) % (2 * math.pi), 0, 0)
			end
		end
	end)
end

return OvenBelts
