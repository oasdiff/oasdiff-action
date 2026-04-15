#!/bin/sh
# release.sh — tag a new oasdiff-action version and update the README
#
# Usage: ./release.sh [new-version] [oasdiff-version]
#   e.g. ./release.sh v0.0.35
#        ./release.sh v0.0.35 v1.13.5   # also pin the oasdiff CLI image to v1.13.5
#        ./release.sh                    # auto-increments the patch version
#

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

DOCKERFILES="breaking/Dockerfile changelog/Dockerfile diff/Dockerfile pr-comment/Dockerfile"

# ── Resolve action version ───────────────────────────────────────────────────

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

# ── Resolve oasdiff version ──────────────────────────────────────────────────

OASDIFF_VERSION=""
if [ -n "$2" ]; then
  OASDIFF_VERSION="$2"
  case "$OASDIFF_VERSION" in v*) ;; *) OASDIFF_VERSION="v${OASDIFF_VERSION}" ;; esac
fi

CURRENT_OASDIFF=$(grep -m1 'FROM tufin/oasdiff:' "$REPO_DIR/breaking/Dockerfile" | sed 's/FROM tufin\/oasdiff://')

if [ -n "$OASDIFF_VERSION" ]; then
  echo "Releasing $OLD → $NEW  (oasdiff ${CURRENT_OASDIFF} → ${OASDIFF_VERSION})"
else
  echo "Releasing $OLD → $NEW  (oasdiff ${CURRENT_OASDIFF}, unchanged)"
fi

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

# ── Verify CI passed on HEAD ─────────────────────────────────────────────────

HEAD_SHA=$(git rev-parse HEAD)
echo "Checking CI status for $(git rev-parse --short HEAD)..."
CI_STATE=$(gh api "repos/oasdiff/oasdiff-action/commits/${HEAD_SHA}/status" --jq '.state' 2>/dev/null || echo "unknown")
CI_CHECKS=$(gh api "repos/oasdiff/oasdiff-action/commits/${HEAD_SHA}/check-runs" --jq '[.check_runs[] | select(.conclusion != "success" and .conclusion != "skipped" and .conclusion != null)] | length' 2>/dev/null || echo "unknown")

if [ "$CI_STATE" = "failure" ] || [ "$CI_CHECKS" != "0" ]; then
  echo "error: CI checks failed on HEAD — fix tests before releasing" >&2
  echo "  See: https://github.com/oasdiff/oasdiff-action/actions" >&2
  exit 1
elif [ "$CI_STATE" = "pending" ] || [ "$CI_CHECKS" = "unknown" ]; then
  echo "warning: CI status is pending or unknown — tests may not have run yet" >&2
  printf "Continue anyway? [y/N] "
  read -r answer
  case "$answer" in [yY]*) ;; *) echo "Aborted."; exit 1 ;; esac
fi

echo "✓ CI passed on HEAD"

# ── Tag ──────────────────────────────────────────────────────────────────────

git tag "$NEW"
git push origin "$NEW"
echo "✓ Tagged and pushed $NEW"

# ── Update Dockerfiles ───────────────────────────────────────────────────────

if [ -n "$OASDIFF_VERSION" ]; then
  for df in $DOCKERFILES; do
    sed -i '' "s|FROM tufin/oasdiff:.*|FROM tufin/oasdiff:${OASDIFF_VERSION}|" "$REPO_DIR/$df"
  done
  echo "✓ Updated Dockerfiles: oasdiff ${CURRENT_OASDIFF} → ${OASDIFF_VERSION}"
fi

# ── Update README.md and commit ──────────────────────────────────────────────

sed -i '' "s|@${OLD}|@${NEW}|g" "$REPO_DIR/README.md"

if [ -n "$OASDIFF_VERSION" ]; then
  COMMIT_MSG="chore: bump action to ${NEW}, pin oasdiff to ${OASDIFF_VERSION}"
  # shellcheck disable=SC2086
  git add README.md $DOCKERFILES
else
  COMMIT_MSG="chore: bump action version to ${NEW}"
  git add README.md
fi

git commit -m "$COMMIT_MSG"
git push origin main
echo "✓ Updated README.md and pushed"

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "Release $NEW complete."
echo "  Tag:     https://github.com/oasdiff/oasdiff-action/releases/tag/${NEW}"
echo ""
