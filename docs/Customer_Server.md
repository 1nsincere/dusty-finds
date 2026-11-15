# Customer server (decisions) and how the NPC side plugs in

`src/Server/Services/CustomerService.luau` (owner: Dev 1, agreed with Sean) holds every **decision** of a customer.
`CustomerNpcService.luau` (owner: Dev 3, to be written) does the **visuals**: models from `ServerStorage.NPCs`, walking along
`CustomerPath`, the counter queue, the Checkout prompt, the 8 s auto-checkout, and the wish bubble (`CustomerUIController`).
Tests: `Server/Tests/CustomerCheck.luau` (51 pass).

## Flow for one customer (per shop)
1. **Arrival:** `CustomerService` calls your spawn handler `fn(player, customer)` when `TrySpawn` lets one in (needs one unreserved
   displayed item, room under the cap of 3 / 5 with the Showroom, and the arrival timer). `customer = { id, typeId, wish, ... }`;
   the model is `ServerStorage.NPCs[CustomerTypes[customer.typeId].model]`.
2. **Choose:** `ChooseItem(player, customer.id)` returns `{ uid, itemId, slot, wishMatched }` and reserves the item. Walk to
   `DisplaySlots/Slot<slot>`. `nil, "nothing"` means no item: the customer is removed (reason `"nothing"`), walk out sad.
3. **Pay:** `Checkout(player, customer.id, tapped)`. `tapped = true` when the owner used the Checkout prompt (+10%), `false` for
   the auto checkout after `Economy.AutoCheckoutSeconds`. Pays through `InventoryService.CompleteSale` (wish x1.25, tip chance
   from rating + the type's `tipBonus`), fires `SaleMade`. Returns `ok, reason, { price, bonus, tip, total }`.
4. **Give up:** `Leave(player, customer.id)` (optionally with your own reason string).

## Hooks you register (both optional; nothing happens until a spawn handler exists)
- `SetSpawnHandler(fn(player, customer))`: called in **its own thread**, so your code may yield while walking. If it errors, the
  customer is removed with reason `"spawnFailed"`.
- `SetRemovedHandler(fn(player, customerId, reason))`: called in its own thread whenever a customer is gone, so the model can walk
  out or be destroyed. Reasons: `"paid"`, `"failed"` (Checkout failed), `"left"` (Leave), `"nothing"` (no item to choose),
  `"timeout"` (stuck longer than 90 s), `"playerLeft"` (the shop owner left), `"spawnFailed"`.
  A customer that is already gone is never reported twice, so calling `Leave` from inside the handler is harmless.

## Rules
- Ownership: the Checkout prompt must check that the player who triggers it owns the shop (`PlotService.GetPlot(player)`), and the
  prompt is a `ProximityPrompt` (there is no checkout remote).
- Never work out prices or tips yourself: `Checkout` does it.
- A stuck customer is removed after 90 s (`MAX_CUSTOMER_SECONDS` in `CustomerService`), so a destroyed NPC can't block the cap.
- Add `"CustomerNpcService"` to `ORDER` in `Main.server.luau` **after** `"CustomerService"` in the same branch as the new file.
