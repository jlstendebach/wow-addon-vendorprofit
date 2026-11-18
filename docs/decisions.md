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
  History, Purchase History, Gold). A minimum height keeps every side tab on
  the window.
- **Front and back like any window**: MEDIUM strata (the game's windows' and
  most addons') and toplevel, raised when it opens. Clicking it brings it to
  the front; clicking another window (bags, the auction house) brings that
  one in front of it. It used to be HIGH strata, above everything however
  you clicked. (The secure Open button over Craft: see Crafting.)
- **Opens and closes only when you do**: `/vprofit` (and its tab commands),
  the title-bar button, its close button, Escape (it's in UISpecialFrames,
  so Escape closes it along with the game's other windows, as they close;
  in combat too). It used to open by itself at the
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
- **Minimap button**: our own small button (the usual round look, from the
  game's own textures, with the addon's coin icon), not LibDBIcon or another
  library: the addon needs nothing but Auctionator. Click opens or closes the
  window on the last tab; drag moves it around the edge (square minimaps
  too); saved for the account; `/vprofit minimap` hides or shows it.
- **Spacing**: the gap between a page's title, its totals line and its table
  is the same everywhere (about 6px between text lines).
- **Table columns** (Columns.lua) never touch, values or headings. Hand-set
  widths kept failing: money columns sized before coin icons and "00s" were
  counted cut "11g 48s 95c" short, and headings got a sort arrow that ran
  into the next one (patched with wider gaps per column). Now one rule:
  a column is as wide as its heading with a sort arrow (whether or not it's
  sorted) and the widest value in the whole list, measured in the game's
  own fonts; 12px between columns; the name takes the rest, at least 160,
  the window widening if needed. Sized first for fixed worst cases (money
  to -999g 99s 99c, totals to -9,999g): never touched, but left wide empty
  columns for everyday values, so now it's laid out again on each refresh
  for what's listed. Not from the rows on screen (the history lists only
  build those, so columns would jump as you scroll, and measuring 10,000
  sales each refresh is slow): each column's lowest and highest numbers
  are found with arithmetic, and one sample per end is measured, with the
  same coins and digits but all nines (12g 05s 07c sizes as 99g 99s 99c),
  so widths change only when a value gains a digit or a coin. The window's
  right edge can move as the list changes (it's held by its top left); if
  that grates, the fix is growing only until the window closes.
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

- **Professions button** (left of Scan): made to be clicked again and
  again, opening each of your professions in turn and closing the window
  with the last click, so every profession's recipes and skill-up colors
  are saved. Opening goes through the same secure cover as the Shopping
  List's Open button (an addon can only open a profession by casting its
  spell from a secure button); closing is C_TradeSkillUI.CloseTradeSkill,
  which needs no secure button (TradeSkillMaster closes it the same way on
  Forever). After each click it waits until that profession is open *and
  saved* before the next click counts, so fast clicking can't skip one
  (3s, then the same one can be tried again). The open profession is
  skipped (its spell would close it). Professions come from GetProfessions,
  without the skill lines that have no window (Herbalism, Skinning,
  Archaeology). Fishing is included: Forever gives it a crafting window
  (Camping), opened by casting Bait and Tackle (1278067), its first
  spellbook entry; "Fishing" (7731) casts a line. Seen in game with a /run
  of Fishing's spellbook entries, and confirmed in game (2026-11-16): the
  button opens Fishing's window. A 1s rest after closing, so the click after Close
  doesn't open the first profession again.
