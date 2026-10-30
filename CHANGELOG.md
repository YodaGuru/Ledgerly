# Changelog

All notable changes to Ledgerly are documented here.

## [3.1.0] - 2026-10-30

### What’s New

- Added a payment date picker to Log Payment and Log Partial Payment, so a payment can be recorded on the day it was actually made. Future dates are not allowed, and the chosen date appears in Payment History and Last Paid. Back-dating does not change which due date the payment counts against or the bill’s next due date.
- Bill table columns (Name, Amount, Due Date, Last Paid) can now be sorted by clicking the column header. The default order is still by due date, and bills that have never been paid sort as oldest in Last Paid.
- Double-click a bill, or press Return, to edit it.
- Added a Log Payment button to the toolbar for the selected bill.
- Added Quick Look for receipts: right-click a payment (or use its “…” menu) in Payment History or a bill’s history and choose Quick Look Receipt, or right-click a payment document in a bill’s history.
- Added keyboard shortcuts: Log Payment ⌘L, and Show/Hide Sidebar ⌃⌘S (macOS 26).
- The sidebar remembers whether it was hidden.

### Liquid Glass

- On macOS 26 the sidebar is now a floating Liquid Glass panel inset from the window edges, with the Ledgerly name on top and a toolbar button to hide it. It uses a standard source list inside, so selection and keyboard navigation come from the system.
- On macOS 26 the details pane (bill details, or the monthly calendar when no bill is selected) is now a matching floating Liquid Glass card with the same shape and margins as the sidebar.
- The window toolbar no longer draws a full-width bar across the floating panels, and the sidebar glass uses a neutral backdrop instead of a blue tint.
- Sidebar section headers and subtitles have more contrast on the glass.
- Content now scrolls under the window toolbar, because the opaque toolbar, list, and inspector backgrounds were removed.
- macOS 13–15 keep a standard split-view sidebar. The details pane uses the system inspector on macOS 14–15 and a plain side pane on macOS 13.

### Changed

- The bill list is now a standard table with native column resizing, selection, and right-click menu. The default column widths were adjusted, with a little more room for Amount and Due Date.
- “Add Bill”, “Add Income”, and search now live in the native window toolbar. Payment History and Overview search moved there from inside the page.
- Each screen now sets a standard window title. The large in-page headings on Income, Forecast, Payment History, and Settings were removed because the window title replaces them.
- The details pane is always shown. Its show/hide setting was removed.
- Added padding between the due-date color bar and the Due Date column edge.
- `build.sh` now skips macOS `._*` metadata files, so builds from non-APFS drives no longer fail with “invalid character in source file”.

### Fixed

- The monthly calendar weekday header was missing Thursday and Saturday because the repeated one-letter symbols (T, S) were dropped. It now shows all seven days in both calendar views.
- The monthly calendar card was always white in Dark Mode. It now follows the app appearance, and its bill-day highlight uses the app accent color.

### Removed

- The hidden title bar and the code that stripped sidebar and toolbar items after launch.
- The custom hand-built sidebar buttons, selection styling, and sidebar glass helpers.
- The custom bill list layout, including its hand-built column resize handles, horizontal scroll bar, and draggable side-pane divider. Saved column and pane widths from earlier versions are no longer used.
- Unused color definitions for the old toolbar, list, and inspector backgrounds.

## [3.0.0] - 2026-07-01

### What’s New

- Added iCloud Drive sync support with automatic disk watching.
- Added a persistent Sync status/action in the sidebar.
- Added manual “Refresh from Disk” support with clearer wording in Settings.
- Added automatic reload when synced data changes on disk.
- Updated Ledgerly to version 3.0.0 across the app, build script, README, and DMG output.

### Bill Tracking

- Added partial payment support.
- Bills can now show a remaining balance when only part of the amount has been paid.
- Added separate actions for:
  - Log Payment
  - Log Partial Payment
  - Skip This Occurrence
- Auto-pay bills can automatically log payment and advance to the next due date.
- Auto-pay confirmation numbers are recorded as Auto Pay.
- Variable bills can now show estimated amounts based on payment history.
- Due date colors were updated:
  - Red for past due
  - Yellow for due within 7 days
  - Green for due later than 7 days

### Payment History

