# Ledgerly Source Layout

Ledgerly is a single Swift module organized by responsibility:

- `LedgerlyApp.swift` contains the app entry point and app-level notifications.
- `Models/` contains persisted data types and display helpers.
- `Store/` contains local JSON storage, reminders, attachments, and app state.
- `Support/` contains platform helpers such as Keychain access.
- `Views/` contains screen-level SwiftUI views.
- `Views/Components/` contains shared reusable UI pieces.
- `Views/Editors/` contains sheets and forms for editing app data.
- `Extensions/` contains small formatting, color, and view-style helpers.

The build script automatically compiles every `.swift` file under `Sources`,
so new source files do not need to be listed manually.
