--!strict
-- Types.luau (ReplicatedStorage.Shared.Types)
-- Purpose: shared type definitions (docs/03_Architecture.md §10): ItemInstance, PlayerData and the Config shapes.
-- Owner: Dev 1 (Ace). Depends on: nothing.
-- Types only: this module returns an empty table. Use it like:  local Types = require(Shared.Types)  then  Types.ItemInstance
-- PlayerData matches the template in DataService; change both together and ask the team first (CLAUDE.md §6.6).

export type ItemState = "Unopened" | "Dirty" | "InProgress" | "Restored" | "Displayed" | "Exhibited"

-- §10.4: an item owned by a player
export type ItemInstance = {
	uid: string,
	itemId: string,
	golden: boolean,
	state: ItemState,
	stepIndex: number, -- next step to do (1-based)
	stepScores: { number },
	stars: number?, -- 1-3 once restored
	slot: number?, -- display/exhibit slot index
	acquiredAt: number, -- os.time()
}

export type CollectionEntry = {
	found: boolean,
	bestStars: number,
	golden: boolean,
}

-- §10.5: the saved player data
export type PlayerData = {
	version: number,
	cash: number,
	xp: number,
	level: number,
	inventory: { [string]: ItemInstance }, -- [uid]
	upgrades: { [string]: number }, -- [upgradeId] = level owned
	collection: { [string]: CollectionEntry }, -- [itemId]
	likes: { received: number, givenToday: { [string]: boolean }, rewardedToday: number, day: number },
	stats: { restored: number, sold: number, earned: number, playSeconds: number },
	timers: { lastFreeDelivery: number },
	tutorial: { step: number, done: boolean },
	settings: { music: boolean, sfx: boolean, reduceEffects: boolean, announcements: boolean },
}

-- §10.1: one step of an item's restoration recipe
export type RecipeStep = {
	type: string, -- Wipe | Scrape | Reassemble | Replace | Polish | Test
	layers: number?,
	parts: { string }?, -- socket / loose-part names, e.g. "Wheel" (final list: docs/STATUS.md, rules: docs/01 §C2)
	style: string?,
	greenZone: number?,
}

-- §10.1: Config/Items.luau
export type ItemDef = {
	id: string,
	name: string,
	tier: number,
	rarity: string,
	category: string,
	baseValue: number,
	model: string,
	flavor: string?,
	recipe: { RecipeStep },
}

-- Config/Crates.luau
export type CrateDef = {
	id: string,
	name: string,
	boxModel: string,
	price: number,
	requiredLevel: number,
	itemCount: number,
	tier: number,
	odds: { [string]: number }, -- percentages by rarity name; add up to 100
}

-- Config/Rarities.luau
export type RarityDef = {
	id: string,
	index: number,
	xpPerRestore: number,
	firstFindBonus: { number }, -- { Tier 1, Tier 2 }
	exhibitPoints: number,
}

-- §10.3: Config/Upgrades.luau
export type UpgradeDef = {
	id: string,
	name: string,
	tab: string,
	maxLevel: number,
	costs: { number },
	requiredLevel: { number },
	requires: string?, -- upgradeId that must already be owned (checked IN ADDITION to requiredLevel)
	effect: { [string]: any },
	description: string,
}

-- §10.2: Config/Customers.luau
export type CustomerDef = {
	id: string,
	model: string,
	walkSpeed: number,
	prefersMinRarity: string?,
	tipBonus: number,
	weight: number,
}

return {}
