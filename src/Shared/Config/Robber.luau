-- Robber.luau (ReplicatedStorage.Shared.Config.Robber)
-- Purpose: every number of the night robber (WP8/WP9, docs/14_Robber_Design.md): when they come, how many, what they target,
-- how the owner shoos them and what happens to a stolen item. Config is data: tune here, never in RobberService.
-- Owner: Dev 2 (Dwayne) / Dev 1 (Ace). Depends on: nothing. Read by Server/Services/RobberService and Tests/RobberCheck.
-- Times are REAL seconds (the game clock runs a 30 minute day, so "game minutes" would be far too short).

local Robber = {
	-- When: every EveryNthNight-th night (night N starts at closing time of game day N), a few robbers in total, each at a different shop.
	EveryNthNight = 2,
	RobbersPerNight = { 1, 3 }, -- random per robber night, capped by the number of eligible shops online
	StartDelay = { 20, 150 }, -- seconds after closing before each robber sets off (random each, so they don't arrive together)
	MinLevel = 3, -- never for brand new players (their first sessions)
	MinStealable = 2, -- a shop needs at least this many items on shelves / pedestals (the last item is never taken)

	-- What: weighted pick among items on display. Pedestal ("flex") items attract robbers more than shelf items.
	TargetWeights = { Exhibit = 3, Display = 1 },

	-- The visit
	WarnSeconds = 9, -- the owner's toast comes this long BEFORE the robber starts walking, so there is time to run back
	WalkSpeed = 10, -- slower than a player (16) on purpose: the owner can always catch up
	FleeSpeed = 20, -- running away: faster than walking (16) so the owner must SPRINT (26) to catch up, but never faster than a sprint
	BreachSeconds = 14, -- the shutter stays lifted this long for the robber (HoursService.Breach)
	GrabSeconds = 6, -- how long the robber "works" at the shelf before the item is taken (the chance to catch them red-handed)
	-- Escape: the robber runs to the nearest CANAL bank (canal-level corners of Config/Townsfolk routes, y below CanalMaxY) it can path to.
	-- Candidates are tried nearest first; none reachable (or too long a run) = it runs for the street like before.
	CanalMaxY = 6,
	CanalCandidates = 8,
	CanalMaxRunStuds = 260,
	LeaveGiveUpSeconds = 40, -- an owner-less / stuck robber is removed after this long
	NpcTemplate = "Teen", -- ServerStorage.NPCs.<name> used as the robber's body (first template is used if missing)
	DisplayName = "Sneaky Visitor", -- kid friendly: no "robber" word on screen

	-- Shoo with the walis tambo (a proximity prompt on the robber, owner only)
	ShooHits = 3, -- taps needed
	ShooCooldown = 0.6, -- seconds between taps (a tap faster than this is ignored)
	ShooRange = 12, -- studs (the prompt's MaxActivationDistance; the server rechecks distance)

	-- If the robber escapes with the item: it is "Stolen" (server memory only, nothing saved) and waits at the Tanod post.
	RecoverySeconds = 240,
	LongRecoverySeconds = 420, -- items of LongRarities get a longer window
	LongRarities = { "Epic", "Legendary", "Mythic", "Secret" },
	FeeFraction = 0.15, -- reclaim fee = this fraction of the item's quick-sell price...
	FeeMin = 5, -- ...but never less than this
	Post = {
		Name = "TanodPost",
		Position = Vector3.new(-130, 21, -58), -- plaza (upper level), on the scanned walking line the townsfolk use
		Label = "Tanod: Lost & Found",
	},
}

return Robber
