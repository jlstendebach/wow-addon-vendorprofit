# Vendor Profit for Auctionator

An addon for World of Warcraft: Forever that adds to Auctionator's crafting info in the professions window, leaving Auctionator's own **To Craft** and **Profit** lines as they are:

```
To Craft: 12s 39c                  <- Auctionator
Profit: -6s                        <- Auctionator: sell on the auction house
Vendor Profit: -10s 92c            <- sell to a vendor instead
------------ Cheapest Route ------------
To Craft: 4s 38c         [Search]  <- crafting reagents yourself where that's cheaper
Profit: 7s 97c                     <- ...sold on the auction house
Vendor Profit: -2s 91c             <- ...sold to a vendor
[Queue]
```

- **Vendor Profit:** what you make by crafting the item and selling it to a vendor, at Auctionator's To Craft cost.
- **Cheapest Route:** the same three numbers when every reagent is got the cheapest way, crafting reagents yourself where that's cheaper than buying them, all the way down. Hover the section to see the route.
- **Search** (at the auction house) looks up live prices for every item in the crafting tree in one request.
- **Vendor Profit** in the professions window's title bar opens the Vendor Profit window on its **Best Crafts** tab: every recipe of the profession, most profitable first.
- **Queue** adds the recipe to a shopping order. The window's **Shopping List** tab then plans it with what you already have, scans the auction house, checks the order is still profitable at live prices, buys what's missing one confirmed purchase at a time, and crafts the steps in order.

