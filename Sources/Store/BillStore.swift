// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 YodaGuru

import SwiftUI
import UserNotifications
import AppKit
import Security
import LinkPresentation
import CoreImage
import Darwin

struct WebsiteBrandAsset {
    let image: NSImage
    let accent: Color?
}

enum SyncActivity: Equatable {
    case idle
    case watching
    case checking
    case updated(Date)
    case unavailable
}

@MainActor
final class BillStore: ObservableObject {
    private static let customStoragePathKey = "customStoragePath"
    private static let ledgerlyFolderName = "Ledgerly"

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
    @Published private(set) var syncActivity: SyncActivity = .idle

    private var storageURL: URL
    private var incomeStorageURL: URL
    private var attachmentsURL: URL
    private var logosURL: URL
    private var hasLoaded = false
    private var isReloadingFromDisk = false
    private var lastKnownBillsModificationDate: Date?
    private var lastKnownIncomeModificationDate: Date?
    private var pendingSave: DispatchWorkItem?
    private var pendingIncomeSave: DispatchWorkItem?
    private var pendingDiskReload: DispatchWorkItem?
    private var storageFolderWatcher: DispatchSourceFileSystemObject?
    private var websiteBrandCache: [String: WebsiteBrandAsset] = [:]
    private let persistenceQueue = DispatchQueue(label: "com.local.ledgerly.persistence", qos: .utility)

    init() {
        let folder: URL
        if let customPath = UserDefaults.standard.string(forKey: Self.customStoragePathKey) {
            folder = URL(fileURLWithPath: customPath, isDirectory: true)
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            folder = support.appendingPathComponent(Self.ledgerlyFolderName, isDirectory: true)
        }
        storageFolder = folder
        storageURL = Self.billsURL(in: folder)
        incomeStorageURL = Self.incomeURL(in: folder)
        attachmentsURL = Self.attachmentsURL(in: folder)
        logosURL = Self.logosURL(in: folder)
        try? prepareStorageFolder(at: folder)
        isReloadingFromDisk = true
        load()
        loadIncome()
        isReloadingFromDisk = false
        captureStorageModificationDates()
        startStorageFolderWatcher()
        refreshReminders()
        updateDockBadge()
    }

    var isUsingICloudDrive: Bool {
        guard let iCloudFolder = Self.iCloudDriveLedgerlyFolder() else { return false }
        return storageFolder.standardizedFileURL == iCloudFolder.standardizedFileURL
    }

    var iCloudDriveSyncStatus: String {
        if isUsingICloudDrive {
            return "Syncing through iCloud Drive"
        }
        if Self.iCloudDriveLedgerlyFolder() == nil {
            return "iCloud Drive is not available on this Mac"
        }
        return "Stored locally on this Mac"
    }

    var syncStatusIcon: String {
        switch syncActivity {
        case .checking:
            return "arrow.triangle.2.circlepath"
        case .updated:
            return "checkmark.icloud"
        case .unavailable:
            return "exclamationmark.icloud"
        case .watching:
            return isUsingICloudDrive ? "icloud" : "externaldrive"
        case .idle:
            return "arrow.triangle.2.circlepath"
        }
    }

    var syncStatusText: String {
        switch syncActivity {
        case .checking:
            return "Checking for synced changes"
        case .updated(let date):
            return "Updated \(date.formatted(date: .omitted, time: .shortened))"
        case .unavailable:
            return "Sync folder unavailable"
        case .watching:
            return isUsingICloudDrive ? "Watching iCloud Drive" : "Watching data folder"
        case .idle:
            return "Ready to refresh"
        }
    }

    func enableICloudDriveSync() throws {
        guard let iCloudFolder = Self.iCloudDriveLedgerlyFolder() else {
            throw StorageMoveError.iCloudDriveUnavailable
        }

        if iCloudFolder.standardizedFileURL != storageFolder.standardizedFileURL,
           folderContainsLedgerlyData(iCloudFolder) {
            try switchStorage(to: iCloudFolder)
            return
        }

        try moveStorage(to: iCloudFolder)
    }

