// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 YodaGuru

import SwiftUI
import UserNotifications
import AppKit
import Security
import LinkPresentation
import CoreImage

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case sync = "Sync"
    case reminders = "Reminders"
    case logging = "Logging"
    case income = "Income"
    case advanced = "Advanced"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .sync: return "arrow.triangle.2.circlepath"
        case .reminders: return "alarm"
        case .logging: return "checkmark.circle"
        case .income: return "banknote"
        case .advanced: return "gearshape.2"
        }
    }
}
struct SettingsView: View {
    @EnvironmentObject private var store: BillStore
    @State private var selectedTab: SettingsTab = .general
    @AppStorage("showAmounts") private var showAmounts = true
    @AppStorage("showPaidBills") private var showPaidBills = true
    @AppStorage("dueSoonDays") private var dueSoonDays = 7
    @AppStorage("showDueSoonBadge") private var showDueSoonBadge = false
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("defaultReminderDays") private var defaultReminderDays = 3
    @AppStorage("reminderHour") private var reminderHour = 9
    @AppStorage("autoLogPayments") private var autoLogPayments = false
    @AppStorage("autoArchiveOneTimeBills") private var autoArchiveOneTimeBills = false
    @AppStorage("incomeEnabled") private var incomeEnabled = true
    @AppStorage("showIncomeSummary") private var showIncomeSummary = true
    @AppStorage("passwordProtectionEnabled") private var passwordProtectionEnabled = false
    @State private var passwordAction: PasswordAction?
    @State private var storageMoveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 16)

            HStack(spacing: 6) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 20, weight: .medium))
                            Text(tab.rawValue)
                                .font(.caption)
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .foregroundStyle(selectedTab == tab ? Color.white : Color.ledgerlySecondaryText)
                        .contentShape(Rectangle())
                        .background(
                            selectedTab == tab ? Color(hex: "#4E8FD3") : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .ledgerlyGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 22)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case .general:
                        generalSettings
                    case .sync:
                        syncSettings
                    case .reminders:
                        reminderSettings
                    case .logging:
                        loggingSettings
                    case .income:
                        incomeSettings
                    case .advanced:
                        advancedSettings
                    }
                }
                .padding(28)
                .frame(maxWidth: 760, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.ledgerlyWorkspace)
        .alert("Couldn’t Move Data", isPresented: Binding(
            get: { storageMoveError != nil },
            set: { if !$0 { storageMoveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(storageMoveError ?? "")
        }
        .sheet(item: $passwordAction) { action in
            PasswordProtectionSheet(action: action) { isEnabled in
                passwordProtectionEnabled = isEnabled
            }
        }
    }

    private var generalSettings: some View {
        Group {
            SettingsGroup(title: "Overview") {
                Toggle("Show bill amounts in the list and sidebar", isOn: $showAmounts)
                Toggle("Include paid bills in Overview", isOn: $showPaidBills)
            }

            SettingsGroup(title: "Bills Due Soon") {
                HStack {
                    Text("Include bills due within")
                    Spacer()
                    Stepper(
                        "\(dueSoonDays) day\(dueSoonDays == 1 ? "" : "s")",
                        value: $dueSoonDays,
                        in: 1...30
                    )
                    .frame(width: 150)
                    .onChange(of: dueSoonDays) { _ in
                        store.updateDockBadge()
                    }
                }
                Text("This controls the Due Soon section in the sidebar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsGroup(title: "Badges") {
                Toggle("Show the Due Soon count on the Dock icon", isOn: $showDueSoonBadge)
                    .onChange(of: showDueSoonBadge) { _ in
                        store.updateDockBadge()
                    }
                Text("The badge uses the same \(dueSoonDays)-day window configured above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var syncSettings: some View {
        SettingsGroup(title: "Sync") {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "icloud.slash")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.ledgerlySecondaryText)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sync is coming later")
                        .font(.headline)
                    Text("Ledgerly currently stores bills, income, and attachments only on this Mac. A future Sync option will keep your Ledgerly data available across your devices.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var reminderSettings: some View {
        Group {
            SettingsGroup(title: "Notification Reminders") {
                Toggle("Enable bill notifications", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { enabled in
                        if enabled {
                            store.requestNotifications()
                        }
                        store.refreshReminders()
                    }

                if notificationsEnabled {
                    Button("Allow Notifications in macOS") {
                        store.requestNotifications()
                    }
                }

                Text("Reminders stay on this Mac and do not send bill data to a server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsGroup(title: "Defaults for New Bills") {
                HStack {
                    Text("Remind me before the due date")
                    Spacer()
                    Stepper(
                        "\(defaultReminderDays) day\(defaultReminderDays == 1 ? "" : "s")",
                        value: $defaultReminderDays,
                        in: 0...30
                    )
                    .frame(width: 150)
                }

                Picker("Notification time", selection: $reminderHour) {
                    ForEach(6...22, id: \.self) { hour in
                        Text(reminderTimeLabel(hour)).tag(hour)
                    }
                }
                .onChange(of: reminderHour) { _ in
                    store.refreshReminders()
                }
            }
        }
    }

    private var loggingSettings: some View {
        SettingsGroup(title: "Logging Payments") {
            Toggle("Auto-log payments when possible", isOn: $autoLogPayments)
                .onChange(of: autoLogPayments) { enabled in
                    if enabled {
                        store.autoLogDuePayments()
                    }
                }
            Text("Bills marked Automatic payment are logged when their due date arrives.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Archive one-time bills after payment", isOn: $autoArchiveOneTimeBills)
            Text("Recurring bills continue to their next due date after a payment is recorded.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var incomeSettings: some View {
        SettingsGroup(title: "Income Tools") {
            Toggle("Enable income management", isOn: $incomeEnabled)
            Toggle("Show the monthly money picture in Overview", isOn: $showIncomeSummary)
                .disabled(!incomeEnabled)
            Text("Turning income tools off hides them without deleting any saved income sources.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var advancedSettings: some View {
        Group {
            SettingsGroup(title: "Data Storage") {
                LabeledContent("Current location") {
                    Text(store.storageFolder.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(store.storageFolder.path)
                }
                HStack {
                    Button("Open Data Folder") {
                        NSWorkspace.shared.open(store.storageFolder)
                    }
                    Button("Move Data…") {
                        chooseNewStorageLocation()
                    }
                    Spacer()
                    Text("Bills and attachments remain on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsGroup(title: "Password Protection") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(passwordProtectionEnabled ? "Enabled" : "Disabled")
                            .fontWeight(.semibold)
                            .foregroundStyle(passwordProtectionEnabled ? Color(hex: "#58A66B") : Color.secondary)
                        Text("Your password is stored securely in the macOS Keychain.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if passwordProtectionEnabled {
                        Button("Lock Now") {
                            NotificationCenter.default.post(name: .lockLedgerly, object: nil)
                        }
                        Button("Change Password") {
                            passwordAction = .change
                        }
                        Button("Disable") {
                            passwordAction = .disable
                        }
                    } else {
                        Button("Enable Password Protection") {
                            passwordAction = .enable
                        }
                        .ledgerlyGlassButton(prominent: true)
                    }
                }
            }

            SettingsGroup(title: "About") {
                LabeledContent("Ledgerly", value: "Version 2.1.1")
                Text("A focused, private bill organizer for macOS.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func chooseNewStorageLocation() {
        let panel = NSOpenPanel()
        panel.title = "Choose a New Ledgerly Data Location"
        panel.prompt = "Move Here"
        panel.message = "Ledgerly will create a Ledgerly folder in the selected location."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let selectedFolder = panel.url else { return }

        do {
            try store.moveStorage(to: selectedFolder)
        } catch {
            storageMoveError = error.localizedDescription
        }
    }

    private func reminderTimeLabel(_ hour: Int) -> String {
        Calendar.current.date(from: DateComponents(hour: hour))?
            .formatted(date: .omitted, time: .shortened) ?? "\(hour):00"
    }
}
enum PasswordAction: String, Identifiable {
    case enable
    case change
    case disable

    var id: String { rawValue }
}
