# Vendor Profit for Auctionator

An addon for World of Warcraft: Forever that adds to Auctionator's crafting info in the professions window, leaving Auctionator's own **To Craft** and **Profit** lines as they are:

```
To Craft: 12s 39c                  <- Auctionator
Profit: -6s                        <- Auctionator: sell on the auction house
Vendor Profit: -10s 92c            <- sell to a vendor instead
[Queue]                            <- queue the recipe as it is
------------ Cheapest Route ------------
To Craft: 4s 38c         [Search]  <- crafting reagents yourself where that's cheaper
Profit: 7s 97c                     <- ...sold on the auction house
Vendor Profit: -2s 91c             <- ...sold to a vendor
[Queue]                            <- queue it along the cheapest route
```

- **Vendor Profit:** what you make by crafting the item and selling it to a vendor, at Auctionator's To Craft cost.
- **Cheapest Route:** the same three numbers when every reagent is got the cheapest way, crafting reagents yourself where that's cheaper than buying them, all the way down. Hover the section to see the route.
- **Search** (at the auction house) looks up live prices for every item in the crafting tree in one request.
- **Vendor Profit** in the professions window's title bar opens the Vendor Profit window on its **Best Crafts** tab: every recipe of the profession, most profitable first.
- **Queue** adds the recipe to a shopping order: under the Cheapest Route, along that route; under Auctionator's lines, the exact recipe, its reagents bought as they are and never crafted. The window's **Shopping List** tab then plans it with what you already have, scans the auction house, checks the order is still profitable at live prices, buys what's missing one confirmed purchase at a time, and crafts the steps in order.

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
    deploy.bat        <- copies the addon into WoW (development)
    update.bat        <- brings your branch up to date with main, then deploys
    README.md
```

The folder must stay named `VendorProfit` to match `VendorProfit.toc`.

For development on Windows, `deploy.bat` mirrors the folder into AddOns and stamps the version from git. It shows the commit it deployed (its short hash and message, and *+ uncommitted changes* when the addon has edits not committed yet), so you can tell deploys apart. Run it, then `/reload` in game, or restart WoW if files were added or removed. It expects WoW in `C:\Program Files (x86)\World of Warcraft`; if yours is elsewhere, create a `deploy.local.bat` next to it (git ignores it) with one line:

```bat
set "ADDONS=D:\Games\World of Warcraft\_forever_\Interface\AddOns"
```

`update.bat` brings the branch you're on up to date with `main`, fetches the release tags, and runs `deploy.bat`. Run it after a pull request is merged. It deploys whatever your branch has, so work not yet merged comes along; if merging `main` hits a conflict, it stops without deploying.

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

**Your recipes.** The game only shares recipe details for the profession window that's open, so the addon saves each profession's learned recipes when you open it, per character. **Open each of your professions once** (Smelting included) so routes can use them. Until then, those reagents can only be bought. The tooltip lists which professions are saved. Each window updates its saved recipes whenever you open it. Only professions you still have count: drop one (unlearn Mining, say) and routes stop crafting with it and Best Crafts stops listing its recipes, straight away. Its saved recipes are kept, and count again if you learn it again.

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

**Money** is shown with silver and copper always two digits after a larger coin, like a clock: **5s 07c**, so it can't be misread as 5s 70c. A zero silver still shows between gold and copper: **1g 00s 38c**, not 1g 38c, which reads as 1g 38s at a glance. That's everywhere this addon shows money; Auctionator's own lines are left as they are.

## Best Crafts

The **Vendor Profit** button in the professions window's title bar (left of TradeSkillMaster's, if you have it), or `/vprofit best`, opens the Vendor Profit window on its **Best Crafts** tab: every saved recipe of every profession you've opened, ranked together by profit per craft, each along its cheapest route. It works with the professions window closed: a profession's recipes are saved the first time you open it (and again whenever its list changes), so open each of your professions once. The **Filter** menu picks which professions are shown (all of them to start with); with just one, the title names it. The list shows 14 at a time and scrolls for the rest; drag the size grip in the window's bottom right corner up or down to show fewer or more (a whole row at a time, never shorter than the side tabs need or past the bottom of the screen; saved per character). The window keeps that height however many recipes are listed, so it doesn't jump as you search or filter. Clicking the title-bar button again closes the window.

```
Best Crafts: Blacksmithing                                 [ Scan ]
[Auction] [Vendor]  [Cheapest] [Exact]  [🔍 Search     ] [Filter (1)] [x]
Recipe                  Investment    Profit▼  Profit/hr    ROI    7d  AH  Q
★ Copper Chain Vest         3s 60c   -2s 10c   -15g 12s   -58%     -   -  -  [-] [+]
─────────────────────────────────────────────────────────────────────────────────────
  Rough Bronze Cuirass      4s 38c    1s 62c    11g 66s    37%     6   5  2  [-] [+]
  Rough Bronze Shoulders    3s 13c       87c     6g 26s    28%     1   -  -  [-] [+]
  Mystery Helm           no price: Strange Ore                      -   -  -  [-] [+]
