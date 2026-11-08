#!/usr/bin/env bash
# Works out the next release version from the commits since the last release.
#
# Prints "<version> <last tag or none>" and exits 0 when there's something to
# release, or prints nothing and exits 0 when there isn't.
#
# Only commits that changed VendorProfit/ count. Their types decide the bump,
# the biggest wins:
#   feat!: ... or BREAKING CHANGE in the body      major  1.4.2 -> 2.0.0
#   feat: ...                                        minor  1.4.2 -> 1.5.0
#   anything else (fix, perf, refactor, docs, ...)   patch  1.4.2 -> 1.4.3
# Squash merges use the PR title as the message, so "Feat - Scope - Title"
# counts the same as "feat: title". With no release yet, it counts up from
# 0.0.0.
set -euo pipefail

last=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2> /dev/null || true)
range=${last:+$last..}HEAD

bump=0   # 0 nothing, 1 patch, 2 minor, 3 major
while IFS= read -r sha; do
    [ -n "$sha" ] || continue
    subject=$(git log -1 --format=%s "$sha")
    body=$(git log -1 --format=%b "$sha")
    lower=$(printf '%s' "$subject" | tr '[:upper:]' '[:lower:]')
    level=1
    if [[ "$lower" =~ ^[a-z]+(\([^\)]*\))?! ]] || [[ "$body" == *"BREAKING CHANGE"* ]]; then
        level=3
    elif [[ "$lower" =~ ^feat(\([^\)]*\))?: ]] || [[ "$lower" =~ ^feat[[:space:]]+-[[:space:]] ]]; then
        level=2
    fi
    (( level > bump )) && bump=$level
done < <(git log --no-merges --format=%H "$range" -- VendorProfit)

if (( bump == 0 )); then
    exit 0
fi

version=${last#v}
version=${version:-0.0.0}
IFS=. read -r major minor patch <<< "$version"
case $bump in
    3) major=$((major + 1)); minor=0; patch=0 ;;
    2) minor=$((minor + 1)); patch=0 ;;
    1) patch=$((patch + 1)) ;;
esac
echo "$major.$minor.$patch ${last:-none}"
