-- Tutorial.luau (ReplicatedStorage.Shared.Tutorial)
-- Purpose: the first-2-minutes tutorial steps (docs/01 §J5) and ONE rule for "is this step done?", read from saved
-- data, so the client (TutorialController: what to show) and the server (TutorialService: what to accept) agree.
-- Owner: Dev 3 (Sean). Depends on: the data shape in docs/03 §10.5 (inventory states, collection, stats).
-- Steps advance from real progress, never from a "Next" button: a returning player resumes where they left off.

local Tutorial = {}

-- Order matters. `hint` is the only text the player reads (short, icon first: docs/01 "no paragraph tutorials").
-- `target` tells the client where the arrow goes (resolved in TutorialController).
Tutorial.Steps = {
	{ id = "opened", hint = "📦 Open the box at your door", target = "DeliveryPoint" },
	{ id = "restored", hint = "🧽 Restore it at your workbench", target = "Bench" },
	{ id = "displayed", hint = "🏷️ Put it on a shelf", target = "EmptyShelf" },
	{ id = "sold", hint = "💰 Wait for a customer. Tap Checkout for a bonus!", target = "Counter" },
}
Tutorial.FinishHint = "🎉 Your shop is open! Try 🔨 Upgrades"

local function anyItemIn(data: any, states: { [string]: boolean }): boolean
	if type(data) ~= "table" or type(data.inventory) ~= "table" then
		return false
	end
	for _, item in data.inventory do
		if type(item) == "table" and states[item.state] then
			return true
		end
	end
	return false
end

local function stat(data: any, key: string): number
	local stats = type(data) == "table" and data.stats
	return type(stats) == "table" and tonumber(stats[key]) or 0
end

-- Later steps also count as proof of earlier ones (a sold item was displayed, a displayed item was restored...),
-- because the item that proved a step may be gone by now.
local DONE: { [string]: (any) -> boolean } = {}
DONE.sold = function(data)
	return stat(data, "sold") > 0
end
DONE.displayed = function(data)
	return DONE.sold(data) or anyItemIn(data, { Displayed = true, Exhibited = true })
end
DONE.restored = function(data)
	return DONE.displayed(data) or stat(data, "restored") > 0 or anyItemIn(data, { Restored = true })
end
DONE.opened = function(data)
	if DONE.restored(data) or anyItemIn(data, { Dirty = true, InProgress = true }) then
		return true
	end
	local collection = type(data) == "table" and data.collection
	return type(collection) == "table" and next(collection) ~= nil
end

function Tutorial.IsStepDone(stepId: string, data: any): boolean
	local check = DONE[stepId]
	return check ~= nil and check(data)
end

-- Index of the first step not done yet, or #Steps + 1 when every step is done.
function Tutorial.CurrentStep(data: any): number
	for index, step in Tutorial.Steps do
		if not DONE[step.id](data) then
			return index
		end
	end
	return #Tutorial.Steps + 1
end

function Tutorial.IndexOf(stepId: string): number?
	for index, step in Tutorial.Steps do
		if step.id == stepId then
			return index
		end
	end
	return nil
end

return Tutorial