Requires [Auctionator](https://www.curseforge.com/wow/addons/auctionator).

> **Unofficial.** Vendor Profit for Auctionator is an independent addon. It is not made, endorsed or supported by Auctionator or its authors. Please report problems with it here, not to Auctionator.

## Install

Download the latest `VendorProfit-<version>.zip` from the repository's **Releases** and unzip it into `World of Warcraft\_forever_\Interface\AddOns\`. Or copy the `VendorProfit` folder there yourself. Everything in it is the addon. Everything outside it (this README, `tests/`, `scripts/`, `.github/`) is for development only.

```
wow-addon-vendorprofit/
    VendorProfit/     <- the addon; copy this folder as-is
    tests/            <- stubbed-client tests
    scripts/          <- release versioning and version stamping
    .github/          <- the test and release workflows
    README.md
```

The folder must stay named `VendorProfit` to match `VendorProfit.toc`.

For development, a local `deploy.bat` (kept out of git, since its paths are machine-specific) mirrors the folder into AddOns. Run it, then `/reload` in game, or restart WoW if files were added or removed.

## Vendor Profit

**Vendor Profit = vendor sell price x number made - cost to craft**

- **Vendor sell price** comes from the game's item info, so it's always known. Bind-on-pickup results count too, since vendors buy those.
- **Number made** is the recipe's guaranteed minimum, the same count Auctionator's Profit line uses.
- **Cost to craft** is Auctionator's own figure, the one on the To Craft line. Auctionator prices each reagent at what a vendor sells it for (if it has seen that item at a vendor) or else at its last auction scan price.
- There's no auction house cut, since nothing is listed.

What the line shows:

- **White:** a profit. **Red with a minus:** a loss.
- **(missing reagent prices)** in red: Auctionator has no price for at least one required reagent and counts it as free, so the real profit is lower. Scan the auction house, or visit the vendor that sells it.
- **can't be sold to vendors** in grey: the item has no vendor price.
- No line: the recipe doesn't make an item (enchants, for example), or Auctionator's crafting info is hidden.

## Cheapest Route

Auctionator prices a Bronze Bar at what a Bronze Bar costs. This section also checks whether smelting it from Copper and Tin Bars is cheaper, and whether those bars are cheaper to smelt from ore, and takes the cheapest option at every step.

For each reagent, the cheapest of:

- **buy (vendor):** what a vendor sells it for, if Auctionator has seen it at a vendor
- **buy (auction):** its auction price from Auctionator's last scan
- **craft:** one of your recipes, its reagents priced the same way

- **To Craft** = the route's cost for one craft
- **Profit** = auction price x number made x 0.95 (the auction house cut) - route cost
- **Vendor Profit** = vendor sell price x number made - route cost

Profit uses Auctionator's auction price for the crafted item, like Auctionator's own Profit line, but isn't rounded down to the silver. **(missing reagent prices)** after To Craft means something on the route has no price and is counted as free.

**Your recipes.** The game only shares recipe details for the profession window that's open, so the addon saves each profession's learned recipes when you open it, per character. **Open each of your professions once** (Smelting included) so routes can use them. Until then, those reagents can only be bought. The tooltip lists which professions are saved. Each window updates its saved recipes whenever you open it.

**The tooltip** (hover anywhere on the section) shows the route as a tree. Each crafted item has what goes into it indented under it, with where to get it and what it costs. Below the tree: Auctionator's To Craft cost and how much the route saves.

```
Cheapest Route
Rough Bronze Cuirass x1                                  4s 38c
    Bronze Bar x7      craft (Mining, makes 2)           4s 38c   saves 8s 1c
        Copper Bar x3.5    craft (Mining)                1s 75c   saves 70c
            Copper Ore x3.5    buy (auction)             1s 75c
        Tin Bar x3.5       buy (auction)                 2s 63c
```

**Search.** At the auction house, **Search** at the top right of the section (where Auctionator puts its own) looks up live lowest prices for every item in the crafting tree: the item, its reagents, and everything your saved recipes could make them from, including options the current route doesn't use, since any of those prices can change it. Items that bind on pickup are left out. It's the same batch lookup as Best Crafts' Scan: one request for the whole tree instead of a search per item, so it takes about a second. Auctionator saves the lowest price of anything the lookup returns (browse results, which it records while the auction house is open), so the section updates from what it finds. **Shift-click** runs Auctionator's own search for every item instead, when you want to see the listings.

**saves** on a crafted step is how much crafting it saves over buying that many outright, with everything under it done the cheapest way. It's what skipping that step would cost: here, buying Copper Bars instead of smelting them costs 70c more per cuirass. Steps that can't be bought show no saving.

How costs are worked out:

- **Per item, averaged over what a craft makes.** A smelt that makes 2 Bronze Bars from 1 Copper Bar and 1 Tin Bar costs half of that per bar, so 7 bars show 3.5 of each. In practice you'd smelt 4 times and keep a spare bar, which the cost treats as worth what it cost to make.
- **A complete price beats a cheaper one with a gap.** A route that counts a reagent as free (no price anywhere) is only used when nothing else has a price, and then the line warns with **(missing reagent prices)**.
- If vendors won't buy the item, the line says **can't be sold to vendors**, and the tooltip still shows the route and its cost.
- **Loops are skipped.** An item is never made from itself, such as a Greater Essence made from Lesser Essences made from a Greater Essence.
- On a tie, buying wins over crafting.

What it can't know:

- **How many are listed.** Auctionator keeps the lowest auction price, not how many are up at that price, so buying a lot can cost more.
- **What you already have.** Reagents in your bags are priced at their market value, since you could sell them instead.
- **Recipes in professions you haven't opened** on this character, or on your other characters.

**Money** is shown with silver and copper always two digits after a larger coin, like a clock: **5s 07c**, so it can't be misread as 5s 70c. That's everywhere this addon shows money; Auctionator's own lines are left as they are.

## Best Crafts

The **Vendor Profit** button in the professions window's title bar (left of TradeSkillMaster's, if you have it), or `/vprofit best`, opens the Vendor Profit window on its **Best Crafts** tab: every saved recipe of the open profession, ranked by profit per craft, each along its cheapest route. The list shows 14 at a time and scrolls for the rest. Clicking it again closes the window. Closing the professions window leaves it open, still listing that profession, so you can scan and queue at the auction house without it.

