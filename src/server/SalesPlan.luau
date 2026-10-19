--!strict
-- Sales forecasting math (no state). A store's week is a random total split
-- into days (each jittered ~3% off its nominal share, renormalized), then into
-- dayparts. Orders are generated against that budget, so the order count
-- follows from the average ticket, which shifts day to day with the order mix.

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local SalesPlan = {}

export type Week = { total: number, days: { number } }
export type Mix = { small: number, medium: number, large: number }
-- One pizza: a size and its toppings (0..Config.MaxToppings, in Config.Toppings order).
export type Item = { size: string, toppings: { string } }

local function sizeWeights(): { number }
	local weights = {}
	for i, size in Config.Sizes do
		weights[i] = Config.OrderSizes.SizeMix[size] or 0
	end
	return weights
end

local function weightedIndex(weights: { number }, rng: Random): number
	local total = 0
	for _, w in weights do
		total += w
	end
	local roll = rng:NextNumber() * total
	for i, w in weights do
		roll -= w
		if roll <= 0 then
			return i
		end
	end
	return #weights
end

function SalesPlan.newWeek(rng: Random, volume: number?): Week
	local S = Config.Sales
	local total = rng:NextNumber(S.Weekly.min, S.Weekly.max) * (volume or 1)
	local shares, sum = {}, 0
	for i, share in S.DayShares do
		shares[i] = share * (1 + rng:NextNumber(-S.DayVariance, S.DayVariance))
		sum += shares[i]
	end
	local days = {}
	for i, share in shares do
		days[i] = total * share / sum
	end
	return { total = total, days = days }
end

-- Today's order-size mix (re-rolled daily so the average ticket varies).
function SalesPlan.dayMix(rng: Random): Mix
	local O = Config.OrderSizes
	local j = O.DailyJitter
	local medium = O.Medium.weight * (1 + rng:NextNumber(-j, j))
	local large = O.Large.weight * (1 + rng:NextNumber(-j, j))
	return { small = 1 - medium - large, medium = medium, large = large }
end

function SalesPlan.rollPizzaCount(mix: Mix, rng: Random): number
	local O = Config.OrderSizes
	local tier = weightedIndex({ mix.small, mix.medium, mix.large }, rng)
	if tier == 1 then
		return O.Small.min + weightedIndex(O.Small.countWeights, rng) - 1
	elseif tier == 2 then
		return rng:NextInteger(O.Medium.min, O.Medium.max)
	end
	return rng:NextInteger(O.Large.min, O.Large.max)
end

-- 0..MaxToppings different toppings, the popular ones more often, in menu order.
function SalesPlan.rollToppings(rng: Random): { string }
	local count = math.min(weightedIndex(Config.ToppingCount, rng) - 1, Config.MaxToppings)
	local left = table.clone(Config.Toppings)
	local picked: { [string]: boolean } = {}
	for _ = 1, count do
		local weights = {}
		for i, t in left do
			weights[i] = Config.ToppingPopularity[t] or 0
		end
		picked[table.remove(left, weightedIndex(weights, rng)) :: string] = true
	end
	local toppings = {}
	for _, t in Config.Toppings do
		if picked[t] then
			table.insert(toppings, t)
		end
	end
	return toppings
end

function SalesPlan.rollItems(mix: Mix, rng: Random): { Item }
	local n = SalesPlan.rollPizzaCount(mix, rng)
	local weights = sizeWeights()
	-- Big orders tend to repeat a few favorites (party orders), small ones are anything.
	local favorites = {}
	for _ = 1, if n > 4 then 3 else n do
		table.insert(favorites, { size = Config.Sizes[weightedIndex(weights, rng)], toppings = SalesPlan.rollToppings(rng) })
	end
	local items = {}
	for i = 1, n do
		local pick = favorites[((i - 1) % #favorites) + 1]
		table.insert(items, { size = pick.size, toppings = table.clone(pick.toppings) })
	end
	return items
end

function SalesPlan.price(items: { Item }): number
	local total = 0
	for _, item in items do
		total += Config.PizzaPrice(item.size, item.toppings)
	end
	return total
end

-- "Large pepperoni & mushrooms", "Small cheese"
function SalesPlan.name(item: Item): string
	if #item.toppings == 0 then
		return item.size .. " cheese"
	end
	return item.size .. " " .. string.lower(table.concat(item.toppings, " & "))
end

-- Cumulative share of a day's sales that should have come in by `hour`.
function SalesPlan.shareByHour(hour: number): number
	local share = 0
	for _, part in Config.Sales.Dayparts do
		share += part.share * math.clamp((hour - part.from) / (part.to - part.from), 0, 1)
	end
	return share
end

-- Expected average ticket for a mix (for the sales board).
function SalesPlan.expectedTicket(mix: Mix): number
	local O = Config.OrderSizes
	local small, total = 0, 0
	for i, w in O.Small.countWeights do
		total += w
		small += w * (O.Small.min + i - 1)
	end
	small /= total
	local medium = (O.Medium.min + O.Medium.max) / 2
	local large = (O.Large.min + O.Large.max) / 2
	local pizzas = mix.small * small + mix.medium * medium + mix.large * large
	local avgToppings = 0
	for i, w in Config.ToppingCount do
		avgToppings += w * (i - 1)
	end
	local avgPrice = 0
	for size, w in O.SizeMix do
		avgPrice += w * ((Config.SizePrice[size] or 0) + (Config.ToppingPrice[size] or 0) * avgToppings)
	end
	return pizzas * avgPrice
end

-- "2 Large pepperoni & mushrooms, 1 Medium cheese"
function SalesPlan.describe(items: { Item }): string
	local order, counts = {}, {}
	for _, item in items do
		local key = SalesPlan.name(item)
		if not counts[key] then
			counts[key] = 0
			table.insert(order, key)
		end
		counts[key] += 1
	end
	local parts = {}
	for _, key in order do
		table.insert(parts, counts[key] .. " " .. key)
	end
	return table.concat(parts, ", ")
end

return SalesPlan
