// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 YodaGuru

import SwiftUI
import UserNotifications
import AppKit
import Security
import LinkPresentation
import CoreImage

struct PaymentHistoryView: View {
    @EnvironmentObject private var store: BillStore
    @State private var searchText = ""
    @State private var editingEntry: PaymentEntry?
    @State private var deletingEntry: PaymentEntry?

    private var entries: [PaymentEntry] {
        store.bills
            .flatMap { bill in bill.payments.map { PaymentEntry(bill: bill, payment: $0) } }
            .filter {
                searchText.isEmpty ||
                $0.bill.name.localizedCaseInsensitiveContains(searchText) ||
                $0.payment.confirmation.localizedCaseInsensitiveContains(searchText) ||
                $0.payment.notes.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { $0.payment.date > $1.payment.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Payment history")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("A searchable record of every payment and confirmation number.")
                        .foregroundStyle(.secondary)
                    Text("Double-click a payment with an attachment to open it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField("Search payments", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
            }

            if entries.isEmpty {
                EmptyState(
                    title: searchText.isEmpty ? "No payments logged" : "No matching payments",
                    message: searchText.isEmpty ? "Payments you log will appear here." : "Try another bill or confirmation number.",
                    icon: searchText.isEmpty ? "checkmark.seal" : "magnifyingglass"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.ledgerlyReportCard, in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18).stroke(Color.ledgerlyDivider)
                }
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 24) {
                        Text("Bill").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Date").frame(width: 130, alignment: .leading)
                        Text("Amount").frame(width: 130, alignment: .trailing)
                        Text("Confirmation").frame(width: 170, alignment: .leading)
                        Text("Attachment").frame(width: 90, alignment: .center)
                        Text("").frame(width: 36)
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)

                    Divider()

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(entries) { entry in
                                PaymentHistoryRow(
                                    entry: entry,
                                    onEdit: { editingEntry = entry },
                                    onDelete: { deletingEntry = entry }
                                )
                                if entry.id != entries.last?.id {
                                    Divider().padding(.leading, 54)
                                }
                            }
                        }
                    }
                }
                .background(Color.ledgerlyReportCard, in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18).stroke(Color.ledgerlyDivider)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
        .padding(28)
        .background(Color.ledgerlyWorkspace)
        .sheet(item: $editingEntry) { entry in
            PaymentEditView(entry: entry)
                .environmentObject(store)
        }
        .alert("Delete Payment?", isPresented: deletePaymentAlertBinding, presenting: deletingEntry) { entry in
            Button("Cancel", role: .cancel) {
                deletingEntry = nil
            }
            Button("Delete", role: .destructive) {
                store.deletePayment(billID: entry.bill.id, paymentID: entry.payment.id)
                deletingEntry = nil
            }
        } message: { entry in
            Text("This removes the payment for \(entry.bill.name) and reverts the bill to the due date it had before that payment was logged.")
        }
    }

    private var deletePaymentAlertBinding: Binding<Bool> {
        Binding(
            get: { deletingEntry != nil },
            set: { isPresented in
                if !isPresented {
                    deletingEntry = nil
                }
            }
        )
    }
}
struct BillPaymentHistoryView: View {
    @EnvironmentObject private var store: BillStore
    @Environment(\.dismiss) private var dismiss
    let bill: Bill
    @State private var editingEntry: PaymentEntry?
    @State private var deletingEntry: PaymentEntry?

