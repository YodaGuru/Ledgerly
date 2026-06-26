# Changelog

All notable changes to Ledgerly are documented here.

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
