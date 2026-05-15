# Releasing LingoPop

This document is for the maintainer. End-user install instructions live in the **public** repo's README (see `PUBLIC_README_TEMPLATE.md`).

## Architecture

```
┌──────────────────────────┐       push tag v0.2.0        ┌──────────────────────────┐
│   PRIVATE repo (source)  │ ──────────────────────────►  │  GitHub Actions          │
│                          │                              │  macos-14 runner         │
│   .github/workflows/     │                              │  • xcodegen + xcodebuild │
│   release.yml            │                              │  • universal arm64+x86_64│
└──────────────────────────┘                              │  • ad-hoc codesign       │
                                                          │  • build .dmg + .zip     │
                                                          └────────────┬─────────────┘
                                                                       │ gh release create
                                                                       ▼
                                                          ┌──────────────────────────┐
                                                          │  PUBLIC repo (releases)  │
                                                          │  Release v0.2.0          │
                                                          │  • LingoPop-...dmg       │
                                                          │  • LingoPop-...zip       │
                                                          └──────────────────────────┘
```

## One-time GitHub setup

### 1. Create the public repo

On GitHub, create a new repo (e.g. `username/lingopop-releases`) — public. Put a README there describing what LingoPop is and how to install (use `PUBLIC_README_TEMPLATE.md` as a starting point). No source code goes here.

### 2. Create a Personal Access Token

The workflow needs a token that can write releases to the **public** repo from inside the **private** repo. Use a **fine-grained PAT** (most restrictive).

- Go to [github.com/settings/personal-access-tokens/new](https://github.com/settings/personal-access-tokens/new)
- **Token name:** `LingoPop release publisher`
- **Expiration:** 1 year (or your preference; you'll need to rotate)
- **Resource owner:** your account / org
- **Repository access** → **Only select repositories** → pick the **public** repo only
- **Permissions** → **Repository permissions**:
  - **Contents** → **Read and write** (needed for creating releases and uploading assets)
  - **Metadata** → Read-only (auto-included)
- Generate. Copy the token (`github_pat_...`). You'll paste it in step 3 — it's only shown once.

### 3. Add the secret + variable to the private repo

In the **private** repo:

- **Settings → Secrets and variables → Actions → Secrets → New repository secret**
  - Name: `PUBLIC_REPO_TOKEN`
  - Value: the PAT from step 2

- **Settings → Secrets and variables → Actions → Variables → New repository variable**
  - Name: `PUBLIC_REPO`
  - Value: `owner/repo` of the public repo, e.g. `username/lingopop-releases`

### 4. Push the workflow + sources

Make sure `.github/workflows/release.yml` is committed and pushed to the private repo. That's it for setup.

## Releasing a new version

From your dev machine:

```bash
# 1. Make sure HEAD is on main with everything you want shipped
git pull
git status   # should be clean

# 2. Tag and push. Use semver, prefix with v.
git tag v0.2.0
git push origin v0.2.0
```

That's it. The tag push triggers `.github/workflows/release.yml`:

1. The macos-14 runner installs Xcode + xcodegen
2. Runs `./scripts/release.sh 0.2.0` → produces `dist/LingoPop-0.2.0-mac-universal.{dmg,zip}`
3. Generates release notes from git log since the previous tag
4. Calls `gh release create v0.2.0 --repo $PUBLIC_REPO ...` with the artifacts

Within ~5 minutes the new release appears in the public repo.

## Manual trigger (without a tag)

You can also fire a build manually from GitHub UI:

- **Actions → Release → Run workflow** → enter version → Run.

This still creates a real release in the public repo, so use sparingly.

## Local dry run

To preview what CI will produce, run the same script on your Mac:

```bash
./scripts/release.sh 0.2.0
# inspects dist/LingoPop-0.2.0-mac-universal.{dmg,zip}
```

Local builds use your `LingoPop Dev` cert if present; CI builds are ad-hoc signed (no cert in the runner). Users get the same Gatekeeper "right-click → Open" experience either way.

## Code signing — current state

We **do not have an Apple Developer Program membership**, so:

- The CI signs ad-hoc (`codesign --sign -`). The resulting `.app` is **not notarized**.
- macOS Gatekeeper will warn the first time a user opens it: *"LingoPop can't be opened because Apple cannot check it for malicious software."* The user must right-click → **Open** to bypass once, after which Gatekeeper remembers the decision.
- The public repo README must document this. Use `PUBLIC_README_TEMPLATE.md`.

If you later get an Apple Developer ID ($99/year), you can:

1. Export the Developer ID Application cert as a p12.
2. Add it as `MACOS_CERT_P12_BASE64` + `MACOS_CERT_PASSWORD` secrets.
3. Update the workflow to import the cert into a temporary keychain and sign with it.
4. Add a notarization step (`xcrun notarytool submit`) — needs Apple ID + app-specific password as secrets.

That's a future change. For now: ad-hoc + clear install instructions.

## Versioning

`scripts/release.sh` passes `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` to xcodebuild from the tag name (`v0.2.0` → `0.2.0`). You don't need to bump anything in `project.yml` before tagging — the version baked into the .app comes from the tag.

If you tag `v0.2.0` more than once you'll need to delete the existing release in the public repo, since `gh release create` refuses to overwrite. Easier: use a new tag.

## Troubleshooting

- **"PUBLIC_REPO is not set"** — you skipped step 3. Add the variable.
- **"PUBLIC_REPO_TOKEN is not set"** — same, add the secret.
- **`gh release create` says "HTTP 403"** — the PAT doesn't have `Contents: Read and write` on the public repo, or it expired. Regenerate.
- **`gh release create` says "release already exists"** — you've already shipped this tag. Delete the existing release in the public repo, or use a new tag.
- **Build fails on the runner with codesign errors** — usually means `xattr -cr` step in `release.sh` missed something. Check the workflow log.
- **`lipo -archs` only shows one arch** — `ONLY_ACTIVE_ARCH` got stuck. The script forces `NO`, but if you customize make sure it stays.
