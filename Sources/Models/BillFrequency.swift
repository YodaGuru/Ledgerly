// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 YodaGuru

import SwiftUI
import UserNotifications
import AppKit
import Security
import LinkPresentation
import CoreImage

enum BillFrequency: String, Codable, CaseIterable, Identifiable {
    case weekly = "Weekly"
    case biweekly = "Biweekly"
    case monthly = "Monthly"
    case quarterly = "Quarterly"
    case yearly = "Yearly"
    case once = "One time"

    var id: String { rawValue }

    var calendarComponent: Calendar.Component? {
        switch self {
        case .weekly, .biweekly: return .weekOfYear
        case .monthly: return .month
        case .quarterly: return .month
        case .yearly: return .year
        case .once: return nil
        }
    }

    var calendarValue: Int {
        switch self {
        case .biweekly: return 2
        case .quarterly: return 3
        default: return 1
        }
    }
}
extension BillFrequency {
    var displayText: String {
        switch self {
        case .weekly: return "Every week"
        case .biweekly: return "Every other week"
        case .monthly: return "Every month"
        case .quarterly: return "Every 3 months"
        case .yearly: return "Every year"
        case .once: return "One time"
        }
    }
}
