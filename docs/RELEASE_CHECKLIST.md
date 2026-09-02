# Release Checklist

Follow these steps in order to cut a release. Do not skip ahead -- later
steps assume earlier ones passed.

1. **Run the full Lua test suite.**
   ```
   "C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua
   ```
   All specs must pass before continuing.

2. **Run the lint check.**
   ```
   .\tools\lint.ps1
   ```
   Must exit 0 with no warnings before continuing. See
   `tools/LINT_README.md` if `luacheck.exe` isn't installed yet.

3. **Bump the version.** Edit `Where2Go/Where2Go.toc`'s `## Version:` line
   to the new version number. This is the single source of truth every
   other step in this checklist reads from.

4. **Package the addon.**
   ```
   .\tools\package.ps1
   ```
   Produces `dist/Where2Go-<version>.zip`.

5. **Run the structural smoke test.**
   ```
   .\tools\smoke-test.ps1 -ZipPath dist\Where2Go-<version>.zip
   ```
   Confirms the packaged zip's contents match the TOC exactly (the same
   check `tests/toc_spec.lua` runs against the source tree, re-run against
   the extracted package). Must exit 0 before continuing.

6. **Manually verify in a real WoW client.** Extract
   `dist/Where2Go-<version>.zip` into a *separate* AddOns folder -- not
   the development junction this repo's live `AddOns\Where2Go` normally
   points at (extracting alongside or over it risks masking a real
   packaging bug with the dev copy's already-working state). Launch WoW,
   confirm the addon loads with no Lua errors, `/where2go` opens the
   panel, and both the Drop and Voidcore tabs work.

7. **Commit and tag.**
   ```
   git add Where2Go/Where2Go.toc
   git commit -m "chore: bump version to <version>"
   git tag v<version>
   ```
   Push the tag when ready to make the release visible
   (`git push --tags`).

## Publishing to CurseForge (not yet set up)

This checklist does not cover actually publishing anywhere. When ready to
publish to CurseForge: register the project on CurseForge's site (a
one-time manual step tied to your own account), then wire up CI (e.g. a
GitHub Action) to run the real BigWigsMods/packager tool against this
repo's existing `.pkgmeta` and upload the result using a CurseForge API
token stored as a repo secret. Nothing in this repo needs to change
structurally for that -- `.pkgmeta`'s `package-as: Where2Go` already
matches this addon's folder name.
