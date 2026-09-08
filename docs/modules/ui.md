# UI contracts

`Theme.lua` provides shared frame, text, and button helpers. `ItemRow.lua` renders reusable item widgets and Blizzard tooltips. `Panel.lua` hooks the group finder lifecycle, preserves collapsed state in `Where2GoCharDB`, renders ranked cards, and refreshes when preferences change. `/w2g` can also show it without the finder.

`BrowserPanel.Show(mode)` opens the independent management window in the requested mode. Filters and mode changes clear temporary selection; committed preference changes notify both windows. Closing the finder does not close this browser.

`tests/helpers/wow_ui.lua` is a small frame double for panel specs. It supports automated lifecycle and interaction checks but cannot replace the current [two-window live UI checklist](../UI_REDESIGN_QA.md).
