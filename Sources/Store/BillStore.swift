// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 YodaGuru

import SwiftUI
import UserNotifications
import AppKit
import Security
import LinkPresentation
import CoreImage

@MainActor
final class BillStore: ObservableObject {
    private static let customStoragePathKey = "customStoragePath"

    @Published var bills: [Bill] = [] {
        didSet {
            scheduleSave()
            updateDockBadge()
        }
    }
    @Published var incomes: [IncomeSource] = [] {
        didSet { scheduleIncomeSave() }
    }
    @Published private(set) var storageFolder: URL

    private var storageURL: URL
    private var incomeStorageURL: URL
    private var attachmentsURL: URL
    private var hasLoaded = false
    private var pendingSave: DispatchWorkItem?
    private var pendingIncomeSave: DispatchWorkItem?
    private let persistenceQueue = DispatchQueue(label: "com.local.ledgerly.persistence", qos: .utility)

    init() {
        let folder: URL
        if let customPath = UserDefaults.standard.string(forKey: Self.customStoragePathKey) {
            folder = URL(fileURLWithPath: customPath, isDirectory: true)
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            folder = support.appendingPathComponent("Ledgerly", isDirectory: true)
        }
        storageFolder = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        storageURL = folder.appendingPathComponent("bills.json")
        incomeStorageURL = folder.appendingPathComponent("income.json")
        attachmentsURL = folder.appendingPathComponent("Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: attachmentsURL, withIntermediateDirectories: true)
        load()
        loadIncome()
        refreshReminders()
        updateDockBadge()
    }

    func moveStorage(to selectedFolder: URL) throws {
        let destination = selectedFolder.lastPathComponent == "Ledgerly"
            ? selectedFolder
            : selectedFolder.appendingPathComponent("Ledgerly", isDirectory: true)
        let source = storageFolder.standardizedFileURL
        let target = destination.standardizedFileURL

        guard source != target else { return }
        guard !target.path.hasPrefix(source.path + "/") else {
            throw StorageMoveError.invalidDestination
        }

        pendingSave?.cancel()
        pendingIncomeSave?.cancel()
        try saveCurrentData()

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: target.path) {
            let contents = try fileManager.contentsOfDirectory(
                at: target,
                includingPropertiesForKeys: nil
            )
            guard contents.isEmpty else {
                throw StorageMoveError.destinationNotEmpty
            }
            try fileManager.removeItem(at: target)
        }

        try fileManager.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: source, to: target)

        guard fileManager.fileExists(atPath: target.appendingPathComponent("bills.json").path) ||
              !fileManager.fileExists(atPath: source.appendingPathComponent("bills.json").path) else {
            try? fileManager.removeItem(at: target)
            throw StorageMoveError.verificationFailed
        }

        storageFolder = target
        storageURL = target.appendingPathComponent("bills.json")
        incomeStorageURL = target.appendingPathComponent("income.json")
        attachmentsURL = target.appendingPathComponent("Attachments", isDirectory: true)
        try fileManager.createDirectory(at: attachmentsURL, withIntermediateDirectories: true)
        UserDefaults.standard.set(target.path, forKey: Self.customStoragePathKey)

