// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 YodaGuru

import SwiftUI
import UserNotifications
import AppKit
import Security
import LinkPresentation
import CoreImage

struct BillAttachment: Identifiable, Codable, Hashable {
    var id = UUID()
    var fileName: String
    var storedName: String
    var addedDate = Date()
}
struct BillCustomLogo: Codable, Hashable {
    var fileName: String
    var storedName: String
}
struct Bill: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var amount: Double
    var isVariableAmount: Bool
    var dueDate: Date
    var frequency: BillFrequency
    var category: String
    var colorHex: String
    var website: String
    var notes: String
    var isReminderEnabled: Bool
    var reminderDays: Int
    var isAutoPay: Bool
    var payments: [Payment]
    var attachments: [BillAttachment]
    var customLogo: BillCustomLogo?
    var isArchived: Bool

    init(
        id: UUID = UUID(),
        name: String,
        amount: Double,
        isVariableAmount: Bool = false,
        dueDate: Date,
        frequency: BillFrequency,
        category: String,
        colorHex: String,
        website: String,
        notes: String,
        isReminderEnabled: Bool = true,
        reminderDays: Int,
        isAutoPay: Bool,
        payments: [Payment],
        attachments: [BillAttachment] = [],
        customLogo: BillCustomLogo? = nil,
        isArchived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.isVariableAmount = isVariableAmount
        self.dueDate = dueDate
        self.frequency = frequency
        self.category = category
        self.colorHex = colorHex
        self.website = website
        self.notes = notes
        self.isReminderEnabled = isReminderEnabled
        self.reminderDays = reminderDays
        self.isAutoPay = isAutoPay
        self.payments = payments
        self.attachments = attachments
        self.customLogo = customLogo
        self.isArchived = isArchived
    }

    enum CodingKeys: String, CodingKey {
        case id, name, amount, isVariableAmount, dueDate, frequency, category, colorHex, website
        case notes, isReminderEnabled, reminderDays, isAutoPay, payments, attachments, customLogo, isArchived
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decode(String.self, forKey: .name)
        amount = try values.decode(Double.self, forKey: .amount)
        isVariableAmount = try values.decodeIfPresent(Bool.self, forKey: .isVariableAmount) ?? false
        dueDate = try values.decode(Date.self, forKey: .dueDate)
        frequency = try values.decode(BillFrequency.self, forKey: .frequency)
        category = try values.decode(String.self, forKey: .category)
        colorHex = try values.decode(String.self, forKey: .colorHex)
        website = try values.decodeIfPresent(String.self, forKey: .website) ?? ""
        notes = try values.decodeIfPresent(String.self, forKey: .notes) ?? ""
        isReminderEnabled = try values.decodeIfPresent(Bool.self, forKey: .isReminderEnabled) ?? true
        reminderDays = try values.decodeIfPresent(Int.self, forKey: .reminderDays) ?? 3
        isAutoPay = try values.decodeIfPresent(Bool.self, forKey: .isAutoPay) ?? false
        payments = try values.decodeIfPresent([Payment].self, forKey: .payments) ?? []
        attachments = try values.decodeIfPresent([BillAttachment].self, forKey: .attachments) ?? []
        customLogo = try values.decodeIfPresent(BillCustomLogo.self, forKey: .customLogo)
        isArchived = try values.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }

    var isPaidForCurrentCycle: Bool {
        guard hasKnownCycleAmount else { return false }
        return cycleRemainingAmount <= 0.005
    }

    var hasKnownCycleAmount: Bool {
        !isVariableAmount || amount > 0.005 || estimatedVariableAmount != nil
    }

    var cyclePaidAmount: Double {
        let calendar = Calendar.current
        return payments
            .filter { payment in
                if let dueDateBeforePayment = payment.dueDateBeforePayment {
                    return calendar.isDate(dueDateBeforePayment, inSameDayAs: dueDate)
                }
                switch frequency {
                case .weekly, .biweekly:
                    return calendar.isDate(payment.date, inSameDayAs: dueDate)
                case .monthly, .quarterly, .yearly, .once:
                    return calendar.isDate(payment.date, equalTo: dueDate, toGranularity: .month)
                }
            }
            .reduce(0) { $0 + $1.amount }
    }

    var cycleRemainingAmount: Double {
        max(planningAmount - cyclePaidAmount, 0)
    }

    var cycleBalanceDisplayText: String {
        if isPaidForCurrentCycle { return "Paid" }
        if cyclePaidAmount > 0 {
            return "\(cycleRemainingAmount.currency) remaining"
        }
        return amountDisplayText
    }

    func isPaymentInCurrentCycle(_ payment: Payment) -> Bool {
        let calendar = Calendar.current
        if let dueDateBeforePayment = payment.dueDateBeforePayment {
            return calendar.isDate(dueDateBeforePayment, inSameDayAs: dueDate)
        }
        switch frequency {
        case .weekly, .biweekly:
            return calendar.isDate(payment.date, inSameDayAs: dueDate)
        case .monthly, .quarterly, .yearly, .once:
            return calendar.isDate(payment.date, equalTo: dueDate, toGranularity: .month)
        }
    }

    var hasPartialPaymentForCurrentCycle: Bool {
        cyclePaidAmount > 0 && !isPaidForCurrentCycle
    }

    var cyclePaidSummaryText: String? {
        guard hasPartialPaymentForCurrentCycle else { return nil }
        return "\(cyclePaidAmount.currency) paid"
    }

    var status: BillStatus {
        if isPaidForCurrentCycle { return .paid }
        if dueDate < Calendar.current.startOfDay(for: Date()) { return .overdue }
        return .upcoming
    }

    var lastPaidDate: Date? {
        payments.map(\.date).max()
    }

    var amountDisplayText: String {
        guard isVariableAmount else { return amount.currency }
        guard let estimatedVariableAmount else { return "Variable" }
        return "Est. \(estimatedVariableAmount.currency)"
    }

    var estimatedVariableAmount: Double? {
        guard isVariableAmount else { return nil }
        let recentPayments = payments
            .filter { $0.amount > 0 }
            .sorted { $0.date > $1.date }
            .prefix(6)

        guard !recentPayments.isEmpty else { return nil }
        let total = recentPayments.reduce(0) { $0 + $1.amount }
        return total / Double(recentPayments.count)
    }

    var planningAmount: Double {
        estimatedVariableAmount ?? amount
    }

    var dueDateColor: Color {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dueDay = calendar.startOfDay(for: dueDate)
        let dueSoonLimit = calendar.date(byAdding: .day, value: 7, to: today) ?? today

        if status == .paid { return .green }
        if dueDay < today { return .red }
        if dueDay <= dueSoonLimit { return .yellow }
        return .green
    }

    var websiteURL: URL? {
        let trimmedWebsite = website.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWebsite.isEmpty else { return nil }

        let address = trimmedWebsite.contains("://")
            ? trimmedWebsite
            : "https://\(trimmedWebsite)"
        guard
            let components = URLComponents(string: address),
            let scheme = components.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            components.host != nil
        else {
            return nil
        }
        return components.url
    }

    func amountDue(in month: Date) -> Double {
        let calendar = Calendar.current
        if frequency == .once {
            return calendar.isDate(dueDate, equalTo: month, toGranularity: .month) ? planningAmount : 0
        }

        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        let dueStart = calendar.date(from: calendar.dateComponents([.year, .month], from: dueDate))!
        guard start >= dueStart else { return 0 }
        let months = calendar.dateComponents([.month], from: dueStart, to: start).month ?? 0

        switch frequency {
        case .weekly, .biweekly:
            guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: start) else {
                return 0
            }
            let weekStride = frequency == .biweekly ? 2 : 1
            var occurrence = dueDate
            if occurrence < start {
                let days = calendar.dateComponents([.day], from: occurrence, to: start).day ?? 0
                let daysPerCycle = weekStride * 7
                let cyclesToAdvance = max(0, (days + daysPerCycle - 1) / daysPerCycle)
                occurrence = calendar.date(byAdding: .weekOfYear, value: cyclesToAdvance * weekStride, to: occurrence) ?? occurrence
            }

            var count = 0
            while occurrence < monthEnd {
                if occurrence >= start {
                    count += 1
                }
                guard let next = calendar.date(byAdding: .weekOfYear, value: weekStride, to: occurrence) else {
                    break
                }
                occurrence = next
            }
            return planningAmount * Double(count)
        case .monthly:
            return planningAmount
        case .quarterly:
            return months % 3 == 0 ? planningAmount : 0
        case .yearly:
            return months % 12 == 0 ? planningAmount : 0
        case .once:
            return 0
        }
    }
}
enum BillStatus: String {
    case overdue = "Overdue"
    case upcoming = "Upcoming"
    case paid = "Paid"

    var color: Color {
        switch self {
        case .overdue: return .red
        case .upcoming: return Color(hex: "#E7793F")
        case .paid: return .green
        }
    }
}
extension Bill {
    var dueLabel: String {
        let calendar = Calendar.current
        if status == .paid { return "Paid" }
        if calendar.isDateInToday(dueDate) { return "Due today" }
        if calendar.isDateInTomorrow(dueDate) { return "Due tomorrow" }
        if dueDate < calendar.startOfDay(for: Date()) {
            let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: dueDate),
                to: calendar.startOfDay(for: Date())
            ).day ?? 0
            return "\(days) day\(days == 1 ? "" : "s") overdue"
        }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: Date()),
            to: calendar.startOfDay(for: dueDate)
        ).day ?? 0
        return "Due in \(days) day\(days == 1 ? "" : "s")"
    }
}
