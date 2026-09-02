# Where2Go lint tooling

`tools/lint.ps1` runs [luacheck](https://github.com/lunarmodules/luacheck)
against every `.lua` file under `Where2Go/`, catching both syntax errors
and common Lua mistakes (unused variables, accidental global writes) --
including the 5 WoW-API-dependent files (`Init.lua`, `DirectDrop.lua`,
`Equipment.lua`, `VoidcoreDrop.lua`, `Panel.lua`) that no unit test
currently touches, since today a syntax error in any of them is only
found via a live `/reload` in-game.

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

A clean run exits 0 with no output. Any warnings or errors luacheck finds
print directly to the terminal with file:line references.