        try? fileManager.removeItem(at: source)
    }

    private func saveCurrentData() throws {
        let encoder = JSONEncoder()
        try encoder.encode(bills).write(to: storageURL, options: .atomic)
        try encoder.encode(incomes).write(to: incomeStorageURL, options: .atomic)
    }

    func load() {
        defer { hasLoaded = true }
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([Bill].self, from: data) else {
            bills = []
            return
        }
        bills = decoded
    }

    private func scheduleSave() {
        guard hasLoaded else { return }
        pendingSave?.cancel()

        let snapshot = bills
        let destination = storageURL
        let work = DispatchWorkItem {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: destination, options: .atomic)
        }
        pendingSave = work
        persistenceQueue.asyncAfter(deadline: .now() + 0.22, execute: work)
    }

    private func loadIncome() {
        guard let data = try? Data(contentsOf: incomeStorageURL),
              let decoded = try? JSONDecoder().decode([IncomeSource].self, from: data) else {
            incomes = []
            return
        }
        incomes = decoded
    }

    private func scheduleIncomeSave() {
        guard hasLoaded else { return }
        pendingIncomeSave?.cancel()
        let snapshot = incomes
        let destination = incomeStorageURL
        let work = DispatchWorkItem {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: destination, options: .atomic)
        }
        pendingIncomeSave = work
        persistenceQueue.asyncAfter(deadline: .now() + 0.22, execute: work)
    }

    func addIncome(_ income: IncomeSource) {
        incomes.append(income)
    }

    func deleteIncome(_ income: IncomeSource) {
        incomes.removeAll { $0.id == income.id }
    }

    func add(_ bill: Bill) {
        bills.append(bill)
        scheduleReminder(for: bill)
        autoLogDuePayments()
    }

    func update(_ bill: Bill) {
        guard let index = bills.firstIndex(where: { $0.id == bill.id }) else { return }
        bills[index] = bill
        scheduleReminder(for: bill)
        autoLogDuePayments()
    }

    func delete(_ bill: Bill) {
        for attachment in bill.attachments {
            try? FileManager.default.removeItem(at: attachmentURL(attachment))
        }
        bills.removeAll { $0.id == bill.id }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [bill.id.uuidString])
    }

    func markPaid(
        _ bill: Bill,
        amount: Double? = nil,
        confirmation: String = "",
        attachments: [BillAttachment] = []
    ) {
        guard let index = bills.firstIndex(where: { $0.id == bill.id }) else { return }
        bills[index].payments.append(
            Payment(
                date: Date(),
                amount: amount ?? bill.amount,
                confirmation: confirmation,
                attachments: attachments
            )
        )
        advanceDueDate(at: index)
        if UserDefaults.standard.bool(forKey: "autoArchiveOneTimeBills"),
           bills[index].frequency == .once {
            bills[index].isArchived = true
        }
    }

    func autoLogDuePayments() {
        guard UserDefaults.standard.bool(forKey: "autoLogPayments") else { return }

        let today = Calendar.current.startOfDay(for: Date())
        for billID in bills.filter({ $0.isAutoPay && !$0.isArchived }).map(\.id) {
            var cyclesLogged = 0

            while let index = bills.firstIndex(where: { $0.id == billID }),
                  bills[index].dueDate <= today,
                  cyclesLogged < 120 {
                if bills[index].frequency == .once && !bills[index].payments.isEmpty {
                    break
                }

                let paymentDate = bills[index].dueDate
                bills[index].payments.append(
                    Payment(
                        date: paymentDate,
                        amount: bills[index].amount,
                        confirmation: "Automatically logged"
                    )
                )
                cyclesLogged += 1

                if bills[index].frequency == .once {
                    if UserDefaults.standard.bool(forKey: "autoArchiveOneTimeBills") {
                        bills[index].isArchived = true
                    }
                    break
                }

                advanceDueDate(at: index)
            }
        }
    }

    func skip(_ bill: Bill) {
        guard let index = bills.firstIndex(where: { $0.id == bill.id }) else { return }
        advanceDueDate(at: index)
    }

    func archive(_ bill: Bill) {
        guard let index = bills.firstIndex(where: { $0.id == bill.id }) else { return }
        bills[index].isArchived = true
    }

    func unarchive(_ bill: Bill) {
        guard let index = bills.firstIndex(where: { $0.id == bill.id }) else { return }
        bills[index].isArchived = false
    }

    func updateNotes(for bill: Bill, notes: String) {
        guard let index = bills.firstIndex(where: { $0.id == bill.id }) else { return }
        bills[index].notes = notes
    }

    func addAttachment(from sourceURL: URL, to bill: Bill) throws {
        guard let index = bills.firstIndex(where: { $0.id == bill.id }) else { return }
        let storedName = "\(UUID().uuidString)-\(sourceURL.lastPathComponent)"
        let destination = attachmentsURL.appendingPathComponent(storedName)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        bills[index].attachments.append(
            BillAttachment(fileName: sourceURL.lastPathComponent, storedName: storedName)
        )
    }

    func copyPaymentAttachment(from sourceURL: URL) throws -> BillAttachment {
        let storedName = "\(UUID().uuidString)-\(sourceURL.lastPathComponent)"
        let destination = attachmentsURL.appendingPathComponent(storedName)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return BillAttachment(fileName: sourceURL.lastPathComponent, storedName: storedName)
    }

    func attachmentURL(_ attachment: BillAttachment) -> URL {
        attachmentsURL.appendingPathComponent(attachment.storedName)
    }

    func removeAttachment(_ attachment: BillAttachment, from bill: Bill) {
        guard let index = bills.firstIndex(where: { $0.id == bill.id }) else { return }
        try? FileManager.default.removeItem(at: attachmentURL(attachment))
        bills[index].attachments.removeAll { $0.id == attachment.id }
    }

    private func advanceDueDate(at index: Int) {
        let frequency = bills[index].frequency
        guard let component = frequency.calendarComponent,
              let next = Calendar.current.date(
                byAdding: component,
                value: frequency.calendarValue,
                to: bills[index].dueDate
              ) else { return }
        bills[index].dueDate = next
        scheduleReminder(for: bills[index])
    }

    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                print("Ledgerly notification authorization failed: \(error.localizedDescription)")
                return
            }

            if granted {
                Task { @MainActor in
                    self.refreshReminders()
                    self.updateDockBadge()
                }
            }
        }
    }

    func refreshReminders() {
        let center = UNUserNotificationCenter.current()

        guard notificationsAreEnabled else {
            center.removeAllPendingNotificationRequests()
            return
        }

        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }

            Task { @MainActor in
                for bill in self.bills where !bill.isArchived {
                    self.scheduleReminder(for: bill)
                }
            }
        }
    }

    private var notificationsAreEnabled: Bool {
        UserDefaults.standard.object(forKey: "notificationsEnabled") == nil ||
        UserDefaults.standard.bool(forKey: "notificationsEnabled")
    }

    func updateDockBadge() {
        let isEnabled = UserDefaults.standard.bool(forKey: "showDueSoonBadge")
        let days = UserDefaults.standard.object(forKey: "dueSoonDays") == nil
            ? 7
            : UserDefaults.standard.integer(forKey: "dueSoonDays")
        let limit = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        let count = bills.filter {
            !$0.isArchived && $0.status != .paid && $0.dueDate <= limit
        }.count

        DispatchQueue.main.async {
            NSApp.dockTile.badgeLabel = isEnabled && count > 0 ? "\(count)" : nil
        }
    }

    private func scheduleReminder(for bill: Bill) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [bill.id.uuidString])

        guard notificationsAreEnabled else { return }
        guard !bill.isArchived else { return }
        guard bill.isReminderEnabled else { return }

        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }

            Task { @MainActor in
                guard let reminderDate = self.reminderDate(for: bill), reminderDate > Date() else { return }

                let content = UNMutableNotificationContent()
                content.title = "\(bill.name) is due soon"
                content.body = "\(bill.name) is due \(bill.dueDate.formatted(date: .abbreviated, time: .omitted)) for \(bill.amountDisplayText)."
                content.sound = .default

                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
                let request = UNNotificationRequest(
                    identifier: bill.id.uuidString,
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                )

                center.add(request) { error in
                    if let error {
                        print("Ledgerly failed to schedule notification for \(bill.name): \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func reminderDate(for bill: Bill) -> Date? {
        guard let reminderDay = Calendar.current.date(
            byAdding: .day,
            value: -bill.reminderDays,
            to: bill.dueDate
        ) else { return nil }

        let reminderHour = UserDefaults.standard.object(forKey: "reminderHour") == nil
            ? 9
            : UserDefaults.standard.integer(forKey: "reminderHour")

        return Calendar.current.date(
            bySettingHour: reminderHour,
            minute: 0,
            second: 0,
            of: reminderDay
        )
    }

    static func sampleBills() -> [Bill] {
        let calendar = Calendar.current
        let today = Date()
        func day(_ value: Int) -> Date {
            calendar.date(byAdding: .day, value: value, to: today)!
        }
        return [
            Bill(name: "Apartment Rent", amount: 1850, dueDate: day(2), frequency: .monthly, category: "Home", colorHex: "#F2854A", website: "", notes: "Paid from checking", reminderDays: 3, isAutoPay: false, payments: []),
            Bill(name: "Electric", amount: 94.20, dueDate: day(6), frequency: .monthly, category: "Utilities", colorHex: "#E8B448", website: "", notes: "", reminderDays: 2, isAutoPay: true, payments: []),
            Bill(name: "Mobile Phone", amount: 68, isVariableAmount: true, dueDate: day(10), frequency: .monthly, category: "Utilities", colorHex: "#4E8FD3", website: "", notes: "", reminderDays: 2, isAutoPay: true, payments: []),
            Bill(name: "Car Insurance", amount: 522, dueDate: day(18), frequency: .quarterly, category: "Transport", colorHex: "#7B6AD8", website: "", notes: "Policy renewal", reminderDays: 7, isAutoPay: false, payments: []),
            Bill(name: "Streaming Bundle", amount: 24.99, dueDate: day(-2), frequency: .monthly, category: "Subscriptions", colorHex: "#D85F74", website: "", notes: "", reminderDays: 1, isAutoPay: false, payments: [])
        ]
    }
}
