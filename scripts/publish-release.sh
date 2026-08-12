#!/usr/bin/env bash
# Publish a LingoPop release from private main to the public product repository.

set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PUBLIC_REPO="${PUBLIC_REPO:-slucheninov/lingopop}"
WORK_DIR=""
PHASE="startup"
PROJECT_BACKUP=""
RELEASE_COMMITTED=0

cleanup() {
    local status=$?
    trap - ERR
    set +e
    if [[ -n "$PROJECT_BACKUP" && -f "$PROJECT_BACKUP" && "$RELEASE_COMMITTED" -eq 0 ]]; then
        if git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
            ! git -C "$PROJECT_DIR" diff --cached --quiet -- project.yml; then
            git -C "$PROJECT_DIR" reset -q HEAD -- project.yml
        fi
        cp "$PROJECT_BACKUP" "$PROJECT_DIR/project.yml"
        echo "→ Restored project.yml because the release commit was not created." >&2
    fi
    if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
        rm -rf -- "$WORK_DIR"
    fi
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
    cat <<'EOF'
Usage:
  ./scripts/publish-release.sh patch|minor|major|X.Y.Z [--dry-run] [--skip-build] [--message TEXT]

Options:
  --dry-run       Print the release plan. No files, Git refs, remotes, or network are changed.
  --skip-build    Skip ./build.sh (risky; intended only when the same commit was already verified).
  --message TEXT  Commit message (default: Release vX.Y.Z).
  -h, --help      Show this help.

To resume a partially completed release, invoke the script with the exact X.Y.Z.
EOF
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

bump_version() {
    local current=$1 kind=$2
    local major minor patch
    IFS=. read -r major minor patch <<< "$current"
    case "$kind" in
        patch) patch=$((patch + 1)) ;;
        minor) minor=$((minor + 1)); patch=0 ;;
        major) major=$((major + 1)); minor=0; patch=0 ;;
        *) die "internal error: unsupported bump '$kind'" ;;
    esac
    printf '%s.%s.%s\n' "$major" "$minor" "$patch"
}

read_project_value() {
    local file=$1 key=$2
    awk -v key="$key" '
        $1 == key ":" {
            value=$2
            gsub(/^"|"$/, "", value)
            print value
            count++
        }
        END { if (count != 1) exit 2 }
    ' "$file"
}

project_value_at_commit() {
    local commit=$1 key=$2
    git show "$commit:project.yml" | awk -v key="$key" '
        $1 == key ":" {
            value=$2
            gsub(/^"|"$/, "", value)
            print value
            count++
        }
        END { if (count != 1) exit 2 }
    '
}

