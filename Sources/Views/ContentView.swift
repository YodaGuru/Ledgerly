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
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage("passwordProtectionEnabled") private var passwordProtectionEnabled = false
    @State private var isLocked = false

    var body: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                Sidebar(selection: $selection)
                    .navigationSplitViewColumnWidth(min: 250, ideal: 250, max: 250)
            } detail: {
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.ledgerlyWorkspace)
                    .ignoresSafeArea(.container, edges: .top)
            }
            .navigationSplitViewStyle(.balanced)
            .modifier(RemoveSidebarToggleModifier())
            .background(SidebarToggleRemovalView().frame(width: 0, height: 0))
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
        .onChange(of: columnVisibility) { newValue in
            if newValue != .all {
                columnVisibility = .all
            }
        }
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

private struct RemoveSidebarToggleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.toolbar(removing: .sidebarToggle)
        } else {
            content
        }
    }
}

private struct SidebarToggleRemovalView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        removeSidebarToggleSoon(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        removeSidebarToggleSoon(from: nsView)
    }

    private func removeSidebarToggleSoon(from view: NSView) {
        let delays: [TimeInterval] = [0, 0.15, 0.35, 0.75, 1.25]

        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                Self.removeSidebarToggle(from: view.window)
            }
        }
    }

    private static func removeSidebarToggle(from window: NSWindow?) {
        guard let window else { return }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true

        guard let toolbar = window.toolbar else { return }

        toolbar.allowsUserCustomization = false

        for index in toolbar.items.indices.reversed() {
            let rawIdentifier = toolbar.items[index].itemIdentifier.rawValue.lowercased()
            if rawIdentifier.contains("sidebar") || rawIdentifier.contains("toggle") {
                toolbar.removeItem(at: index)
            }
        }

        if toolbar.items.isEmpty {
            window.toolbar = nil
        }
    }
}
