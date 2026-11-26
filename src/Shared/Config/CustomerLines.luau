-- CustomerLines.luau (ReplicatedStorage.Shared.Config.CustomerLines)
-- Purpose: what customers say in their speech bubbles (CustomerNpcService sets the model attribute "Say"). Plain data: add lines freely.
-- Owner: Dev 1 (Ace). Kept OUT of Config/Customers on purpose: services loop over every entry of that table as a customer type.

return {
	look = { "Hmm…", "Ooh, what's this?", "Let me see…", "Interesting…" },
	buy = { "I'll take it!", "Cute! Sold.", "That's the one!", "Perfect!" },
	think = { "Hmm… let me think about it.", "I'll look around a bit more.", "Not sure yet…" },
	back = { "I changed my mind!", "I keep thinking about this one.", "Okay, I'm back!" },
	hello = { "Hello? Anyone at the till?", "Excuse me!", "Um… I'd like to pay?" },
	gone = { "Never mind, I'll come back another day.", "Too slow for me, bye!" },
	-- haggling: %d = the discount asked, in percent
	haggle = { "Psst… can I get %d%% off?", "Would you do %d%% off for me?", "%d%% off and it's a deal?", "Come on, %d%% off, please?" },
	deal = { "Deal! Thank you!", "Yes! You're the best.", "Pleasure doing business!" },
	grumble = { "Fine… full price then.", "Hmph. Okay, okay.", "You drive a hard bargain." },
	refused = { "Then forget it!", "Too expensive, bye!", "No deal, then. Goodbye." },
	-- critiques, by what put them off
	critique = {
		scratched = { "It's a bit scratched.", "Hmm, it's seen better days.", "Needs more polish, honestly." },
		notWanted = { "Not really what I'm after.", "Pretty, but not what I wanted.", "I was looking for something else." },
		plainShop = { "This shop looks a little… plain.", "I expected more from this place.", "Not many nice things here." },
		pricey = { "A bit pricey for me.", "Hmm, too much.", "I can find it cheaper." },
	},
}
