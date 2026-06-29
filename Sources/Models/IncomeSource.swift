// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 YodaGuru

import SwiftUI
import UserNotifications
import AppKit
import Security
import LinkPresentation
import CoreImage

struct IncomeSource: Identifiable, Codable, Hashable {
    enum Frequency: String, Codable, CaseIterable, Identifiable {
        case weekly = "Weekly"
        case biweekly = "Biweekly"
        case twiceMonthly = "Twice monthly"
        case monthly = "Monthly"
        case quarterly = "Quarterly"
        case yearly = "Yearly"
        case once = "One time"

        var id: String { rawValue }

        var displayText: String {
            switch self {
            case .weekly: return "Every week"
            case .biweekly: return "Every other week"
            case .twiceMonthly: return "Twice monthly"
            case .monthly: return "Every month"
            case .quarterly: return "Every 3 months"
            case .yearly: return "Every year"
            case .once: return "One time"
            }
        }
    }

    var id = UUID()
    var name: String
    var amount: Double
    var nextDate: Date
    var frequency: Frequency
    var firstPayday: Int
    var secondPayday: Int
    var notes: String
    var colorHex: String

    init(
        id: UUID = UUID(),
        name: String,
        amount: Double,
        nextDate: Date,
        frequency: Frequency,
        firstPayday: Int = 15,
        secondPayday: Int = 30,
        notes: String,
        colorHex: String
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.nextDate = nextDate
        self.frequency = frequency
        self.firstPayday = firstPayday
        self.secondPayday = secondPayday
        self.notes = notes
        self.colorHex = colorHex
    }

    enum CodingKeys: String, CodingKey {
        case id, name, amount, nextDate, frequency, firstPayday, secondPayday, notes, colorHex
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decode(String.self, forKey: .name)
        amount = try values.decode(Double.self, forKey: .amount)
        nextDate = try values.decode(Date.self, forKey: .nextDate)
        frequency = try values.decode(Frequency.self, forKey: .frequency)
        firstPayday = try values.decodeIfPresent(Int.self, forKey: .firstPayday) ?? 15
        secondPayday = try values.decodeIfPresent(Int.self, forKey: .secondPayday) ?? 30
        notes = try values.decodeIfPresent(String.self, forKey: .notes) ?? ""
        colorHex = try values.decodeIfPresent(String.self, forKey: .colorHex) ?? "#58A66B"
    }

    func estimatedAmount(in month: Date) -> Double {
        switch frequency {
        case .weekly:
            return amount * 4.33
        case .biweekly:
            return amount * 26 / 12
        case .twiceMonthly:
            return amount * 2
        case .monthly:
            return amount
        case .quarterly:
            return amount / 3
        case .yearly:
            return amount / 12
        case .once:
            return Calendar.current.isDate(nextDate, equalTo: month, toGranularity: .month)
                ? amount
                : 0
        }
    }

    func nextExpectedDate(from date: Date = Date()) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)

        if frequency == .biweekly {
            var expectedDate = calendar.startOfDay(for: nextDate)
            while expectedDate < today {
                guard let next = calendar.date(byAdding: .weekOfYear, value: 2, to: expectedDate) else {
                    return nextDate
                }
                expectedDate = next
            }
            return expectedDate
        }

        guard frequency == .twiceMonthly else { return nextDate }

        let days = [firstPayday, secondPayday].sorted()

        for monthOffset in 0...1 {
            guard let month = calendar.date(byAdding: .month, value: monthOffset, to: today),
                  let range = calendar.range(of: .day, in: .month, for: month) else { continue }

            for day in days {
                var components = calendar.dateComponents([.year, .month], from: month)
                components.day = min(day, range.count)
                if let candidate = calendar.date(from: components), candidate >= today {
                    return candidate
                }
            }
        }

        return nextDate
    }
}
