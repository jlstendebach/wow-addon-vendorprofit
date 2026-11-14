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
  History, Purchase History, Gold). Strata HIGH and toplevel, so it sits above
  the professions window and auction house. A minimum height keeps every side
  tab on the window.
- **Opens and closes only when you do**: `/vprofit` (and its tab commands),
  the title-bar button, its close button. It used to open by itself at the
  auction house, bank and a vendor with an order, and on Queue (switching to
  the Shopping List); now Queue just says so in chat.
- **Closes in combat**: the window template's close button closes through
  HideUIPanel, which the game blocks in combat (it silently did nothing), so
  it's rewired to hide the window directly. The window isn't protected (see
  the secure Open button under Crafting), so that works in combat.
- **Not docked**: it's a window of its own (it used to dock beside the
  auction house, bank, vendor or professions window). It opens centered
  near the top of the screen until you move it, then where you left it,
  held by its top left corner either way (by its center, its edges jumped
  as tabs of different sizes switched), including right after a drag (the
  game leaves a moved window anchored by its center until it's re-anchored,
  so pages changing height grew it at both edges). It's only ever anchored to
  UIParent: anchored to a protected window it would be protected too, and
  hiding it in combat would be blocked.
- **Spacing**: the gap between a page's title, its totals line and its table
  is the same everywhere (about 6px between text lines).
- **Dates** are mm/dd, to save space.
- **Money**: two-digit silver and copper after a larger coin (5s 07c), and
  a zero silver kept between gold and copper (1g 00s 38c): "1g 38c" was
  read as 1g 38s, making a correct 57% ROI look wrong.
