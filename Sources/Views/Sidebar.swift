// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 YodaGuru

import SwiftUI
import UserNotifications
import AppKit
import Security
import LinkPresentation
import CoreImage

/// Standard source-list sidebar. On macOS 26 the system supplies the floating
/// Liquid Glass sidebar, selection highlight, and keyboard navigation, so no
/// custom backgrounds or glass effects are applied here.
struct Sidebar: View {
    @EnvironmentObject private var store: BillStore
    @Binding var selection: SidebarItem
    @AppStorage("showAmounts") private var showAmounts = true
    @AppStorage("showPaidBills") private var showPaidBills = true
    @AppStorage("dueSoonDays") private var dueSoonDays = 7
    @AppStorage("incomeEnabled") private var incomeEnabled = true

    /// `List` single selection needs an optional binding; never clear the selection.
    private var listSelection: Binding<SidebarItem?> {
        Binding(
            get: { selection },
            set: { newValue in
                if let newValue {
                    selection = newValue
                }
            }
        )
    }

    var body: some View {
        List(selection: listSelection) {
            Section(header: SidebarHeader("Bills")) {
                ForEach([SidebarItem.overview, .dueSoon, .dueMonth, .paidRecently]) { item in
                    sidebarRow(item)
                }
            }

            Section(header: SidebarHeader("Reports")) {
                if incomeEnabled {
                    sidebarRow(.income)
                }

                ForEach([SidebarItem.forecast, .history]) { item in
                    sidebarRow(item)
                }
            }

            Section(header: SidebarHeader("Archived")) {
                sidebarRow(.archive)
            }

            Section(header: SidebarHeader("App")) {
                syncButton
                sidebarRow(.settings)
            }
        }
        .listStyle(.sidebar)
    }

    private var syncButton: some View {
        Button {
            store.reloadFromDiskIfChanged(manual: true)
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Sync")
                    Text(store.syncStatusText)
                        .font(.caption)
                        .foregroundStyle(Color.primary.opacity(0.7))
                        .lineLimit(1)
                }
            } icon: {
                Image(systemName: store.syncStatusIcon)
            }
        }
        .buttonStyle(.plain)
        .help("Check the Ledgerly data folder for synced changes.")
    }

    private func sidebarRow(_ item: SidebarItem) -> some View {
        SidebarRow(item: item, subtitle: subtitle(for: item))
            .tag(item)
    }

    private func subtitle(for item: SidebarItem) -> String? {
        let active = store.bills.filter { !$0.isArchived }
        let calendar = Calendar.current
        let bills: [Bill]

        switch item {
        case .overview:
            bills = showPaidBills ? active : active.filter { $0.status != .paid }

        case .dueSoon:
            let limit = calendar.date(byAdding: .day, value: dueSoonDays, to: Date())!
            bills = active.filter {
                $0.dueDate <= limit && $0.status != .paid
            }

        case .dueMonth:
            bills = active.filter {
                calendar.isDate($0.dueDate, equalTo: Date(), toGranularity: .month)
            }

        case .paidRecently:
            bills = active.filter { !$0.payments.isEmpty }

        case .archive:
            return nil

        default:
            return nil
        }

        let total = bills.reduce(0) { $0 + $1.cycleRemainingAmount }

        return showAmounts
            ? "\(bills.count) · \(total.currency)"
            : "\(bills.count)"
    }
}

/// Section header with more contrast than the system default, which gets hard to
/// read on the glass sidebar.
struct SidebarHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.primary.opacity(0.7))
            .textCase(nil)
    }
}

struct SidebarRow: View {
    let item: SidebarItem
    let subtitle: String?

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.rawValue)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.primary.opacity(0.7))
                }
            }
        } icon: {
            Image(systemName: item.icon)
        }
    }
}

/// Floating Liquid Glass sidebar card (macOS 26+). Rounded, inset from the window
/// edges, with the app name on top; the list scrolls inside the glass.
@available(macOS 26.0, *)
struct FloatingSidebarPanel: View {
    @Binding var selection: SidebarItem

    private let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.title2)
                    .foregroundStyle(Color(hex: "#4E8FD3"))
                Text("Ledgerly")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 6)

            Sidebar(selection: $selection)
                .scrollContentBackground(.hidden)
        }
        .frame(width: 262)
        .clipShape(shape)
        .glassEffect(.regular, in: shape)
    }
}
