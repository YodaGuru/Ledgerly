// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 YodaGuru

import SwiftUI
import UserNotifications
import AppKit
import Security
import LinkPresentation
import CoreImage

struct ContentView: View {
    @EnvironmentObject private var store: BillStore
    @State private var selection: SidebarItem = .overview
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showingAddBill = false
    @AppStorage("passwordProtectionEnabled") private var passwordProtectionEnabled = false
    @State private var isLocked = false

    var body: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                Sidebar(selection: $selection)
                    .navigationSplitViewColumnWidth(min: 250, ideal: 250, max: 250)
            } detail: {
                Group {
                    switch selection {
                    case .overview, .dueSoon, .dueMonth, .paidRecently, .archive:
                        OverviewView(showingAddBill: $showingAddBill, filter: selection)
                    case .forecast:
                        ForecastView()
                    case .history:
                        PaymentHistoryView()
                    case .income:
                        IncomeView()
                    case .settings:
                        SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.ledgerlyWorkspace)
            }
            .navigationSplitViewStyle(.balanced)
            .allowsHitTesting(!isLocked)

            if isLocked {
                AppLockView {
                    isLocked = false
                }
                .transition(.opacity)
            }
        }
        .background {
            ZStack {
                Color.ledgerlyWorkspace
                LinearGradient(
                    colors: [
                        Color(hex: "#4E8FD3").opacity(0.10),
                        Color(hex: "#7B6AD8").opacity(0.06),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .ignoresSafeArea()
        }
        .tint(Color(hex: "#4E8FD3"))
        .sheet(isPresented: $showingAddBill) {
            BillEditorView()
                .environmentObject(store)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAddBill)) { _ in
            if !isLocked {
                showingAddBill = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lockLedgerly)) { _ in
            lockIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            lockIfNeeded()
        }
        .onAppear {
            columnVisibility = .all
            store.autoLogDuePayments()
            store.updateDockBadge()
            lockIfNeeded()
        }
    }

    private func lockIfNeeded() {
        if passwordProtectionEnabled && PasswordKeychain.hasPassword {
            showingAddBill = false
            isLocked = true
        }
    }
}