- **Row tooltips** (tried at the cursor, at the column's left, at the
  row's end): Shopping List rows put the tooltip above the row at the end of
  the item's name, like a Classic item. History rows put it above the row at
  the top right of the column under the mouse, moving with it across
  columns. Buttons keep the usual ANCHOR_RIGHT.

## Best Crafts

- **Every profession, window closed**: Best Crafts lists the saved recipes of
  every profession you've opened (each is saved when its window opens), ranked
  together: gold is gold whichever profession made it, and the cross-profession
  view is the useful one. A one-profession picker was considered and dropped
  for that. The Filter menu has a Professions section (all ticked at first,
  unticked ones count as filters, the red X ticks them all again); the title
  names the profession when only one is shown. Opening it from a profession's
  title-bar button leaves the ticks alone: the window doesn't change things by
  itself. Live prices are per item; a scan "covers" the professions it looked
  up, for the "Live prices from" line. Ranking 450 recipes takes about 11 ms
  in the test harness, so the ranking isn't cached.
- **Skill-up colors** are only reported for the open profession, so each
  recipe's color is saved when its window is open, and shown for the others
  as of their last opening (possibly out of date). Josh wanted that said: a
  note in the Filter menu under the colors, and a line in a recipe's tooltip
  when its color is a saved one. The menu note is two short lines ("Closed
  professions: / colors as last seen."): the game's menu doesn't wrap and is
  as wide as its widest line, and a one-line note made it far too wide.

- **Columns**: Recipe, Investment, Profit, ROI, AH, Q, then **-** and **+**.
  No rank numbers (they took space and meant little once you sort and
  filter). Clicking a recipe's name shows it in the professions window (only
  while it's open); the magnifying-glass button was removed for that.
  Hovering the name shows the item's Best Sellers figures over all time
  (not Profit History's range, which would be a hidden setting here), with
  profit and both ROIs, placed like an item's tooltip.
- **Q (queued)** went through several tries before a column stuck: "x2" after
  the name (hard to see, and next to + it read as "add 2"), "(2 queued)"
  (too long), a bag icon, a gold row highlight, a centered "Queued"/"#"
  column (looked offset). Final: a narrow right-aligned "Q" column at the row's
  end, a gray dash for none, sortable. **AH** (your auctions of the item)
  works the same way. Both sort every recipe, priced or not, ties keeping the
  profit order. The count columns get a 12px gap so a sort arrow doesn't touch
  the next column.
- **Item info not loaded yet** (the first time a profession's list shows):
  each item is asked for once, and the list redraws once per batch, 0.2s
  after items start arriving (`VendorProfit.RedrawWhenLoaded`, used by every
  list). It used to redraw per arrival and ask again on every redraw, so
  redraws doubled with each missing item (10 items: 1,024 full re-ranks) and
  a big profession froze the game.
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

- **Two Queue buttons**: under the Cheapest Route (along that route), and
  under Auctionator's Vendor Profit line for the exact recipe: its reagents
  only bought (or taken from what you have), never crafted, as Auctionator
  prices it. An exact entry is its own entry (marked "(exact)"), so the same
  recipe can be queued both ways. The exact button folds to nothing when
  hidden (nothing a vendor buys), so the Cheapest Route doesn't move down.
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

- **Items that don't stack** (gear: Green Leather Armor as a reagent) used
  to be listed as "buy yourself". Now they're bought too: the scan reads
  each single auction (with a buyout, not yours; bid-only ones skipped, the
  panel never bids), cheapest each first, and one click buys one auction
  outright with `PlaceBid` at its buyout, as Auctionator does. No Buy and
  Confirm: there's no quote, the buyout is fixed and on the button. Bought
  on the "auction won" notification; failed on an error message. "Item not
  found" (someone else bought it first) drops that auction and Buy goes on
  to the next cheapest without a new scan; any other error scans the item
  again; no reply in 15s says so, and a late win is still recorded.
  Unconfirmed in game: the notification and error events for a buyout on
  Forever (taken from TSM's handling), and whether a search finds suffixed
  versions of an item ("of the Monkey").

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
  (a docked window moving, back when it docked; height change while
  centered; alt-tab display
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
  sold, average profit each, total, Avg ROI, ROI; sortable), a search box
  and a Range menu (all time, last 7/30/90 days, last 50/100/250 sales).
  "Sold to" moved from a column into the tooltip.
- **Two ROIs**: ROI is all the profit over all the cost (the return on the
  money). Avg ROI is each unit's own return on its cost, averaged per unit
  like Avg profit, so a few cheap, very profitable sales show there more
  than in ROI. Avg ROI needs per-sale detail, so the totals keep roiSum and
  roiUnits; saves from before were filled in from the sales list (sales
  already added up by day aren't in it).

## Gold

- **Why it's here**: a graph of your gold over time, like TradeSkillMaster's
  Player Gold, so TSM doesn't have to stay installed just for that. The
  behavior is borrowed (ranges, drag to zoom, hover, green when up and red
  when down); the code and the look are our own.
- **Only the player's gold**, on every character of the account, added up.
  No guild bank, no warbank: not wanted.
- **Saved for the whole account** (`VendorProfitDB`, the addon's only
  account-wide save), so the graph can add characters together. A character
  is recorded from its first login with the addon; before its first point
  it counts at that first value (an untouched alt had that gold all along),
  rather than 0, which would show as a sudden step up when it first logs in.
- **Exact copper, at most one point a minute**: a point is saved when gold
  changes (the last value in a minute wins). TSM rounds to whole gold on
  Forever, which showed a 16s alt as 0. Points older than 90 days are thinned
  to the last one in each hour, far finer than the graph can draw.
- **Stored as a string** per character ("minute:copper;..."), read once when
  needed, written back on logout: much smaller and faster to load than a Lua
  table of thousands of points.
- **Gold the game reports as 0**: right after logging in or a loading
  screen, the game can report 0 for a few seconds, so a 0 then is retried
  every second for 30 seconds before it's believed (TSM does the same).
  While logging out or reloading it reports 0 too (seen on Forever: the
  first version saved a 0 at every /reload), so nothing is recorded between
  leaving the world and entering it again, and logout only saves. A real
  change to 0 is recorded at once.
- **Names on Forever**: `UnitName` is the bare name ("Josten") and the realm
  is "CAMWOW US1 Realm 2 PvP". TSM and Syndicator save other forms
  ("Josten Blackwolf", "PvP"); don't copy their keys.
- **Tab icon**: the Gold Bar's, read with `C_Item.GetItemInfoInstant`, so the
  client is sure to have it: `INV_Misc_Coin_01` drew nothing on Forever.
- **Characters menu**: the Best Crafts Filter pattern: a red panel button
  ("Characters", or "Characters (2 of 7)" while some are hidden), the game's
  menu of checkboxes under it, and the red X beside it to show everyone
  again. Each row is the name (with the realm if you have more than one) and
  that character's gold. Ticks are saved for the account, so a hidden
  character stays hidden on every character; new characters start ticked.
  Nothing ticked: "No characters selected", not a flat line at zero.
- **Range**: a menu like Profit History's (rather than TSM's row of
  buttons, to match the window): last 24 hours, 7 and 30 days, 3 and 6
  months, last year, all time. Saved per character, like Profit History's.
  A range never starts before the first point. Zoom is for the moment:
  changing the range or reopening the tab resets it.
- **The line** is a 2.5-pixel stroke drawn with our own texture that fades
  out across its width (`Media/GraphLine.png`), not snapped to the pixel
  grid: a plain color fill looked jagged next to TSM's, and with snapping on
  a slanted line stair-steps. Green when the stretch shown ends at least as high
  as it starts, red when lower, gold while hovered (as TSM).
- **Hover**, as TSM: a gold guide line, a round dot on the line and the gold
  then above the guide's top, exact to the copper. No tooltip (the first
  version had one, with each character: too busy). The time shows beside the
  page's title.
- **Cost**: the graph is ~145 samples (about one per 3 pixels), drawn again
  only when the logs, ticks, range, zoom or minute changed: the window
  refreshes its open page on every bag and gold change. Measured in the test
  harness with 7 characters and years of heavy play (56,000 points on the
  played one): about 200 ms at login to read and thin it (during the
  loading screen), 70 ms to save at logout, 600 KB saved, 2 ms per redraw.
  Typical logs are a fraction of that.
- **Totals line**: the selected characters' gold now, and the change over
  the last 7 days, like Profit History's line.
- **TSM import, once, by hand**: Josh's TSM gold log (Josten from Nov 5,
  2026, and Slysten) was copied into the account save file. No import
  command: the addon never reads TSM. Only write a save file with WoW fully
  closed: the first attempt was written while it ran, and the file was gone
  by the next save.

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
- **Unconfirmed in game**: the gold graph's drawing (lines, hover, drag to
  zoom), gold read right after login, and that the game says the world is
  being left before logout reports 0 gold; whether stations are reported for
  professions that aren't open; the owned-auctions counts against the Auctions
  tab; tooltip placement and the filter menu position feel.
