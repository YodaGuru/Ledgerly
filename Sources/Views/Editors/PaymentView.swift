// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 YodaGuru

import SwiftUI
import UserNotifications
import AppKit
import Security
import LinkPresentation
import CoreImage

struct PaymentView: View {
    @EnvironmentObject private var store: BillStore
    @Environment(\.dismiss) private var dismiss
    let bill: Bill
    @State private var amount: Double
    @State private var confirmation = ""
    @State private var attachmentURLs: [URL] = []
    @State private var attachmentError: String?

    init(bill: Bill) {
        self.bill = bill
        _amount = State(initialValue: bill.amount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Log payment")
                .font(.title2.bold())
            Text(bill.name)
                .font(.headline)
            TextField("Amount", value: $amount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
            TextField("Confirmation number (optional)", text: $confirmation)

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

            Text("The next due date will be calculated automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Mark Paid") {
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
                        attachments: copiedAttachments
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
