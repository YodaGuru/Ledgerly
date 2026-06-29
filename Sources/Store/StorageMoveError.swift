// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 YodaGuru

import SwiftUI
import UserNotifications
import AppKit
import Security
import LinkPresentation
import CoreImage

enum StorageMoveError: LocalizedError {
    case destinationNotEmpty
    case invalidDestination
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .destinationNotEmpty:
            return "The selected location already contains a non-empty Ledgerly folder. Choose another location."
        case .invalidDestination:
            return "Choose a location outside the current Ledgerly data folder."
        case .verificationFailed:
            return "Ledgerly could not verify the copied data, so the current storage location was left unchanged."
        }
    }
}
