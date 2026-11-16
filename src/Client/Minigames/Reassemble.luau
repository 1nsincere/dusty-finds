-- Reassemble.luau (StarterPlayerScripts.Client.Minigames.Reassemble)
-- Purpose: Reassemble step (broken parts go back on): tap a loose part, tap its glowing socket. The logic is Socket.luau.
-- Owner: Dev 1 (Ace) for Dev 2's restoration. Depends on: Socket, an item model with Sockets and LooseParts folders.
local Socket = require(script.Parent.Socket)

local Reassemble = {}

function Reassemble.new(model, stepConfig, onProgress, onComplete, fx)
	return Socket.new(model, stepConfig, onProgress, onComplete, fx)
end

return Reassemble
