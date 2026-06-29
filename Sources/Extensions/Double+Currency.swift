// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 YodaGuru

import SwiftUI
import UserNotifications
import AppKit
import Security
import LinkPresentation
import CoreImage

extension Double {
    var currency: String {
        formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }

    var currencyCompact: String {
        if self >= 1000 {
            return String(format: "$%.1fk", self / 1000)
        }
        return String(format: "$%.0f", self)
    }
}