Prices from Auctionator's last scan.
```

- **Money in the list** shows two coins at most: amounts in gold drop their copper (*1g 20s 94c* shows as *1g 20s*), cut off rather than rounded so a figure is never more than it really is, to keep the columns narrow. Sorting, the filters and the minimums use the exact amounts, and tooltips and the Shopping List keep the copper.
- **Profit/hr** is a craft's profit times how many you can make in an hour, from the game's cast times: the gold an hour of crafting it back to back makes. It counts every craft on its cheapest route, not just the last one: a cuirass made from bars you'd smelt includes the smelting (3.5 smelts for 7 bars when a smelt makes 2). Just the casting (not walking to an anvil or the moment between crafts), and not whether that many would sell: check **7d** for that. A recipe with a craft on its route the game gives no cast time for shows a dash. It sorts like the other columns.
- **Investment** is what one craft's items cost along its cheapest route: what you'd spend, counting items you already have at what they'd cost to get. **Profit** is what one craft makes after that, and **ROI** (return on investment) is the profit as a share of the investment. The tab is wider than the Shopping List to fit them and the search and filter controls.
- **Search.** Type in the search box to filter the list by recipe name as you type (any case). Clear it to see everything.
- **Filter.** The **Filter** button opens a menu with **Profitable only** (a positive profit on the tab you're on), **Hot only** (see **7d**, below) and skill-up colors: **Guaranteed** (orange), **Likely** (yellow) and **Unlikely** (green). Check any colors to see only recipes of those colors. The menu opens under the button, and clicking the button again closes it. The button shows how many filters are on (*Filter (2)*), and the red X at the end of the row clears them (it's grayed out while none are on). Filters are saved per character. Recipe names are shown in their skill-up color, as in the professions window; ones that won't skill you up stay white. The game only reports skill-up colors for the profession whose window is open, so each recipe's color is saved whenever its window is open: the others show the color as of their last opening, which may be out of date if you've skilled up since. The menu says so under the colors (*Closed professions: colors as last seen.*), and hovering a recipe whose color is saved says when it's from. A recipe saved before colors were kept has none until you open its profession again, and a color filter leaves it out (and says why). Under **Professions**, one checkbox per saved profession, all ticked to start with: untick one to leave its recipes out. Unticked professions count as filters, and the red X ticks them all again.
- **Minimums.** On the bottom row of the window, under the notes, **Min profit:** and **Min profit/hr:** (gold and silver boxes each, up to 9,999 gold; recipes with no Profit/hr are hidden while that one's set) and **Min ROI:** (a percentage, up to 9,999%) hide recipes below them, as you type: profit per craft and ROI on the tab you're on (ROI as shown, a whole percentage). Each box looks like the search box, with its unit inside at the right (a coin, or %), 0 to start; 0 is no minimum, and a box left empty goes back to 0. Recipes with no profit to rank are hidden while either is set. Between the minimums, a small red **and** button says a recipe must meet every one that's set; click it (either one: they switch together) for **or**, to show recipes meeting any one of them. A box at 0 doesn't count either way. They're saved per character, and the red X clears them along with the filters, back to **and**.
- **Favorites.** Click the star before a recipe's name (it shows when the mouse is on the name or the star's place) to make it a favorite: favorites stay at the top of the list, sorted among themselves by the same column, with their star always showing, and a gold line, with a little room either side, between them and the rest. Click it again to remove it. Favorites are saved per character; filters and the search still apply to them.
- **Sorting.** Click a column's heading to sort by it (highest first; Recipe A to Z); click it again to reverse. The sorted column is in white with an arrow, and recipes with no profit to rank stay at the bottom. The sort is saved per character. By default it's by Profit.
- **Auction** (the default) ranks by Auctionator's price after the 5% cut. **Vendor** ranks by selling to a vendor: usually lower, but a guaranteed sale.
- **Turn-ins.** Anyone of the level can hand 200 Thorium Shells to an NPC for 200 Thorium Headed Arrows (*Arrows Are For Sissies*, Artilleryman Sheldonore in Ironforge, level 52; *A Fair Trade*, Bounty Hunter Kolark in Orgrimmar, level 60). Best Crafts lists that as a recipe making 200 arrows from 200 shells, under its own **Turn-ins** heading (a checkbox under Professions in the Filter menu), whether or not you can make the shells: **Cheapest** crafts the shells if you can and that's cheaper, otherwise buys them; **Exact** buys them. Profit/hr counts the shells' crafting only (a dash when they're bought: nothing's cast). Hovering it says where to hand them in and what crafting the shells makes for the same 200, to compare. **+** and **-** queue it like a recipe: the Crafting Queue marks it *(turn-in)*, the plan buys or crafts the shells it takes (crafted on the way, they aren't queued to post: the arrows are), and To do gets a **Hand in** step after Craft saying how many to hand to whom (*Thorium Shells x200*, *Artilleryman Sheldonore, Ironforge*; in the box under the steps, like a craft, what it makes, where and how many times: *Thorium Headed Arrow x200*, *Ironforge, 1 time*), with no button: an addon can't hand in a quest for you. When you hand it in, the order counts down, the 200 arrows go into the Post Queue, and what the shells cost you passes on to the arrows in Profit History, as a craft's reagents do. Handing in shells without queuing the arrows still passes the cost on, and swaps any of those shells waiting in the Post Queue for the arrows.
- **Cheapest** (the default) prices each craft along its cheapest route, its reagents crafted where that's cheaper than buying them. **Exact** prices it as the exact recipe, as Auctionator does: its direct reagents bought (vendor or auction, the cheaper), never crafted. It changes every money column, the ranking, sorting, filters and minimums, and what **+** queues. Saved per character.
- Losses are listed too (in red), below the crafts that make money. Recipes with no profit to rank by come last, saying why: a reagent with no price anywhere (*no price: Strange Ore*, so their profit can't be trusted), or no vendor (or auction) price for what they make.
- **7d** is how many of what the recipe makes you sold at auction in the last 7 days (items, not crafts: 3000 shells is 15 crafts of 200), from Profit History, in orange for the **hot** ones: what's been selling best for you at auction lately. Each auction sale's profit counts for half as much every 7 days it ages (so last week's sales count half, and nothing drops off all at once), added up per item; the top fifth of items that have sold at auction count as hot, if they had at least 2 separate auction sales in the last 7 days (so one buyer, even of a whole stack, doesn't make an item hot). It's measured against your own sales, so it works whether you sell a little or a lot. Vendor sales don't count: a vendor buys anything. Hovering a recipe says how many sold at auction this week and in how many sales, and for a hot one about how much profit a day it's been making lately. It sorts like AH and Q.
- **Per craft and per item.** Investment, Profit and ROI are per craft: what you actually spend (you can't craft part of a stack) and what one cast earns. 7d and AH count items. For a recipe that makes more than one, hovering its name says how many a craft makes and its investment and profit per item (*<1c* when it's under half a copper).
- **AH** is how many of what the recipe makes you have up for auction, and **Q** how many crafts of it your shopping order holds (a dash for none). Both sort like the other columns, every recipe included. The game only lists your auctions at the auction house, so AH is as of your last visit: it's read when the auction house opens and again after you post or cancel, and sales or expiries since then show at the next visit. **+** adds one craft to the order and **-** takes one off (**Shift-click** for five); the window stays on Best Crafts.
- **Ctrl: the other way.** Hold **Ctrl** with the mouse on a row and that row is priced the other way from the list (as the exact recipe while **Cheapest** is on, along its cheapest route while **Exact** is): its money columns change, and the name is marked *(exact)* or *(cheapest)*. The row keeps its place (the list is still ranked, sorted and filtered the list's way), and it goes back when you let go of Ctrl or move off it. **Ctrl-click +** queues it the other way, a separate entry from the list's way; **Ctrl-click -** takes one off only the entry queued the other way.
- The row under the mouse is lit, with the same highlight the game's own lists use, so you can follow it across the columns.
- Clicking a recipe's name selects it in the professions window, while that recipe's profession is the one open there. Hovering it names its profession (and shows your sales of it, below).
- Hovering a recipe's name shows what you've made selling its item, over all time, from Profit History: how many sold in how many sales, the average and total profit, the average and overall ROI, its average cost and sale price, how many went to vendors and to the auction house, and when it last sold. An item that hasn't sold says so.
- **Professions**, left of **Scan**, brings every profession's recipes and skill-up colors up to date in a few clicks: keep clicking it. The first click opens your first profession, each click after that opens the next one (*Next 2/3*), and the last one (**Close**) closes the professions window. After each opening it says **Opening...** until that profession is open and saved, so clicking fast can't skip one; if one doesn't open within a few seconds, click again to retry. The profession already open when you start is skipped (it's saved already). Herbalism and Skinning have no window and aren't opened; Fishing's window (Camping) is. After **Close** the button rests for a second, so a click too many doesn't start it again; closing the window yourself part way through starts over. Like the Shopping List's **Open Mining**, it can't open professions in combat.
- It ranks straight away from Auctionator's prices. At the auction house, **Scan** looks up live lowest prices for everything that matters to the profession: every recipe's crafting tree, merged into one list of unique items, looked up 100 at a time (the most the server allows in one request) with the auction house's batch lookup (the one it uses for favorites) rather than one search per item. It takes seconds. Items with nothing listed count as unavailable until the next scan, and Auctionator saves the prices it sees too. Items that bind on pickup aren't looked up.

## Shopping

**1. Queue.** Set the number in the professions window's Create box (say 10) and click **Queue** under the Cheapest Route section's Vendor Profit line, to craft reagents yourself where that's cheaper. Or click the **Queue** under Auctionator's lines (below the first Vendor Profit line) for the exact recipe, as Auctionator prices it: its reagents are bought (or taken from what you have), never crafted. An exact one is marked *(exact)* in the Crafting Queue, and its tooltip prices it that way. Queuing a recipe already in the order the same way adds to it; queued the other way, it's a separate entry. A chat line confirms it; the order is on the Vendor Profit window's Shopping List tab, which `/vprofit` opens (the window never opens by itself).

**2. The plan.** The panel works out, in whole numbers, what the order needs, using what you already have (bags and bank) first:

```
10 Rough Bronze Cuirasses need 70 Bronze Bars. You have 12, so 58 to make: 29 smelts.
29 smelts need 29 Copper Bars (you have 5, so 24 to smelt from 24 Copper Ore) and 29 Tin Bars.
```

The panel is laid out as:

```
Shopping List                                [ Scan ]
─────────────── [-] Profit ───────────────
    Vendor price                             60s
    Auction price                            1g 23s 50c

    Items you have                           -10s
    Items to buy                             -33s 75c
    Spent on this order so far               0c

    Vendor profit                            16s 25c
    Auction profit                           79s 75c
