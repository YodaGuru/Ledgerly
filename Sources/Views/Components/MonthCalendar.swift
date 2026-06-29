// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 YodaGuru

import SwiftUI
import UserNotifications
import AppKit
import Security
import LinkPresentation
import CoreImage

struct MonthCalendar: View {
    let month: Date
    let bills: [Bill]

    private var days: [Date?] {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        let dayRange = calendar.range(of: .day, in: .month, for: start)!
        let weekday = calendar.component(.weekday, from: start)
        let padding = Array<Date?>(repeating: nil, count: weekday - 1)
        return padding + dayRange.compactMap {
            calendar.date(byAdding: .day, value: $0 - 1, to: start)
        }.map(Optional.some)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Monthly calendar")
                        .font(.headline)
                    Text("Colored dots show bills on each due date.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.subheadline.weight(.semibold))
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 7) {
                ForEach(Calendar.current.veryShortWeekdaySymbols, id: \.self) { weekday in
                    Text(weekday.uppercased())
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        CalendarDay(day: day, bills: bills.filter { Calendar.current.isDate($0.dueDate, inSameDayAs: day) })
                    } else {
                        Color.clear.frame(height: 58)
                    }
                }
            }
        }
        .padding(20)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06))
        }
        .shadow(color: .black.opacity(0.04), radius: 18, y: 8)
    }
}
struct CalendarDay: View {
    let day: Date
    let bills: [Bill]

    var body: some View {
        VStack(spacing: 6) {
            Text(day.formatted(.dateTime.day()))
                .font(.subheadline.weight(Calendar.current.isDateInToday(day) ? .bold : .regular))
                .foregroundStyle(Calendar.current.isDateInToday(day) ? .white : .primary)
                .frame(width: 27, height: 27)
                .background(
                    Calendar.current.isDateInToday(day) ? Color(hex: "#4E8FD3") : Color.clear,
                    in: Circle()
                )
            HStack(spacing: 3) {
                ForEach(bills.prefix(3)) { bill in
                    Circle()
                        .fill(Color(hex: bill.colorHex))
                        .frame(width: 6, height: 6)
                }
            }
            .frame(height: 7)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background(bills.isEmpty ? Color.clear : Color(hex: "#FAF2EA"), in: RoundedRectangle(cornerRadius: 10))
    }
}
