# Phase 5, Sub-project 3: Packaging and Release Readiness — Design

Status: approved
Scope: `docs/DEVELOPMENT_PLAN.md` Phase 5's third bullet ("Establish
packaging, a clean-install smoke test, and a release checklist"). Builds
on Sub-projects 1 and 2 (both merged), but is otherwise independent of
either.

## Decisions carried into this design

- **Distribution target**: the addon is for personal/private use for now,
  with an explicit intent to publish to CurseForge later. This design does
  not implement CurseForge publishing (project registration, CI upload,
  API tokens) — those are out of scope until the user is actually ready to
  publish, and project registration in particular is an external-account
  action outside what this session performs. What this design DOES do is
  adopt the packaging conventions the CurseForge ecosystem's standard tool
  (BigWigsMods/packager) expects, so that a later move to actual CurseForge
  CI only means wiring automation around the same structure, not
  redesigning packaging from scratch.
- **Packaging tool**: a hand-written PowerShell script, not the real
  BigWigsMods/packager tool. That tool is Perl-based and needs a Unix-like
  environment (Cygwin/git-bash) on Windows; since this addon has zero
  external libraries and zero localization files (an explicit product
  decision — no Ace3/vendored libraries), a naive zip of the addon folder
  can produce a structurally equivalent result to what the real packager
  would produce -- but only if the zip itself is spec-compliant. PowerShell's
  built-in `Compress-Archive` is not: it stores backslash path separators in
  zip entry names, which violates the ZIP spec and breaks spec-compliant
  extractors (e.g. on macOS, or many addon managers). The packaging script
  therefore shells out to Windows's bundled `tar.exe`, which writes
  forward-slash entry names as the spec requires. Reaching for the real
  BigWigsMods/packager tool now would add a dependency this addon
  structurally doesn't need yet.
- **`.pkgmeta`**: added now as minimal, inert scaffolding (`package-as:
  Where2Go`) even though nothing consumes it yet — cheap to add, and gives
  a concrete anchor for "what changes when we wire up real CI later"
  rather than a note buried in a doc. Note this scaffolding is not yet
  sufficient on its own: the real BigWigsMods/packager tool copies the
  repo ROOT into the `package-as` folder, not a chosen subdirectory. Since
  this addon's code lives in a `Where2Go/` subdirectory alongside `docs/`,
  `tests/`, `tools/`, `README.md` at the repo root, a real packager run
  today would nest the addon one level too deep
  (`Where2Go/Where2Go/Where2Go.toc`). A future move to real CI-based
  packaging will additionally need a `move-folders` (or `ignore`) key in
  `.pkgmeta` to place `Where2Go/`'s contents at the package root — not
  yet configured here.
- **Version source of truth**: `Where2Go/Where2Go.toc`'s `## Version:`
  line. The packaging script only reads it; bumping it is a manual step in
  the release checklist, not something the script does automatically —
  avoids the script silently making a product decision (what the next
  version number should be) that belongs to a human.
