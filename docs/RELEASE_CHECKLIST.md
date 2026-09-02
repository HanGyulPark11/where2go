# Release Checklist

Follow these steps in order to cut a release. Do not skip ahead -- later
steps assume earlier ones passed. All commands below assume your working
directory is the repo root.

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
   the extracted package). Must exit 0 before continuing. Pass `-LuaPath`
   if your Lua interpreter isn't at the default location (mirroring
   `tools/lint.ps1`'s equivalent override for `luacheck.exe`, see
   `tools/LINT_README.md`).

6. **Manually verify in a real WoW client.** WoW reads addons from exactly
   one `AddOns` directory per install -- there is no separate `AddOns`
   folder it will also read from -- and it requires an addon's folder
   name to match its `.toc` filename exactly, so a renamed copy (e.g.
   `Where2GoPackageTest`) simply won't appear in the addon list. The
   procedure that actually works is a junction swap:
   1. Rename or temporarily remove the `AddOns\Where2Go` junction (it
      normally points at this repo's dev copy of `Where2Go\` --
      confirmed via `Get-ChildItem <AddOns path> | Select-Object Name,
      LinkType, Target`).
   2. Extract the packaged zip's `Where2Go` folder into `AddOns\` under
      its real name (`Where2Go`), so it's the actual folder, not a
      junction.
   3. Launch WoW (or `/reload` if already running), confirm the addon
      loads with no Lua errors, `/where2go` opens the panel, and both
      the Drop and Voidcore tabs work.
   4. Delete the extracted test copy and restore the original junction
      afterward.

   SavedVariables are keyed by addon name, so this swap-and-restore is
   safe and does not lose any saved data.

7. **Commit and tag.**
   ```
   git add Where2Go/Where2Go.toc
   git commit -m "chore: bump version to <version>"
   git tag v<version>
   ```
   Push the branch first so the tag doesn't end up pointing at a commit
   the remote doesn't have, then push the tag:
   ```
   git push
   git push --tags
   ```

## Publishing to CurseForge (not yet set up)

This checklist does not cover actually publishing anywhere. When ready to
publish to CurseForge: register the project on CurseForge's site (a
one-time manual step tied to your own account), then wire up CI (e.g. a
GitHub Action) to run the real BigWigsMods/packager tool against this
repo's existing `.pkgmeta` and upload the result using a CurseForge API
token stored as a repo secret. Note this repo DOES still need a change for
that: the real packager copies the repo ROOT into the `package-as` folder,
not a chosen subdirectory. Since this addon's code lives in a `Where2Go/`
subdirectory alongside `docs/`, `tests/`, `tools/`, `README.md` at the
repo root, a real packager run today would nest the addon one level too
deep (`Where2Go/Where2Go/Where2Go.toc` instead of `Where2Go/Where2Go.toc`).
`.pkgmeta` will additionally need a `move-folders` (or `ignore`)
configuration to place `Where2Go/`'s contents at the package root -- not
yet configured here.
