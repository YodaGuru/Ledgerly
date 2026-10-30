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
    @State private var showingAddBill = false
    @AppStorage("passwordProtectionEnabled") private var passwordProtectionEnabled = false
    @State private var isLocked = false
    @AppStorage("showSidebarPanel") private var showSidebar = true

    var body: some View {
        ZStack {
            shell
                .allowsHitTesting(!isLocked)

            if isLocked {
                AppLockView {
                    isLocked = false
                }
                .transition(.opacity)
            }
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
            store.autoLogDuePayments()
            store.updateDockBadge()
            lockIfNeeded()
        }
    }

    @ViewBuilder
    private var shell: some View {
        if #available(macOS 26.0, *) {
            floatingShell
        } else {
            // Standard split view fallback for macOS 13-15.
            NavigationSplitView {
                Sidebar(selection: $selection)
                    .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 320)
            } detail: {
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle(selection.rawValue)
            }
        }
    }

    /// macOS 26+: the sidebar is a floating Liquid Glass panel inset from the
    /// window edges (like the Apple Maps panel), with content beside it.
    @available(macOS 26.0, *)
    private var floatingShell: some View {
        HStack(spacing: 0) {
            if showSidebar {
                FloatingSidebarPanel(selection: $selection)
                    .padding(.leading, 10)
                    .padding(.trailing, 4)
                    .padding(.vertical, 10)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(selection.rawValue)
        }
        .background {
            // A neutral, slightly uneven backdrop so the glass has something to pick up
            // without tinting it a color.
            ZStack {
                Color.ledgerlyWorkspace
                LinearGradient(
                    colors: [
                        Color.primary.opacity(0.10),
                        Color.primary.opacity(0.03),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .ignoresSafeArea()
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.smooth) { showSidebar.toggle() }
                } label: {
                    Label("Toggle Sidebar", systemImage: "sidebar.leading")
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .help(showSidebar ? "Hide Sidebar (\u{2303}\u{2318}S)" : "Show Sidebar (\u{2303}\u{2318}S)")
            }
        }
        // Experiment: drop the full-width toolbar background/divider that cuts across
        // above the floating panel. Remove this line to restore the system toolbar.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }

    private func lockIfNeeded() {
        if passwordProtectionEnabled && PasswordKeychain.hasPassword {
            showingAddBill = false
            isLocked = true
        }
    }

    @ViewBuilder
    private var detailContent: some View {
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
}
