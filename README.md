# Vendor Profit for Auctionator

An addon for World of Warcraft: Forever that adds a **Vendor Profit** line under Auctionator's **To Craft** and **Profit** lines in the professions window: what you make by crafting the item and selling it to a vendor instead of on the auction house.

```
To Craft: 12s 39c
Profit: -6s               <- Auctionator: sell on the auction house
Vendor Profit: -10s 92c   <- this addon: sell to a vendor
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

## How it's worked out

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

## How it works

- Auctionator makes its crafting info frame (`AuctionatorCraftingInfoProfessionsFrame`) the first time the professions window opens. Vendor Profit hooks the function that makes it, attaches right after, and retries on the next frame in case it sees the event first.
- It adds one FontString to that frame, anchored under Auctionator's text, so it shows and hides with Auctionator's lines.
- It post-hooks the frame's `UpdateTotal`, which Auctionator calls whenever the recipe, reagents or prices change, and refreshes right after.
- Prices come from Auctionator's public API (`Auctionator.API.v1`). The cost to craft calls `Auctionator.CraftingInfo.CalculateCraftCost` so it matches To Craft exactly, with its own reagent total as a fallback.
- It only reads from Auctionator. It never changes Auctionator's text, settings or data, and an error in Vendor Profit is reported without breaking Auctionator's refresh.
- No saved variables.

## Tests

`tests/` loads the addon into a stubbed WoW client and a stubbed Auctionator, running real Lua 5.1:

```powershell
pip install lupa
python tests/test.py
```

The stub is not the real client. Anything it passes still needs checking in game.
