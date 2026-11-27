-- StolenItems.luau (ServerScriptService.Server.Lib.StolenItems)
-- Purpose: the SERVER-ONLY set of items a robber has taken (WP8). The item stays in the player's saved inventory (so a crash or rejoin
-- simply gives it back and no data schema changes); while it is in this set it cannot be displayed or sold. Entries expire by themselves.
-- Owner: Dev 2 (Dwayne) / Dev 1 (Ace). Used by: RobberService (writes), DisplayService and InventoryService (read).
-- Depends on: nothing. Memory only: it is empty after a server restart, which is the safe direction (the item is normal again).

local StolenItems = {}

local stolen: { [any]: { [string]: { expiresAt: number, itemId: string, fee: number } } } = {}

-- Marks an item as stolen for `seconds` seconds. info: { itemId, fee }.
function StolenItems.Add(player: any, uid: string, itemId: string, fee: number, seconds: number, now: number?)
	stolen[player] = stolen[player] or {}
	stolen[player][uid] = { expiresAt = (now or os.clock()) + seconds, itemId = itemId, fee = fee }
end

-- True while the item is stolen. An expired entry counts as not stolen at once (TakeExpired removes it and tells the owner).
function StolenItems.Is(player: any, uid: any, now: number?): boolean
	local mine = stolen[player]
	local entry = mine and type(uid) == "string" and mine[uid]
	return entry ~= nil and entry ~= false and (now or os.clock()) < entry.expiresAt
end

function StolenItems.Remove(player: any, uid: string): boolean
	local mine = stolen[player]
	if mine and mine[uid] then
		mine[uid] = nil
		return true
	end
	return false
end

-- Entries that are still stolen: { { uid, itemId, fee, secondsLeft } }, soonest to expire first.
function StolenItems.List(player: any, now: number?): { { uid: string, itemId: string, fee: number, secondsLeft: number } }
	local t = now or os.clock()
	local out = {}
	for uid, entry in stolen[player] or {} do
		if t < entry.expiresAt then
			table.insert(out, { uid = uid, itemId = entry.itemId, fee = entry.fee, secondsLeft = entry.expiresAt - t })
		end
	end
	table.sort(out, function(a, b)
		return a.secondsLeft < b.secondsLeft
	end)
	return out
end

-- Entries that ran out since the last call (the owner gets the item back): { uid, itemId }. Removes them.
function StolenItems.TakeExpired(player: any, now: number?): { { uid: string, itemId: string } }
	local t = now or os.clock()
	local out = {}
	local mine = stolen[player]
	for uid, entry in mine or {} do
		if t >= entry.expiresAt then
			table.insert(out, { uid = uid, itemId = entry.itemId })
			mine[uid] = nil
		end
	end
	return out
end

function StolenItems.Clear(player: any)
	stolen[player] = nil
end

return StolenItems
