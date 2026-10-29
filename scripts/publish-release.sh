#!/usr/bin/env bash
# Release flow for the single public repository. `main` is protected (PR-only):
#   prepare <version>  bump the version on release/v<version> and open a PR
#   tag <version>      after the PR is merged: tag origin/main, wait for the
#                      Release workflow, verify the published assets

set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR=""
PHASE="startup"
ROLLBACK_BRANCH=""

cleanup() {
    local status=$?
    trap - ERR
    set +e
    if [[ "$status" -ne 0 && -n "$ROLLBACK_BRANCH" ]]; then
        git reset -q HEAD -- project.yml; git checkout -q -- project.yml
        git switch -q main && git branch -D "$ROLLBACK_BRANCH" >/dev/null 2>&1
        echo "→ Rolled back: branch $ROLLBACK_BRANCH removed, back on main." >&2
    fi
    [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"
    exit "$status"
}

on_error() {
    local status=$?
    echo "Error: phase '$PHASE' failed (exit $status)." >&2
    exit "$status"
}

trap cleanup EXIT
trap on_error ERR

usage() {
    cat <<'USAGE'
Usage:
  ./scripts/publish-release.sh prepare <X.Y.Z> [--skip-build]
  ./scripts/publish-release.sh tag <X.Y.Z>

prepare  Requires a clean, up-to-date main and a "## v<X.Y.Z>" section in
         CHANGELOG.md. Bumps MARKETING_VERSION / CURRENT_PROJECT_VERSION in
         project.yml, runs ./build.sh (unless --skip-build), commits
         "Release v<X.Y.Z>" on branch release/v<X.Y.Z>, pushes it and opens a PR.
         Never pushes to main.
tag      Run after the PR is merged. Tags origin/main as v<X.Y.Z>, pushes the tag,
         waits for the Release workflow and verifies the published assets.
USAGE
}

die() {
    echo "Error [$PHASE]: $*" >&2
    exit 1
}

is_semver() {
    [[ "$1" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
}

version_gt() {
    local left=$1 right=$2
    local l_major l_minor l_patch r_major r_minor r_patch
    IFS=. read -r l_major l_minor l_patch <<< "$left"
    IFS=. read -r r_major r_minor r_patch <<< "$right"
    (( l_major > r_major )) ||
        (( l_major == r_major && l_minor > r_minor )) ||
        (( l_major == r_major && l_minor == r_minor && l_patch > r_patch ))
}

# Print the value of a unique `KEY: "value"` line from a project.yml stream.
project_value() {
    local key=$1
    awk -v key="$key" '
        $1 == key ":" {
            value=$2
            gsub(/^"|"$/, "", value)
            print value
            count++
        }
        END { if (count != 1) exit 2 }
    '
}

read_project_value() {
    project_value "$2" < "$1"
}

# Number of "## v<version>" or "## [<version>]" headings on stdin.
changelog_version_count() {
    awk -v version="$1" '
        {
            for (i = 0; i < 2; i++) {
                prefix = (i == 0) ? "## v" version : "## [" version "]"
                if (index($0, prefix) == 1) {
                    suffix = substr($0, length(prefix) + 1, 1)
                    if (suffix == "" || suffix ~ /[[:space:]]/) count++
                }
            }
        }
        END { print count + 0 }
    '
}

verify_release() {
    local tag=$1 version=$2 repo=$3 asset_names expected asset_dir
    PHASE="verify release"
    gh release view "$tag" --repo "$repo" >/dev/null
    [[ "$(gh release view "$tag" --repo "$repo" --json isDraft --jq '.isDraft')" == "false" ]] ||
        die "release $tag is still a draft"
    asset_names=$(gh release view "$tag" --repo "$repo" --json assets --jq '.assets[].name')
    for expected in \
        "LingoPop-$version-mac-universal.dmg" \
        "LingoPop-$version-mac-universal.zip" \
        "SHA256SUMS"; do
        printf '%s\n' "$asset_names" | grep -Fxq "$expected" ||
            die "release $tag is missing asset $expected"
    done

    WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/lingopop-verify.XXXXXX")
    asset_dir="$WORK_DIR/assets"
    mkdir -p "$asset_dir"
    gh release download "$tag" --repo "$repo" --dir "$asset_dir" \
        --pattern "LingoPop-$version-mac-universal.dmg" \
        --pattern "LingoPop-$version-mac-universal.zip" \
        --pattern "SHA256SUMS"
    (cd "$asset_dir" && shasum -a 256 -c SHA256SUMS)
}

require_gh() {
    command -v gh >/dev/null 2>&1 || die "gh CLI is required"
    gh auth status >/dev/null 2>&1 || die "gh CLI is not authenticated"
}

cmd_prepare() {
    local version=$1 skip_build=$2
    local tag="v$version" branch="release/v$version"
    local current_version current_build target_build current_branch tmp

    PHASE="local preflight"
    current_version=$(read_project_value project.yml MARKETING_VERSION) ||
        die "project.yml must contain exactly one MARKETING_VERSION"
    current_build=$(read_project_value project.yml CURRENT_PROJECT_VERSION) ||
        die "project.yml must contain exactly one CURRENT_PROJECT_VERSION"
    is_semver "$current_version" || die "invalid MARKETING_VERSION in project.yml: $current_version"
    [[ "$current_build" =~ ^(0|[1-9][0-9]*)$ ]] ||
        die "CURRENT_PROJECT_VERSION must be a non-negative integer without leading zeroes"
    version_gt "$version" "$current_version" ||
        die "version $version must be greater than current $current_version"
    target_build=$((current_build + 1))

    [[ "$(changelog_version_count "$version" < CHANGELOG.md)" == "1" ]] ||
        die "CHANGELOG.md must contain exactly one '## v$version' section"

    current_branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)
    [[ "$current_branch" == "main" ]] ||
        die "prepare must run on main (current: ${current_branch:-detached HEAD})"
    [[ -z "$(git status --porcelain)" ]] || die "worktree must be clean"
    require_gh

    PHASE="fetch"
    git fetch --prune origin main
    [[ "$(git rev-parse HEAD)" == "$(git rev-parse refs/remotes/origin/main)" ]] ||
        die "local main must equal origin/main"
    ! git rev-parse -q --verify "refs/heads/$branch" >/dev/null || die "local branch $branch already exists"
    [[ -z "$(git ls-remote --heads origin "$branch")" ]] || die "remote branch $branch already exists"

    PHASE="create branch"
    git switch -c "$branch"
    ROLLBACK_BRANCH=$branch   # removed again by cleanup() if anything fails before the commit

    PHASE="bump version"
    tmp=$(mktemp "${TMPDIR:-/tmp}/lingopop-project.XXXXXX")
    awk -v version="$version" -v build="$target_build" '
        $1 == "MARKETING_VERSION:" { sub(/"[^"]*"/, "\"" version "\""); marketing++; print; next }
        $1 == "CURRENT_PROJECT_VERSION:" { sub(/"[^"]*"/, "\"" build "\""); current++; print; next }
        { print }
        END { if (marketing != 1 || current != 1) exit 2 }
    ' project.yml > "$tmp" || die "could not safely update the two version keys"
    cat "$tmp" > project.yml
    rm -f "$tmp"
    [[ "$(git diff --numstat -- project.yml | awk '{print $1 ":" $2}')" == "2:2" ]] ||
        die "expected exactly two replaced lines in project.yml"

    if [[ "$skip_build" -eq 1 ]]; then
        echo "WARNING: --skip-build is active; the version bump is not locally build-verified."
    else
        PHASE="local build"
        echo "→ Building $version..."
        ./build.sh
    fi

    PHASE="commit"
    git add -- project.yml
    git commit -m "Release $tag"
    ROLLBACK_BRANCH=""
    PHASE="push branch"
    git push -u origin "$branch"

    PHASE="open pull request"
    gh pr create --fill --base main --head "$branch"
    echo "✓ Merge the PR, then run: ./scripts/publish-release.sh tag $version"
}

