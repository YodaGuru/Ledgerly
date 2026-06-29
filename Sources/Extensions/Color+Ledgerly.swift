// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 YodaGuru

import SwiftUI
import UserNotifications
import AppKit
import Security
import LinkPresentation
import CoreImage

extension Color {
    static let ledgerlyPrimaryText = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.94, alpha: 1)
                : NSColor(calibratedWhite: 0.12, alpha: 1)
        }
    )

    static let ledgerlySecondaryText = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.64, alpha: 1)
                : NSColor(calibratedWhite: 0.42, alpha: 1)
        }
    )

    static let ledgerlySidebar = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.09, alpha: 1)
                : NSColor(calibratedRed: 0.94, green: 0.925, blue: 0.90, alpha: 1)
        }
    )

    static let ledgerlyDivider = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.22, alpha: 1)
                : NSColor(calibratedWhite: 0.82, alpha: 1)
        }
    )

    static let ledgerlyWorkspace = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.075, alpha: 1)
                : NSColor(calibratedRed: 0.945, green: 0.922, blue: 0.89, alpha: 1)
        }
    )

    static let ledgerlyListSurface = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.105, alpha: 1)
                : NSColor(calibratedRed: 0.984, green: 0.973, blue: 0.953, alpha: 1)
        }
    )

    static let ledgerlyToolbar = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.125, alpha: 1)
                : NSColor(calibratedRed: 1, green: 0.976, blue: 0.953, alpha: 1)
        }
    )

    static let ledgerlyInspector = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.115, alpha: 1)
                : NSColor(calibratedRed: 1, green: 0.992, blue: 0.976, alpha: 1)
        }
    )

    static let ledgerlyInspectorHeader = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.17, green: 0.14, blue: 0.12, alpha: 1)
                : NSColor(calibratedRed: 1, green: 0.969, blue: 0.929, alpha: 1)
        }
    )

    static let ledgerlyReportCard = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.145, alpha: 1)
                : NSColor(calibratedWhite: 1.0, alpha: 1)
        }
    )

    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var integer: UInt64 = 0
        Scanner(string: value).scanHexInt64(&integer)
        let red = Double((integer >> 16) & 0xFF) / 255
        let green = Double((integer >> 8) & 0xFF) / 255
        let blue = Double(integer & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
