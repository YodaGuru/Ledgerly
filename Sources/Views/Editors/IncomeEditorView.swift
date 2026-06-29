// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 YodaGuru

import SwiftUI
import UserNotifications
import AppKit
import Security
import LinkPresentation
import CoreImage

struct IncomeEditorView: View {
    @EnvironmentObject private var store: BillStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount = 0.0
    @State private var nextDate = Date()
    @State private var frequency: IncomeSource.Frequency = .monthly
    @State private var firstPayday = 15
    @State private var secondPayday = 30
    @State private var notes = ""
    @State private var colorHex = "#58A66B"

    private let colors = ["#58A66B", "#4E8FD3", "#7B6AD8", "#E8B448", "#F2854A"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add income")
                    .font(.title2.bold())
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add Income") {
                    store.addIncome(
                        IncomeSource(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            amount: amount,
                            nextDate: nextDate,
                            frequency: frequency,
                            firstPayday: firstPayday,
                            secondPayday: secondPayday,
                            notes: notes,
                            colorHex: colorHex
                        )
                    )
                    dismiss()
                }
                .ledgerlyGlassButton(prominent: true)
                .disabled(
                    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    amount <= 0 ||
                    (frequency == .twiceMonthly && firstPayday == secondPayday)
                )
            }
            .padding(20)
            Divider()
            Form {
                TextField("Source name", text: $name)
                TextField(
                    (frequency == .biweekly || frequency == .twiceMonthly) ? "Amount per payment" : "Amount",
                    value: $amount,
                    format: .currency(code: Locale.current.currency?.identifier ?? "USD")
                )
                Picker("Repeats", selection: $frequency) {
                    ForEach(IncomeSource.Frequency.allCases) { Text($0.rawValue).tag($0) }
                }
                if frequency == .twiceMonthly {
                    Stepper("First payday: \(firstPayday)", value: $firstPayday, in: 1...31)
                    Stepper("Second payday: \(secondPayday)", value: $secondPayday, in: 1...31)
                    Text("If a payday does not exist in a shorter month, Ledgerly uses the last day of that month.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    DatePicker("Next expected date", selection: $nextDate, displayedComponents: .date)
                }
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
                HStack {
                    Text("Color")
                    Spacer()
                    ForEach(colors, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 22, height: 22)
                            .overlay {
                                if colorHex == hex {
                                    Circle().stroke(Color.primary, lineWidth: 2).padding(-3)
                                }
                            }
                            .onTapGesture { colorHex = hex }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 500, height: frequency == .twiceMonthly ? 560 : 470)
    }
}