origin_repo_slug() {
    local url=$1 slug
    case "$url" in
        git@github.com:*) slug=${url#git@github.com:} ;;
        https://github.com/*) slug=${url#https://github.com/} ;;
        ssh://git@github.com/*) slug=${url#ssh://git@github.com/} ;;
        *) return 1 ;;
    esac
    slug=${slug%.git}
    [[ "$slug" == */* ]] || return 1
    printf '%s\n' "$slug"
}

is_valid_resume_commit() {
    local target=$1 current_build=$2
    local parent parent_version parent_build changed
    parent=$(git rev-parse HEAD^ 2>/dev/null) || return 1
    changed=$(git diff-tree --no-commit-id --name-only -r HEAD)
    [[ "$changed" == "project.yml" ]] || return 1
    parent_version=$(project_value_at_commit "$parent" MARKETING_VERSION) || return 1
    parent_build=$(project_value_at_commit "$parent" CURRENT_PROJECT_VERSION) || return 1
    is_semver "$parent_version" || return 1
    [[ "$parent_build" =~ ^[0-9]+$ ]] || return 1
    version_gt "$target" "$parent_version" || return 1
    (( current_build == parent_build + 1 )) || return 1
}

remote_tag_commit() {
    local tag=$1 output peeled direct
    output=$(git ls-remote --tags origin "refs/tags/$tag" "refs/tags/$tag^{}")
    peeled=$(printf '%s\n' "$output" | awk '$2 ~ /\^\{\}$/ {print $1; exit}')
    direct=$(printf '%s\n' "$output" | awk '$2 !~ /\^\{\}$/ {print $1; exit}')
    printf '%s\n' "${peeled:-$direct}"
}

verify_public_release() {
    local tag=$1 version=$2 asset_names expected asset_dir
    PHASE="verify public release"
    gh release view "$tag" --repo "$PUBLIC_REPO" >/dev/null
    [[ "$(gh release view "$tag" --repo "$PUBLIC_REPO" --json isDraft --jq '.isDraft')" == "false" ]] ||
        die "public release $tag is still a draft"
    asset_names=$(gh release view "$tag" --repo "$PUBLIC_REPO" --json assets --jq '.assets[].name')
    for expected in \
        "LingoPop-$version-mac-universal.dmg" \
        "LingoPop-$version-mac-universal.zip" \
        "SHA256SUMS"; do
        printf '%s\n' "$asset_names" | grep -Fxq "$expected" ||
            die "public release $tag is missing asset $expected"
    done

    asset_dir="$WORK_DIR/assets"
    mkdir -p "$asset_dir"
    gh release download "$tag" --repo "$PUBLIC_REPO" --dir "$asset_dir" \
        --pattern "LingoPop-$version-mac-universal.dmg" \
        --pattern "LingoPop-$version-mac-universal.zip" \
        --pattern "SHA256SUMS"
    (cd "$asset_dir" && shasum -a 256 -c SHA256SUMS)
}

[[ $# -gt 0 ]] || { usage >&2; exit 2; }

VERSION_ARG=""
DRY_RUN=0
SKIP_BUILD=0
COMMIT_MESSAGE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        patch|minor|major)
            [[ -z "$VERSION_ARG" ]] || die "specify exactly one version or bump kind"
            VERSION_ARG=$1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --skip-build)
            SKIP_BUILD=1
            shift
            ;;
        --message)
            [[ $# -ge 2 && -n "$2" ]] || die "--message requires non-empty text"
            COMMIT_MESSAGE=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --*) die "unknown option: $1" ;;
        *)
            if is_semver "$1"; then
                [[ -z "$VERSION_ARG" ]] || die "specify exactly one version or bump kind"
                VERSION_ARG=$1
                shift
            else
                die "invalid version '$1' (expected patch, minor, major, or X.Y.Z)"
            fi
            ;;
    esac
done

[[ -n "$VERSION_ARG" ]] || die "a version or bump kind is required"
if [[ "$DRY_RUN" -eq 1 ]]; then
    export GIT_OPTIONAL_LOCKS=0
fi
cd "$PROJECT_DIR"

PHASE="read project version"
CURRENT_VERSION=$(read_project_value project.yml MARKETING_VERSION) ||
    die "project.yml must contain exactly one MARKETING_VERSION"
CURRENT_BUILD=$(read_project_value project.yml CURRENT_PROJECT_VERSION) ||
    die "project.yml must contain exactly one CURRENT_PROJECT_VERSION"
is_semver "$CURRENT_VERSION" || die "invalid MARKETING_VERSION in project.yml: $CURRENT_VERSION"
[[ "$CURRENT_BUILD" =~ ^(0|[1-9][0-9]*)$ ]] ||
    die "CURRENT_PROJECT_VERSION must be a non-negative integer without leading zeroes"

RESUME=0
if [[ "$VERSION_ARG" == patch || "$VERSION_ARG" == minor || "$VERSION_ARG" == major ]]; then
    TARGET_VERSION=$(bump_version "$CURRENT_VERSION" "$VERSION_ARG")
else
    TARGET_VERSION=$VERSION_ARG
    if version_gt "$TARGET_VERSION" "$CURRENT_VERSION"; then
        :
    elif [[ "$TARGET_VERSION" == "$CURRENT_VERSION" ]] &&
        is_valid_resume_commit "$TARGET_VERSION" "$CURRENT_BUILD"; then
        RESUME=1
    else
        die "exact version must be higher than current $CURRENT_VERSION (equality is allowed only for a validated resume commit)"
    fi
fi

if [[ "$RESUME" -eq 1 ]]; then
    TARGET_BUILD=$CURRENT_BUILD
else
    TARGET_BUILD=$((CURRENT_BUILD + 1))
fi
TAG="v$TARGET_VERSION"
[[ -n "$COMMIT_MESSAGE" ]] || COMMIT_MESSAGE="Release $TAG"

BRANCH=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)
UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)
ORIGIN_URL=$(git remote get-url origin 2>/dev/null || true)
PRIVATE_REPO=$(origin_repo_slug "$ORIGIN_URL" 2>/dev/null || true)
DIRTY=$(git status --porcelain)

if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "DRY RUN — no files, refs, remotes, builds, or network calls will be changed."
    echo "Current version/build: $CURRENT_VERSION ($CURRENT_BUILD)"
    echo "Target version/build:  $TARGET_VERSION ($TARGET_BUILD)"
    echo "Commit message:        $COMMIT_MESSAGE"
    echo "Public repository:     $PUBLIC_REPO"
    [[ "$SKIP_BUILD" -eq 0 ]] || echo "WARNING: --skip-build would bypass local build verification."
    blockers=0
    if [[ -n "$DIRTY" ]]; then
        echo "BLOCKER for real run: worktree is dirty (dry-run continues)." >&2
        blockers=1
    fi
    if [[ "$BRANCH" != "main" ]]; then
        echo "BLOCKER for real run: branch is '${BRANCH:-detached}', expected main." >&2
        blockers=1
    fi
    if [[ -z "$ORIGIN_URL" || "$UPSTREAM" != "origin/main" ]]; then
        echo "BLOCKER for real run: origin/upstream is missing or upstream is not origin/main." >&2
        blockers=1
    fi
    echo "Planned phases: preflight/fetch → build → version commit → push private main → sync public docs → push annotated tag → wait for exact CI run → verify public assets and checksums"
    if [[ "$blockers" -eq 1 ]]; then
        echo "Dry-run completed with blockers; no changes were made."
    else
        echo "Dry-run completed; remote-only checks are deferred to the real run."
    fi
    exit 0
fi

PHASE="local preflight"
[[ -z "$DIRTY" ]] || die "worktree must be clean"
[[ "$BRANCH" == "main" ]] || die "release must run on main (current: ${BRANCH:-detached HEAD})"
[[ -n "$ORIGIN_URL" ]] || die "origin remote is missing"
[[ "$UPSTREAM" == "origin/main" ]] || die "main must track origin/main (current: ${UPSTREAM:-none})"
[[ -n "$PRIVATE_REPO" ]] || die "origin must be a GitHub repository URL"
command -v gh >/dev/null 2>&1 || die "gh CLI is required"
command -v rsync >/dev/null 2>&1 || die "rsync is required"
gh auth status >/dev/null || die "gh CLI is not authenticated"

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/lingopop-publish.XXXXXX")

PHASE="fetch private state"
echo "→ Fetching origin/main and tags..."
git fetch --prune origin main --tags

HEAD_COMMIT=$(git rev-parse HEAD)
REMOTE_MAIN=$(git rev-parse refs/remotes/origin/main)
if [[ "$RESUME" -eq 1 ]]; then
    PARENT_COMMIT=$(git rev-parse HEAD^)
    if [[ "$REMOTE_MAIN" != "$HEAD_COMMIT" && "$REMOTE_MAIN" != "$PARENT_COMMIT" ]]; then
        die "resume requires origin/main to equal the release commit or its direct parent"
    fi
    RELEASE_COMMIT=$HEAD_COMMIT
    TARGET_BUILD=$CURRENT_BUILD
    echo "→ Validated resume at $TAG ($RELEASE_COMMIT)."
else
    [[ "$HEAD_COMMIT" == "$REMOTE_MAIN" ]] ||
        die "local main must equal origin/main before starting a release"
fi

LOCAL_TAG_COMMIT=""
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    LOCAL_TAG_COMMIT=$(git rev-list -n 1 "$TAG")
fi
REMOTE_TAG_COMMIT=$(remote_tag_commit "$TAG")
PUBLIC_RELEASE_EXISTS=0
PUBLIC_RELEASE_ERROR="$WORK_DIR/public-release-error"
if gh api "repos/$PUBLIC_REPO/releases/tags/$TAG" --silent 2>"$PUBLIC_RELEASE_ERROR"; then
    PUBLIC_RELEASE_EXISTS=1
elif grep -q "HTTP 404" "$PUBLIC_RELEASE_ERROR"; then
    PUBLIC_RELEASE_EXISTS=0
else
    sed -n '1,5p' "$PUBLIC_RELEASE_ERROR" >&2
    die "could not determine whether public release $TAG exists"
fi

if [[ "$RESUME" -eq 0 ]]; then
    [[ -z "$LOCAL_TAG_COMMIT" ]] || die "local tag $TAG already exists"
    [[ -z "$REMOTE_TAG_COMMIT" ]] || die "remote tag $TAG already exists"
    [[ "$PUBLIC_RELEASE_EXISTS" -eq 0 ]] || die "public release $TAG already exists"

    PHASE="update project version"
    PROJECT_BACKUP="$WORK_DIR/project.yml.original"
    cp project.yml "$PROJECT_BACKUP"
    UPDATE_FILE=$(mktemp "$PROJECT_DIR/.publish-project.XXXXXX")
    awk -v version="$TARGET_VERSION" -v build="$TARGET_BUILD" '
        $1 == "MARKETING_VERSION:" { sub(/"[^"]*"/, "\"" version "\""); marketing++; print; next }
        $1 == "CURRENT_PROJECT_VERSION:" { sub(/"[^"]*"/, "\"" build "\""); current++; print; next }
        { print }
        END { if (marketing != 1 || current != 1) exit 2 }
    ' project.yml > "$UPDATE_FILE" || die "could not safely update the two version keys"
    mv "$UPDATE_FILE" project.yml

    [[ "$(read_project_value project.yml MARKETING_VERSION)" == "$TARGET_VERSION" ]] ||
        die "MARKETING_VERSION verification failed"
    [[ "$(read_project_value project.yml CURRENT_PROJECT_VERSION)" == "$TARGET_BUILD" ]] ||
        die "CURRENT_PROJECT_VERSION verification failed"
    [[ "$(git diff --name-only)" == "project.yml" ]] ||
        die "version update changed files outside project.yml"
    [[ "$(git diff --numstat -- project.yml | awk '{print $1 ":" $2}')" == "2:2" ]] ||
        die "expected exactly two replaced lines in project.yml"

    if [[ "$SKIP_BUILD" -eq 1 ]]; then
        echo "WARNING: --skip-build is active; this release commit is not locally build-verified."
    else
        PHASE="local build"
        echo "→ Building target version $TARGET_VERSION..."
        ./build.sh
    fi

    PHASE="commit release version"
    git add -- project.yml
    [[ "$(git diff --cached --name-only)" == "project.yml" ]] ||
        die "staged allowlist violation: only project.yml may be committed"
    git commit -m "$COMMIT_MESSAGE"
    RELEASE_COMMIT=$(git rev-parse HEAD)
    RELEASE_COMMITTED=1
    PROJECT_BACKUP=""
fi

if [[ -n "$LOCAL_TAG_COMMIT" && "$LOCAL_TAG_COMMIT" != "$RELEASE_COMMIT" ]]; then
    die "local tag $TAG points to $LOCAL_TAG_COMMIT, expected $RELEASE_COMMIT"
fi
if [[ -n "$REMOTE_TAG_COMMIT" && "$REMOTE_TAG_COMMIT" != "$RELEASE_COMMIT" ]]; then
    die "remote tag $TAG points to $REMOTE_TAG_COMMIT, expected $RELEASE_COMMIT"
fi
if [[ "$PUBLIC_RELEASE_EXISTS" -eq 1 && -z "$REMOTE_TAG_COMMIT" ]]; then
    die "public release $TAG exists without the expected private remote tag; refusing ambiguous resume"
fi

PHASE="push private main"
REMOTE_MAIN=$(git rev-parse refs/remotes/origin/main)
if [[ "$REMOTE_MAIN" != "$RELEASE_COMMIT" ]]; then
    echo "→ Pushing private main..."
    git push origin main
else
    echo "✓ Private main already contains $RELEASE_COMMIT."
fi

PHASE="sync public documentation"
echo "→ Synchronizing public documentation..."
"$PROJECT_DIR/scripts/sync-public-repo.sh" "Sync public docs for $TAG"

PHASE="create private tag"
if [[ -z "$LOCAL_TAG_COMMIT" ]]; then
    git tag -a "$TAG" "$RELEASE_COMMIT" -m "Release $TAG"
    LOCAL_TAG_COMMIT=$RELEASE_COMMIT
else
    echo "✓ Local tag $TAG already points to the release commit."
fi

PHASE="push private tag"
REMOTE_TAG_COMMIT=$(remote_tag_commit "$TAG")
if [[ -z "$REMOTE_TAG_COMMIT" ]]; then
    echo "→ Pushing $TAG to trigger the release workflow..."
    git push origin "refs/tags/$TAG"
elif [[ "$REMOTE_TAG_COMMIT" == "$RELEASE_COMMIT" ]]; then
    echo "✓ Remote tag $TAG already points to the release commit."
else
    die "remote tag $TAG points to $REMOTE_TAG_COMMIT, expected $RELEASE_COMMIT"
fi

PHASE="locate release workflow"
echo "→ Waiting for the exact Release workflow for $TAG..."
RUN_ROW=""
attempt=0
while [[ -z "$RUN_ROW" && "$attempt" -lt 30 ]]; do
    RUN_ROW=$(gh run list --repo "$PRIVATE_REPO" --workflow release.yml --event push \
        --commit "$RELEASE_COMMIT" --limit 20 \
        --json databaseId,headBranch,headSha,event,status,conclusion,url \
        --jq ".[] | select(.headBranch == \"$TAG\" and .headSha == \"$RELEASE_COMMIT\" and .event == \"push\") | [.databaseId,.status,.conclusion,.url] | @tsv" | sed -n '1p')
    [[ -n "$RUN_ROW" ]] || { sleep 2; attempt=$((attempt + 1)); }
done
[[ -n "$RUN_ROW" ]] || die "could not find the exact tag-triggered workflow run for $TAG"
IFS=$'\t' read -r RUN_ID RUN_STATUS RUN_CONCLUSION RUN_URL <<< "$RUN_ROW"
echo "→ Workflow: $RUN_URL"

PHASE="wait for release workflow"
if [[ "$RUN_STATUS" != "completed" ]]; then
    gh run watch "$RUN_ID" --repo "$PRIVATE_REPO" --exit-status
fi
RUN_CONCLUSION=$(gh run view "$RUN_ID" --repo "$PRIVATE_REPO" --json conclusion --jq '.conclusion')
[[ "$RUN_CONCLUSION" == "success" ]] || die "workflow $RUN_URL concluded with '$RUN_CONCLUSION'"

verify_public_release "$TAG" "$TARGET_VERSION"

echo "✓ Release $TAG completed successfully."
echo "  Private commit: $RELEASE_COMMIT"
echo "  Workflow:       $RUN_URL"
echo "  Public release: https://github.com/$PUBLIC_REPO/releases/tag/$TAG"
