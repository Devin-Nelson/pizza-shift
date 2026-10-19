--!strict
-- Turns an order's pizzas into ticket rows: identical pizzas (same size and
-- toppings) share a row with a count, in the order they were rung in, so a
-- 30-pizza party order still fits on a ticket. Each topping gets its own line.
-- Pure: plain tables in and out.

local TicketRows = {}

export type Item = { size: string, toppings: { string }, loaded: boolean? }
export type Row = { size: string, toppings: { string }, count: number, loaded: number }

function TicketRows.group(items: { Item }): { Row }
	local rows: { Row } = {}
	local index: { [string]: Row } = {}
	for _, item in items do
		local key = item.size .. "|" .. table.concat(item.toppings, "+")
		local row = index[key]
		if not row then
			row = { size = item.size, toppings = item.toppings, count = 0, loaded = 0 }
			index[key] = row
			table.insert(rows, row)
		end
		row.count += 1
		if item.loaded then
			row.loaded += 1
		end
	end
	return rows
end

-- The row's lines: its first topping (or CHEESE) with the count - "x3", or
-- "1/3" while some of a group are loaded - then each other topping.
function TicketRows.lines(row: Row): { string }
	local first = if #row.toppings > 0 then string.upper(row.toppings[1]) else "CHEESE"
	if row.count > 1 then
		first ..= if row.loaded > 0 and row.loaded < row.count then string.format(" %d/%d", row.loaded, row.count) else string.format(" x%d", row.count)
	end
	local lines = { first }
	for i = 2, #row.toppings do
		table.insert(lines, string.upper(row.toppings[i]))
	end
	return lines
end

-- A row is done (struck through) once every pizza in it is loaded.
function TicketRows.done(row: Row): boolean
	return row.loaded >= row.count
end

-- Rows that fit in `max` lines; the rest fold into a count of pizzas left over
-- (which takes the last line).
function TicketRows.fit(rows: { Row }, max: number): ({ Row }, number)
	local total = 0
	for _, row in rows do
		total += math.max(1, #row.toppings)
	end
	if total <= max then
		return rows, 0
	end
	local shown, used, hidden = {}, 0, 0
	for _, row in rows do
		local h = math.max(1, #row.toppings)
		if hidden == 0 and used + h <= max - 1 then
			table.insert(shown, row)
			used += h
		else
			hidden += row.count
		end
	end
	return shown, hidden
end

return TicketRows
