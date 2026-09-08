# Where2Go lint tooling

Run `C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe tests/run_tests.lua`
from the repository root for the registered Lua suite. Automated lint/tests do
not replace required live WoW QA for changed or deleted API, event, or
SavedVariables behavior.

`tools/lint.ps1` runs [luacheck](https://github.com/lunarmodules/luacheck)
against every `.lua` file under `Where2Go/`, catching both syntax errors
and common Lua mistakes (unused variables, accidental global writes). This
includes WoW-API-dependent modules, whether they have frame-double, pure-helper,
integration, syntax-only, or no registered test coverage. Those automated checks
still cannot establish real-client API, event, layout, or SavedVariables behavior.

## One-time setup

Download the official Windows binary release from
https://github.com/lunarmodules/luacheck/releases -- a single
`luacheck.exe` bundling everything needed (Lua 5.4.4, luacheck itself, and
its dependencies). No build tools, no LuaRocks, no admin rights required.

Place it at:

```
C:\tools\luacheck\luacheck.exe
```

(Or anywhere else you like -- pass `-LuacheckPath` when running the script
to point at a different location.)

## Running it

From the repo root, in PowerShell:

```powershell
.\tools\lint.ps1
```

With a non-default luacheck location:

```powershell
.\tools\lint.ps1 -LuacheckPath "D:\somewhere\luacheck.exe"
```

A clean run exits 0 and prints a per-file `Checking <file> ... OK` line for
each file plus a summary line showing zero warnings and errors (it is not
silent). Any warnings or errors luacheck finds print directly to the
terminal with file:line references.
