-- CustomerPatience.luau
-- Purpose: WP2 wait budgets and presentation copy.
-- Owner: Dev 3 (Sean). Depends on: CustomerType IDs.

return {
	Seconds = { Kid = 54, Grandpa = 135, Collector = 90, Teen = 72 },
	DefaultSeconds = 90,
	PollSeconds = 0.25,
	FidgetingAt = 0.5,
	IrritatedAt = 0.8,
	Complaints = {
		Kid = "Ang tagal naman!",
		Grandpa = "May sandali pa po?",
		Collector = "Ang haba ng hintay.",
		Teen = "Matagal pa ba?",
	},
	DefaultComplaint = "Matagal pa ba?",
}