    func reloadFromDiskIfChanged(manual: Bool = false) {
        syncActivity = .checking
        let billsDate = modificationDate(for: storageURL)
        let incomeDate = modificationDate(for: incomeStorageURL)

        guard billsDate != lastKnownBillsModificationDate ||
              incomeDate != lastKnownIncomeModificationDate else {
            syncActivity = .watching
            return
        }

        pendingSave?.cancel()
        pendingIncomeSave?.cancel()

        isReloadingFromDisk = true
        load()
        loadIncome()
        isReloadingFromDisk = false
        captureStorageModificationDates()
        refreshReminders()
        updateDockBadge()
        syncActivity = .updated(Date())
    }

    func moveStorage(to selectedFolder: URL) throws {
        let destination = selectedFolder.lastPathComponent == Self.ledgerlyFolderName
            ? selectedFolder
            : selectedFolder.appendingPathComponent(Self.ledgerlyFolderName, isDirectory: true)
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

        guard fileManager.fileExists(atPath: Self.billsURL(in: target).path) ||
              !fileManager.fileExists(atPath: Self.billsURL(in: source).path) else {
            try? fileManager.removeItem(at: target)
            throw StorageMoveError.verificationFailed
        }

        storageFolder = target
        storageURL = Self.billsURL(in: target)
        incomeStorageURL = Self.incomeURL(in: target)
        attachmentsURL = Self.attachmentsURL(in: target)
        logosURL = Self.logosURL(in: target)
        try prepareStorageFolder(at: target)
        UserDefaults.standard.set(target.path, forKey: Self.customStoragePathKey)
        captureStorageModificationDates()
        startStorageFolderWatcher()

        try? fileManager.removeItem(at: source)
    }

    private func switchStorage(to folder: URL) throws {
        pendingSave?.cancel()
        pendingIncomeSave?.cancel()

        try prepareStorageFolder(at: folder)
        storageFolder = folder.standardizedFileURL
        storageURL = Self.billsURL(in: storageFolder)
        incomeStorageURL = Self.incomeURL(in: storageFolder)
        attachmentsURL = Self.attachmentsURL(in: storageFolder)
        logosURL = Self.logosURL(in: storageFolder)
        UserDefaults.standard.set(storageFolder.path, forKey: Self.customStoragePathKey)

        isReloadingFromDisk = true
        load()
        loadIncome()
        isReloadingFromDisk = false
        captureStorageModificationDates()
        startStorageFolderWatcher()
        refreshReminders()
        updateDockBadge()
    }