────────────[-] Crafting Queue ───────────
    Rough Bronze Cuirass x10                 [-] [+] [x]
────────────── [-] Post Queue ─────────────
    Items to post at the auction house. ...
─────────────── [-] To do ───────────────
1. Buy                         2 items       [ Buy ]
2. Take from bank              1 item        [ Take ]
3. Craft                       3 recipes     [ Craft ]
  » Copper Bar x24       Mining, 24 crafts
┌─────────────────────────────────────────┐
│ Buy                                      │
│ Copper Ore x24             auction 12s 70c│
│ Tin Bar x29                auction 21s 75c│
│ Take from bank                           │
│ Copper Bar x2                            │
│ Craft                                    │
│ » Copper Bar x24       Mining, 24 crafts │
│ Bronze Bar x58         Mining, 29 crafts │
│ Rough Bronze Cuirass x10  Blacksmithing  │
└─────────────────────────────────────────┘
────────── [-] Already in your bags ──────────
    Bronze Bar x12
    Copper Bar x3
```

**To do** is a checklist in the order you'd do it: **Buy** first (prices are what can change, so you find out at the auction house before fetching or crafting anything), **Collect from mailbox** (purchases not collected yet), **Take from bank**, **Craft**, **Hand in** (turn-ins, below), then **Post** (below). Each step shows only while it has something left in it and they're numbered in order, so the list gets shorter as you go: when a step is done, the next one moves up into its place, so you keep clicking in the same spot. The steps stay at the top, each with how many items (or recipes) it has and its button, with the next craft under Craft; **Craft** also says about how long its crafts will take, to the nearest minute (*Craft (63 min)*), from the game's cast times (just the casting: not walking to an anvil, and not recipes the game gives no cast time); their items are listed in a box below, as tall as its rows (none with nothing to list) up to 12, scrolling past that so a big order doesn't make the window run off the screen; its scroll bar only shows when there's more than fits (fold To do to hide the box). A step that has just moved up into the place of one that finished ignores clicks for half a second, so a click meant for the finished one doesn't land on it. Every button has a short label; hover one for the details. There's no button bar at the bottom. Your items are used from your bags first, then the mailbox, then the bank, so **Take from bank** lists exactly what to fetch. Bags include the reagent bank, since crafting uses it directly. **Already in your bags** is just for information. The sections go Profit, Crafting Queue, Post Queue, To do, Already in your bags, and every one shows even with nothing in it, saying in gray what it's for and when it fills (*Items to post at the auction house. What the queue crafts comes here, and so do auctions that come back by mail.*), so the page keeps its shape. Every section folds away: click its divider (the line with its name and a minus sign) to fold it, and again to open it. A folded section says how many rows it holds (*Crafting Queue (2)*, *To do (3)*), and which ones are folded is remembered per character. Folding **To do** folds just its box of items: the steps and their buttons stay. **Scan** is on the page's title line, as on Best Crafts, since it's for the whole order. Several queued recipes share your items, so nothing is counted twice.

**Take from bank.** At the bank, **Take** on the **Take from bank** step moves exactly those amounts into your bags: it splits them off the bank's stacks (smallest stacks first) into empty bag slots, one move at a time, waiting for each to finish. If something isn't in the bank after all, or your bags fill up, or the bank closes, it stops and says so.

**Profit** is three small groups: what everything still queued sells for (**Vendor price**, and **Auction price**: Auctionator's price after the 5% auction house cut, so it's what you'd actually get, or *no auction price*), what it costs (**Items you have**, what the items you have are worth, and **Items to buy**), and what finishing the order makes from where you stand (**Vendor profit** and **Auction profit**: each price minus both costs). Buying checks Vendor profit. Items you have count at the cheapest way to get them now, whether you had them already or bought them for this order. What you've paid is spent either way, so it doesn't change whether finishing is worth it. It's shown under **Items to buy** as **Spent on this order so far** (always, from 0), but not taken off. That way an order you've partly shopped for and crafted gives the same answer as clearing it and queuing what's left.

**Crafting counts the order down.** Each time you craft a queued recipe, its count drops by one, and the order finishes when everything queued is made. Reagents you craft with leave your bags, so the plan always works from what's actually left.

The buttons for each part sit on their section's heading, with short labels; hover one for the details.

**3. Scan.** At the auction house, open the window (`/vprofit`). **Scan**, at the top right by the page's title, first looks up every item in the order's crafting trees in one batch request (the same lookup as Best Crafts' Scan), so the order is planned with live prices straight away and items with nothing listed are skipped, not searched. Then it reads every listing of each item the order buys there, so buying 24 is priced by walking up the cheapest listings, not at the lowest single price, and your own listings are left out. Those listings are what purchases are priced and checked against. With them the order is planned again: if crafting something has become cheaper than buying it, or the other way round, the plan changes and the new items are scanned too. An item with nothing listed at all is planned another way (crafted, where you can, buying its materials instead), and the panel says so (*Nothing listed for Mithril Casing: planned without the auction house*). The scan's prices are kept for an hour after you leave the auction house, so an item that wasn't there doesn't go back to Auctionator's last price for it and onto the Buy list again; after that, or on the next scan, the plan uses fresh prices.

The auction house is shared with its own Browse tab and other addons (Auctionator, TradeSkillMaster), which send requests too, especially as it opens. So the scan recovers rather than waits: when another addon's results replace the batch lookup's, it's sent again a second later; when the game reports a request dropped by its throttle, a search is sent again straight away. Price quotes are different: the game only gives one for a request made as part of a click, so a quote is never asked for by itself. And just after a purchase the game is briefly busy and drops requests, so **Buy** and **Confirm** are held for that moment (hover: *Waiting a moment for the auction house to be ready...*) and your click always counts. If a quote request is dropped anyway, it says so straight away; if one simply never comes, it says so after 10 seconds. Either way, **Buy** is ready to click again. The server answers at most 100 item searches a minute from all addons together, and drops the rest without a word, so searches wait for room (the Buy button's tooltip says so) instead of timing out. If the game ever blocks an action ("Interface action failed because of an AddOn"), Vendor Profit prints which one in chat.

**4. Buy.** **Buy** on the **Buy** step works before a scan too: it scans first, then says *Prices are in. Click Buy for Copper Ore.* (or offers **Buy anyway** if neither selling to a vendor nor at auction would make money). The game only gives a price quote for a click, so the first purchase needs that second click. The same goes for anything queued after a scan: **Buy** scans just the new items first (hover: *Scans prices for what was queued since the last scan*). Once scanned, **Buy** (away from the auction house it says **Open AH**; hover it: *Buy 24 Copper Ore for 12s 70c*) asks the auction house for a price quote. If the quote is no more than the scan, the button becomes **Confirm**, with *Confirm: 24 Copper Ore for 12s 70c* and a **Cancel** button shown right under the step, and clicking Confirm buys. That's two clicks per item, the same as Auctionator's own buying: the game only allows a purchase as part of a click. Items that don't stack (gear and the like) are sold as separate auctions, and **Buy** buys them one auction per click, cheapest first, outright at its buyout (hover: *Buy 1 Green Leather Armor for 39s 95c*); there's no quote to confirm, since an auction's buyout is fixed. The auction house only sells an auction from the latest search, so if another item was searched since (the scan's next item, Auctionator, the game's own window), the first click searches it again (*Finding Green Leather Armor's auctions again...*) and the next one buys. **Scan** again any time to refresh prices.

- **Price went up:** if the quote is higher than the scan (someone bought the cheap ones first), the purchase is cancelled and the item scanned again.
- **Not profitable:** before each purchase, finishing the order must still make money one way or the other at current prices: selling to a vendor or at auction. If neither does, the button says **Buy anyway**, with a message saying so: clicking it is your go-ahead, until the next scan. If only one of them loses money, buying goes ahead, and that one shows in red under Profit.
- **Not enough listed:** it buys what's there and says how many are missing.
- **Not enough gold, no reply, a failed purchase:** nothing is recorded, the panel says what happened, and the item is scanned again. A purchase that gets no reply but goes through later is still recorded when the success arrives.
- **Items that don't stack** (gear and the like): auctions with no buyout (bid only) and your own are skipped; the panel never bids. If someone else buys an auction before your click, the game says so, nothing is recorded, and **Buy** goes on to the next cheapest.

**Vendors.** Opening a vendor's window records what it charges for each item it sells for gold without a stock limit, per character, keeping the cheapest seen: a vendor can charge less than the usual price with a reputation discount (Heavy Stock for 18s instead of 20s), and that's what you'll pay. Recorded prices come first everywhere: the Shopping List, routes and Best Crafts. Items you haven't seen at a vendor yet use Auctionator's recorded vendor price, and failing that the item's usual price from the addon's own list (`VendorPrices.lua`), so a new install doesn't plan Coarse Thread from the auction house just because you haven't visited a trade-goods vendor yet.

The list is maintained here, by hand: one item per line, `[itemID] = copper for one,`. To update it, talk to a vendor and type `/vprofit prices`: a box lists that vendor's prices in the same format, sorted, marking items that are new or whose price differs from the list. Copy the lines you want (Ctrl+C) into `VendorPrices.lua`.

Items the plan gets from a vendor (Weak Flux, thread, vials) are bought at a vendor. Talk to one that sells any of them and, with the window open, **Buy** is on the **Buy** step (hover it: *Buy from this vendor: 3 Weak Flux, for 2s 70c*). One click buys all of it: exactly what's needed, or whole batches for items sold several at a time, and only for gold. It also buys anything planned from the auction house that this vendor sells for no more. If you run short of gold it buys what it can and says what's missing. After a purchase, the button shows **Buying...** until the items reach your bags (or 10 seconds pass), so a double click can't buy twice. Away from vendors, with only vendor items left, the button is off and says to find a vendor.

**5. Craft.** **Craft** on the **Craft** step crafts the step marked **»**, as many times as it needs (up to what you have materials for; hover it: *Craft Copper Bar, 7 times*). The game only crafts recipes of the profession window that's open, so when the next step is in another profession the button says **Open Mining**, and clicking it opens that profession (Mining opens with Smelting). Once clicked it shows **Opening...** until the profession has loaded, so a second click can't close the window it's opening; if nothing opens within a few seconds, it's clickable again. In combat it can't be clicked (hover: *Open Mining after combat*): the game doesn't let addons open professions then. It skips ahead to a later step the open window can make if you have its materials, is off with *Missing materials for ...* when you don't, and says **Crafting...** while you're casting.

**6. Post.** The **Post Queue** section, under the Crafting Queue, lists what's waiting to be posted, first in, first out: what the order crafted, as many as each craft made (the outputs of the recipes you queued, not the reagents crafted on the way, and not recipes queued from Best Crafts' **Vendor** tab, which are meant for a vendor), and auctions that come back by mail, expired or cancelled, as many as came back, once you take them out (one by one or with the mailbox's Open All). Each item shows how many to post, and how many are in your bags when that's more (*Thorium Shells x200 (250 in bags)*); **-** and **+** post fewer or more (five with Shift), from 1 up to what's in your bags, and **×** takes it off the queue, to keep it. It stays after the order is done, until it's posted. It follows your bags: queued items that leave them some other way (crafted into something else, handed in, sold to a vendor, mailed or banked) come off the queue a few seconds later, so having some again later as a reagent doesn't put them up to post.

At the auction house, the To do list's **Post** step looks up the first item's price (asking again if no answer comes within 3 seconds), then the price shows under the step (*Post 200 Thorium Shells at 3c each*), the cheapest prices found are listed first in To do's box for a gut check, under *Listed now: Thorium Shells* (each price and how many are at it, the ones passed over marked *(skipped)*), so they're in view even when you start posting before the other steps are done, and the next click posts the queued count, for the shortest time, in one go (items that don't stack too). An item you last posted for longer (by hand, in the game's Sell tab or Auctionator) is posted for that long again, and the price line says so (*, for 8 hours*); post it at the shortest again and it's back to the default. An auction mailed back doesn't say how long it was up, so the addon remembers it from the post. Then the next item is looked up by itself. The price matches the lowest listed, unless that looks like bait: 3 or fewer at a price more than 20% below the next one up, in which case it goes up a price, at most twice. With nothing listed it's Auctionator's last known price *x* (in gold) raised to *x* + min(*x*, *x*^0.7), cut down to whole gold: a step that grows with the price but more slowly (1g → 2g, 3g → 5g, 10g → 15g, 30g → 40g, 100g → 125g), and at most double under 1g; never seen at all, the item comes off the queue and it says so. Below what the items cost you (after the auction house's cut), the note and the button turn red, and the first click only arms it: click again to post anyway. The game only posts as part of a click, so each item is one click. An item counts as posted once the items leave your bags, however long a multisell of things that don't stack takes; only if nothing leaves for 15 seconds does it say there was no word, so you can check your auctions and try again.

**Crafting stations.** Which profession it offers depends on what you can do where you are. It only offers steps you have the materials for, so it won't send you to Mining with no ore. Among those, it offers one whose station (Anvil, Forge, Cooking Fire) you're standing at, or that needs none, before the rest: beside a cooking fire with Cooking, Mining and Blacksmithing queued, it offers **Open Cooking**. In the open profession, away from its station, it moves on to a profession you can craft right there; if there isn't one, the button is off with *Needs Anvil nearby to craft ...*. The game reliably says whether you're at the open profession's station. For other professions it may not, so their steps rank after ones it vouches for. The game sends nothing when you walk up to a station or away from one, so while a Craft step is shown the panel checks each second and updates when that changes. `/vprofit stations` lists each queued step's station and what the game reports, if you want to check. Materials are counted from your bags and reagent bank, which is what crafting can use; items in the main bank don't count until you take them out. Crafting the queued item counts the order down as usual.

**Mail.** Auction purchases may arrive in your mailbox rather than your bags. A purchase counts as **in the mail** until that many more of the item show up in your bags or bank, so it's counted either way and never bought twice. Opening the mailbox corrects that from what's actually in the inbox, so a purchase that arrived without the panel seeing it (say you used it up as it arrived) stops counting.

**The window.** The Shopping List, Best Crafts, Profit History, Purchase History and Gold are tabs down the right side of one Vendor Profit window. It comes to the front when it opens or you click it, and another window you click (your bags, the auction house) comes in front of it. It opens centered near the top of the screen; drag it anywhere, and from then on it opens where you left it (saved per character). It only opens when you open it (`/vprofit`, a `/vprofit` tab command, or the title-bar button) and only closes when you close it (its close button, Escape, the title-bar button, or `/vprofit`), in combat too: never by itself at the auction house, bank or a vendor, or when you queue something. `/vprofit reset` puts it back there.

**Minimap button.** The coin button on the minimap's edge opens or closes the window, on the tab you last used. Drag it to move it around the edge (on a square minimap too); where you leave it is saved for the whole account. `/vprofit minimap` hides it, and again shows it.

The order is saved per character. Each queued recipe has three small buttons: **-** and **+** craft one fewer or one more (five with **Shift-click**; at least one), and **x** takes it out of the order; removing the last one empties the order and its record. Hover a queued recipe to see its own cost along the cheapest route and its vendor and auction profit at today's prices; click it to show its recipe in the professions window (when that window is open). Its name is red when neither would make money.

**Vendor profit** and **Auction profit** are red, label and all, when they're a loss.

## Profit History

The window's **Profit History** tab (or `/vprofit history`) shows what you've made selling things you crafted, with totals for everything and for the last 7 days at the top. Two buttons switch between views, the search box filters both by item name as you type, and **Range** narrows both to recent sales:

- **Sales** (the default): every sale, newest first: the date (mm/dd), the item, what it cost you, what it sold for and the profit. Click a heading to sort by it (again to reverse); the sort is saved per character. Hover a sale to see whether it sold to a vendor or at auction, and its cost split into what you bought and your own items.
- **Best Sellers**: one row per item: how many **Sold**, the **Avg profit** on each, the total **Profit**, the **Avg ROI** (each one's own return on what it cost you, averaged) and the overall **ROI** (all its profit over all it cost), most profit first. Click a heading to sort by it (again to reverse); the sort is saved per character. Hover a row for its average cost and sale price, how many went to vendors and to the auction house, and when it last sold.
- **Range** (the button at the end of the row): **All time**, the **last 7, 30 or 90 days**, or the **last 50, 100 or 250 sales**. It's saved per character. Use All time for each item's long-run average, and a range to see how it's doing lately.

The list keeps your last 10,000 sales in full. Older ones aren't thrown away: each is added up with that item's other sales that day, so the day ranges and Best Sellers reach back as far as you've been selling; only the per-sale detail (the exact sale, its cost split) is gone. Every sale is also added up per item as it happens, so the totals at the top and Best Sellers over All time cover every sale since tracking began. The last-so-many-sales ranges use the full list. However long the list, only the rows on screen are built, and they're refilled as you scroll, so it opens and scrolls as fast with 10,000 sales as with 10.

```
Profit History
Profit: 2s 80c from 3 sales. Last 7 days: 2s 80c.
[Sales] [Best Sellers]  [🔍 Search                ] [All time]
Date   Item                        Cost   Sold for    Profit
11/08  Test Ring                    50c         2s    1s 50c
11/08  Test Ring                 1s 50c     1s 80c       30c
11/07  Test Ring                     1s         2s        1s
```

Costs follow the items, so each sale has its own cost, not today's prices:

- **Bought** items cost exactly what you paid. Auction house purchases are read from their mail when you take the item out of the mailbox, however you bought them; vendor purchases when you buy, from any vendor.
- **Your own** items (farmed, owned before installing, from an alt or a trade) cost their market value at the moment a craft uses them: the cheapest way to get one right then, which is what using it instead of selling it cost you.
- **Crafted** items cost what their reagents cost, used up oldest first. Bars smelted from bought ore carry the ore's exact cost into whatever they make.

Sales use up the item's costs oldest first. Vendor sales are read from the vendor's buyback list, with the exact price, and from the sell itself (right-click, or a vendor addon), counted once its stack leaves your bags, so a 13th identical stack in one visit still counts once the 12-slot buyback list is full; buying something back undoes its sale. Auction sales are read from the "Auction successful" mail, counted once its gold actually arrives: the sale price less the auction house's cut (the deposit comes back with it, so it cancels out). So an auction sale only shows up once you've collected it, and a mail asked for twice (Open All with TradeSkillMaster) counts once. Auction purchases and returned auctions likewise count once their items land in your bags.

- Only crafts made since installing are tracked. Selling something made before that leaves it out rather than inventing a cost.
- Items that leave some other way (mailed to an alt, destroyed, used) stop counting once they're nowhere to be seen: not in your bags or bank, and not yours at the auction house (up, or sold with the gold not sent yet, as of your last visit). They're set aside for 31 days rather than forgotten, since some are only out of sight: a sale from the mail takes their cost, and items that turn up again (an expired auction taken from the mail) get theirs back.
- The last 10,000 sales are kept in full, older ones added up by item and day, per character.

## Purchase History

The **Purchase History** tab (or `/vprofit purchases`) lists your last 5,000 purchases, newest first, for a gut check: the date (mm/dd), the item and how many, whether it came from the auction house or a vendor, what you paid **each** and in **total**, and what one costs **now** (the cheaper of the vendor and auction prices). Click a heading to sort by it (again to reverse), saved per character. Hover a purchase for the exact time.

Vendor purchases show up straight away, from any vendor. Auction house purchases show up when you take them out of the mailbox, read from their mail, however you bought them. These are the same purchases whose costs feed the Profit History.

## Gold

The **Gold** tab (or `/vprofit gold`) graphs your gold over time, added up over your characters, like TradeSkillMaster's Player Gold graph. Only your characters' own gold counts: no guild bank. The line is green when the stretch shown ends at least as high as it starts, red when it ends lower. The line at the top gives the gold of the characters shown now, and how much it changed over the last 7 days.

```
Gold
Gold: 28g across 2 characters. Last 7 days: +11g.
[Characters] [x]                                   [All time]
  30g |                                        ____/
  20g |                       ________________/
  10g |______________________/
       10/25          11/01          11/08
