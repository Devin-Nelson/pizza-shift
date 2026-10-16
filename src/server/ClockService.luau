--!strict
-- Advances the shared 24-hour clock, drives the sun, and fires Closed at
-- midnight. The clock is published to clients via GameClock (shared).

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local GameClock = require(ReplicatedStorage.Shared.GameClock)

local ClockService = {}

local weekHour = Config.Day.StartWeekHour
local weekNumber = 1

local closedEvent = Instance.new("BindableEvent")
ClockService.Closed = closedEvent.Event -- fires when the store closes (midnight)

function ClockService.WeekHour(): number
	return weekHour
end

function ClockService.WeekNumber(): number
	return weekNumber
end

function ClockService.Init()
	ReplicatedStorage:SetAttribute("WeekHour", weekHour)
	local wasOpen = GameClock.isOpen(weekHour)
	local published = 0
	RunService.Heartbeat:Connect(function(dt)
		local before = weekHour
		weekHour += dt / Config.Day.RealSecondsPerHour
		if weekHour >= 168 then
			weekHour -= 168
			weekNumber += 1
		end
		-- Sun follows the clock.
		Lighting.ClockTime = weekHour % 24
		-- Publish a few times a second (clients interpolate between updates).
		published += dt
		if published >= 0.25 or math.floor(before) ~= math.floor(weekHour) then
			published = 0
			ReplicatedStorage:SetAttribute("WeekHour", weekHour)
		end
		local open = GameClock.isOpen(weekHour)
		if wasOpen and not open then
			closedEvent:Fire()
		end
		wasOpen = open
	end)
end

return ClockService
