// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 YodaGuru

import SwiftUI
import UserNotifications
import AppKit
import Security
import LinkPresentation
import CoreImage

struct ForecastView: View {
    @EnvironmentObject private var store: BillStore
    @State private var selectedMonth = Date()
    private let months = (0..<12).compactMap {
        Calendar.current.date(byAdding: .month, value: $0, to: Date())
    }

    private var totals: [Double] {
        months.map { month in
            store.bills
                .filter { !$0.isArchived }
                .reduce(0) { $0 + $1.amountDue(in: month) }
        }
    }

    private var maxTotal: Double { max(totals.max() ?? 1, 1) }

    private var selectedBills: [Bill] {
        store.bills
            .filter { !$0.isArchived && $0.amountDue(in: selectedMonth) > 0 }
            .sorted {
                if $0.dueDate == $1.dueDate {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.dueDate < $1.dueDate
            }
    }

    private var selectedTotal: Double {
        selectedBills.reduce(0) { $0 + $1.amountDue(in: selectedMonth) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("12-month forecast")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Plan ahead for recurring and one-time bills.")
                    .foregroundStyle(.secondary)

                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(Array(months.enumerated()), id: \.offset) { index, month in
                        Button {
                            selectedMonth = month
                        } label: {
                            VStack(spacing: 8) {
                                Text(totals[index].currencyCompact)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(
                                        Calendar.current.isDate(
                                            selectedMonth,
                                            equalTo: month,
                                            toGranularity: .month
                                        )
                                            ? Color(hex: "#4E8FD3")
                                            : Color(hex: "#EDB28E")
                                    )
                                    .frame(height: max(8, 250 * totals[index] / maxTotal))
                                Text(month.formatted(.dateTime.month(.narrow)))
                                    .font(.caption.bold())
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .help("Show bills due in \(month.formatted(.dateTime.month(.wide).year()))")
                    }
                }
                .frame(height: 310, alignment: .bottom)
                .padding(24)
                .background(Color.ledgerlyReportCard, in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18).stroke(Color.ledgerlyDivider)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(selectedMonth.formatted(.dateTime.month(.wide).year()))
                                .font(.headline)
                            Text("\(selectedBills.count) bill\(selectedBills.count == 1 ? "" : "s") due")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(selectedTotal.currency)
                            .font(.title3.bold())
                    }

                    Divider()

                    if selectedBills.isEmpty {
                        Text("No bills are projected for this month.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(selectedBills) { bill in
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color(hex: bill.colorHex).opacity(0.18))
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        Circle()
                                            .fill(Color(hex: bill.colorHex))
                                            .frame(width: 9, height: 9)
                                    }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bill.name)
                                        .fontWeight(.semibold)
                                    Text("\(bill.category) · \(bill.frequency.displayText)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(bill.amountDue(in: selectedMonth).currency)
                                    .fontWeight(.semibold)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding(22)
                .background(Color.ledgerlyReportCard, in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18).stroke(Color.ledgerlyDivider)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Monthly set-aside")
                        .font(.headline)
                    ForEach(store.bills.filter {
                        !$0.isArchived && ($0.frequency == .quarterly || $0.frequency == .yearly)
                    }) { bill in
                        HStack {
                            Circle().fill(Color(hex: bill.colorHex)).frame(width: 10, height: 10)
                            Text(bill.name)
                            Spacer()
                            Text("\((bill.amount / (bill.frequency == .yearly ? 12 : 3)).currency) / month")
                                .fontWeight(.semibold)
                        }
                        .padding(.vertical, 4)
                    }
                    if !store.bills.contains(where: {
                        !$0.isArchived && ($0.frequency == .quarterly || $0.frequency == .yearly)
                    }) {
                        Text("Add quarterly or yearly bills to see suggested monthly savings.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(22)
                .background(Color.ledgerlyReportCard, in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18).stroke(Color.ledgerlyDivider)
                }
            }
            .padding(28)
        }
        .background(Color.ledgerlyWorkspace)
    }
}

// Payment History
