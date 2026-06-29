# Contributing to Ledgerly

Thanks for helping improve Ledgerly.

## Before you start

- Search existing issues and pull requests before opening a duplicate.
- Open an issue before beginning a large feature or interface redesign.
- Do not use public issues for security vulnerabilities; follow
  [SECURITY.md](SECURITY.md).
- By contributing, you agree that your contribution is licensed under the
  GNU General Public License v3.0 or later.

## Development

Ledgerly is a native SwiftUI macOS application that currently targets Apple
silicon and macOS 13 or later.

Requirements:

- The current Xcode command-line tools
- Python 3 with Pillow when generating a full app or DMG

Type-check the application:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun swiftc \
  -parse-as-library \
  -typecheck \
  -target arm64-apple-macos13.0 \
  -sdk "$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun --sdk macosx --show-sdk-path)" \
  -framework SwiftUI \
  -framework AppKit \
  -framework Security \
  -framework UserNotifications \
  Sources/LedgerlyApp.swift
```

Build the app and DMG:

```sh
./build.sh
```

## Pull requests

1. Create a focused branch from `main`.
2. Keep unrelated changes out of the pull request.
3. Update documentation or the changelog when behavior changes.
4. Confirm the Swift type-check passes.
5. Explain the user impact and include screenshots for visible interface work.

Pull requests are squash-merged after automated checks pass and all review
conversations are resolved.
