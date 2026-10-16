--!strict
-- The 24-hour game clock. The server advances it (ClockService) and publishes
-- it as the "WeekHour" attribute on ReplicatedStorage: hours since Monday
-- 00:00 of the current week, 0 <= WeekHour < 168. Everyone reads it here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)

local GameClock = {}

function GameClock.weekHour(): number
	return tonumber(ReplicatedStorage:GetAttribute("WeekHour")) or Config.Day.StartWeekHour
end

-- Day index 1..7 (Mon..Sun) and hour of day 0..24.
function GameClock.split(weekHour: number?): (number, number)
	local w = weekHour or GameClock.weekHour()
	local day = math.floor(w / 24) % 7 + 1
	return day, w % 24
end

function GameClock.isOpen(weekHour: number?): boolean
	local _, hour = GameClock.split(weekHour)
	return hour >= Config.Day.OpenHour and hour < Config.Day.CloseHour
end

-- Staff may clock in a little before opening to prep (e.g. stretch dough).
function GameClock.canClockIn(weekHour: number?): boolean
	local _, hour = GameClock.split(weekHour)
	return hour >= Config.Day.OpenHour - Config.Day.ClockInEarly and hour < Config.Day.CloseHour
end

function GameClock.dayName(day: number): string
	return Config.Day.DayNames[day] or "?"
end

-- "5:42 PM"
function GameClock.format(hour: number): string
	local h = math.floor(hour) % 24
	local m = math.floor((hour - math.floor(hour)) * 60)
	local suffix = if h < 12 then "AM" else "PM"
	local h12 = h % 12
	if h12 == 0 then
		h12 = 12
	end
	return string.format("%d:%02d %s", h12, m, suffix)
end

-- "10 AM", "9:30 AM", "midnight" (for messages built from Config hours).
function GameClock.shortTime(hour: number): string
	if hour % 24 == 0 then
		return "midnight"
	end
	return (GameClock.format(hour):gsub(":00 ", " "))
end

-- "open 10 AM to midnight, clock-in from 9:30 AM"
function GameClock.hoursText(): string
	local D = Config.Day
	return string.format("open %s to %s, clock-in from %s", GameClock.shortTime(D.OpenHour), GameClock.shortTime(D.CloseHour), GameClock.shortTime(D.OpenHour - D.ClockInEarly))
end

-- Hours until clock-in next opens (0 if staff can clock in now).
function GameClock.hoursUntilClockIn(weekHour: number?): number
	local _, hour = GameClock.split(weekHour)
	if GameClock.canClockIn(weekHour) then
		return 0
	end
	local start = Config.Day.OpenHour - Config.Day.ClockInEarly
	return if hour < start then start - hour else 24 - hour + start
end

function GameClock.daypart(hour: number): any?
	for _, part in Config.Sales.Dayparts do
		if hour >= part.from and hour < part.to then
			return part
		end
	end
	return nil
end

return GameClock
