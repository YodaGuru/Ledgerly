// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 YodaGuru

import SwiftUI
import UserNotifications
import AppKit
import Security
import LinkPresentation
import CoreImage

struct Sidebar: View {
    @EnvironmentObject private var store: BillStore
    @Binding var selection: SidebarItem
    @AppStorage("showAmounts") private var showAmounts = true
    @AppStorage("showPaidBills") private var showPaidBills = true
    @AppStorage("dueSoonDays") private var dueSoonDays = 7
    @AppStorage("incomeEnabled") private var incomeEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.title2)
                    .foregroundStyle(Color(hex: "#4E8FD3"))

                Text("Ledgerly")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ledgerlyPrimaryText)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SidebarSection(title: "BILLS") {
                        ForEach([SidebarItem.overview, .dueSoon, .dueMonth, .paidRecently]) { item in
                            sidebarButton(item)
                        }
                    }

                    SidebarSection(title: "REPORTS") {
                        if incomeEnabled {
                            sidebarButton(.income)
                        }

                        ForEach([SidebarItem.forecast, .history]) { item in
                            sidebarButton(item)
                        }
                    }

                    SidebarSection(title: "ARCHIVED") {
                        sidebarButton(.archive)
                    }

                    SidebarSection(title: "APP") {
                        sidebarButton(.settings)
                    }
                }
                .padding(.horizontal, 10)
            }

            VStack(spacing: 5) {
                Text("Version 2.1.1")
                    .font(.caption)
                    .foregroundStyle(Color.ledgerlySecondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity)
            .padding(18)
        }
    }

    private func sidebarButton(_ item: SidebarItem) -> some View {
        Button {
            selection = item
        } label: {
            SidebarRow(
                item: item,
                subtitle: subtitle(for: item),
                isSelected: selection == item
            )
        }
        .buttonStyle(.plain)
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

        let total = bills.reduce(0) { $0 + $1.amount }

        return showAmounts
            ? "\(bills.count) · \(total.currency)"
            : "\(bills.count)"
    }
}
struct LedgerlySidebarGlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .background(.clear)
                .glassEffect(.regular.interactive(), in: Rectangle())
        } else {
            content
                .ledgerlyGlass(in: Rectangle())
        }
    }
}
struct SidebarSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.bold())
                .tracking(1.1)
                .foregroundStyle(Color.ledgerlySecondaryText)
                .padding(.horizontal, 10)
            content
        }
    }
}
struct SidebarRow: View {
    let item: SidebarItem
    let subtitle: String?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 22)
                .foregroundStyle(isSelected ? Color.white : Color.ledgerlySecondaryText)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.rawValue)
                    .fontWeight(.medium)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.76) : Color.ledgerlySecondaryText)
                }
            }
            Spacer()
        }
        .foregroundStyle(isSelected ? Color.white : Color.ledgerlyPrimaryText)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(LedgerlySidebarSelectionBackground(isSelected: isSelected))
        .contentShape(Rectangle())
    }
}
struct LedgerlySidebarSelectionBackground: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .background(
                    isSelected ? Color.white.opacity(0.10) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .glassEffect(isSelected ? .regular.interactive() : .identity, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            content
                .background(
                    isSelected ? Color(hex: "#4E8FD3") : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10)
                )
        }
    }
}

// Overview