- **Smoke test scope**: structural verification (does the packaged zip
  contain exactly the right files, matching the TOC) is automated by
  reusing the existing `tests/toc_spec.lua` check against the extracted
  package rather than writing new verification logic. Actually loading the
  addon in a live WoW client is manual — same pattern as every other
  live-client verification in this project (Phases 1-4, Sub-project 1's
  Task 7, Sub-project 2's Task 4) — nothing in this session can substitute
  for a real client load.

## Reference material

- `Where2Go/` folder contents (verified during brainstorming): exactly 12
  `.lua` files plus `Where2Go.toc`, no test/dev artifacts mixed in — the
  packaging script can zip this folder wholesale with no exclusion list.
- `tests/toc_spec.lua`: the existing TOC↔filesystem bidirectional check
  (Phase 1). It hardcodes the relative path `Where2Go/Where2Go.toc` and
  reads files relative to the process's current working directory, which
  means running it with the working directory set to a package's
  extraction root re-validates the exact same properties against a
  packaged artifact with no code changes to the test itself.
  Confirmed (via `Get-ChildItem ... | Select-Object Name, LinkType,
  Target`) that the live `AddOns\Where2Go` folder is a junction pointing
  directly at this repo's `Where2Go\` — the packaging/smoke-test flow
  deliberately targets a *separate* extraction location, not this dev
  junction, so the smoke test proves the standalone package works, not
  just that the dev symlink still works.
- BigWigsMods/packager (https://github.com/BigWigsMods/packager):
  examined for its conventions (`.pkgmeta`'s `package-as` key, zip
  structure with the addon folder at the archive root) — not installed or
  invoked, per the "Packaging tool" decision above.

## Architecture

```
.pkgmeta                       NEW: minimal CurseForge-packager-convention
                                file (package-as: Where2Go), unused by any
                                tool today, forward-compatible scaffolding

tools/package.ps1               NEW: reads Where2Go/Where2Go.toc's
                                ## Version: line, zips Where2Go/ into
                                dist/Where2Go-<version>.zip (the addon
                                folder itself is the zip's top-level entry)

tools/smoke-test.ps1            NEW: extracts a given zip to a temp
                                directory and re-runs tests/toc_spec.lua
                                with that directory as the working
                                directory -- reuses the existing test,
                                writes no new TOC-parsing logic

docs/RELEASE_CHECKLIST.md       NEW: full release procedure --
                                tests -> lint -> version bump -> package ->
                                structural smoke test -> manual live-client
                                check -> commit + tag

.gitignore                      MODIFY: add dist/ (packaged zips, never
                                committed)
```

## Components

- **`.pkgmeta`** (new, repo root): a single line, `package-as: Where2Go`.
  Not read by anything in this design; documented in
  `docs/RELEASE_CHECKLIST.md` as scaffolding for a future CI-based
  CurseForge packaging step.
- **`tools/package.ps1`** (new): reads `Where2Go/Where2Go.toc`, extracts
  the `## Version:` value, creates `dist/` if needed, and produces
  `dist/Where2Go-<version>.zip` via Windows's bundled `tar.exe` (not
  `Compress-Archive`, which stores spec-violating backslash path
  separators), `-C`'d into the repo root with an explicit list of the
  addon's files (relative, forward-slash paths) rather than just the
  `Where2Go` directory — passing the directory would make tar add extra
  directory entries to the archive on top of the file entries. The listed
  files' common `Where2Go/` prefix becomes the zip's effective top-level
  folder (so extracting the zip anywhere yields a `Where2Go/` folder
  ready to drop into an `AddOns/` folder, with spec-compliant
  forward-slash entry names). Overwrites any existing zip for the same
  version rather than erroring, since re-running after a fix during the
  same release attempt is a normal workflow.
- **`tools/smoke-test.ps1`** (new): takes a `-ZipPath` parameter (and an
  optional `-LuaPath` override matching this project's established
  external-tool-path-override convention from Sub-projects 1-2),
  extracts it to a fresh temp directory, confirms
  `<temp>/Where2Go/Where2Go.toc` exists at the expected nesting depth (a
  cheap sanity check before trusting the deeper Lua-based check), then
  runs `lua5.1.exe tests/toc_spec.lua` with the temp directory as the
  working directory. Cleans up the temp directory afterward regardless of
  outcome. Exit code mirrors the underlying Lua check's exit code.
- **`docs/RELEASE_CHECKLIST.md`** (new): the full, ordered procedure --
  covers the parts this design automates (test, lint, package, structural
  smoke test) and the parts that stay manual (version-number decision,
  live-client verification, git tagging), so a release never depends on
  remembering steps that live only in this conversation.

## Data flow

1. Developer runs the full test suite and lint (`tests/run_tests.lua`,
   `tools/lint.ps1`) — both already exist, from Phase 1 and Sub-project 2
   respectively.
2. Developer manually bumps `Where2Go/Where2Go.toc`'s `## Version:` line.
3. Developer runs `tools/package.ps1`, producing
   `dist/Where2Go-<version>.zip`.
4. Developer runs `tools/smoke-test.ps1 -ZipPath dist/Where2Go-<version>.zip`,
   which extracts the zip and re-validates TOC/filesystem consistency
   against the extracted copy.
5. Developer manually extracts the same zip into a separate, non-dev
   AddOns location, launches WoW, and confirms the addon loads without
   error and the panel opens — the one step nothing in this session can
   perform.
6. Developer commits the version bump and tags the release in git.

## Testing

- No automated test suite for `tools/package.ps1` or `tools/smoke-test.ps1`
  themselves, consistent with Sub-projects 1 and 2's precedent for small,
  low-frequency developer tooling. `tools/package.ps1`'s own correctness is
  what `tools/smoke-test.ps1` verifies; `tools/smoke-test.ps1`'s own
  correctness is exercised for real as this sub-project's completion
  check (Task N: run the whole chain against the current, real 0.1.0
  build).
- `tests/toc_spec.lua` itself is unmodified — this design is purely a new
  consumer of it (via a different working directory), not a change to its
  logic.

## Error handling

- `tools/package.ps1`: if `Where2Go/Where2Go.toc` has no `## Version:`
  line (shouldn't happen given the file's current content, but a real
  possible authoring mistake), fail loudly with a clear message rather
  than producing a zip named `Where2Go-.zip` or similar.
- `tools/smoke-test.ps1`: if the given zip path doesn't exist, or if the
  extracted structure doesn't have `Where2Go/Where2Go.toc` at the expected
  location, fail with a clear message rather than letting `toc_spec.lua`
  fail with a more confusing "file not found" error one layer down.

## Acceptance check

- Running the full chain (`tools/package.ps1` then
  `tools/smoke-test.ps1`) against the current 0.1.0 build produces a zip
  and a clean (exit 0) structural smoke-test result.
- A human confirms, via a real WoW client, that extracting that same zip
  into a separate (non-dev-junction) `AddOns/` location and loading the
  game shows the addon working exactly as it does through the dev
  junction today (no Lua errors, panel opens, both tabs work) — this is
  Phase 5's "clean-install smoke test" requirement in its fullest sense,
  which the automated structural check alone cannot satisfy.
- `docs/RELEASE_CHECKLIST.md` exists and, followed top to bottom, would
  let someone (including a future session with no memory of this one)
  cut a release without reconstructing the process from scattered
  knowledge.

## Out of scope for this sub-project

- Actually publishing to CurseForge, WoWInterface, or Wago — registration
  and any of those services' own submission requirements. Explicitly
  deferred until the user is ready to go public.
- CI/GitHub Actions automation of any part of this flow — this repo has
  no CI configured (confirmed: no `.github/workflows/`), and adding one is
  a bigger, separate decision the user hasn't made yet.
- Installing or invoking the real BigWigsMods/packager tool.
- Automatic version-number bumping/semantic-version decisions — a human
  call, made explicit in the release checklist rather than automated.
- Localization file handling, external library vendoring — not applicable
  today (no locales, no libraries), and `.pkgmeta`'s scope here is
  deliberately minimal rather than pre-building machinery for features
  that don't exist yet.
