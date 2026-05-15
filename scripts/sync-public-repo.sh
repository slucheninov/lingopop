#!/usr/bin/env bash
# Push contents of ./public-repo/ to the public GitHub repo.
#
# Run this whenever you change anything in public-repo/ (README, CHANGELOG,
# issue templates, etc.). Authentication uses gh CLI — run `gh auth login`
# once if you haven't.
#
# Usage:
#   ./scripts/sync-public-repo.sh                 # commits with default message
#   ./scripts/sync-public-repo.sh "Custom message"
#   ./scripts/sync-public-repo.sh --dry-run       # show diff without pushing

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PUBLIC_REPO="${PUBLIC_REPO:-slucheninov/lingopop}"
SOURCE_DIR="$PROJECT_DIR/public-repo"

if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "Error: $SOURCE_DIR doesn't exist." >&2
    exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
    echo "Error: gh CLI not found. Install with 'brew install gh', then 'gh auth login'." >&2
    exit 1
fi

DRY_RUN=0
COMMIT_MSG=""
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -h|--help)
            grep '^#' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) COMMIT_MSG="$arg" ;;
    esac
done

if [[ -z "$COMMIT_MSG" ]]; then
    COMMIT_MSG="Sync public docs from private repo ($(date +%Y-%m-%d))"
fi

WORK_DIR="$(mktemp -d -t lingopop-public-sync)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "→ Cloning $PUBLIC_REPO into $WORK_DIR..."
gh repo clone "$PUBLIC_REPO" "$WORK_DIR/repo" -- --quiet

cd "$WORK_DIR/repo"

echo "→ Mirroring $SOURCE_DIR → ."
# Pure upsert: copy everything from public-repo/ on top of the clone.
# We intentionally do NOT use --delete so that screenshots committed via the
# GitHub web UI (or any other extra files) are preserved.
rsync -av --exclude='.git' "$SOURCE_DIR/" ./

git add -A
if git diff --cached --quiet; then
    echo "✓ Public repo already in sync — no changes."
    exit 0
fi

echo ""
echo "→ Changes about to be committed:"
git diff --cached --stat
echo ""

if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "(dry run — not committing or pushing)"
    exit 0
fi

git -c user.email="actions@github.com" -c user.name="LingoPop maintainer" \
    commit -m "$COMMIT_MSG"
git push
echo "✓ Pushed to $PUBLIC_REPO."
