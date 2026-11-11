# Route modes: saving time (planning, not built)

Status: **parked, still being planned.** Nothing here is implemented yet. This
records what's been decided so far and what's still open, so the work can pick
up where it left off.

## The problem

Routes always pick the cheapest way to get each item, however small the
saving. Copper bars at 1s 10c to buy and 1s 9c to smelt get smelted: 1 copper
saved per cast, 35 casts for 35 bars. Past a point the time matters more than
a few copper or silver. But losing money, or making 10s instead of 20s, is
never acceptable.

## Decided

### Two modes, Cheapest by default

- **Cheapest**: today's behaviour. The default, so nothing changes until you
  choose otherwise.
- **Save time**: skip crafting steps that don't save enough per craft, without
  giving up more than a set share of the recipe's profit.

The setting is saved per character, on a Route button on the Shopping List's
Profit heading that opens a menu like Best Crafts' Filter. Best Crafts, the
crafting screen's Cheapest Route section and the Shopping List all follow it.

### Worth crafting: a fixed amount saved per craft

A step is worth crafting if crafting it saves at least a set amount **per
craft (cast)** compared with buying: choices of 5s, 10s or 50s, default 10s.
Not a percentage of the price. A fixed amount is a percentage that shrinks as
the price grows:

- copper bar, 1s 10c to buy vs 1s 9c to craft: saves 1c a craft, so buy it
- a 30s item crafted for 25s: saves 5s, under 10s, so buy it
- a 10g item crafted for 9g: saves 1g a craft, so craft it

Per craft, because time is spent in casts. A recipe that makes two per cast
counts the saving on both against that one cast.

### Profit guard

Skipping crafts never gives up more than **10% of the recipe's profit** on the
cheapest route. A plain per-item percentage rule would let cheap skips wipe out
a thin margin (cost 1g, sale 1g 10s: buying intermediates at up to 10% more
could cost the whole 10s profit). If the guard binds, the steps that save the
least per craft are crafted again first.

### Never worse than Cheapest where it matters

- The queued item itself is always crafted.
- Anything with no buy price is crafted.
- A recipe that doesn't make money on the cheapest route uses the cheapest
  route: Save time never turns a profit into a loss.

### No cascading: decide once per queued recipe, over the cheapest tree

Concern: if intermediates are deemed not worth crafting, their higher (bought)
cost feeds into everything made from them, profits shrink level by level, and
eventually nothing looks worth crafting.

Decision: never re-price level by level.

1. Work out the cheapest route for the whole tree, as today.
2. Against that tree, consider switching each crafted step to bought. A switch
   covers everything below it: buying bronze bars skips the bronze, copper and
   tin smelting together, so its saving is spread over all the casts it skips.
3. Apply switches with the smallest saving per skipped cast first, while each
   is under the per-craft amount and the profit guard holds.

Intermediate prices are never recomputed with Save time choices baked in, so
costs can't compound up the tree. Profit drops at most 10% from the best
possible.

### Profit history and items you already have

- Bought items keep their exact cost through every craft, oldest first, as
  today. That's what you spent, whatever the mode.
- Items you already have (farmed, owned before tracking, from an alt) are
  valued by **your setting's route**: under Save time, what you'd pay if the
  route would buy it; under Cheapest, the cheapest way to get it. The same rule
  prices "Items you have" on the Shopping List and own items in Profit History,
  so they always agree.

### Use materials you already have

If the cheapest route would craft a step and you have its materials, craft from
them even when Save time would buy the result: crafting from ore you're already
carrying costs nothing extra, and buying would leave it unused. Exception: if
your materials are worth more than the result (ore selling above the bar), the
step stays bought.

### Live prices: plan changes are the exception, not the rule

1. **Choose once per scan, then hold.** Sources are decided when a scan
   finishes. Buying, crafting and bag changes after that only update
   quantities, never where things come from. Exception: an item whose price
   jumped since the scan (already re-checked today) is reconsidered alone.
2. **A margin to switch.** On a later scan, a step only changes source if the
   other option is clearly better: under Save time by the per-craft amount;
   under Cheapest by a small margin (around 5% of the step's cost), so a copper
   or two doesn't flip a plan.
3. **What you've bought commits you.** Ore bought for a branch keeps that
   branch crafting from it (use what you have), so a later drop in the bar
   price doesn't strand the ore.
4. **Price by the quantity needed.** Buy-or-craft compares the cost of the
   actual quantity, walking up the listings, not the single lowest listing:
   70 bars can cost much more per bar than the cheapest 10.
5. **Say when it changes.** A scan that changes a source says so in one line,
   e.g. *Plan changed: buying Bronze Bar instead of smelting it (saves 14s a
   craft now).*

Expected, not an exception: before the first scan of a session the plan uses
Auctionator's last-seen prices, which can be days old, so the first scan may
change several steps at once. It still says what changed.

## Still open

- The exact Cheapest switching margin (5% of the step's cost is a suggestion).
- Whether the per-craft amount and the 10% guard should be one combined menu
  or two settings.
- Whether cast time should ever matter. Per craft treats every cast as the
  same length; the game does report each recipe's cast time if it's needed.
- How "Plan changed" lines are shown when several steps change at once.
- Tests: route switches, the guard binding, no cascade, use-what-you-have,
  holding sources between scans, the switch margin.
