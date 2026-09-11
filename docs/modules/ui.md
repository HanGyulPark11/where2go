# UI contracts

`Theme.lua` provides shared frame, text, and button helpers. `ItemRow.lua` renders reusable item widgets with localized `slot · item level · fixed secondary stats` summaries, omitting absent segments. It validates a corrected live Encounter Journal link through `C_TooltipInfo` against the caller's calculated level and track/rank, retains a validated full link with its non-track bonuses and trailing fields, and falls back to the canonical synthetic link when rendered metadata conflicts or cannot be recovered. Successful full links and definitive conflicts are cached per item and requested rank; transient misses retry. A pooled row that is repopulated while hovered refreshes its visible tooltip immediately. `Panel.lua` hooks the group finder lifecycle, preserves collapsed state in `Where2GoCharDB`, renders ranked cards, and refreshes when preferences change. Its automatic placement must clear the visible Raider.IO profile tooltip and the finder, while title-bar dragging stores a validated per-character manual position that a title-bar right-click clears. `/w2g` can also show it without the finder.

`BrowserPanel.Show(mode)` opens the independent management window in the requested mode. Filters and mode changes clear temporary selection; committed preference changes notify both windows. Closing the finder does not close this browser.

The recommendation panel's ownership toggle switches the shared character rule
between same-item and slot filtering and refreshes immediately. Bag/equipment
events refresh visible recommendations; item-cache events retry comparisons
when metadata arrives. The saved preferred list is not modified by filtering.

`tests/helpers/wow_ui.lua` is a small frame double for panel specs. It supports automated lifecycle and interaction checks but cannot replace the current [two-window live UI checklist](../UI_REDESIGN_QA.md).
