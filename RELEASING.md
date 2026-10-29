# Releasing LingoPop

Maintainer-only notes. Source, docs and releases all live in this one public repository (`slucheninov/lingopop`).

## How it works

Pushing a tag `v<version>` triggers `.github/workflows/release.yml`. The workflow builds on `macos-15` (Xcode 16.4) via `scripts/release.sh`, ad-hoc signs the universal (arm64 + x86_64) app, and publishes a GitHub Release in this repository using the built-in `GITHUB_TOKEN`. No personal access token, secret or repository variable is needed.

Release assets:

- `LingoPop-<version>-mac-universal.dmg`
- `LingoPop-<version>-mac-universal.zip`
- `SHA256SUMS`

Because there is no Apple Developer Program membership, the app is ad-hoc signed and not notarized. Users see a one-time Gatekeeper warning on first launch (right-click the app, **Open**); the README documents this.

## Cutting a release

1. Make sure `main` is green in CI and `CHANGELOG.md` is ready for the new version.
2. Prepare the release:

   ```bash
   ./scripts/publish-release.sh prepare 0.3.19            # add --skip-build to skip the local build check
   ```

   This bumps the version on branch `release/v0.3.19` and opens a pull request.
3. Review the PR, wait for `build-and-test` to pass, and merge it into `main`.
4. Tag and publish:

   ```bash
   ./scripts/publish-release.sh tag 0.3.19
   ```

   This tags `origin/main` as `v0.3.19`, pushes the tag, waits for the Release workflow to finish, and verifies the published assets.

## Building artifacts locally

`scripts/release.sh` produces the same artifacts in `dist/`:

```bash
./scripts/release.sh                       # universal, version from project.yml
./scripts/release.sh 0.3.19 --arch arm64   # single architecture
./scripts/release.sh 0.3.19 --no-dmg       # zip only
```

It prints the `lipo -archs` slice list at the end; check it if a user reports a missing architecture.

## If something goes wrong

- **Release workflow failed:** fix the cause on `main` via a PR, delete the tag locally and on origin (`git push origin :refs/tags/v<version>`), then run `publish-release.sh tag <version>` again.
- **Wrong assets:** delete the GitHub Release and the tag, then re-tag as above.
- **Docs-only changes** (README, CHANGELOG, issue templates) need no sync step: they are part of this repository.