- Added notes to logged payments.
- Payment history entries can now be edited.
- Payment history entries can now be deleted.
- Deleting a payment restores the bill back to the previous due date when appropriate.
- Payment records now preserve more context about the bill state at the time of payment.

### Calendar and Monthly Planning

- Calendar dates are now clickable.
    - Clicking a date shows bills due on that day.
- The monthly bill list now includes all bills due in the selected month.
- Added a scope control for monthly planning:
  - Full month
  - Until next pay
- Renamed the monthly section to “Due this month” for clarity.
- Monthly Money Picture now follows the selected scope.
- Monthly Money Picture stays anchored at the bottom of the right panel.
- The due list expands better when the window has more vertical space.

### Bill Icons and Logos

- Added website-based biller icons for the bill list.
- Added a General setting to enable or disable biller website icons.
- Added support for custom biller logos.
- Custom logos take priority over website icons.
- Improved icon presentation in the bill list.

### macOS Interface Polish

- Restored the native macOS NavigationSplitView layout for proper Liquid Glass/sidebar behavior.
- Removed the sidebar collapse behavior.
- Removed the sidebar collapse button from the titlebar.
- Improved window resizing behavior.
- Improved horizontal scrolling for the bill table.
- Removed the version footer from the sidebar since version information already appears in Settings.
- Cleaned up spacing and sidebar presentation.

### App Icon and Build Updates

- Replaced the old app icon setup with the new AppIcon.icon asset.
- Added support for Apple’s new icon export structure.
- Updated the build process to package the new icon correctly.
- DMG output now builds as Ledgerly-3.0.0.dmg.

### Fixes and Improvements

- Fixed several sidebar collapse/layout issues.
- Fixed the overview list not resizing properly with the window.
- Fixed the calendar/sidebar area taking over resize behavior.
- Fixed monthly bill counts that were not reflecting all due bills.
- Improved totals so remaining balances are used where appropriate.
- Improved release/build consistency across app metadata and documentation.

## [2.1.1] - 2026-06-29

- Fixed overdue bill labels so they show the correct number of calendar days overdue instead of sometimes showing 0 days overdue.

## [2.1] - 2026-06-28

### Added

- Added biweekly scheduling for bills.
- Use this for bills due every other week, such as every other Friday.
- Added biweekly scheduling for income.
- Paychecks can now be tracked every other week instead of only weekly, twice monthly, or monthly.

### Improved

- Forecasts now calculate biweekly bills correctly across each month.
- Income estimates now account for biweekly pay using 26 payments per year.
- Weekly and biweekly bills now track paid status by the exact due date, so multiple same-month cycles do not incorrectly appear paid.

## [2.0.2] - 2026-06-25

### Fixed

- Fixed split-view layout behavior that could show only the sidebar on some Macs.
- Improved sidebar/footer alignment.
- Continued UI polish for the Ledgerly 2.x interface.

## [2.0.1] - 2026-06-25

### Added

- Added “Delete Bill…” to the bill right-click menu.
- Added a confirmation alert before permanently deleting a bill.

### Changed

- Updated the app icon.
- Improved top toolbar/header spacing.
- Improved column resize handle spacing.
- Centered the version label in the sidebar.

### Fixed

- Fixed layout spacing around the bills table header.
- Fixed visual alignment issues in the left/sidebar area.

## [2.0.0] - 2026-06-25

### Changed

- Released the redesigned Ledgerly 2.0 interface.
- Added the updated sidebar, overview layout, calendar panel, and report styling.
- Updated the app branding and visual design.

## [1.0.0] - 2026-06-25

### Added

- Native macOS bill overview, Due Soon, monthly, paid, and archived sections
- Recurring and one-time bills with reminders, notes, websites, and attachments
- Payment logging, confirmation numbers, history, and receipt attachments
- Income tracking and monthly after-bills summary
- Twelve-month forecast with recurring-bill calculations
- Automatic payment logging and one-time bill archiving options
- Dock badges based on the configurable Due Soon window
- Password protection using macOS Keychain
- Settings for general behavior, reminders, logging, income, storage, and privacy
- Liquid Glass presentation on macOS 26 with older-macOS material fallbacks
- Local-only JSON persistence with no bank connection or online account

### Distribution

- Apple silicon build for macOS 13 or later
- DMG packaging through `build.sh`
- Initial GitHub release
