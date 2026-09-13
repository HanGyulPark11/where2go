# UI contracts

`Theme.lua` provides shared frame, text, and button helpers. `ItemRow.lua` renders reusable item widgets with localized `slot · item level · fixed secondary stats` summaries, omitting absent segments. For a known track bonus, it always builds the canonical synthetic link directly from the item ID and track bonus. Items with a curated static effect/context variant use the static non-track bonuses plus the track bonus only when `C_TooltipInfo` confirms the caller's calculated level and track/rank. A final rank beyond the normal track length can instead validate from an exact item-level line plus the requested plain track marker when no numeric track/rank metadata conflicts; conflicts and unavailable tooltip data use the canonical link. Hovering never loads, selects, queries, or rewrites Encounter Journal links. A pooled row that is repopulated while hovered refreshes its visible tooltip immediately. `Panel.lua` hooks the group finder lifecycle, preserves collapsed state in `Where2GoCharDB`, renders ranked cards, localizes addon-owned content names through `Locale.ContentName`, and refreshes when preferences change. Its automatic placement must clear the visible Raider.IO profile tooltip and the finder, while title-bar dragging stores a validated per-character manual position that a title-bar right-click clears. `/w2g` can also show it without the finder.

`BrowserPanel.Show(mode)` opens the independent management window in the requested mode. Filters and mode changes clear temporary selection; committed preference changes notify both windows. Closing the finder does not close this browser. Source filters and result hover source lines use the same addon-owned content-name localization as the recommendation panel. Browser dropdowns share a single top-row filter layout, name their filter category by default, show the selected entry directly, keep their labels on one line outside Blizzard's dropdown-template text region, and show up to two selected entries before a `+N` suffix when that text fits the button width. The reset action lives on the lower filter row so the top-row filters reserve enough width for localized labels. A new browser session starts with the current specialization selected, and resetting filters returns to that current-specialization default.

The recommendation panel's ownership toggle switches the shared character rule
between same-item and slot filtering and refreshes immediately. Bag/equipment
events refresh visible recommendations; item-cache events retry comparisons
when metadata arrives. The saved preferred list is not modified by filtering.
Its session-only source control cycles All, Dungeons, and Raids beside the
ownership toggle, filters both Drop and Voidcore rankings by `ranked.kind`,
survives mode changes, names the selected state in the button text, resets to All on
reload, and summarizes only visible filtered targets.

`tests/helpers/wow_ui.lua` is a small frame double for panel specs. It supports automated lifecycle and interaction checks but cannot replace the current [two-window live UI checklist](../UI_REDESIGN_QA.md).
