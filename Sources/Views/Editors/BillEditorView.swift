// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 YodaGuru

import SwiftUI
import UserNotifications
import AppKit
import Security
import LinkPresentation
import CoreImage

struct BillEditorView: View {
    @EnvironmentObject private var store: BillStore
    @Environment(\.dismiss) private var dismiss

    private let existingBill: Bill?
    @State private var name: String
    @State private var amount: Double
    @State private var isVariableAmount: Bool
    @State private var dueDate: Date
    @State private var frequency: BillFrequency
    @State private var category: String
    @State private var colorHex: String
    @State private var website: String
    @State private var notes: String
    @State private var isReminderEnabled: Bool
    @State private var reminderDays: Int
    @State private var isAutoPay: Bool

    private let categories = ["Home", "Utilities", "Credit Cards", "Transport", "Insurance", "Subscriptions", "Health", "Education", "Other"]
    private let colors = [
        "#F2854A", "#E8B448", "#58A66B", "#4E8FD3", "#7B6AD8",
        "#D85F74", "#2AA198", "#A66B3D", "#8E5EA2", "#64748B"
    ]

    init(existingBill: Bill? = nil) {
        self.existingBill = existingBill
        let savedReminderDays = UserDefaults.standard.object(forKey: "defaultReminderDays") == nil
            ? 3
            : UserDefaults.standard.integer(forKey: "defaultReminderDays")
        _name = State(initialValue: existingBill?.name ?? "")
        _amount = State(initialValue: existingBill?.amount ?? 0)
        _isVariableAmount = State(initialValue: existingBill?.isVariableAmount ?? false)
        _dueDate = State(initialValue: existingBill?.dueDate ?? Date())
        _frequency = State(initialValue: existingBill?.frequency ?? .monthly)
        _category = State(initialValue: existingBill?.category ?? "Utilities")
        _colorHex = State(initialValue: existingBill?.colorHex ?? "#F2854A")
        _website = State(initialValue: existingBill?.website ?? "")
        _notes = State(initialValue: existingBill?.notes ?? "")
        _isReminderEnabled = State(initialValue: existingBill?.isReminderEnabled ?? true)
        _reminderDays = State(initialValue: existingBill?.reminderDays ?? savedReminderDays)
        _isAutoPay = State(initialValue: existingBill?.isAutoPay ?? false)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(existingBill == nil ? "Add a bill" : "Edit bill")
                    .font(.title2.bold())
                Spacer()
                Button("Cancel") { dismiss() }
                Button(existingBill == nil ? "Add Bill" : "Save") { save() }
                    .ledgerlyGlassButton(prominent: true)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || amount < 0)
            }
            .padding(20)

            Divider()

            Form {
                Section("Bill") {
                    TextField("Name", text: $name)
                    Toggle("Variable amount", isOn: $isVariableAmount)
                    TextField(isVariableAmount ? "Estimated amount" : "Amount", value: $amount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                    DatePicker("Due date", selection: $dueDate, displayedComponents: .date)
                    Picker("Repeats", selection: $frequency) {
                        ForEach(BillFrequency.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }
                }

                Section("Appearance") {
                    HStack {
                        Text("Color")
                        Spacer()
                        ForEach(colors, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 22, height: 22)
                                .overlay {
                                    if colorHex == hex {
                                        Circle().stroke(.primary, lineWidth: 2).padding(-3)
                                    }
                                }
                                .onTapGesture { colorHex = hex }
                        }
                    }
                }

                Section("Payment") {
                    Toggle("Automatic payment", isOn: $isAutoPay)
                    Toggle("Reminder", isOn: $isReminderEnabled)
                    if isReminderEnabled {
                        Stepper(
                            "Remind me \(reminderDays) day\(reminderDays == 1 ? "" : "s") before",
                            value: $reminderDays,
                            in: 0...30
                        )
                    }
                    TextField("Biller website (example.com)", text: $website)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 540, height: 650)
    }

    private func save() {
        let bill = Bill(
            id: existingBill?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amount,
            isVariableAmount: isVariableAmount,
            dueDate: dueDate,
            frequency: frequency,
            category: category,
            colorHex: colorHex,
            website: website,
            notes: notes,
            isReminderEnabled: isReminderEnabled,
            reminderDays: reminderDays,
            isAutoPay: isAutoPay,
            payments: existingBill?.payments ?? [],
            attachments: existingBill?.attachments ?? [],
            isArchived: existingBill?.isArchived ?? false
        )
        if existingBill == nil {
            store.add(bill)
        } else {
            store.update(bill)
        }
        dismiss()
    }
}