```
Best Crafts: Blacksmithing
[ Vendor ] [ Auction ]  [🔍 Search      ]                  [ Scan ]
Recipe                     Investment    Profit▼    ROI
1. Rough Bronze Cuirass        4s 38c    1s 62c     37%   [+] [🔍]
2. Rough Bronze Shoulders      3s 13c       87c     28%   [+] [🔍]
3. Copper Chain Vest           3s 60c   -2s 10c    -58%   [+] [🔍]
-  Mystery Helm             no price: Strange Ore         [+] [🔍]
Prices from Auctionator's last scan.
```

- **Investment** is what one craft's items cost along its cheapest route: what you'd spend, counting items you already have at what they'd cost to get. **Profit** is what one craft makes after that, and **ROI** (return on investment) is the profit as a share of the investment. The tab is wider than the Shopping List to fit them.
- **Search.** Type in the search box to filter the list by recipe name as you type (any case); recipes keep their place number in the full ranking. Clear it to see everything.
- **Sorting.** Click a column's heading to sort by it (highest first; Recipe A to Z); click it again to reverse. The sorted column is in white with an arrow, numbers follow the sort, and recipes with no profit to rank stay at the bottom. The sort is saved per character. By default it's by Profit.
- **Vendor** ranks by selling to a vendor, a guaranteed sale. **Auction** ranks by Auctionator's price after the 5% cut; usually higher, but an auction might not sell.
- Losses are listed too (in red), below the crafts that make money. Recipes with no profit to rank by come last, unnumbered, saying why: a reagent with no price anywhere (*no price: Strange Ore*, so their profit can't be trusted), or no vendor (or auction) price for what they make.
- The **magnifying glass** selects the recipe in the professions window (it's off while that window is closed). **+** adds one craft to the shopping order (click again for more); the window stays on Best Crafts.
- It ranks straight away from Auctionator's prices. At the auction house, **Scan** looks up live lowest prices for everything that matters to the profession: every recipe's crafting tree, merged into one list of unique items, looked up a couple of hundred at a time with the auction house's batch lookup (the one it uses for favorites) rather than one search per item. It takes seconds. Items with nothing listed count as unavailable until the next scan, and Auctionator saves the prices it sees too. Items that bind on pickup aren't looked up.

## Shopping

**1. Queue.** Set the number in the professions window's Create box (say 10) and click **Queue** under the Cheapest Route section's Vendor Profit line. Queuing a recipe already in the order adds to it. The Vendor Profit window opens on its Shopping List tab (switching to it if the window was on Best Crafts); `/vprofit` toggles it any time.

**2. The plan.** The panel works out, in whole numbers, what the order needs, using what you already have (bags and bank) first:

```
10 Rough Bronze Cuirasses need 70 Bronze Bars. You have 12, so 58 to make: 29 smelts.
29 smelts need 29 Copper Bars (you have 5, so 24 to smelt from 24 Copper Ore) and 29 Tin Bars.
```

The panel is laid out as:

```
Queued
    Rough Bronze Cuirass x10                 [-] [+] [x]
Profit                                       [ Scan ]
    Vendor price                             60s
    Auction price                            1g 23s 50c

    Items you have                           -10s
    Items to buy                             -33s 75c

    Vendor profit                            16s 25c
    Auction profit                           79s 75c
──────────────── To do ────────────────
1. Buy                                       [ Buy ]
    Copper Ore x24             auction       12s 70c
    Tin Bar x29                auction       21s 75c
2. Take from bank                            [ Take ]
    Copper Bar x2
3. Craft                                     [ Craft ]
  » Copper Bar x24       Mining, 24 crafts
    Bronze Bar x58       Mining, 29 crafts
    Rough Bronze Cuirass x10   Blacksmithing, 10 crafts
────────── [-] Already in your bags ──────────
    Bronze Bar x12
    Copper Bar x3
```

**To do** is a checklist in the order you'd do it: **Buy** first (prices are what can change, so you find out at the auction house before fetching or crafting anything), **Collect from mailbox** (purchases not collected yet), **Take from bank**, then **Craft**. Each step shows only while it has something left in it and they're numbered in order, so the list gets shorter as you go. Every button sits on its section's heading, with a short label; hover one for the details. There's no button bar at the bottom. Your items are used from your bags first, then the mailbox, then the bank, so **Take from bank** lists exactly what to fetch. Bags include the reagent bank, since crafting uses it directly. **Already in your bags** is just for information; click its divider to fold it away (it then shows how many items it holds) or open it again. That's remembered per character. Several queued recipes share your items, so nothing is counted twice.

**Take from bank.** At the bank, **Take** on the **Take from bank** step moves exactly those amounts into your bags: it splits them off the bank's stacks (smallest stacks first) into empty bag slots, one move at a time, waiting for each to finish. If something isn't in the bank after all, or your bags fill up, or the bank closes, it stops and says so. The window opens beside the bank by itself when the order has something to fetch.

**Profit** is three small groups: what everything still queued sells for (**Vendor price**, and **Auction price**: Auctionator's price after the 5% auction house cut, so it's what you'd actually get, or *no auction price*), what it costs (**Items you have**, what the items you have are worth, and **Items to buy**), and what finishing the order makes from where you stand (**Vendor profit** and **Auction profit**: each price minus both costs). Buying checks Vendor profit. Items you have count at the cheapest way to get them now, whether you had them already or bought them for this order. What you've paid is spent either way, so it doesn't change whether finishing is worth it. It's shown below the profits as **Spent on this order so far**, but not taken off. That way an order you've partly shopped for and crafted gives the same answer as clearing it and queuing what's left.

**Crafting counts the order down.** Each time you craft a queued recipe, its count drops by one, and the order finishes when everything queued is made. Reagents you craft with leave your bags, so the plan always works from what's actually left.

The buttons for each part sit on their section's heading, with short labels; hover one for the details.

**3. Scan.** At the auction house the panel docks beside it (and opens by itself when something is queued). **Scan** on the **Profit** heading first looks up every item in the order's crafting trees in one batch request (the same lookup as Best Crafts' Scan), so the order is planned with live prices straight away and items with nothing listed are skipped, not searched. Then it reads every listing of each item the order buys there, so buying 24 is priced by walking up the cheapest listings, not at the lowest single price, and your own listings are left out. Those listings are what purchases are priced and checked against. With them the order is planned again: if crafting something has become cheaper than buying it, or the other way round, the plan changes and the new items are scanned too.

**4. Buy.** **Buy** on the **Buy** step works before a scan too: it scans first, then goes straight on to the first purchase (stopping at **Buy anyway** if neither selling to a vendor nor at auction would make money). Once scanned, **Buy** (away from the auction house it says **Open AH**; hover it: *Buy 24 Copper Ore for 12s 70c*) asks the auction house for a price quote. If the quote is no more than the scan, the button becomes **Confirm**, with *Confirm: 24 Copper Ore for 12s 70c* and a **Cancel** button shown right under the step, and clicking Confirm buys. That's two clicks per item, the same as Auctionator's own buying: the game only allows a purchase as part of a click. **Scan** again any time to refresh prices.

- **Price went up:** if the quote is higher than the scan (someone bought the cheap ones first), the purchase is cancelled and the item scanned again.
- **Not profitable:** before each purchase, finishing the order must still make money one way or the other at current prices: selling to a vendor or at auction. If neither does, the button says **Buy anyway**, with a message saying so: clicking it is your go-ahead, until the next scan. If only one of them loses money, buying goes ahead, and that one shows in red under Profit.
- **Not enough listed:** it buys what's there and says how many are missing.
- **Not enough gold, no reply, a failed purchase:** nothing is recorded, the panel says what happened, and the item is scanned again. A purchase that gets no reply but goes through later is still recorded when the success arrives.
- **Items that don't stack** (gear and the like) are listed as **buy yourself**: the panel only buys stackable items.

**Vendors.** Vendor prices come from Auctionator, which records them when you open the window of a vendor that sells the item. Until it has, the addon uses the item's usual vendor price from its own list (`VendorPrices.lua`), so a new install doesn't plan Coarse Thread from the auction house just because you haven't visited a trade-goods vendor yet. Auctionator's recorded price always wins.

The list is maintained here, by hand: one item per line, `[itemID] = copper for one,`. To update it, talk to a vendor and type `/vprofit prices`: a box lists that vendor's prices in the same format, sorted, marking items that are new or whose price differs from the list. Copy the lines you want (Ctrl+C) into `VendorPrices.lua`.

Items the plan gets from a vendor (Weak Flux, thread, vials) are bought at a vendor. Talk to one that sells any of them and the window opens beside it, with **Buy** on the **Buy** step (hover it: *Buy from this vendor: 3 Weak Flux, for 2s 70c*). One click buys all of it: exactly what's needed, or whole batches for items sold several at a time, and only for gold. It also buys anything planned from the auction house that this vendor sells for no more. If you run short of gold it buys what it can and says what's missing. After a purchase, the button shows **Buying...** until the items reach your bags (or 10 seconds pass), so a double click can't buy twice. Away from vendors, with only vendor items left, the button is off and says to find a vendor.

**5. Craft.** **Craft** on the **Craft** step crafts the step marked **»**, as many times as it needs (up to what you have materials for; hover it: *Craft Copper Bar, 7 times*). The game only crafts recipes of the profession window that's open, so when the next step is in another profession the button says **Open Mining**, and clicking it opens that profession (Mining opens with Smelting). Once clicked it shows **Opening...** until the profession has loaded, so a second click can't close the window it's opening; if nothing opens within a few seconds, it's clickable again. In combat it can't be clicked (hover: *Open Mining after combat*): the game doesn't let addons open professions then. It skips ahead to a later step the open window can make if you have its materials, is off with *Missing materials for ...* when you don't, and says **Crafting...** while you're casting. Materials are counted from your bags and reagent bank, which is what crafting can use; items in the main bank don't count until you take them out. Crafting the queued item counts the order down as usual.

**Mail.** Auction purchases may arrive in your mailbox rather than your bags. A purchase counts as **in the mail** until that many more of the item show up in your bags or bank, so it's counted either way and never bought twice. Opening the mailbox corrects that from what's actually in the inbox, so a purchase that arrived without the panel seeing it (say you used it up as it arrived) stops counting.

**The window.** The Shopping List and Best Crafts are tabs down the right side of one Vendor Profit window. Drag it anywhere. From then on it opens where you left it (saved per character). It opens with the auction house when something is queued (on the Shopping List, unless it's already open on another tab), but only ever closes when you close it (its close button, the title-bar button, or `/vprofit`). `/vprofit reset` docks it beside the auction house or professions window again.

The order is saved per character. Each queued recipe has three small buttons: **-** and **+** craft one fewer or one more (at least one), and **x** takes it out of the order; removing the last one empties the order and its record. Hover a queued recipe to see its own cost along the cheapest route and its vendor and auction profit at today's prices; click it to show its recipe in the professions window (when that window is open). Its name is red when neither would make money.

**Vendor profit** and **Auction profit** are red, label and all, when they're a loss.

## Profit History

The window's **Profit History** tab (or `/vprofit history`) lists every sale of something you crafted, newest first: the date, the item, whether it sold to a vendor or at auction, what it cost you, what it sold for and the profit. Totals for everything and for the last 7 days are at the top. Hover a sale to see its cost split into what you bought and your own items.

```
Profit History
Profit: 2s 80c from 3 sales. Last 7 days: 2s 80c.
Date    Item          Sold to     Cost   Sold for    Profit
Nov 08  Test Ring     Vendor       50c         2s    1s 50c
Nov 08  Test Ring     Auction   1s 50c     1s 80c       30c
Nov 07  Test Ring     Vendor        1s         2s        1s
```

Costs follow the items, so each sale has its own cost, not today's prices:

- **Bought** items cost exactly what you paid. Auction house purchases are read from their mail when you take the item out of the mailbox, however you bought them; vendor purchases when you buy, from any vendor.
- **Your own** items (farmed, owned before installing, from an alt or a trade) cost their market value at the moment a craft uses them: the cheapest way to get one right then, which is what using it instead of selling it cost you.
- **Crafted** items cost what their reagents cost, used up oldest first. Bars smelted from bought ore carry the ore's exact cost into whatever they make.

Sales use up the item's costs oldest first. Vendor sales are read from the vendor's buyback list, with the exact price; buying something back undoes its sale. Auction sales are read from the "Auction successful" mail when you take its money: the sale price less the auction house's cut (the deposit comes back with it, so it cancels out). So an auction sale only shows up once you've collected it.

- Only crafts made since installing are tracked. Selling something made before that leaves it out rather than inventing a cost.
- Bought reagents that leave some other way (mailed to an alt, destroyed) stop counting once you no longer have them. Crafted items out of your bags keep counting, since they may be up for auction.
- The last 500 sales are kept, per character.

## Purchase History

The **Purchase History** tab (or `/vprofit purchases`) lists your last 500 purchases, newest first, for a gut check: the date, the item and how many, whether it came from the auction house or a vendor, what you paid **each** and in **total**, and what one costs **now** (the cheaper of the vendor and auction prices). Hover a purchase for the exact time.

Vendor purchases show up straight away, from any vendor. Auction house purchases show up when you take them out of the mailbox, read from their mail, however you bought them. These are the same purchases whose costs feed the Profit History.

## How it works

- Auctionator makes its crafting info frame (`AuctionatorCraftingInfoProfessionsFrame`) the first time the professions window opens. The addon hooks the function that makes it, attaches right after, and retries on the next frame in case it sees the event first.
- It adds its lines to that frame, anchored under Auctionator's text, so they show and hide with Auctionator's lines. A mouse-enabled frame over the Cheapest Route section shows its tooltip.
- It post-hooks the frame's `UpdateTotal`, which Auctionator calls whenever the recipe, reagents or prices change, and refreshes right after. Saving a profession's recipes refreshes too.
- Prices come from Auctionator's public API (`Auctionator.API.v1`). Vendor Profit's cost to craft calls `Auctionator.CraftingInfo.CalculateCraftCost` so it matches To Craft exactly, with its own reagent total as a fallback.
- It only reads from Auctionator. It never changes Auctionator's text, settings or data, and an error in this addon is reported without breaking Auctionator's refresh.
- Recipes are read with `C_TradeSkillUI` when your own profession window is ready. Linked, guild and NPC crafting windows aren't saved. If the game can't list every recipe at once, the window's (possibly filtered) list is added to what's saved instead of replacing it.

Files:

| File | What it does |
| --- | --- |
| `Core.lua` | Prices, working out the shown recipe, attaching to Auctionator's frame |
| `VendorPrices.lua` | Usual vendor prices, for items Auctionator hasn't seen a vendor sell yet; updated with `/vprofit prices` |
| `VendorLine.lua` | The Vendor Profit line |
| `Recipes.lua` | Saving and looking up this character's recipes |
| `Route.lua` | Finding the cheapest route |
| `RouteSection.lua` | The Cheapest Route section and its tooltip |
| `Inventory.lua` | Counting what you have in bags and bank |
| `Plan.lua` | Turning queued crafts into what to buy and craft, in whole numbers |
| `Order.lua` | The saved order: what's in the mail, what was spent, counting crafts down |
| `QueueButton.lua` | The Queue button |
| `Shopper.lua` | Scanning the auction house, live pricing, quotes and purchases |
| `SearchButton.lua` | The Search button: the whole crafting tree in Auctionator |
| `Crafter.lua` | The Craft button: the next step the open profession can make |
| `OpenButton.lua` | Opening another profession from the Craft button |
| `Banker.lua` | Take from bank: moving exactly what's needed into your bags |
| `Merchant.lua` | Buying what the order needs from the vendor you're talking to |
| `Panel.lua` | The Vendor Profit window and its tabs, the Shopping List tab, moving it, and `/vprofit` |
| `BestCrafts.lua` | Ranking a profession's recipes, and the batch price lookup |
| `BestPanel.lua` | The Best Crafts tab, and the button in the professions window's title bar |
| `History.lua` | Profit history: what items cost you as they come in, and their sales |
| `HistoryPanel.lua` | The Profit History tab |
| `PurchasePanel.lua` | The Purchase History tab |

Saved data, per character (`VendorProfitCharDB`):

- `professions[professionID] = { name, recipes = { [recipeID] = { item, count, reagents } } }`
- `order = { entries, inMail, lastSeen, spent }`: the queued crafts, purchases not seen in bags or bank yet (and the count they're waiting to rise from), and what the panel spent.
- `panel = { left, top }`: where you moved the Vendor Profit window, if you did.
- `bestSort = { key, ascending }`: how Best Crafts is sorted.
- `history = { stock, sales, purchases }`: what the items you have cost you, your sales, and your last 500 purchases.

Opening a profession uses a secure action button casting the profession's spell, as TradeSkillMaster does in Forever. It's a separate invisible button laid over the Craft button rather than part of the panel, because a secure button inside the panel would make the panel protected and the game would block showing, hiding or moving it in combat. It's only placed out of combat and hidden as combat starts.

Shopping uses `C_AuctionHouse`: `SendSearchQuery` and the commodity search results to scan, `StartCommoditiesPurchase` for the quote (`COMMODITY_PRICE_UPDATED`), and `ConfirmCommoditiesPurchase`, called straight from the Confirm click, to buy (`COMMODITY_PURCHASE_SUCCEEDED` / `_FAILED`). Searches wait for the auction house's throttle and for the item to be loaded, are sent again if there's no reply, and ask for more results when the first page isn't enough.

## Tests

`tests/` loads the addon into a stubbed WoW client and a stubbed Auctionator, running real Lua 5.1:

```powershell
pip install lupa
python tests/test.py
```

The stub is not the real client. Anything it passes still needs checking in game.

## Contributing

`CLAUDE.md` holds the project's rules and the routine for every change (tests, README, branch, commit message, pull request), for Claude sessions and people alike. Personal additions go in a `CLAUDE.local.md`, which git ignores.

`main` is protected: every change goes through a pull request. `.github/workflows/test.yml` checks each one: the tests pass, every commit is a [Conventional Commit](https://www.conventionalcommits.org/) (`feat: ...`, `fix: ...`), the `.toc` still says `## Version: @project-version@`, and it notes what merging would release.

## Releases

Releases are automatic, and nobody sets the version by hand. `VendorProfit.toc` says `## Version: @project-version@`; the real version is worked out from the commit messages. Merging into `main` runs `.github/workflows/release.yml`, which, if anything in `VendorProfit/` changed since the last release:

1. works out the version (`scripts/next-version.sh`) from the commits since the last release that changed the addon, the biggest wins:
   - `feat!:` or `BREAKING CHANGE`: major (1.26.0 → 2.0.0)
   - `feat:`: minor (1.26.0 → 1.27.0)
   - anything else: patch (1.26.0 → 1.26.1)
2. runs the tests (no release if any fail),
3. stamps the version into the `.toc` inside the zip and checks every file it loads is there,
4. zips the `VendorProfit` folder as `VendorProfit-<version>.zip`,
5. publishes a GitHub release tagged `v<version>`, titled *Vendor Profit for Auctionator &lt;version&gt;*, with the commit messages since the last release as its notes.

Merges that only change docs, tests or workflows release nothing. Two people merging at once can't collide: releases run one at a time, each counting up from the last tag. Squash merges count too: their message is the pull request's title, and `Feat - Scope - Title` counts as a `feat`.

**Local copies.** `scripts/stamp-version.ps1` stamps the version from git into a copy of the `.toc`, for deploy scripts: `1.26.0` on a release, `1.26.0-3` three commits past it. Copied by hand, the addon shows `@project-version@`.
