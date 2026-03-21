#!/bin/sh
# release.sh — tag a new oasdiff-action version and update the README
#
# Usage: ./release.sh [new-version]
#   e.g. ./release.sh v0.0.35
#        ./release.sh        # auto-increments the patch version
#

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Resolve version ──────────────────────────────────────────────────────────

if [ -n "$1" ]; then
  NEW="$1"
else
  LATEST=$(git -C "$REPO_DIR" tag --sort=-v:refname | grep '^v[0-9]' | head -1)
  if [ -z "$LATEST" ]; then
    echo "error: no existing tags found — provide a version explicitly" >&2
    exit 1
  fi
  MAJOR=$(echo "$LATEST" | cut -d. -f1)
  MINOR=$(echo "$LATEST" | cut -d. -f2)
  PATCH=$(echo "$LATEST" | cut -d. -f3)
  NEW="${MAJOR}.${MINOR}.$((PATCH + 1))"
fi

case "$NEW" in v*) ;; *) NEW="v${NEW}" ;; esac

OLD=$(git -C "$REPO_DIR" tag --sort=-v:refname | grep '^v[0-9]' | head -1)

if [ "$NEW" = "$OLD" ]; then
  echo "error: new version ($NEW) is the same as the current tag" >&2
  exit 1
fi

echo "Releasing $OLD → $NEW"

# ── Validate git state ───────────────────────────────────────────────────────

cd "$REPO_DIR"

BRANCH=$(git branch --show-current)
if [ "$BRANCH" != "main" ]; then
  echo "error: not on main (currently on '$BRANCH') — check out main before releasing" >&2
  exit 1
fi

git fetch origin main --quiet
if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
  echo "error: local main is not up to date with origin/main — run 'git pull' first" >&2
  exit 1
fi

# ── Tag ──────────────────────────────────────────────────────────────────────

git tag "$NEW"
git push origin "$NEW"
echo "✓ Tagged and pushed $NEW"

# ── Update README.md ─────────────────────────────────────────────────────────

sed -i '' "s|@${OLD}|@${NEW}|g" "$REPO_DIR/README.md"
git add README.md
git commit -m "chore: bump action version to ${NEW}"
git push origin main
echo "✓ Updated README.md and pushed"

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "Release $NEW complete."
echo "  Tag:     https://github.com/oasdiff/oasdiff-action/releases/tag/${NEW}"
echo ""