    private var currentBill: Bill {
        store.bills.first { $0.id == bill.id } ?? bill
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(currentBill.name) history")
                        .font(.title2.bold())
                    Text("\(currentBill.payments.count) payment\(currentBill.payments.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            Divider()

            if currentBill.payments.isEmpty {
                EmptyState(
                    title: "No payments logged",
                    message: "Payments for this bill will appear here.",
                    icon: "clock.arrow.circlepath"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(currentBill.payments.sorted { $0.date > $1.date }) { payment in
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color(hex: "#58A66B"))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(payment.date.formatted(date: .long, time: .omitted))
                                        .fontWeight(.semibold)
                                    Text(payment.confirmation.isEmpty ? "No confirmation number" : payment.confirmation)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if !payment.notes.isEmpty {
                                        Text(payment.notes)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                                Text(payment.amount.currency)
                                    .fontWeight(.bold)
                                if !payment.attachments.isEmpty {
                                    Image(systemName: "paperclip.circle.fill")
                                        .foregroundStyle(Color(hex: "#4E8FD3"))
                                }
                                Menu {
                                    Button("Edit Payment") {
                                        editingEntry = PaymentEntry(bill: currentBill, payment: payment)
                                    }
                                    Button("Delete Payment", role: .destructive) {
                                        deletingEntry = PaymentEntry(bill: currentBill, payment: payment)
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .foregroundStyle(.secondary)
                                }
                                .menuStyle(.borderlessButton)
                            }
                            .padding(16)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                if let attachment = payment.attachments.first {
                                    NSWorkspace.shared.open(store.attachmentURL(attachment))
                                }
                            }
                            Divider().padding(.leading, 50)
                        }

                        if !bill.attachments.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Payment documents")
                                    .font(.headline)
                                ForEach(bill.attachments) { attachment in
                                    Button {
                                        NSWorkspace.shared.open(store.attachmentURL(attachment))
                                    } label: {
                                        HStack {
                                            Image(systemName: "doc.fill")
                                                .foregroundStyle(Color(hex: "#4E8FD3"))
                                            Text(attachment.fileName)
                                                .lineLimit(1)
                                            Spacer()
                                            Image(systemName: "arrow.up.forward.app")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .padding(10)
                                    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                            .padding(16)
                        }
                    }
                }
            }
        }
        .frame(width: 520, height: 440)
        .background(Color.ledgerlyWorkspace)
        .sheet(item: $editingEntry) { entry in
            PaymentEditView(entry: entry)
                .environmentObject(store)
        }
        .alert("Delete Payment?", isPresented: deletePaymentAlertBinding, presenting: deletingEntry) { entry in
            Button("Cancel", role: .cancel) {
                deletingEntry = nil
            }
            Button("Delete", role: .destructive) {
                store.deletePayment(billID: entry.bill.id, paymentID: entry.payment.id)
                deletingEntry = nil
            }
        } message: { entry in
            Text("This removes the payment and reverts \(entry.bill.name) to the due date it had before that payment was logged.")
        }
    }

    private var deletePaymentAlertBinding: Binding<Bool> {
        Binding(
            get: { deletingEntry != nil },
            set: { isPresented in
                if !isPresented {
                    deletingEntry = nil
                }
            }
        )
    }
}
struct PaymentHistoryRow: View {
    @EnvironmentObject private var store: BillStore
    let entry: PaymentEntry
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            HStack(spacing: 11) {
                Circle()
                    .fill(Color(hex: entry.bill.colorHex).opacity(0.18))
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(Color(hex: entry.bill.colorHex))
                    }
                Text(entry.bill.name)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(entry.payment.date.formatted(date: .abbreviated, time: .omitted))
                .frame(width: 130, alignment: .leading)
            Text(entry.payment.amount.currency)
                .fontWeight(.semibold)
                .frame(width: 130, alignment: .trailing)
            Text(entry.payment.confirmation.isEmpty ? "—" : entry.payment.confirmation)
                .foregroundStyle(entry.payment.confirmation.isEmpty ? Color.secondary : Color.primary)
                .lineLimit(1)
                .frame(width: 170, alignment: .leading)
            Group {
                if !entry.payment.attachments.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(hex: "#58A66B"))
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 90, alignment: .center)
            Menu {
                Button("Edit Payment", action: onEdit)
                Button("Delete Payment", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 36)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if let attachment = entry.payment.attachments.first {
                NSWorkspace.shared.open(store.attachmentURL(attachment))
            }
        }
    }
}

struct PaymentEditView: View {
    @EnvironmentObject private var store: BillStore
    @Environment(\.dismiss) private var dismiss
    let entry: PaymentEntry
    @State private var date: Date
    @State private var amount: Double
    @State private var confirmation: String
    @State private var notes: String

    init(entry: PaymentEntry) {
        self.entry = entry
        _date = State(initialValue: entry.payment.date)
        _amount = State(initialValue: entry.payment.amount)
        _confirmation = State(initialValue: entry.payment.confirmation)
        _notes = State(initialValue: entry.payment.notes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Edit payment")
                    .font(.title2.bold())
                Text(entry.bill.name)
                    .foregroundStyle(.secondary)
            }

            DatePicker("Payment date", selection: $date, displayedComponents: .date)
            TextField("Amount", value: $amount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
            TextField("Confirmation number", text: $confirmation)
            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(3...6)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    store.updatePayment(
                        billID: entry.bill.id,
                        paymentID: entry.payment.id,
                        date: date,
                        amount: amount,
                        confirmation: confirmation,
                        notes: notes
                    )
                    dismiss()
                }
                .ledgerlyGlassButton(prominent: true)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

// Settings
struct PaymentEntry: Identifiable {
    let bill: Bill
    let payment: Payment
    var id: UUID { payment.id }
}
