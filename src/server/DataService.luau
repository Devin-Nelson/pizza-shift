--!strict
-- Player persistence + leaderstats. Fails soft in Studio when API access is off.

local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

export type Profile = {
	Coins: number,
	XP: number,
	PizzasMade: number,
	Deliveries: number,
	Franchise: { owned: boolean, name: string },
}

local DataService = {}

-- Internal key (predates the Dominus rename). Changing it orphans existing saves.
local STORE_NAME = "PizzaShift_v1"
local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[DataService] DataStore unavailable (enable Studio API access to save):", result)
	end
end

local profiles: { [Player]: Profile } = {}
local loaded: { [Player]: boolean } = {}
local doublePay: { [Player]: boolean } = {}

local function defaultProfile(): Profile
	return {
		Coins = 0,
		XP = 0,
		PizzasMade = 0,
		Deliveries = 0,
		Franchise = { owned = false, name = "" },
	}
end

local function reconcile(data: any): Profile
	local profile = defaultProfile()
	if type(data) == "table" then
		for key, value in data do
			if (profile :: any)[key] ~= nil and typeof(value) == typeof((profile :: any)[key]) then
				(profile :: any)[key] = value
			end
		end
	end
	return profile
end

local function key(player: Player): string
	return "u_" .. player.UserId
end

local function retry<T>(fn: () -> T): (boolean, T?)
	for attempt = 1, 3 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn("[DataService] attempt", attempt, "failed:", result)
		task.wait(attempt)
	end
	return false, nil
end

local function makeLeaderstats(player: Player, profile: Profile)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = profile.Coins
	coins.Parent = stats
	local level = Instance.new("IntValue")
	level.Name = "Level"
	level.Value = Config.LevelFromXP(profile.XP)
	level.Parent = stats
	stats.Parent = player

	-- XP replicates as an attribute for the HUD (leaderstats only shows Level).
	player:SetAttribute("XP", profile.XP)
end

local function syncStats(player: Player)
	local profile = profiles[player]
	local stats = player:FindFirstChild("leaderstats")
	if not profile or not stats then
		return
	end
	(stats:FindFirstChild("Coins") :: IntValue).Value = profile.Coins;
	(stats:FindFirstChild("Level") :: IntValue).Value = Config.LevelFromXP(profile.XP)
	player:SetAttribute("XP", profile.XP)
end

function DataService.Load(player: Player): Profile?
	local data = nil
	if store and RunService:IsStudio() then
		-- One quick try in Studio; if API access is off, play unsaved instead of retrying.
		local ok, result = pcall(function()
			return (store :: DataStore):GetAsync(key(player))
		end)
		if ok then
			data = result
		else
			warn("[DataService] Saving disabled for this Studio session:", result)
			store = nil
		end
	elseif store then
		local ok, result = retry(function()
			return (store :: DataStore):GetAsync(key(player))
		end)
		if not ok then
			player:Kick("Couldn't load your save data. Please rejoin.")
			return nil
		end
		data = result
	end
	if not player.Parent then
		return nil
	end
	local profile = reconcile(data)
	profiles[player] = profile
	loaded[player] = true
	makeLeaderstats(player, profile)

	if Config.GamePasses.DoublePay ~= 0 then
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, Config.GamePasses.DoublePay)
		end)
		doublePay[player] = ok and owns == true
	end
	return profile
end

function DataService.Save(player: Player)
	local profile = profiles[player]
	if not store or not profile or not loaded[player] then
		return
	end
	retry(function()
		(store :: DataStore):SetAsync(key(player), profile)
		return true
	end)
end

function DataService.Release(player: Player)
	DataService.Save(player)
	profiles[player] = nil
	loaded[player] = nil
	doublePay[player] = nil
end

function DataService.Get(player: Player): Profile?
	return profiles[player]
end

-- Pays a worker. Returns the amount actually granted.
function DataService.AddCoins(player: Player, amount: number, ignoreMultiplier: boolean?): number
	local profile = profiles[player]
	if not profile then
		return 0
	end
	local final = math.floor(amount)
	if not ignoreMultiplier and doublePay[player] then
		final *= 2
	end
	profile.Coins += final
	syncStats(player)
	return final
end

function DataService.SpendCoins(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile or profile.Coins < amount then
		return false
	end
	profile.Coins -= amount
	syncStats(player)
	return true
end

-- Returns true if the player levelled up.
function DataService.AddXP(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	local before = Config.LevelFromXP(profile.XP)
	profile.XP += amount
	syncStats(player)
	return Config.LevelFromXP(profile.XP) > before
end

function DataService.GetLevel(player: Player): number
	local profile = profiles[player]
	return if profile then Config.LevelFromXP(profile.XP) else 1
end

function DataService.Sync(player: Player)
	syncStats(player)
end

function DataService.Init()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased and passId == Config.GamePasses.DoublePay then
			doublePay[player] = true
		end
	end)

	-- Autosave every 2 minutes.
	task.spawn(function()
		while true do
			task.wait(120)
			for _, player in Players:GetPlayers() do
				task.spawn(DataService.Save, player)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for _, player in Players:GetPlayers() do
			pending += 1
			task.spawn(function()
				DataService.Save(player)
				pending -= 1
			end)
		end
		local start = os.clock()
		while pending > 0 and os.clock() - start < 25 do
			task.wait(0.1)
		end
	end)
end

return DataService
