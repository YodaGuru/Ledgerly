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
                        Text(bill.amountDisplayText)
                            .font(.title3.bold())
                            .foregroundStyle(bill.status.color)
                    }

                    Button("Log Payment", action: onPay)
                        .ledgerlyGlassButton(prominent: true)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)

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
        .task(id: bill.websiteURL?.absoluteString) {
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
        guard let websiteURL = bill.websiteURL else {
            websiteBrandImage = nil
            websiteBrandAccent = nil
            return
        }

        let provider = LPMetadataProvider()
        guard let metadata = await fetchMetadata(provider: provider, url: websiteURL) else {
            websiteBrandImage = nil
            websiteBrandAccent = nil
            return
        }

        if let provider = metadata.iconProvider ?? metadata.imageProvider,
           let image = await loadImage(from: provider) {
            websiteBrandImage = image
            websiteBrandAccent = averageAccentColor(from: image)
        } else {
            websiteBrandImage = nil
            websiteBrandAccent = nil
        }
    }

    private func fetchMetadata(provider: LPMetadataProvider, url: URL) async -> LPLinkMetadata? {
        await withCheckedContinuation { continuation in
            provider.startFetchingMetadata(for: url) { metadata, _ in
                continuation.resume(returning: metadata)
            }
        }
    }

    private func loadImage(from provider: NSItemProvider) async -> NSImage? {
        await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: NSImage.self) { object, _ in
                continuation.resume(returning: object as? NSImage)
            }
        }
    }

    private func averageAccentColor(from image: NSImage) -> Color? {
        guard let tiff = image.tiffRepresentation,
              let ciImage = CIImage(data: tiff) else { return nil }

        guard let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: ciImage.extent), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return nil }

        let context = CIContext(options: nil)
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        return Color(
            red: Double(bitmap[0]) / 255.0,
            green: Double(bitmap[1]) / 255.0,
            blue: Double(bitmap[2]) / 255.0
        )
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
