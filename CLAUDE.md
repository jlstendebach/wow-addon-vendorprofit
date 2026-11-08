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
- **Keep the look consistent.** New controls match the addon's own style
  (the red panel buttons, small icon buttons, gold headings), not whatever
  another window uses. Borrow the game's behavior (its menus, its colors),
  not a mismatched look.
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
2. **Never set the version.** `VendorProfit.toc` says
   `## Version: @project-version@`, and stays that way: the release works the
   version out from the commit messages (see Releases). The PR check fails if
   the line changes.
3. **Update the README** wherever the change shows.
4. If files were added or removed in `VendorProfit/`, say to restart WoW
   rather than `/reload` (the game only reads the file list at startup).
5. **Suggest the commands** (see below). Don't commit, push or merge yourself;
   the developer runs them.

## Releases come from commit messages

Merging into `main` releases the addon if anything in `VendorProfit/` changed
since the last release (`.github/workflows/release.yml`). The version is
worked out from the commits that changed the addon since then
(`scripts/next-version.sh`), the biggest wins:

| Commit | Release | Example |
|---|---|---|
| `feat!: ...`, or `BREAKING CHANGE` in the body | major | 1.26.0 -> 2.0.0 |
| `feat: ...` | minor | 1.26.0 -> 1.27.0 |
| anything else that changed the addon | patch | 1.26.0 -> 1.26.1 |
| changes outside `VendorProfit/` only | none | |

So **the commit message decides the release**; choose the type with care:

- `feat`: something new a player can see or do. Not a tweak to wording or
  layout of something that exists (that's `fix` or `refactor`).
- `fix`: something that didn't work, or worked wrong, now does.
- `perf`: faster, same behavior. `refactor`: restructured, same behavior.
- `docs`, `test`, `ci`, `chore`: no player-facing change. Even these release
  a patch if they touch `VendorProfit/`, so an addon change always ships.
- `!` after the type (`feat!:`) only for changes that break saved data or
  how players use the addon.

One commit per change: don't mix a feature and an unrelated fix in one
commit, so each gets its own type and its own line in the release notes. The
release notes are the commit messages, so write them for players to read.

The PR check (`.github/workflows/test.yml`) runs the tests, fails any commit
that isn't a Conventional Commit, and notes what merging would release.

Deploying locally (`deploy.bat`) stamps the version from git
(`scripts/stamp-version.ps1`): `1.26.0` on a release, `1.26.0-3` three
commits past it. After a merge, `update.bat` brings the branch up to date
with `main`, fetches the tags and deploys.

## Branches and pull requests

`main` is protected: changes reach it only through a pull request, and the
**Tests and commits** check must pass.

- One branch per change, named after its commit: `feat/investment-column`,
  `fix/one-click-open`. A long-lived personal branch is fine too; merge it
  with a merge commit so its commits (and their types) reach `main`.
- **Squash-merge** per-change branches. The squash commit's message is the
  pull request's title, and the release reads that format too
  (`Feat - Best Crafts - ...` counts as a `feat`), so the title's type must
  match the branch's biggest change.
- **If `main` moved on** (someone else merged first), bring the branch up to
  date before merging:
  ```
  git pull --rebase origin main
  git push --force-with-lease
  ```
- **A commit message is wrong** (the check fails, or the type is off): fix it
  before merging with `git rebase -i origin/main` (mark it `reword`), then
  `git push --force-with-lease`.

## The commands

End every reply that changes files with one copyable code block, one command
per line (no `&&`, which fails in Windows PowerShell 5.1). On `main`, start a
branch first; on the change's own branch (or a personal branch), leave that
line out:

```
git switch -c feat/investment-column
git add -A
git commit -m "feat: show investment in best crafts"
git push -u origin HEAD
.\deploy.bat
```

End with `.\deploy.bat` only when something in `VendorProfit/` changed, so
the change can be tried in game; leave it out for docs, tests, scripts and
workflows. After a merge, suggest `.\update.bat` instead of separate pull,
fetch and deploy commands.

The commit message is a short [Conventional Commit](https://www.conventionalcommits.org/):
`type: what changed`, lowercase, under about 50 characters, no period, no
body (except `BREAKING CHANGE: ...` for a major release). Its type decides the
release (see above), so get it right. If a reply makes unrelated changes,
suggest a commit for each (`git add` the files of one, commit, then the next).

Don't write a pull request with every change: a branch often collects
several changes before it's merged. Give the pull request's title and summary
only when the developer asks for them, or makes clear they're ready to open a
pull request or merge. Then cover everything on the branch since `main`
(`git log origin/main..HEAD`), each in its own copyable code block:

- **Title:** `<Type> - <Scope> - <Short description>`, short (a few words
  after the scope), for example `Feat - Best Crafts - Show investment` or
  `Fix - Shopping List - One-click open`. The type is the biggest change's,
  capitalized (`Feat`, `Fix`, `Perf`, `Refactor`, `Test`, `Docs`, `CI`,
  `Chore`); the scope is the part of the addon (`Best Crafts`,
  `Shopping List`, `Profit History`, `Crafting Screen`, `Workflow`, ...).
- **Summary:** a line on what it's for, a few bullets of what changed, and
  what merging releases (a minor or patch release, or none).

A `CLAUDE.local.md` (not in git) may add personal steps; follow it too.
