--!strict
-- Following the top pizza (pure, specced): where a player who follows the
-- make process goes next. ShopService gathers the kitchen's state.

local Follow = {}

-- A pizza on the make-line that nobody's working on.
export type Waiting = { id: number, size: string, station: string }

-- `needed`: the size of every pizza the tickets still need, oldest first.
-- `covered`: per size, how many are already in someone's hands (a pizza being
-- worked, a skin being stretched or sauced); they cover the oldest tickets of
-- that size. `waiting`: pizzas nobody's on, furthest along first. `skins`:
-- free skins on the racks by size. Returns the station to go to, the pizza
-- to work there (or nil), and the size to stretch or sauce (nil with nothing
-- on order: stretch ahead, any size).
function Follow.target(needed: { string }, covered: { [string]: number }, waiting: { Waiting }, skins: { [string]: number }): (string, number?, string?)
	local left = table.clone(covered)
	for _, size in needed do
		if (left[size] or 0) > 0 then
			left[size] -= 1
		else
			for _, w in waiting do
				if w.size == size then
					return w.station, w.id, nil
				end
			end
			return if (skins[size] or 0) > 0 then "Sauce" else "Dough", nil, size
		end
	end
	return "Dough", nil, nil
end

return Follow
