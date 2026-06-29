// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 YodaGuru

import SwiftUI
import UserNotifications
import AppKit
import Security
import LinkPresentation
import CoreImage

enum SidebarItem: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case dueSoon = "Due Soon"
    case dueMonth = "Due This Month"
    case paidRecently = "Paid Recently"
    case income = "Income"
    case forecast = "Forecast"
    case history = "Payment History"
    case archive = "Archived Bills"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "list.bullet.rectangle"
        case .dueSoon: return "bell"
        case .dueMonth: return "calendar"
        case .paidRecently: return "checkmark"
        case .income: return "banknote.fill"
        case .forecast: return "chart.bar.fill"
        case .history: return "clock.arrow.circlepath"
        case .archive: return "archivebox"
        case .settings: return "gearshape.fill"
        }
    }
}
