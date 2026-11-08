# Vendor Profit for Auctionator

A World of Warcraft: Forever addon (Interface 16001, a modern client with the
retail APIs: `C_TradeSkillUI`, `ProfessionsFrame`, `C_AuctionHouse`). It adds
vendor-sale profit to Auctionator's crafting info, works out the cheapest
crafting route, shops for an order, ranks a profession's best crafts and
keeps a profit and purchase history. `README.md` describes every feature and
file; read it before changing anything.

## Rules

- **Only Auctionator.** The addon depends on Auctionator alone and only reads
  from it (its public API, plus the few internals listed in the README). It
  never needs another addon, and never changes Auctionator.
- **Unofficial.** It must not look like it's made by Auctionator's authors:
  keep the title "Vendor Profit for Auctionator", the "Unofficial" note in the
  `.toc`, and the notice in the README.
- **One folder.** Everything the addon needs lives in `VendorProfit/`;
  everything else (tests, README, workflow) is for development.
- **Text** shown in game goes in the `L` table in `Core.lua`; every string
  there must be used, and nothing unused left behind.
- **No secure frames in the panel.** Opening a profession goes through the
  separate overlay in `OpenButton.lua` so the panel stays unprotected.

## Every change

1. **Run the tests**, and add tests for what changed:
   ```
   pip install lupa
   python tests/test.py
   ```
   They load the addon into a stubbed client (`tests/wowstub.lua`); extend the
   stub when the addon uses something new. Passing tests still need checking
   in game, so say what couldn't be tested.
2. **Bump the version** in `VendorProfit/VendorProfit.toc` (`## Version:`)
   with every change to the addon, without being asked:
   - `feat` (something new a player can see or do): minor, `1.24.1` -> `1.25.0`
   - `fix`, `perf`, `refactor` and other changes to the addon: patch,
     `1.24.1` -> `1.24.2`
   - changes outside `VendorProfit/` only (tests, README, workflow): no bump.
   Pushing a new version to `main` releases it automatically
   (`.github/workflows/release.yml`).
3. **Update the README** wherever the change shows.
4. **Suggest the commit**, ending your reply with the git commands in one
   copyable code block, one command per line (no `&&`, which fails in
   Windows PowerShell 5.1):
   ```
   git add -A
   git commit -m "feat: show investment in best crafts"
   ```
   The message is a short [Conventional Commit](https://www.conventionalcommits.org/):
   `type: what changed`, lowercase, under about 50 characters, no period,
   no body. Types: `feat`, `fix`, `perf`, `refactor`, `test`, `docs`, `ci`,
   `chore`. Don't commit or push yourself; the developer runs the commands.
