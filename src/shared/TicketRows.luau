--!strict
-- Turns an order's pizzas into ticket rows: identical pizzas (same size and
-- recipe) share a row with a count, in the order they were rung in, so a
-- 30-pizza party order still fits on a ticket. Pure: plain tables in and out.

local TicketRows = {}

export type Item = { size: string, pizza: string, loaded: boolean? }
export type Row = { size: string, pizza: string, count: number, loaded: number }

function TicketRows.group(items: { Item }): { Row }
	local rows: { Row } = {}
	local index: { [string]: Row } = {}
	for _, item in items do
		local key = item.size .. "|" .. item.pizza
		local row = index[key]
		if not row then
			row = { size = item.size, pizza = item.pizza, count = 0, loaded = 0 }
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

-- "PEPPERONI", "PEPPERONI x3", or "PEPPERONI 1/3" while some of a group are loaded.
function TicketRows.label(row: Row): string
	local name = string.upper(row.pizza)
	if row.count == 1 then
		return name
	end
	if row.loaded > 0 and row.loaded < row.count then
		return string.format("%s %d/%d", name, row.loaded, row.count)
	end
	return string.format("%s x%d", name, row.count)
end

-- A row is done (struck through) once every pizza in it is loaded.
function TicketRows.done(row: Row): boolean
	return row.loaded >= row.count
end

-- At most `max` rows; the rest fold into a count of pizzas left over.
function TicketRows.fit(rows: { Row }, max: number): ({ Row }, number)
	if #rows <= max then
		return rows, 0
	end
	local shown = {}
	local hidden = 0
	for i, row in rows do
		if i < max then
			table.insert(shown, row)
		else
			hidden += row.count
		end
	end
	return shown, hidden
end

return TicketRows