cmd_tag() {
    local version=$1 tag="v$1"
    local main_version commit repo run_id run_url attempt=0

    require_gh

    PHASE="fetch"
    git fetch --prune origin main --tags

    PHASE="preflight"
    ! git rev-parse -q --verify "refs/tags/$tag" >/dev/null || die "local tag $tag already exists"
    [[ -z "$(git ls-remote --tags origin "refs/tags/$tag")" ]] || die "remote tag $tag already exists"
    main_version=$(git show origin/main:project.yml | project_value MARKETING_VERSION) ||
        die "origin/main:project.yml must contain exactly one MARKETING_VERSION"
    [[ "$main_version" == "$version" ]] ||
        die "origin/main has MARKETING_VERSION $main_version, expected $version (is the release PR merged?)"

    commit=$(git rev-parse refs/remotes/origin/main)
    repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)

    PHASE="push tag"
    git tag -a "$tag" "$commit" -m "Release $tag"
    echo "→ Pushing $tag ($commit)..."
    git push origin "refs/tags/$tag"

    PHASE="locate release workflow"
    run_id=""
    while [[ -z "$run_id" && "$attempt" -lt 30 ]]; do
        run_id=$(gh run list --repo "$repo" --workflow Release --event push --branch "$tag" \
            --limit 5 --json databaseId,headSha \
            --jq ".[] | select(.headSha == \"$commit\") | .databaseId" | sed -n '1p')
        [[ -n "$run_id" ]] || { sleep 2; attempt=$((attempt + 1)); }
    done
    [[ -n "$run_id" ]] || die "could not find the Release workflow run for $tag"
    run_url=$(gh run view "$run_id" --repo "$repo" --json url --jq '.url')
    echo "→ Workflow: $run_url"

    PHASE="wait for release workflow"
    gh run watch "$run_id" --repo "$repo" --exit-status

    verify_release "$tag" "$version" "$repo"

    echo "✓ Release $tag completed successfully."
    echo "  Commit:   $commit"
    echo "  Workflow: $run_url"
    echo "  Release:  https://github.com/$repo/releases/tag/$tag"
}

[[ $# -gt 0 ]] || { usage >&2; exit 2; }

SUBCOMMAND=$1
shift
case "$SUBCOMMAND" in
    -h|--help) usage; exit 0 ;;
    prepare|tag) ;;
    *) usage >&2; exit 2 ;;
esac

VERSION=""
SKIP_BUILD=0
for arg in "$@"; do
    case "$arg" in
        --skip-build)
            [[ "$SUBCOMMAND" == prepare ]] || { usage >&2; exit 2; }
            SKIP_BUILD=1
            ;;
        -h|--help) usage; exit 0 ;;
        --*) usage >&2; exit 2 ;;
        *)
            [[ -z "$VERSION" ]] || { usage >&2; exit 2; }
            VERSION=$arg
            ;;
    esac
done
[[ -n "$VERSION" ]] || { usage >&2; exit 2; }
is_semver "$VERSION" || die "invalid version '$VERSION' (expected X.Y.Z)"

cd "$PROJECT_DIR"
if [[ "$SUBCOMMAND" == prepare ]]; then
    cmd_prepare "$VERSION" "$SKIP_BUILD"
else
    cmd_tag "$VERSION"
fi