    private func saveCurrentData() throws {
        let encoder = JSONEncoder()
        try encoder.encode(bills).write(to: storageURL, options: .atomic)
        try encoder.encode(incomes).write(to: incomeStorageURL, options: .atomic)
        captureStorageModificationDates()
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
        guard !isReloadingFromDisk else { return }
        pendingSave?.cancel()

        let snapshot = bills
        let destination = storageURL
        let work = DispatchWorkItem {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: destination, options: .atomic)
            Task { @MainActor in
                self.lastKnownBillsModificationDate = self.modificationDate(for: destination)
            }
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
        guard !isReloadingFromDisk else { return }
        pendingIncomeSave?.cancel()
        let snapshot = incomes
        let destination = incomeStorageURL
        let work = DispatchWorkItem {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: destination, options: .atomic)
            Task { @MainActor in
                self.lastKnownIncomeModificationDate = self.modificationDate(for: destination)
            }
        }
        pendingIncomeSave = work
        persistenceQueue.asyncAfter(deadline: .now() + 0.22, execute: work)
    }

    private func startStorageFolderWatcher() {
        stopStorageFolderWatcher()

        let descriptor = open(storageFolder.path, O_EVTONLY)
        guard descriptor >= 0 else {
            syncActivity = .unavailable
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .attrib, .extend],
            queue: persistenceQueue
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.scheduleDiskReload()
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        storageFolderWatcher = source
        syncActivity = .watching
        source.resume()
    }

    private func stopStorageFolderWatcher() {
        pendingDiskReload?.cancel()
        pendingDiskReload = nil
        storageFolderWatcher?.cancel()
        storageFolderWatcher = nil
    }

    private func scheduleDiskReload() {
        pendingDiskReload?.cancel()

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.reloadFromDiskIfChanged()
            }
        }
        pendingDiskReload = work
        persistenceQueue.asyncAfter(deadline: .now() + 0.75, execute: work)
    }

    private func prepareStorageFolder(at folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: Self.attachmentsURL(in: folder),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: Self.logosURL(in: folder),
            withIntermediateDirectories: true
        )
    }

    private func captureStorageModificationDates() {
        lastKnownBillsModificationDate = modificationDate(for: storageURL)
        lastKnownIncomeModificationDate = modificationDate(for: incomeStorageURL)
    }

    private func modificationDate(for url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private func folderContainsLedgerlyData(_ folder: URL) -> Bool {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: Self.billsURL(in: folder).path) ||
            fileManager.fileExists(atPath: Self.incomeURL(in: folder).path) {
            return true
        }

        let attachmentContents = try? fileManager.contentsOfDirectory(
            at: Self.attachmentsURL(in: folder),
            includingPropertiesForKeys: nil
        )
        let logoContents = try? fileManager.contentsOfDirectory(
            at: Self.logosURL(in: folder),
            includingPropertiesForKeys: nil
        )
        return !(attachmentContents ?? []).isEmpty || !(logoContents ?? []).isEmpty
    }

    private static func billsURL(in folder: URL) -> URL {
        folder.appendingPathComponent("bills.json")
    }

    private static func incomeURL(in folder: URL) -> URL {
        folder.appendingPathComponent("income.json")
    }

    private static func attachmentsURL(in folder: URL) -> URL {
        folder.appendingPathComponent("Attachments", isDirectory: true)
    }

    private static func logosURL(in folder: URL) -> URL {
        folder.appendingPathComponent("Logos", isDirectory: true)
    }

    private static func iCloudDriveLedgerlyFolder() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cloudDocs = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Mobile Documents", isDirectory: true)
            .appendingPathComponent("com~apple~CloudDocs", isDirectory: true)

        guard FileManager.default.fileExists(atPath: cloudDocs.path) else {
            return nil
        }
        return cloudDocs.appendingPathComponent(ledgerlyFolderName, isDirectory: true)
    }

    func addIncome(_ income: IncomeSource) {
        incomes.append(income)
    }

    func deleteIncome(_ income: IncomeSource) {
        incomes.removeAll { $0.id == income.id }
    }

    func websiteBrand(for url: URL) async -> WebsiteBrandAsset? {
        let cacheKey = url.host?.lowercased() ?? url.absoluteString
        if let cached = websiteBrandCache[cacheKey] {
            return cached
        }

        let provider = LPMetadataProvider()
        guard let metadata = await fetchMetadata(provider: provider, url: url) else {
            return nil
        }

        guard let itemProvider = metadata.iconProvider ?? metadata.imageProvider,
              let image = await loadImage(from: itemProvider) else {
            return nil
        }

        let brand = WebsiteBrandAsset(image: image, accent: averageAccentColor(from: image))
        websiteBrandCache[cacheKey] = brand
        return brand
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
            red: Double(bitmap[0]) / 255,
            green: Double(bitmap[1]) / 255,
            blue: Double(bitmap[2]) / 255
        )
    }

    func add(_ bill: Bill) {
        bills.append(bill)
        scheduleReminder(for: bill)
        autoLogDuePayments()
    }

    func update(_ bill: Bill) {
        guard let index = bills.firstIndex(where: { $0.id == bill.id }) else { return }
        let previousLogo = bills[index].customLogo
        bills[index] = bill
        if previousLogo != bill.customLogo {
            removeCustomLogoFile(previousLogo)
        }
        scheduleReminder(for: bill)
        autoLogDuePayments()
    }

    func delete(_ bill: Bill) {
        for attachment in bill.attachments {
            try? FileManager.default.removeItem(at: attachmentURL(attachment))
        }
        removeCustomLogoFile(bill.customLogo)
        bills.removeAll { $0.id == bill.id }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [bill.id.uuidString])
    }

    func markPaid(
        _ bill: Bill,
        amount: Double? = nil,
        confirmation: String = "",
        notes: String = "",
        attachments: [BillAttachment] = [],
        advancesDueDate: Bool = true
    ) {
        guard let index = bills.firstIndex(where: { $0.id == bill.id }) else { return }
        let dueDateBeforePayment = bills[index].dueDate
        let paymentAmount = amount ?? bills[index].cycleRemainingAmount
        bills[index].payments.append(
            Payment(
                date: Date(),
                amount: paymentAmount,
                confirmation: confirmation,
                notes: notes,
                attachments: attachments,
                dueDateBeforePayment: dueDateBeforePayment
            )
        )
        if advancesDueDate || bills[index].cycleRemainingAmount <= 0.005 {
            advanceDueDate(at: index)
        }
        if UserDefaults.standard.bool(forKey: "autoArchiveOneTimeBills"),
           bills[index].frequency == .once {
            bills[index].isArchived = true
        }
    }

    func autoLogDuePayments() {
        let autoLoggingEnabled = UserDefaults.standard.object(forKey: "autoLogPayments") == nil ||
            UserDefaults.standard.bool(forKey: "autoLogPayments")
        guard autoLoggingEnabled else { return }

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
                        amount: bills[index].planningAmount,
                        confirmation: "Auto Pay",
                        dueDateBeforePayment: paymentDate
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

    func updatePayment(
        billID: UUID,
        paymentID: UUID,
        date: Date,
        amount: Double,
        confirmation: String,
        notes: String
    ) {
        guard let billIndex = bills.firstIndex(where: { $0.id == billID }),
              let paymentIndex = bills[billIndex].payments.firstIndex(where: { $0.id == paymentID })
        else { return }

        bills[billIndex].payments[paymentIndex].date = date
        bills[billIndex].payments[paymentIndex].amount = amount
        bills[billIndex].payments[paymentIndex].confirmation = confirmation
        bills[billIndex].payments[paymentIndex].notes = notes
    }

    func deletePayment(billID: UUID, paymentID: UUID) {
        guard let billIndex = bills.firstIndex(where: { $0.id == billID }),
              let paymentIndex = bills[billIndex].payments.firstIndex(where: { $0.id == paymentID })
        else { return }

        let payment = bills[billIndex].payments[paymentIndex]
        for attachment in payment.attachments {
            try? FileManager.default.removeItem(at: attachmentURL(attachment))
        }
        bills[billIndex].payments.remove(at: paymentIndex)
        if let dueDateBeforePayment = payment.dueDateBeforePayment {
            bills[billIndex].dueDate = dueDateBeforePayment
            scheduleReminder(for: bills[billIndex])
            updateDockBadge()
        } else {
            reverseDueDate(at: billIndex)
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

    func copyCustomLogo(from sourceURL: URL) throws -> BillCustomLogo {
        let storedName = "\(UUID().uuidString)-\(sourceURL.lastPathComponent)"
        let destination = logosURL.appendingPathComponent(storedName)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return BillCustomLogo(fileName: sourceURL.lastPathComponent, storedName: storedName)
    }

    func customLogoURL(for bill: Bill) -> URL? {
        guard let customLogo = bill.customLogo else { return nil }
        return logosURL.appendingPathComponent(customLogo.storedName)
    }

    func customLogoImage(for bill: Bill) -> NSImage? {
        guard let url = customLogoURL(for: bill) else { return nil }
        return NSImage(contentsOf: url)
    }

    func removeCustomLogoFile(_ logo: BillCustomLogo?) {
        guard let logo else { return }
        try? FileManager.default.removeItem(at: logosURL.appendingPathComponent(logo.storedName))
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

    private func reverseDueDate(at index: Int) {
        let frequency = bills[index].frequency
        guard let component = frequency.calendarComponent,
              let previous = Calendar.current.date(
                byAdding: component,
                value: -frequency.calendarValue,
                to: bills[index].dueDate
              ) else { return }
        bills[index].dueDate = previous
        scheduleReminder(for: bills[index])
        updateDockBadge()
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
                content.body = "\(bill.name) is due \(bill.dueDate.formatted(date: .abbreviated, time: .omitted)) for \(bill.cycleBalanceDisplayText)."
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
