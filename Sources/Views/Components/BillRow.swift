// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 YodaGuru

import SwiftUI
import UserNotifications
import AppKit
import Security
import LinkPresentation
import CoreImage

struct BillRow: View {
    let bill: Bill
    let onPay: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: bill.colorHex))
                .frame(width: 8, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(bill.name)
                    .fontWeight(.semibold)
                HStack(spacing: 6) {
                    Text(bill.dueDate.formatted(date: .abbreviated, time: .omitted))
                    Text("•")
                    Text(bill.category)
                    if bill.isAutoPay {
                        Text("AUTO")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1), in: Capsule())
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(bill.cycleBalanceDisplayText)
                    .fontWeight(.bold)
                Text(bill.status.rawValue)
                    .font(.caption2.bold())
                    .foregroundStyle(bill.dueDateColor)
            }

            Menu {
                if bill.status != .paid {
                    Button("Log Payment", systemImage: "checkmark.circle", action: onPay)
                }
                Button("Edit", systemImage: "pencil", action: onEdit)
                if let url = bill.websiteURL {
                    Link("Open Biller Website", destination: url)
                }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 26)
        }
        .padding(14)
        .contentShape(Rectangle())
    }
}

// Forecast
