--!strict
-- The rules for hired staff (numbers in Config.Staff*): shifts, station
-- levels and XP, what a level does, call-outs, managers' Flexibility, and
-- generating a new hire.
-- Pure (no engine state), so it's specced headlessly in tests/specs.luau.

local Config = require(script.Parent.Config)

-- One station's stat: its level and the XP earned toward the next.
export type Stat = { level: number, xp: number }
-- A hired team member as saved in the owner's profile.
export type Member = {
	id: number,
	kind: string,
	name: string,
	stations: { string }, -- where they work (StaffStations; the heat rack = driving); one for team members
	stats: { [string]: Stat }, -- per station
	reliability: number, -- 1..Config.Reliability.Max
	flexibility: number?, -- 1..Config.Flexibility.Max, managers only
	avail: { [string]: boolean }, -- shifts they can work
	shifts: { [string]: boolean }, -- shifts the owner scheduled them for (within avail)
}

local Staff = {}

-- Shift names, in order: the sales dayparts (Lunch, Dinner, Late Night).
Staff.Shifts = {} :: { string }
for _, part in Config.Sales.Dayparts do
	table.insert(Staff.Shifts, part.name)
end

-- The shift at `hour` of the day (nil while the store's shut). The first one
-- starts early, with the prep window.
function Staff.shiftAt(hour: number): string?
	local first = Config.Sales.Dayparts[1]
	if hour >= Config.Day.OpenHour - Config.Day.PrepEarly and hour < first.to then
		return first.name
	end
	for _, part in Config.Sales.Dayparts do
		if hour >= part.from and hour < part.to then
			return part.name
		end
	end
	return nil
end

-- Jobs it takes to go from `level` to the next.
function Staff.xpToNext(level: number): number
	local L = Config.StaffLevels
	return L.XPBase + L.XPPerLevel * level
end

-- Adds `n` XP to a stat. Returns true if it levelled up.
function Staff.addXP(stat: Stat, n: number): boolean
	local max = Config.StaffLevels.Max
	if stat.level >= max then
		return false
	end
	stat.xp += n
	local leveled = false
	while stat.level < max and stat.xp >= Staff.xpToNext(stat.level) do
		stat.xp -= Staff.xpToNext(stat.level)
		stat.level += 1
		leveled = true
	end
	if stat.level >= max then
		stat.xp = 0
	end
	return leveled
end

local function along(range: { number }, level: number): number
	local t = math.clamp((level - 1) / (Config.StaffLevels.Max - 1), 0, 1)
	return range[1] + (range[2] - range[1]) * t
end

-- How well a member at `level` does the job (0..1).
function Staff.quality(level: number): number
	return along(Config.StaffLevels.Quality, level)
end

-- Multiplier on the station's base job time at `level` (lower = faster).
function Staff.speed(level: number): number
	return along(Config.StaffLevels.Speed, level)
end

-- Kinds that can work several stations at once (managers).
function Staff.isFlexible(kind: string): boolean
	local def = Config.Staff[kind]
	return def ~= nil and def.flexible == true
end

-- Stations a member with `flexibility` handles before being overwhelmed
-- (no Flexibility, as for team members: one).
function Staff.stationLimit(flexibility: number?): number
	return if flexibility then 1 + flexibility // 2 else 1
end

-- How many stations past their limit the member is working.
function Staff.overload(m: Member): number
	return math.max(0, #m.stations - Staff.stationLimit(m.flexibility))
end

-- How well the member does a job at `station` (0..1): their level there,
-- less what being overwhelmed costs.
function Staff.jobQuality(m: Member, station: string): number
	local stat = m.stats[station]
	local q = Staff.quality(if stat then stat.level else 1)
	return math.max(0, q * (1 - Config.Flexibility.Sloppy * Staff.overload(m)))
end

-- Multiplier on the base job time at `station` (lower = faster).
function Staff.jobSpeed(m: Member, station: string): number
	local stat = m.stats[station]
	return Staff.speed(if stat then stat.level else 1) * (1 + Config.Flexibility.Slow * Staff.overload(m))
end

-- Chance (0..1) a member with `reliability` calls out of a scheduled shift.
function Staff.calloutChance(reliability: number): number
	local R = Config.Reliability
	return math.clamp((R.Max - reliability) * R.CalloutPerPoint, 0, 1)
end

-- Open availability: every shift.
function Staff.isOpen(avail: { [string]: boolean }): boolean
	for _, shift in Staff.Shifts do
		if not avail[shift] then
			return false
		end
	end
	return true
end

-- How many members are scheduled for `shift`.
function Staff.scheduled(members: { Member }, shift: string): number
	local n = 0
	for _, m in members do
		if m.shifts[shift] then
			n += 1
		end
	end
	return n
end

type Rng = { NextNumber: (any, number?, number?) -> number, NextInteger: (any, number, number) -> number }

-- A new hire of `kind` from a Config.StaffGen pool (e.g. "Buy"): random
-- station levels, reliability, availability (and Flexibility for managers).
-- Starts at `station`, scheduled for every shift they're available for (the
-- owner trims it to fit).
function Staff.newMember(rng: Rng, pool: string, kind: string, id: number, name: string, station: string): Member
	local gen = Config.StaffGen[pool]
	local stats: { [string]: Stat } = {}
	for _, s in Config.StaffStations do
		stats[s] = { level = rng:NextInteger(gen.levels[1], gen.levels[2]), xp = 0 }
	end
	-- How many shifts they can work, then which.
	local u, count = rng:NextNumber(), #gen.shifts
	for i, p in gen.shifts do
		if u < p then
			count = i
			break
		end
		u -= p
	end
	local left = table.clone(Staff.Shifts)
	local avail: { [string]: boolean } = {}
	for _ = 1, math.min(count, #left) do
		avail[table.remove(left, rng:NextInteger(1, #left)) :: string] = true
	end
	local flex = if Staff.isFlexible(kind) and gen.flexibility then gen.flexibility else nil
	return {
		id = id,
		kind = kind,
		name = name,
		stations = { station },
		stats = stats,
		reliability = rng:NextInteger(gen.reliability[1], gen.reliability[2]),
		flexibility = if flex then rng:NextInteger(flex[1], flex[2]) elseif Staff.isFlexible(kind) then 1 else nil,
		avail = avail,
		shifts = table.clone(avail),
	}
end

-- A saved member made safe to use: unknown kinds dropped, missing or bad
-- fields filled in, numbers clamped, stations deduplicated (one for team
-- members), schedule kept inside availability.
function Staff.sanitize(raw: any, rng: Rng, id: number): Member?
	if type(raw) ~= "table" or not Config.Staff[raw.kind] or type(raw.name) ~= "string" then
		return nil
	end
	local kind = raw.kind
	local fresh = Staff.newMember(rng, if Config.StaffGen[kind] then kind else "Buy", kind, id, raw.name, Config.StaffStations[1])
	local stations = {}
	-- `station` (one) is the older save shape.
	for _, s in (if type(raw.stations) == "table" then raw.stations else { raw.station }) do
		if table.find(Config.StaffStations, s) and not table.find(stations, s) then
			table.insert(stations, s)
		end
	end
	if #stations == 0 then
		stations = { Config.StaffStations[1] }
	elseif not Staff.isFlexible(kind) then
		stations = { stations[1] }
	end
	local m: Member = {
		id = if type(raw.id) == "number" then raw.id else id,
		kind = kind,
		name = raw.name,
		stations = stations,
		stats = fresh.stats,
		reliability = if type(raw.reliability) == "number" then math.clamp(math.floor(raw.reliability), 1, Config.Reliability.Max) else fresh.reliability,
		flexibility = if not Staff.isFlexible(kind) then nil elseif type(raw.flexibility) == "number" then math.clamp(math.floor(raw.flexibility), 1, Config.Flexibility.Max) else fresh.flexibility,
		avail = {},
		shifts = {},
	}
	for _, s in Config.StaffStations do
		local st = type(raw.stats) == "table" and raw.stats[s]
		if type(st) == "table" and type(st.level) == "number" and type(st.xp) == "number" then
			m.stats[s] = { level = math.clamp(math.floor(st.level), 1, Config.StaffLevels.Max), xp = math.max(0, st.xp) }
		end
	end
	local savedAvail = type(raw.avail) == "table"
	for _, shift in Staff.Shifts do
		m.avail[shift] = if savedAvail then raw.avail[shift] == true else fresh.avail[shift] == true
		m.shifts[shift] = m.avail[shift] and (if type(raw.shifts) == "table" then raw.shifts[shift] == true else m.avail[shift])
	end
	return m
end

-- The kind a staff roll lands on, from a uniform number 0 <= u < 1.
function Staff.rollKind(u: number): string
	local odds = Config.StaffRoll.Odds
	for _, o in odds do
		if u < o.weight then
			return o.kind
		end
		u -= o.weight
	end
	return odds[#odds].kind
end

return Staff
