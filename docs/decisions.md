# Decisions

Why the addon works the way it does: the choices made while building it, what
was tried and dropped, and what's still open. `README.md` says what each
feature does; this says why. Read it before changing a feature, so a rejected
idea isn't tried again by accident.

Plans not built yet have their own notes: `docs/route-modes.md` (a "Save
time" route mode).

## Look and feel

- **Classic, not "an addon".** Controls match the addon's own style: red
  panel buttons, small icon buttons, gold headings, the game's own menus
  (MenuUtil) for dropdowns. Borrowed game widgets that looked out of place
  (the game's filter dropdown, Scan off on its own) were replaced with the
  addon's own style.
- **One window, pages as side tabs** (Shopping List, Best Crafts, Profit
  History, Purchase History). Strata HIGH and toplevel, so it sits above the
  professions window and auction house. A minimum height keeps every side tab
  on the window. It never closes by itself: only its close button, the
  title-bar button or `/vprofit`.
- **Docks** beside the auction house, bank, vendor or professions window
  (in that order) until you move it; then it opens where you left it.
- **Spacing**: the gap between a page's title, its totals line and its table
  is the same everywhere (about 6px between text lines).
- **Dates** are mm/dd, to save space.
- **Row tooltips** (tried at the cursor, at the column's left, at the
  row's end): Shopping List rows put the tooltip above the row at the end of
  the item's name, like a Classic item. History rows put it above the row at
  the top right of the column under the mouse, moving with it across
  columns. Buttons keep the usual ANCHOR_RIGHT.

## Best Crafts

- **Columns**: Recipe, Investment, Profit, ROI, AH, Q, then **-** and **+**.
  No rank numbers (they took space and meant little once you sort and
  filter). Clicking a recipe's name shows it in the professions window (only
  while it's open); the magnifying-glass button was removed for that.
- **Q (queued)** went through several tries before a column stuck: "x2" after
  the name (hard to see, and next to + it read as "add 2"), "(2 queued)"
  (too long), a bag icon, a gold row highlight, a centered "Queued"/"#"
  column (looked offset). Final: a narrow right-aligned "Q" column at the row's
  end, a gray dash for none, sortable. **AH** (your auctions of the item)
  works the same way. Both sort every recipe, priced or not, ties keeping the
  profit order. The count columns get a 12px gap so a sort arrow doesn't touch
  the next column.
- **AH counts** come from your owned auctions, which the game only lists at
  the auction house: read when it opens and after you post or cancel, saved,
  and shown as of your last visit.
- **Auction tab is the default**: it's what the tab is used for most.
- **Search** filters as you type (no Search button). **Filter** is a red
  button opening the game's checkbox menu under the button (not at the
  mouse); clicking it again closes it. The reset X is grayed out, not hidden,
  when no filters are on. Skill-up colors follow the professions window;
  trivial recipes stay white, not gray.
- **Shift-click + or -** queues or unqueues five (`SHIFT_STEP` in Core.lua).
- **Scan** looks up live prices with one batch request
  (`C_AuctionHouse.SearchForItemKeys`) instead of a search per item.
  **At most 100 items per request: more disconnects you from the server.**
  It was 200 once and kicked the player to the login screen.

## Shopping List

- **Queued rows**: - + and a red X; clicking the name shows the recipe; the
  name is red when neither vendor nor auction makes money; the tooltip shows
  the item's cost and both profits. A profit box was tried and removed.
- **Buy anyway** only appears when neither selling to a vendor nor at
  auction makes money.
- **"Already in your bags"** folds away (remembered per character).
- **Buy before a scan scans first**: a grayed-out Buy pointing at Scan was
  friction. Buy with items queued since the last scan scans just those.

### Buying: what the game allows

- **A price quote (StartCommoditiesPurchase) only works from a click.** Asked
  for in code (after a scan, as a retry), the game ignores it or blocks it
  ("Interface action failed because of an AddOn"). So quotes are never asked
  for by themselves: Buy before a scan scans, then says "Prices are in. Click
  Buy for ...". Confirm (ConfirmCommoditiesPurchase) is a click too.
- **The game is briefly busy after a purchase** and silently drops requests
  sent then. Buy and Confirm are held (grayed, "Waiting a moment...") until
  `IsThrottledMessageSystemReady()`, so a click always counts.
- **A dropped quote** (the throttle's dropped-message event within 1s of
  asking) is reported at once; one that never comes, after 10s. Either way
  the player clicks Buy again.
- Tried and reverted: waiting for the throttle and re-asking for a quote
  automatically, and re-searching the item after 4s. Both moved the request
  out of the click, which made things worse.

### Scanning: sharing the auction house

The auction house is shared with its own Browse tab and other addons
(Auctionator, TradeSkillMaster), which send requests too, especially as it
opens.

- **Browse results are one shared slot.** When another addon's results
  replace the batch lookup's, it's sent again a second later (twice at most)
  instead of waiting out 15s.
- **Dropped searches** (the throttle's dropped-message event) are sent again
  at once instead of waiting out 10s.
- **The server answers at most 100 item searches a minute from all addons
  together**, and drops the rest silently. Every addon's searches are counted
  (hooksecurefunc on SendSearchQuery) and ours wait for room.
- **Items whose info never loads** don't stall a scan (timeouts).
- **Blocked actions** are reported in chat with the function's name, since
  the game's own message doesn't say. Kept on for now while the buying
  fixes prove themselves; may later be limited to blocks blamed on Vendor
  Profit. (A block blamed on Auctionator while cancelling auctions was
  Auctionator's own CancelAuction, not ours.)

## Crafting

- **Opening another profession** needs a secure button. It's a separate
  invisible overlay laid over the Craft button at screen coordinates, never
  anchored to the panel (that would make the panel protected in combat). It
  hides in combat and after a click (until the profession opens or 3s pass).
- **It used to get left behind** when the window moved without redrawing
  (docked window moving, height change while centered, alt-tab display
  changes): clicks hit the plain button and nothing opened. It now follows
  the button (checked every 0.1s), is put back under the mouse on hover, and
  is re-placed on display or UI-scale changes.
- **Which step comes next**: only steps you have the materials for; among
  them one at its crafting station (Anvil, Forge, Cooking Fire) or needing
  none, then ones the game can't vouch for, then the rest. Away from the open
  profession's station with nothing else ready: "Needs Anvil nearby".
  Stations are saved with each recipe. Whether the game reports a station
  for a profession that isn't open is unconfirmed: `/vprofit stations` shows
  what it says.
- **Walking up to a station sends no event**, so while a Craft step is shown
  the panel checks once a second and redraws if the next craft changed.

## Profit and Purchase History

- **Costs follow the items** (first in, first out), so each sale has its own
  cost, not today's prices. Bought items cost exactly what was paid. Your own
  items (farmed, owned before, from an alt) cost their market value when a
  craft uses them: the opportunity cost of not selling them, not free.
- **Auction purchases are read from their mail.** A purchase of more than a
  stack comes as one mail per stack, each with the invoice for the whole
  purchase: price each = invoice total / invoice count, times that mail's
  stack. Taking a mail again before the inbox updates is the same mail
  (double click); after it updates, an identical mail is a new one. (The old
  rule, "identical mails within 10s are a double click", skipped four of
  every five stacks and put the whole price on one: Solid Sharpening Stones
  showed a loss. Josten's saved Solid Stone records were corrected by hand
  on 2026-11-11, backup beside the save file; other multi-stack purchases
  from before the fix still carry inflated costs.)
- **Sales**: vendor sales from the buyback list (buying back undoes a sale);
  auction sales from the "Auction successful" mail when its money is taken
  (sale less the cut).
- **How much is kept**: the last 10,000 sales in full and 5,000 purchases.
  Sales that drop off are added up per item per day, for good, so day ranges
  and Best Sellers reach back indefinitely; every sale is also added up per
  item (all-time totals). Rough costs: 10,000 sales is about 1.2 MB of saved
  data; 50,000+ would slow reloads.
- **Long lists scroll fast**: only the rows on screen are built (about 19)
  and refilled as you scroll; what the list shows is worked out once per
  change (a version counter), item names are cached. Pagination was rejected:
  the data is local, and pages fight search and ranges.
- **Profit History views**: Sales and Best Sellers (one row per item: units
  sold, average profit each, total; sortable), a search box and a Range menu
  (all time, last 7/30/90 days, last 50/100/250 sales). "Sold to" moved from
  a column into the tooltip.

## Vendors

- Buys what the order needs from the vendor you're talking to; pending
  purchases block double clicks.
- **Vendor prices are our own list** (`VendorPrices.lua`), first filled from
  public data, used when Auctionator hasn't seen a vendor sell the item.
  Updated by hand with `/vprofit prices`. Not tied to another addon.

## Releases and workflow

- **Versions come from commit messages** on merge to `main` (feat: minor,
  anything else: patch, `!`: major). Never set by hand.
- **Squash a branch's commits** before a pull request when some describe
  versions that were replaced later (the release notes are the commit
  messages): `git reset --soft origin/main`, one commit, force-with-lease.
- **deploy.bat** (shared, with an optional gitignored `deploy.local.bat` for
  another install folder) and **update.bat** (merge main, fetch tags,
  deploy), both with styled output that says at a glance whether to
  `/reload` or restart WoW.

## Open items

- **Save time route mode**: planned, not built (`docs/route-modes.md`).
- **Blocked-action report**: narrow it once buying has been reliable for a
  while.
- **Unconfirmed in game**: whether stations are reported for professions
  that aren't open; the owned-auctions counts against the Auctions tab;
  tooltip placement and the filter menu position feel.
