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
  everything else (tests, README, workflows) is for development.
- **Text** shown in game goes in the `L` table in `Core.lua`; every string
  there must be used, and nothing unused left behind.
- **Money** is shown with `VendorProfit.FormatMoney` (silver and copper
  always two digits after a larger coin: 5s 07c).
- **No secure frames in the panel.** Opening a profession goes through the
  separate overlay in `OpenButton.lua` so the panel stays unprotected and
  works in combat.
- **Other addons are references, not sources.** When unsure how a Forever API
  or Auctionator behaves, read the installed Auctionator and TradeSkillMaster
  code to find out, and say what you found. Don't copy their code
  (TradeSkillMaster's is all rights reserved).

## How we work

- **Pick a side.** When there are options, recommend one and say why, briefly;
  the developer may still choose differently. Push back when a request has a
  problem.
- **Just do clear, cheap work.** Ask first only when a change is big or costly
  to redo, or the request is ambiguous; then explain the plan in a few lines
  and ask once.
- **Be honest about what's untested.** The tests use a stub, not the game. Say
  which parts depend on game behavior you couldn't check, and what to look
  for in game. Never claim something works in game unless it was seen there.
- **Explain causes.** For a bug, say what actually went wrong before the fix.
- **Comments say why.** Each file starts with what it's for; comments explain
  reasons and game quirks, not what the code obviously does.
- **Short replies.** End with what changed (a few bullets at most), what to
  check in game, the new version and the test count, then the commands. No
  recap of the steps taken.

## Every change

1. **Run the tests**, and add tests for what changed:
   ```
   pip install lupa
   python tests/test.py
   ```
   They load the addon into a stubbed client (`tests/wowstub.lua`); extend the
   stub when the addon uses something new.
2. **Bump the version** in `VendorProfit/VendorProfit.toc` (`## Version:`)
   with every change to the addon, without being asked, counting up from the
   version on `main`:
   - `feat` (something new a player can see or do): minor, `1.24.1` -> `1.25.0`
   - `fix`, `perf`, `refactor` and other changes to the addon: patch,
     `1.24.1` -> `1.24.2`
   - changes outside `VendorProfit/` only (tests, README, workflows): no bump.
3. **Update the README** wherever the change shows.
4. If files were added or removed in `VendorProfit/`, say to restart WoW
   rather than `/reload` (the game only reads the file list at startup).
5. **Suggest the commands** (see below). Don't commit, push or merge yourself;
   the developer runs them.

## Branches and pull requests

`main` is protected: changes reach it only through a pull request, and the
**Test** check (`.github/workflows/test.yml`) must pass: the tests, and, if
the addon changed, a version higher than `main`'s. Merging releases it
(`.github/workflows/release.yml`): a zip and a GitHub release tagged with the
version, with the commit messages as its notes.

- One branch per change, named after its commit: `feat/investment-column`,
  `fix/one-click-open`.
- **Squash-merge** pull requests, so `main` (and the release notes) get one
  line per change: the pull request's title.
- **If `main` moved on** (someone else merged first), bring the branch up to
  date before merging:
  ```
  git pull --rebase origin main
  ```
  If `VendorProfit.toc` conflicts, both changes bumped the version: take
  `main`'s version and bump again from it (never keep your own number), then:
  ```
  git add VendorProfit/VendorProfit.toc
  git rebase --continue
  git push --force-with-lease
  ```

## The commands

End every reply that changes files with one copyable code block, one command
per line (no `&&`, which fails in Windows PowerShell 5.1). On `main`, start a
branch first; on the change's own branch, leave that line out:

```
git switch -c feat/investment-column
git add -A
git commit -m "feat: show investment in best crafts"
git push -u origin HEAD
```

Then say to open the pull request from the link `git push` prints, and give
its title and summary, each in its own copyable code block:

- **Title:** `<Type> - <Scope> - <Short description>`, for example
  `Feat - Best Crafts - Show investment per craft` or
  `Fix - Shopping List - Open professions with one click`. The type is the
  commit's, capitalized (`Feat`, `Fix`, `Perf`, `Refactor`, `Test`, `Docs`,
  `CI`, `Chore`); the scope is the part of the addon (`Best Crafts`,
  `Shopping List`, `Profit History`, `Crafting Screen`, `Workflow`, ...).
- **Summary:** a line on what it's for, a few bullets of what changed, and
  the new version (or that there's none, and so no release).

The commit message is a short [Conventional Commit](https://www.conventionalcommits.org/):
`type: what changed`, lowercase, under about 50 characters, no period, no
body. Types: `feat`, `fix`, `perf`, `refactor`, `test`, `docs`, `ci`,
`chore`.

A `CLAUDE.local.md` (not in git) may add personal steps; follow it too.
