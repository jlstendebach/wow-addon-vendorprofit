# Vendor Profit for Auctionator

An addon for World of Warcraft: Forever that adds two lines under Auctionator's **To Craft** and **Profit** lines in the professions window:

- **Vendor Profit:** what you make by crafting the item and selling it to a vendor instead of on the auction house.
- **Vendor Profit (route):** the same, but getting every reagent the cheapest way, crafting reagents yourself where that's cheaper than buying them, all the way down. Hover it to see the route.

```
To Craft: 12s 39c
Profit: -6s                     <- Auctionator: sell on the auction house
Vendor Profit: -10s 92c         <- sell to a vendor
Vendor Profit (route): -2s 91c  <- same, crafting reagents where it's cheaper
```

Requires [Auctionator](https://www.curseforge.com/wow/addons/auctionator).

> **Unofficial.** Vendor Profit for Auctionator is an independent addon. It is not made, endorsed or supported by Auctionator or its authors. Please report problems with it here, not to Auctionator.

## Install

Copy the `VendorProfit` folder into `World of Warcraft\_forever_\Interface\AddOns\`. Everything in it is the addon. Everything outside it (this README, `tests/`) is for development only.

```
wow-addon-vendorprofit/
    VendorProfit/     <- the addon; copy this folder as-is
    tests/            <- stubbed-client tests
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

## Vendor Profit (route)

Auctionator prices a Bronze Bar at what a Bronze Bar costs. This line also checks whether smelting it from Copper and Tin Bars is cheaper, and whether those bars are cheaper to smelt from ore, and takes the cheapest option at every step.

For each reagent, the cheapest of:

- **buy (vendor):** what a vendor sells it for, if Auctionator has seen it at a vendor
- **buy (auction):** its auction price from Auctionator's last scan
- **craft:** one of your recipes, its reagents priced the same way

**Vendor Profit (route) = vendor sell price x number made - route cost**

**Your recipes.** The game only shares recipe details for the profession window that's open, so the addon saves each profession's learned recipes when you open it, per character. **Open each of your professions once** (Smelting included) so routes can use them. Until then, those reagents can only be bought. The tooltip lists which professions are saved. Each window updates its saved recipes whenever you open it.

**The tooltip** shows the route as a tree. Each crafted item has what goes into it indented under it, with where to get it and what it costs. Below the tree: the route's crafting cost, Auctionator's To Craft cost, how much the route saves, and the vendor profit.

```
Cheapest Route
Rough Bronze Cuirass x1                                  4s 38c
    Bronze Bar x7      craft (Mining, makes 2)           4s 38c
        Copper Bar x3.5    craft (Mining)                1s 75c
            Copper Ore x3.5    buy (auction)             1s 75c
        Tin Bar x3.5       buy (auction)                 2s 63c
```

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

## How it works

- Auctionator makes its crafting info frame (`AuctionatorCraftingInfoProfessionsFrame`) the first time the professions window opens. The addon hooks the function that makes it, attaches right after, and retries on the next frame in case it sees the event first.
- It adds its lines to that frame, anchored under Auctionator's text, so they show and hide with Auctionator's lines. A mouse-enabled frame over the route line shows its tooltip.
- It post-hooks the frame's `UpdateTotal`, which Auctionator calls whenever the recipe, reagents or prices change, and refreshes right after. Saving a profession's recipes refreshes too.
- Prices come from Auctionator's public API (`Auctionator.API.v1`). Vendor Profit's cost to craft calls `Auctionator.CraftingInfo.CalculateCraftCost` so it matches To Craft exactly, with its own reagent total as a fallback.
- It only reads from Auctionator. It never changes Auctionator's text, settings or data, and an error in this addon is reported without breaking Auctionator's refresh.
- Recipes are read with `C_TradeSkillUI` when your own profession window is ready. Linked, guild and NPC crafting windows aren't saved. If the game can't list every recipe at once, the window's (possibly filtered) list is added to what's saved instead of replacing it.

Files:

| File | What it does |
| --- | --- |
| `Core.lua` | Prices, working out the shown recipe, attaching to Auctionator's frame |
| `VendorLine.lua` | The Vendor Profit line |
| `Recipes.lua` | Saving and looking up this character's recipes |
| `Route.lua` | Finding the cheapest route |
| `RouteLine.lua` | The Vendor Profit (route) line and its tooltip |

Saved data, per character: `VendorProfitCharDB.professions[professionID] = { name, recipes = { [recipeID] = { item, count, reagents } } }`.

## Tests

`tests/` loads the addon into a stubbed WoW client and a stubbed Auctionator, running real Lua 5.1:

```powershell
pip install lupa
python tests/test.py
```

The stub is not the real client. Anything it passes still needs checking in game.
