#!/usr/bin/env bash
# Checks that every commit in a range is a Conventional Commit, since the
# release version is worked out from them (scripts/next-version.sh).
# Usage: check-commits.sh <base> <head>
set -euo pipefail

pattern='^(feat|fix|perf|refactor|test|docs|ci|chore|build|style|revert)(\([a-z0-9 _/-]+\))?!?: .+'
bad=0
while IFS= read -r line; do
    [ -n "$line" ] || continue
    sha=${line%% *}
    subject=${line#* }
    if ! [[ "$subject" =~ $pattern ]]; then
        echo "::error::${sha:0:7} \"$subject\" isn't a Conventional Commit (type: description), so the release can't tell what it is. Reword it: git rebase -i, then git push --force-with-lease."
        bad=1
    fi
done < <(git log --no-merges --format='%H %s' "$1..$2")
exit $bad
