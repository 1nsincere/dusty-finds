-- Replace.luau (StarterPlayerScripts.Client.Minigames.Replace)
-- Purpose: Replace step (a missing part): the tray holds the right part plus decoys; picking a decoy costs points. Logic is Socket.luau.
-- Owner: Dev 1 (Ace) for Dev 2's restoration. Depends on: Socket, an item model whose LooseParts folder holds the right part AND the
-- decoys (decoys are simply LooseParts with no matching Sockets entry). The Repair Toolkit L2+ highlight is a visual job for the view.
local Socket = require(script.Parent.Socket)

local Replace = {}

function Replace.new(model, stepConfig, onProgress, onComplete, fx)
	return Socket.new(model, stepConfig, onProgress, onComplete, fx)
end

return Replace
