// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 YodaGuru

import SwiftUI
import UserNotifications
import AppKit
import Security
import LinkPresentation
import CoreImage

enum PaymentLoggingMode: String {
    case full
    case partial

    var title: String {
        switch self {
        case .full: return "Log payment"
        case .partial: return "Log partial payment"
        }
    }

    var actionTitle: String {
        switch self {
        case .full: return "Mark Paid"
        case .partial: return "Log Partial Payment"
        }
    }
}

struct PaymentView: View {
    @EnvironmentObject private var store: BillStore
    @Environment(\.dismiss) private var dismiss
    let bill: Bill
    let mode: PaymentLoggingMode
    @State private var amount: Double
    @State private var confirmation = ""
    @State private var notes = ""
    @State private var attachmentURLs: [URL] = []
    @State private var attachmentError: String?

    init(bill: Bill, mode: PaymentLoggingMode = .full) {
        self.bill = bill
        self.mode = mode
        _amount = State(initialValue: mode == .full ? bill.cycleRemainingAmount : min(25, bill.cycleRemainingAmount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(mode.title)
                .font(.title2.bold())
            Text(bill.name)
                .font(.headline)
            if bill.hasPartialPaymentForCurrentCycle {
                Text("\(bill.cyclePaidAmount.currency) paid · \(bill.cycleRemainingAmount.currency) remaining")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextField("Amount", value: $amount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
            TextField("Confirmation number (optional)", text: $confirmation)
            TextField("Notes (optional)", text: $notes, axis: .vertical)
                .lineLimit(2...4)

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Receipt or statement")
                        .font(.headline)
                    Spacer()
                    Button {
                        chooseAttachments()
                    } label: {
                        Label("Attach", systemImage: "paperclip")
                    }
                }

                if attachmentURLs.isEmpty {
                    Text("Optionally attach a receipt, confirmation, PDF, or image to this payment.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(attachmentURLs, id: \.self) { url in
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(Color(hex: "#4E8FD3"))
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                attachmentURLs.removeAll { $0 == url }
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(8)
                        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            Text(mode == .full ? "The next due date will be calculated automatically." : "The bill will stay due until the remaining balance is paid.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(mode.actionTitle) {
                    var copiedAttachments: [BillAttachment] = []
                    do {
                        for url in attachmentURLs {
                            copiedAttachments.append(
                                try store.copyPaymentAttachment(from: url)
                            )
                        }
                    } catch {
                        attachmentError = error.localizedDescription
                        return
                    }
                    store.markPaid(
                        bill,
                        amount: amount,
                        confirmation: confirmation,
                        notes: notes,
                        attachments: copiedAttachments,
                        advancesDueDate: mode == .full
                    )
                    dismiss()
                }
                .ledgerlyGlassButton(prominent: true)
            }
        }
        .padding(24)
        .frame(width: 460)
        .alert("Couldn’t Attach File", isPresented: Binding(
            get: { attachmentError != nil },
            set: { if !$0 { attachmentError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(attachmentError ?? "")
        }
    }

    private func chooseAttachments() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.title = "Attach Files to Payment"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !attachmentURLs.contains(url) {
            attachmentURLs.append(url)
        }
    }
}

// Helpers