- **Minimum profit and ROI** are boxes on their own row under the search,
  not Filter menu entries: they take exact amounts, and typing in the
  game's menus is fiddly (they close when they lose focus). Presets plus a
  "Custom..." popup in the menu were offered and turned down for that
  reason. First tried on a row under the search with the game's own money
  input (the auction house's gold/silver/copper boxes, coins inside): it
  didn't look good; then plain boxes with units after them, cramped. Now a
  row under the list, above the notes: number boxes made like the search
  box (same template, height, font, text from the left, the same 14px gap
  as the search box beside the Vendor tab), each unit inside at the right
  (a small coin icon or %) with the text inset short of it, showing 0,
  which is no minimum (a box left empty goes back to 0). Boxes only as
  wide as their digits need (gold and ROI up to 4 digits), nearly
  touching; the row is the window's bottom line with the notes just above
  it (swapped from notes-last), both held at the bottom, so
  they stay there when the window is taller than the list needs. Applied as you type; ROI compared as shown (whole
  percent); unpriced recipes hidden while either is set; the red X clears
  them with the filters. Confirmed working in game (2026-11-16).
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

- **Resizable height** (2026-11-18): a size grip (the chat frame's) in the
  bottom right corner sets how many rows the list shows, whole rows only
  (no row cut off), height only (the width follows the columns). Dragging
  works the rows out from how far the mouse moved, not the game's frame
  sizing (StartSizing), which would fight the height Panel.Refresh sets.
  Fewest rows: enough for the side tabs (Panel.MinHeight); most: down to
  the bottom of the screen. The list is now always that tall, even with
  fewer recipes (it used to shrink to fit, up to 14): a window you sized
  shouldn't jump as you search or filter, and the grip shouldn't move out
  from under the mouse. It always leaves room for the favorites' divider
  gap, so starring something doesn't change the height either.
- **Favorites** (2026-11-18): a star before the name. First in a column of
  its own (a column gap before the names, out past the heading): it looked
  misaligned. Then by the - and + buttons: Josh preferred it on the left.
  Now it's the first thing in the name column, where the "Recipe" heading
  starts, 4px before the name and centered on its line; every name is
  indented by the star's room whether its star shows or not, so the rows
  line up. At 14px it looked off-center next to the item icon, so it's
  the icon's size: the font's height (an inline |T:0|t icon's), in the
  atlas's own shape. A gold line (the Shopping List divider's color)
  between the favorites and the rest, only while there are both. Drawn on
  the boundary between two rows it sat closer to one than the other, so
  the rows after it move down 7px: with the 2px a row's buttons leave
  free, that's 4px, the line, 4px. Favorites are listed
  first, each group (favorites, then the rest) sorted by the chosen column,
  unpriced favorites after priced ones but above everything else. A bare
  star, not a red icon button: a third button on every row next to - and +
  was too much. Empty stars show only while the mouse is on the row, faded
  (as TradeSkillMaster's crafting list does), so the list isn't 14 rows of
  outlines; a favorite's star always shows. The texture is the auction
  house's favorite star atlas (`auctionhouse-icon-favorite`), desaturated
  when off; the star raid marker if the client lacks that atlas. Saved per
  character by recipe ID (`bestFavorites`), like the filters. Filters and
  search still apply: favorites go first, they aren't exempt.
- **Columns**: Recipe (the favorite star first), Investment, Profit, ROI,
  7d, AH, Q, then **-** and **+**.
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
  profit order.
- **Hot crafts** (2026-11-17): Best Crafts showed profit at today's prices
  but nothing about what actually sells. Josh asked for a "this item is
  HOT" indicator from a rolling average. Chosen, after trying rules against
  his real history (664 sales over ~10 days on Josten): **heat** = each
  auction sale's profit, weight halving every 7 days, added up per item;
  **hot** = top fifth (rounded up) of items with positive heat that also
  sold 2+ at auction in the last 7 days. Why each part:
  - Exponential decay, not a fixed window: nothing falls off a cliff on
    day 8, and recent sales count most. 7-day half-life: shorter made one
    lucky day hot; longer was slow to notice a new seller.
  - Profit, not units: units made Solid Sharpening Stones (hundreds sold
    at ~2c profit) the hottest thing; profit is what the tab ranks by.
  - Auction sales only: a vendor buys anything, so vendor sales say
    nothing about demand.
  - Relative (top fifth of your own sellers), not a gold threshold: works
    for small and big sellers alike, with nothing to set.
  - At least 2 sold this week: without it a single big sale (a 20g
    Dragonling) made an item hot.
  The marker is the count in a new **7d** column (units sold at auction in
  the last 7 days), in orange for hot ones, not next to the name: names are
  cut short to fit, so a marker after them could be cut off, and two icons
  before the name looked cluttered. A flame icon (Fireball's, before the
  count) was tried first and dropped: Josh found it distracting. Orange
  (the game's legendary color) rather than a row highlight: it marks the
  number without competing with the skill-up colors on the names. The tooltip gives the week's count and profit a day lately
  (heat x ln 2 / 7, the rate that would give that heat if steady). A "Hot
  only" filter. Worked out from the history, cached until it changes (and
  hourly, as sales age). Sales past 8 half-lives (under 1/256 weight) aren't
  read; ones rolled up into daily totals count their day's auction share.
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
- **To do's items scroll**: a big order made the window run off the
  screen. The steps (with counts and buttons) and the next craft stay at
  the top; their items scroll in a box under them, at most 12 rows, on a
  darker background with 6px of padding. The
  buttons stay out of the box so they never scroll: the secure Open
  Profession cover has to sit exactly on its button, which a scrolled-
  away button would break. A single "next step" button instead was
  weighed and turned down: steps happen in different places (auction
  house, bank, a forge), so it would hide the one you need where you are.
  When a step finishes, the next moves up into its place, so clicks stay
  in one spot; a step that just moved into the place of one that's gone
  ignores clicks for 0.5s (and the cover waits as long), so a click meant
  for the finished step doesn't buy, take or craft by accident. Steps that
  only shifted (a line added above) aren't held. Folding To do now folds
  only the box, so Buy and Craft never disappear.
- **Every section folds away**: Queued, Profit, To do and Already in your
  bags are all dividers (title between lines, a plus or minus sign) that
  fold on a click, remembered per character, a folded one saying how many
  rows it holds. (Queued and Profit used to be plain headings; only the
  bags folded, saved as bagsCollapsed, carried over.) Scan, which sat on
  the Profit heading, moved to the page's title line ("Shopping List"),
  where Best Crafts has its Scan: it's for the whole order, and stays
  reachable with every section folded. With To do folded there's no Craft
  button, so the open-profession cover goes too (it's only ever over a
  Craft button that's shown).
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
- **Only from the latest search**: the first try said "not found" for every
  auction and bought nothing. The auction house only sells an auction from
  the latest item search, anyone's, and the scan had searched other items
  since (TradeSkillMaster searches the item again before every buy for
  this reason). Every search is watched (a hook on SendSearchQuery); when
  the latest isn't the item's, Buy searches it again first and says so,
  and the next click buys. Buying several of one item in a row needs no
  new search. Confirmed in game (2026-11-16): gear is bought, and the
  "won" notification records it.
  Unconfirmed in game: whether a search finds suffixed versions of an item
  ("of the Monkey").

- **A scan outlives the auction house, for an hour**: Mithril Casing with
  nothing listed was planned as crafted at the auction house (right), but
  closing it wiped the scan, so the plan went back to Auctionator's last
  price and put it on the Buy list again, and at the auction house it
  "disappeared without buying". Now the scan's listings and batch prices
  are kept after closing for KEEP_SCAN (1 hour), until the next scan
  replaces them; after that, Auctionator's prices again. And when a scan
  drops something from the Buy list for having nothing listed, the panel
  says so.

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

- **Only professions you still have**: a dropped profession (Mining
  unlearned) kept its saved recipes and routes went on smelting bars you
  could no longer make, so the "cheapest" route wasn't one you could
  follow. Now routes, Best Crafts and the route tooltip use only saved
  professions the game lists for you (GetProfessions, by skill line or
  name), re-checked on login and when skills change (SKILL_LINES_CHANGED).
  The saved recipes are kept, not deleted: they count again if it's learned
  again. Just after logging in the game lists no professions yet, so while
  it lists none every saved one counts (a character with no professions at
  all is the one case this can't tell apart). Confirmed in game
  (2026-11-16): Josten's dropped Mining no longer shows or counts.

- **Opening another profession** needs a secure button. It's a separate
  invisible overlay laid over the Craft button at screen coordinates, never
  anchored to the panel (that would make the panel protected in combat). It's
  there only while the mouse is on the Craft button, in DIALOG strata above
  every window. It used to sit in the panel's strata, just above the Craft
  button by frame level, so a window in front of the panel would cover it:
  but once the panel was raised to the front (on opening, or a click), it
  ended up under the Craft button, and clicks hit the plain button and
  opened nothing. Above everything but only under the mouse, it's on top
  however the window was raised, and it can't open a profession through
  another window over the panel, since the mouse never reaches the Craft
  button there. It hides in combat and after a click (until the profession
  opens or 3s pass).
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
- **Vendor prices are recorded per character**: a vendor with a reputation
  discount sold Heavy Stock and Strong Flux for 18s, under both the usual
  20s and the auction house's ~19s 45c, but the plan still said "auction"
  (it only knew the usual 20s, from Auctionator and the list). Opening a
  merchant now records its gold prices for items without a stock limit
  (per one, batches divided out), keeping the cheapest seen, per character
  since reputation is. Recorded prices come first in GetBuyPrices
  (everywhere), then Auctionator's, then the list. Tried first: using the
  open vendor's prices only while its window was open; dropped, since the
  price should be known before you get there and after you leave.

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
  tab; tooltip placement and the filter menu position feel; that a hidden
  font string measures text (Columns.lua) as a shown one does.
