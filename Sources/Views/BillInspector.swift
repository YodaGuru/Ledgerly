// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 YodaGuru

import SwiftUI
import UserNotifications
import AppKit
import Security
import LinkPresentation
import CoreImage

struct BillInspector: View {
    @EnvironmentObject private var store: BillStore
    let bill: Bill
    let onPay: () -> Void
    let onPartialPay: () -> Void
    let onEdit: () -> Void
    let onClose: () -> Void
    @State private var notesDraft = ""
    @State private var notesSaveTask: Task<Void, Never>?
    @State private var showingBillHistory = false
    @State private var websiteBrandImage: NSImage?
    @State private var websiteBrandAccent: Color?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let websiteBrandImage {
                    Image(nsImage: websiteBrandImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill((websiteBrandAccent ?? Color(hex: bill.colorHex)).opacity(0.18))
                        )
                } else {
                    Circle()
                        .fill(websiteBrandAccent ?? Color(hex: bill.colorHex))
                        .frame(width: 16, height: 16)
                }
                Text(bill.name)
                    .font(.title3.bold())
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(.secondary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Close Bill Details")
            }
            .padding(18)
            .background(
                LinearGradient(
                    colors: [
                        (websiteBrandAccent ?? Color(hex: bill.colorHex)).opacity(0.24),
                        Color.ledgerlyInspectorHeader
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(bill.dueLabel)
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                        Text(bill.dueDate.formatted(date: .complete, time: .omitted))
                            .foregroundStyle(.secondary)
                        Text(bill.cycleBalanceDisplayText)
                            .font(.title3.bold())
                            .foregroundStyle(bill.dueDateColor)
                        if let paidSummary = bill.cyclePaidSummaryText {
                            Text(paidSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("Log Payment", action: onPay)
                        .ledgerlyGlassButton(prominent: true)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)

                    Button("Log Partial Payment", action: onPartialPay)
                        .ledgerlyGlassButton()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .disabled(bill.status == .paid)

                    Button("Skip This Occurrence") {
                        store.skip(bill)
                    }
                    .ledgerlyGlassButton()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)

                    Button {
                        showingBillHistory = true
                    } label: {
                        InspectorLink(
                            title: "Payment History",
                            subtitle: bill.payments.isEmpty ? "Never paid" : "\(bill.payments.count) payment\(bill.payments.count == 1 ? "" : "s")",
                            icon: "clock.arrow.circlepath"
                        )
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.headline)
                        TextEditor(text: $notesDraft)
                            .font(.body)
                            .frame(minHeight: 90)
                            .padding(7)
                            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                            .onChange(of: notesDraft) { newValue in
                                scheduleNotesSave(newValue)
                            }
                    }

                    if let websiteURL = bill.websiteURL {
                        Link(destination: websiteURL) {
                            Label("Open Biller Website", systemImage: "safari")
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.ledgerlyInspector)

            Divider()
            HStack {
                Button("Archive") { store.archive(bill) }
                    .disabled(bill.isArchived)
                Spacer()
                Button("Edit", action: onEdit)
            }
            .padding(14)
        }
        .onAppear { notesDraft = bill.notes }
        .onChange(of: bill.id) { _ in
            notesSaveTask?.cancel()
            notesDraft = bill.notes
        }
        .onDisappear {
            notesSaveTask?.cancel()
            if notesDraft != bill.notes {
                store.updateNotes(for: bill, notes: notesDraft)
            }
        }
        .task(id: "\(bill.customLogo?.storedName ?? "none")-\(bill.websiteURL?.absoluteString ?? "")") {
            await loadWebsiteBrand()
        }
        .sheet(isPresented: $showingBillHistory) {
            BillPaymentHistoryView(bill: bill)
        }
    }

    private func scheduleNotesSave(_ notes: String) {
        notesSaveTask?.cancel()
        notesSaveTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            store.updateNotes(for: bill, notes: notes)
        }
    }

    private func loadWebsiteBrand() async {
        if let customLogoImage = store.customLogoImage(for: bill) {
            websiteBrandImage = customLogoImage
            websiteBrandAccent = Color(hex: bill.colorHex)
            return
        }

        guard let websiteURL = bill.websiteURL else {
            websiteBrandImage = nil
            websiteBrandAccent = nil
            return
        }

        if let brand = await store.websiteBrand(for: websiteURL) {
            websiteBrandImage = brand.image
            websiteBrandAccent = brand.accent
        } else {
            websiteBrandImage = nil
            websiteBrandAccent = nil
        }
    }
}
struct InspectorLink: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
struct AttachmentRow: View {
    let attachment: BillAttachment
    let onOpen: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .foregroundStyle(Color(hex: "#4E8FD3"))
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName)
                    .lineLimit(1)
                Text(attachment.addedDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onOpen) {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
        }
        .padding(9)
        .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}
