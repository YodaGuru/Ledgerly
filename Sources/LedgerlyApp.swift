// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 YodaGuru

import SwiftUI
import UserNotifications
import AppKit
import Security
import LinkPresentation
import CoreImage

@main
struct LedgerlyApp: App {
    @StateObject private var store = BillStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1180, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Bill…") {
                    NotificationCenter.default.post(name: .showAddBill, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}
extension Notification.Name {
    static let showAddBill = Notification.Name("showAddBill")
    static let lockLedgerly = Notification.Name("lockLedgerly")
}
