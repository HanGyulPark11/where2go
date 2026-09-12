# Code map

`Where2Go/Where2Go.toc` is the load-order contract. `tests/toc_spec.lua` parses every listed module and checks Core/UI TOC completeness. The class column is completion-gate input: only `pure` and `data` are exempt from live QA. The gate checks both the baseline and current maps so deleting or reclassifying a `wow-api` module cannot erase its QA requirement; an unclassified addon Lua path also requires QA.

| Path | Class | Responsibility | Test |
| --- | --- | --- | --- |
| Where2Go/Core/Constants.lua | pure | Defaults and slot mappings. | constants_spec.lua |
| Where2Go/Core/Locale.lua | pure | Localized labels. | locale_spec.lua |
| Where2Go/Core/Tracks.lua | data | Upgrade-track rules. | tracks_spec.lua |
| Where2Go/Core/Sources.lua | data | Season dungeon and raid loot pools. | sources_spec.lua |
| Where2Go/Core/VoidcacheIds.lua | data | Voidcache source identifiers. | voidcacheids_spec.lua |
| Where2Go/Core/SpecEligibilityData.lua | data | Generated eligibility data. | specEligibilityData_spec.lua |
| Where2Go/Core/ItemStats.lua | data | Imported item stats. | itemstats_spec.lua |
| Where2Go/Core/ItemLinkBonuses.lua | data | Generated full-link templates preserving Encounter Journal tooltip context. | itemlinkbonuses_spec.lua |
| Where2Go/Core/ItemBrowser.lua | pure | Pool filtering and sorting. | itembrowser_spec.lua |
| Where2Go/Core/Selection.lua | pure | Staged-item selection. | selection_spec.lua |
| Where2Go/Core/Preferences.lua | pure | Preferred lists, undo, subscribers. | preferences_spec.lua |
| Where2Go/Core/RaidRanks.lua | data | Direct-drop and Voidcore raid level/rank rules. | raidranks_spec.lua, voidcoredrop_spec.lua |
| Where2Go/Core/Ranking.lua | pure | Eligible-pool ranking. | ranking_spec.lua |
| Where2Go/Core/DirectDrop.lua | wow-api | Direct-drop candidates and live spec. | browserpanel_spec.lua (integration) |
| Where2Go/Core/VoidcoreHistory.lua | wow-api | Voidcore event history. | voidcorehistory_spec.lua |
| Where2Go/Core/VoidcoreDrop.lua | wow-api | Voidcore candidates and Great Vault-equivalent raid reward metadata. | voidcoredrop_spec.lua, browserpanel_spec.lua (integration) |
| Where2Go/Core/SpecEligibilityScan.lua | wow-api | Encounter Journal scan/export. | specEligibilityScan_spec.lua |
| Where2Go/Core/ItemLinkBonusScan.lua | wow-api | Prewarmed per-encounter EJ full-link scan with raw-link, conflict, and unresolved-link diagnostics. | itemLinkBonusScan_spec.lua |
| Where2Go/Core/Compare.lua | pure | Candidate comparison. | compare_spec.lua |
| Where2Go/Core/Equipment.lua | wow-api | Equipped-item lookup, carried ownership and filtering mode. | equipment_spec.lua |
| Where2Go/Core/Init.lua | wow-api | Addon initialization and commands. | toc_spec.lua |
| Where2Go/UI/Theme.lua | wow-api | Shared frame helpers. | panel_spec.lua |
| Where2Go/UI/ItemRow.lua | wow-api | Item widgets and synthetic tracked tooltips. | panel_spec.lua |
| Where2Go/UI/Panel.lua | wow-api | Recommendation panel. | panel_spec.lua |
| Where2Go/UI/BrowserPanel.lua | wow-api | Item browser panel. | browserpanel_spec.lua |

Use `C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe tests/run_tests.lua` and `./tools/lint.ps1` in PowerShell. Frame-double specs verify modeled UI behavior, not real WoW APIs, event timing, layout, or localization. Keep concurrent writers out of the working tree while the completion gate verifies and commits its selected paths. See [core](modules/core.md), [data](modules/data.md), and [UI](modules/ui.md) contracts.