Drag across the graph to zoom in. Right-click to zoom back out.
```

- **Hover** the graph for a guide line with the gold then at its top, and the time beside the page's title. The line turns gold while you hover.
- **Drag** across the graph to zoom into that stretch; **right-click** zooms back out. Changing the range or reopening the tab also zooms out.
- **Range**: the last 24 hours, 7 or 30 days, 3 or 6 months, the last year, or **All time** (the default). It's saved per character and never starts before the first point recorded.
- **Characters**: a checkbox for each character, with its gold now (and its realm, if you have characters on more than one). Untick one to leave it out of the graph and the totals; the button then says how many are shown (*Characters (2 of 7)*), and the red **x** beside it shows everyone again. What's ticked is saved for the whole account, and a new character starts ticked.

Each character's gold is saved when it changes, at most once a minute, from its first login with the addon on. Before that, a character counts at the gold it had then: an alt that sat untouched had that gold all along, so it doesn't show up as a sudden jump. Gold the game reports as 0 just after logging in or a loading screen is checked again each second for 30 seconds before it's believed, since the game sometimes reports 0 for a moment; while logging out or reloading it reports 0 too, so nothing is recorded then. Points older than 90 days are thinned to one an hour.

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
| `ScrollBox.lua` | The scroll boxes every list uses: shaded, padded, the scroll bar only when there's more than fits (`docs/ui-design.md`) |
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
| `Poster.lua` | Posting what the order crafted at the auction house |
| `SearchButton.lua` | The Search button: the whole crafting tree in Auctionator |
| `Crafter.lua` | The Craft button: the next step the open profession can make |
| `OpenButton.lua` | Opening another profession from the Craft button |
| `Banker.lua` | Take from bank: moving exactly what's needed into your bags |
| `Merchant.lua` | Buying what the order needs from the vendor you're talking to |
| `Auctions.lua` | How many of each item you have up for auction, as of your last visit |
| `Panel.lua` | The Vendor Profit window and its tabs, the Shopping List tab, moving it, and `/vprofit` |
| `MinimapButton.lua` | The minimap button |
| `Columns.lua` | Lays out the tabs' table columns so values and headings never touch |
| `TurnIns.lua` | NPC turn-ins priced like recipes (Thorium Shells for Thorium Headed Arrows) |
| `BestCrafts.lua` | Ranking a profession's recipes, and the batch price lookup |
| `ProfessionCycle.lua` | Best Crafts' Professions button: opening each profession in turn |
| `BestPanel.lua` | The Best Crafts tab, and the button in the professions window's title bar |
| `History.lua` | Profit history: what items cost you as they come in, and their sales |
| `HistoryPanel.lua` | The Profit History tab |
| `PurchasePanel.lua` | The Purchase History tab |
| `Gold.lua` | Each character's gold over time, saved for the account |
| `GoldPanel.lua` | The Gold tab: the graph, its Range and Characters menus |
| `Media/` | The Gold graph's line and dot textures (our own) |

Saved data, per character (`VendorProfitCharDB`):

- `professions[professionID] = { name, recipes = { [recipeID] = { item, count, reagents, stations, skillUp } } }`: `skillUp` is the recipe's skill-up color when its window was last open.
- `order = { entries, inMail, lastSeen, spent }`: the queued crafts, purchases not seen in bags or bank yet (and the count they're waiting to rise from), and what the panel spent.
- `panel = { left, top }`: where you moved the Vendor Profit window, if you did.
- `bestSort = { key, ascending }` and `bestFilters`: how Best Crafts is sorted and filtered.
- `bestFavorites = { [recipeID] = true }`: Best Crafts' favorite recipes.
- `bestRows`: how many rows Best Crafts' list shows (its size grip).
- `bestExact`: Best Crafts prices exact recipes (its **Exact** button) rather than cheapest routes.
- `postQueue = { { itemID, count }, ... }`: the Post Queue.
- `bestSellersSort = { key, ascending }`: how Profit History's Best Sellers is sorted.
- `auctions = { counts, sold, time }`: how many of each item you had up for auction at your last visit to the auction house, how many sold with the gold not sent yet, and when.
- `history = { stock, missing, sales, items, daily, purchases }`: what the items you have cost you, recorded items not seen anywhere (kept 31 days), your last 10,000 sales, every sale added up per item, older sales added up per item per day, and your last 5,000 purchases.
- `historyRange`: Profit History's range.
- `goldRange`: the Gold tab's range.

Saved data, for the whole account (`VendorProfitDB`):

- `gold[name-realm] = { name, realm, log }`: each character's gold over time. `log` is one string, `minute:copper;...` oldest first (minutes since 1970), each point holding until the next.
- `goldHidden[name-realm] = true`: characters left out of the Gold tab.
- `minimap = { angle, hide }`: where the minimap button sits on the minimap's edge (degrees, 0 = right), and whether it's hidden.

Opening a profession uses a secure action button casting the profession's spell, as TradeSkillMaster does in Forever. It's a separate invisible button laid over the Craft button rather than part of the panel, because a secure button inside the panel would make the panel protected and the game would block showing, hiding or moving it in combat. It's only there while the mouse is on the Craft button, only placed out of combat, and hidden as combat starts.

Shopping uses `C_AuctionHouse`: `SendSearchQuery` and the commodity search results to scan, `StartCommoditiesPurchase` for the quote (`COMMODITY_PRICE_UPDATED`), and `ConfirmCommoditiesPurchase`, called straight from the Confirm click, to buy (`COMMODITY_PURCHASE_SUCCEEDED` / `_FAILED`). Items that don't stack use the item search results (`ITEM_SEARCH_RESULTS_UPDATED`) and `PlaceBid` with the auction's buyout, called straight from the Buy click; it's bought when the game says so in any of its ways: the "auction won" notification (`AUCTION_HOUSE_SHOW_NOTIFICATION` or `_FORMATTED_NOTIFICATION`), `AUCTION_HOUSE_PURCHASE_COMPLETED` for that auction, `BIDS_UPDATED`, or "Bid accepted." / "You won an auction for ..." in chat (only the first counts), and failed on an error message (`UI_ERROR_MESSAGE`: item not found means someone else bought it first). An auction can only be bought from the latest item search, so the latest `SendSearchQuery` (anyone's) is watched and the item searched again first when it isn't the latest. Searches wait for the auction house's throttle and for the item to be loaded, are sent again if there's no reply, and ask for more results when the first page isn't enough.

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
