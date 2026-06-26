import SwiftUI
import UserNotifications
import AppKit
import Security
import LinkPresentation
import CoreImage

enum PasswordKeychain {
    private static let service = "com.local.ledgerly.password"
    private static let account = "primary"

    static var hasPassword: Bool {
        password != nil
    }

    static var password: String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ password: String) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }
        SecItemDelete(baseQuery as CFDictionary)

        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func delete() -> Bool {
        let status = SecItemDelete(baseQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

// Model

enum BillFrequency: String, Codable, CaseIterable, Identifiable {
    case weekly = "Weekly"
    case monthly = "Monthly"
    case quarterly = "Quarterly"
    case yearly = "Yearly"
    case once = "One time"

    var id: String { rawValue }

    var calendarComponent: Calendar.Component? {
        switch self {
        case .weekly: return .weekOfYear
        case .monthly: return .month
        case .quarterly: return .month
        case .yearly: return .year
        case .once: return nil
        }
    }

    var calendarValue: Int {
        self == .quarterly ? 3 : 1
    }
}

struct Payment: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var amount: Double
    var confirmation: String
    var attachments: [BillAttachment] = []

    enum CodingKeys: String, CodingKey {
        case id, date, amount, confirmation, attachments
    }

    init(
        id: UUID = UUID(),
        date: Date,
        amount: Double,
        confirmation: String,
        attachments: [BillAttachment] = []
    ) {
        self.id = id
        self.date = date
        self.amount = amount
        self.confirmation = confirmation
        self.attachments = attachments
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try values.decode(Date.self, forKey: .date)
        amount = try values.decode(Double.self, forKey: .amount)
        confirmation = try values.decodeIfPresent(String.self, forKey: .confirmation) ?? ""
        attachments = try values.decodeIfPresent([BillAttachment].self, forKey: .attachments) ?? []
    }
}

struct IncomeSource: Identifiable, Codable, Hashable {
    enum Frequency: String, Codable, CaseIterable, Identifiable {
        case weekly = "Weekly"
        case twiceMonthly = "Twice monthly"
        case monthly = "Monthly"
        case quarterly = "Quarterly"
        case yearly = "Yearly"
        case once = "One time"

        var id: String { rawValue }

        var displayText: String {
            switch self {
            case .weekly: return "Every week"
            case .twiceMonthly: return "Twice monthly"
            case .monthly: return "Every month"
            case .quarterly: return "Every 3 months"
            case .yearly: return "Every year"
            case .once: return "One time"
            }
        }
    }

    var id = UUID()
    var name: String
    var amount: Double
    var nextDate: Date
    var frequency: Frequency
    var firstPayday: Int
    var secondPayday: Int
    var notes: String
    var colorHex: String

    init(
        id: UUID = UUID(),
        name: String,
        amount: Double,
        nextDate: Date,
        frequency: Frequency,
        firstPayday: Int = 15,
        secondPayday: Int = 30,
        notes: String,
        colorHex: String
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.nextDate = nextDate
        self.frequency = frequency
        self.firstPayday = firstPayday
        self.secondPayday = secondPayday
        self.notes = notes
        self.colorHex = colorHex
    }

    enum CodingKeys: String, CodingKey {
        case id, name, amount, nextDate, frequency, firstPayday, secondPayday, notes, colorHex
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decode(String.self, forKey: .name)
        amount = try values.decode(Double.self, forKey: .amount)
        nextDate = try values.decode(Date.self, forKey: .nextDate)
        frequency = try values.decode(Frequency.self, forKey: .frequency)
        firstPayday = try values.decodeIfPresent(Int.self, forKey: .firstPayday) ?? 15
        secondPayday = try values.decodeIfPresent(Int.self, forKey: .secondPayday) ?? 30
        notes = try values.decodeIfPresent(String.self, forKey: .notes) ?? ""
        colorHex = try values.decodeIfPresent(String.self, forKey: .colorHex) ?? "#58A66B"
    }

    func estimatedAmount(in month: Date) -> Double {
        switch frequency {
        case .weekly:
            return amount * 4.33
        case .twiceMonthly:
            return amount * 2
        case .monthly:
            return amount
        case .quarterly:
            return amount / 3
        case .yearly:
            return amount / 12
        case .once:
            return Calendar.current.isDate(nextDate, equalTo: month, toGranularity: .month)
                ? amount
                : 0
        }
    }

    func nextExpectedDate(from date: Date = Date()) -> Date {
        guard frequency == .twiceMonthly else { return nextDate }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        let days = [firstPayday, secondPayday].sorted()

        for monthOffset in 0...1 {
            guard let month = calendar.date(byAdding: .month, value: monthOffset, to: today),
                  let range = calendar.range(of: .day, in: .month, for: month) else { continue }

            for day in days {
                var components = calendar.dateComponents([.year, .month], from: month)
                components.day = min(day, range.count)
                if let candidate = calendar.date(from: components), candidate >= today {
                    return candidate
                }
            }
        }

        return nextDate
    }
}

struct BillAttachment: Identifiable, Codable, Hashable {
    var id = UUID()
    var fileName: String
    var storedName: String
    var addedDate = Date()
}

struct Bill: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var amount: Double
    var isVariableAmount: Bool
    var dueDate: Date
    var frequency: BillFrequency
    var category: String
    var colorHex: String
    var website: String
    var notes: String
    var isReminderEnabled: Bool
    var reminderDays: Int
    var isAutoPay: Bool
    var payments: [Payment]
    var attachments: [BillAttachment]
    var isArchived: Bool

    init(
        id: UUID = UUID(),
        name: String,
        amount: Double,
        isVariableAmount: Bool = false,
        dueDate: Date,
        frequency: BillFrequency,
        category: String,
        colorHex: String,
        website: String,
        notes: String,
        isReminderEnabled: Bool = true,
        reminderDays: Int,
        isAutoPay: Bool,
        payments: [Payment],
        attachments: [BillAttachment] = [],
        isArchived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.isVariableAmount = isVariableAmount
        self.dueDate = dueDate
        self.frequency = frequency
        self.category = category
        self.colorHex = colorHex
        self.website = website
        self.notes = notes
        self.isReminderEnabled = isReminderEnabled
        self.reminderDays = reminderDays
        self.isAutoPay = isAutoPay
        self.payments = payments
        self.attachments = attachments
        self.isArchived = isArchived
    }

    enum CodingKeys: String, CodingKey {
        case id, name, amount, isVariableAmount, dueDate, frequency, category, colorHex, website
        case notes, isReminderEnabled, reminderDays, isAutoPay, payments, attachments, isArchived
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decode(String.self, forKey: .name)
        amount = try values.decode(Double.self, forKey: .amount)
        isVariableAmount = try values.decodeIfPresent(Bool.self, forKey: .isVariableAmount) ?? false
        dueDate = try values.decode(Date.self, forKey: .dueDate)
        frequency = try values.decode(BillFrequency.self, forKey: .frequency)
        category = try values.decode(String.self, forKey: .category)
        colorHex = try values.decode(String.self, forKey: .colorHex)
        website = try values.decodeIfPresent(String.self, forKey: .website) ?? ""
        notes = try values.decodeIfPresent(String.self, forKey: .notes) ?? ""
        isReminderEnabled = try values.decodeIfPresent(Bool.self, forKey: .isReminderEnabled) ?? true
        reminderDays = try values.decodeIfPresent(Int.self, forKey: .reminderDays) ?? 3
        isAutoPay = try values.decodeIfPresent(Bool.self, forKey: .isAutoPay) ?? false
        payments = try values.decodeIfPresent([Payment].self, forKey: .payments) ?? []
        attachments = try values.decodeIfPresent([BillAttachment].self, forKey: .attachments) ?? []
        isArchived = try values.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }

    var isPaidForCurrentCycle: Bool {
        let calendar = Calendar.current
        return payments.contains { payment in
            calendar.isDate(payment.date, equalTo: dueDate, toGranularity: .month)
        }
    }

    var status: BillStatus {
        if isPaidForCurrentCycle { return .paid }
        if dueDate < Calendar.current.startOfDay(for: Date()) { return .overdue }
        return .upcoming
    }

    var lastPaidDate: Date? {
        payments.map(\.date).max()
    }

    var amountDisplayText: String {
        isVariableAmount ? "Variable" : amount.currency
    }

    var websiteURL: URL? {
        let trimmedWebsite = website.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWebsite.isEmpty else { return nil }

        let address = trimmedWebsite.contains("://")
            ? trimmedWebsite
            : "https://\(trimmedWebsite)"
        guard
            let components = URLComponents(string: address),
            let scheme = components.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            components.host != nil
        else {
            return nil
        }
        return components.url
    }

    func amountDue(in month: Date) -> Double {
        let calendar = Calendar.current
        if frequency == .once {
            return calendar.isDate(dueDate, equalTo: month, toGranularity: .month) ? amount : 0
        }

        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        let dueStart = calendar.date(from: calendar.dateComponents([.year, .month], from: dueDate))!
        guard start >= dueStart else { return 0 }
        let months = calendar.dateComponents([.month], from: dueStart, to: start).month ?? 0

        switch frequency {
        case .weekly:
            guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: start) else {
                return 0
            }
            var occurrence = dueDate
            if occurrence < start {
                let days = calendar.dateComponents([.day], from: occurrence, to: start).day ?? 0
                let weeksToAdvance = max(0, (days + 6) / 7)
                occurrence = calendar.date(byAdding: .weekOfYear, value: weeksToAdvance, to: occurrence) ?? occurrence
            }

            var count = 0
            while occurrence < monthEnd {
                if occurrence >= start {
                    count += 1
                }
                guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: occurrence) else {
                    break
                }
                occurrence = next
            }
            return amount * Double(count)
        case .monthly:
            return amount
        case .quarterly:
            return months % 3 == 0 ? amount : 0
        case .yearly:
            return months % 12 == 0 ? amount : 0
        case .once:
            return 0
        }
    }
}

enum BillStatus: String {
    case overdue = "Overdue"
    case upcoming = "Upcoming"
    case paid = "Paid"

    var color: Color {
        switch self {
        case .overdue: return .red
        case .upcoming: return Color(hex: "#E7793F")
        case .paid: return .green
        }
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case dueSoon = "Due Soon"
    case dueMonth = "Due This Month"
    case paidRecently = "Paid Recently"
    case income = "Income"
    case forecast = "Forecast"
    case history = "Payment History"
    case archive = "Archived Bills"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "list.bullet.rectangle"
        case .dueSoon: return "bell"
        case .dueMonth: return "calendar"
        case .paidRecently: return "checkmark"
        case .income: return "banknote.fill"
        case .forecast: return "chart.bar.fill"
        case .history: return "clock.arrow.circlepath"
        case .archive: return "archivebox"
        case .settings: return "gearshape.fill"
        }
    }
}

enum StorageMoveError: LocalizedError {
    case destinationNotEmpty
    case invalidDestination
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .destinationNotEmpty:
            return "The selected location already contains a non-empty Ledgerly folder. Choose another location."
        case .invalidDestination:
            return "Choose a location outside the current Ledgerly data folder."
        case .verificationFailed:
            return "Ledgerly could not verify the copied data, so the current storage location was left unchanged."
        }
    }
}

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

// App

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

struct AppLockView: View {
    let onUnlock: () -> Void
    @State private var password = ""
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.ledgerlyWorkspace

            VStack(spacing: 18) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(Color(hex: "#4E8FD3"))

                Text("Ledgerly is locked")
                    .font(.title2.bold())

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                    .onSubmit(unlock)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button("Unlock", action: unlock)
                    .ledgerlyGlassButton(prominent: true)
                    .disabled(password.isEmpty)
            }
            .padding(34)
            .background(Color.ledgerlyReportCard, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.ledgerlyDivider)
            }
        }
        .ignoresSafeArea()
    }

    private func unlock() {
        if password == PasswordKeychain.password {
            password = ""
            errorMessage = nil
            onUnlock()
        } else {
            errorMessage = "That password is incorrect."
            password = ""
        }
    }
}

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
                Text("Version 2.0.2")
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

struct OverviewView: View {
    @EnvironmentObject private var store: BillStore
    @Binding var showingAddBill: Bool
    let filter: SidebarItem
    @AppStorage("showAmounts") private var showAmounts = true
    @AppStorage("showPaidBills") private var showPaidBills = true
    @AppStorage("dueSoonDays") private var dueSoonDays = 7
    @AppStorage("overviewRightPaneWidth") private var overviewRightPaneWidth = 350.0
    @AppStorage("overviewNameColumnWidth") private var overviewNameColumnWidth = 320.0
    @AppStorage("overviewAmountColumnWidth") private var overviewAmountColumnWidth = 110.0
    @AppStorage("overviewDueDateColumnWidth") private var overviewDueDateColumnWidth = 160.0
    @AppStorage("overviewLastPaidColumnWidth") private var overviewLastPaidColumnWidth = 140.0
    @State private var selectedBillID: UUID?
    @State private var editingBill: Bill?
    @State private var payingBill: Bill?
    @State private var billPendingDeletion: Bill?
    @State private var searchText = ""
    @State private var nameColumnDragStartWidth: CGFloat?
    @State private var amountColumnDragStartWidth: CGFloat?
    @State private var dueDateColumnDragStartWidth: CGFloat?
    @State private var lastPaidColumnDragStartWidth: CGFloat?

    private var visibleBills: [Bill] {
        let calendar = Calendar.current
        let base: [Bill]
        switch filter {
        case .dueSoon:
            let limit = calendar.date(byAdding: .day, value: dueSoonDays, to: Date())!
            base = store.bills.filter { !$0.isArchived && $0.dueDate <= limit && $0.status != .paid }
        case .dueMonth:
            base = store.bills.filter {
                !$0.isArchived && calendar.isDate($0.dueDate, equalTo: Date(), toGranularity: .month)
            }
        case .paidRecently:
            base = store.bills.filter { !$0.isArchived && !$0.payments.isEmpty }
        case .archive:
            base = store.bills.filter(\.isArchived)
        default:
            base = store.bills.filter { !$0.isArchived && (showPaidBills || $0.status != .paid) }
        }
        return base
            .filter {
                searchText.isEmpty ||
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.category.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var selectedBill: Bill? {
        guard let selectedBillID else { return nil }
        return store.bills.first { $0.id == selectedBillID }
    }

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 900
            let minWidth: CGFloat = compact ? 300 : 260
            let maxWidth: CGFloat = compact ? 340 : min(560, max(320, geometry.size.width * 0.42))
            let sideWidth: CGFloat = min(max(CGFloat(overviewRightPaneWidth), minWidth), maxWidth)
            let amountsVisible = showAmounts
            let nameWidth: CGFloat = min(max(CGFloat(overviewNameColumnWidth), 190), 420)
            let amountWidth: CGFloat = min(max(CGFloat(overviewAmountColumnWidth), 90), 180)
            let dueDateWidth: CGFloat = min(max(CGFloat(overviewDueDateColumnWidth), 120), 240)
            let lastPaidWidth: CGFloat = min(max(CGFloat(overviewLastPaidColumnWidth), 110), 240)
            let dividerWidth: CGFloat = compact ? 1 : 10
            let listPaneWidth = max(1, geometry.size.width - sideWidth - dividerWidth)
            let tableWidth = max(
                listPaneWidth,
                42 + nameWidth + (amountsVisible ? amountWidth + 8 : 0)
                    + dueDateWidth + lastPaidWidth + 72
            )

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    listToolbar(compact: compact)
                    ScrollView(.horizontal) {
                        VStack(spacing: 0) {
                            columnHeader(
                                compact: compact,
                                amountsVisible: amountsVisible,
                                nameWidth: nameWidth,
                                amountWidth: amountWidth,
                                dueDateWidth: dueDateWidth,
                                lastPaidWidth: lastPaidWidth
                            )
                            if visibleBills.isEmpty {
                                EmptyState(
                                    title: "No bills here",
                                    message: "Try another section or add a new bill.",
                                    icon: filter.icon
                                )
                            } else {
                                ScrollView(.vertical) {
                                    ZStack(alignment: .top) {
                                        Color.clear
                                            .contentShape(Rectangle())
                                            .onTapGesture { selectedBillID = nil }

                                        LazyVStack(spacing: 2) {
                                            ForEach(visibleBills) { bill in
                                                Button {
                                                    selectedBillID = bill.id
                                                } label: {
                                                    DesktopBillRow(
                                                        bill: bill,
                                                        isSelected: bill.id == selectedBill?.id,
                                                        compact: compact,
                                                        amountsVisible: amountsVisible,
                                                        nameWidth: nameWidth,
                                                        amountWidth: amountWidth,
                                                        dueDateWidth: dueDateWidth,
                                                        lastPaidWidth: lastPaidWidth
                                                    )
                                                }
                                                .buttonStyle(.plain)
                                                .contextMenu {
                                                    if bill.isArchived {
                                                        Button("Unarchive") { store.unarchive(bill) }
                                                        Button("Delete Bill…", role: .destructive) { billPendingDeletion = bill }
                                                    } else {
                                                        Button("Edit Bill") { editingBill = bill }
                                                        Button("Log Payment") { payingBill = bill }
                                                        Divider()
                                                        Button("Archive") { store.archive(bill) }
                                                        Button("Delete Bill…", role: .destructive) { billPendingDeletion = bill }
                                                    }
                                                }
                                            }
                                        }
                                        .padding(10)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: geometry.size.height - 105, alignment: .top)
                                }
                            }
                        }
                        .frame(width: tableWidth, height: geometry.size.height - 54, alignment: .top)
                    }
                    .scrollIndicators(.visible)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity)
                .background(Color.ledgerlyListSurface)

                if compact {
                    Color.clear.frame(width: 1)
                } else {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 10)
                        .contentShape(Rectangle())
                        .overlay(alignment: .center) {
                            Rectangle()
                                .fill(Color.ledgerlyDivider.opacity(0.42))
                                .frame(width: 1)
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let proposed = sideWidth - value.translation.width
                                    overviewRightPaneWidth = Double(min(max(proposed, minWidth), maxWidth))
                                }
                        )
                }

                if let bill = selectedBill {
                    BillInspector(
                        bill: bill,
                        onPay: { payingBill = bill },
                        onEdit: { editingBill = bill },
                        onClose: { selectedBillID = nil }
                    )
                    .frame(width: sideWidth)
                } else {
                    MonthlyCalendarPanel(bills: visibleBills)
                        .frame(width: sideWidth)
                }
            }
        }
        .background(Color.ledgerlyWorkspace)
        .sheet(item: $editingBill) { bill in
            BillEditorView(existingBill: bill)
                .environmentObject(store)
        }
        .sheet(item: $payingBill) { bill in
            PaymentView(bill: bill)
                .environmentObject(store)
        }
        .alert("Delete Bill?", isPresented: deleteBillAlertBinding, presenting: billPendingDeletion) { bill in
            Button("Cancel", role: .cancel) {
                billPendingDeletion = nil
            }
            Button("Delete", role: .destructive) {
                if selectedBillID == bill.id {
                    selectedBillID = nil
                }
                store.delete(bill)
                billPendingDeletion = nil
            }
        } message: { bill in
            Text("Are you sure you want to permanently delete \"\(bill.name)\"? This action cannot be undone.")
        }
        .onChange(of: filter) { _ in
            selectedBillID = nil
        }
    }

    private var deleteBillAlertBinding: Binding<Bool> {
        Binding(
            get: { billPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    billPendingDeletion = nil
                }
            }
        )
    }

    private func listToolbar(compact: Bool) -> some View {
        HStack(spacing: 12) {
            Button {
                showingAddBill = true
            } label: {
                Image(systemName: "plus")
                    .font(.title3)
                    .frame(width: 24, height: 24)
            }
            .ledgerlyGlassButton()
            .help("Add Bill")

            VStack(alignment: .leading, spacing: 1) {
                Text(filter.rawValue)
                    .font(.headline)
            }
            Text("\(visibleBills.count)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.secondary.opacity(0.12), in: Capsule())
            Spacer()
            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: compact ? 145 : 230)
        }
        .padding(.horizontal, 24)
        .frame(height: 54)
        .background(Color.ledgerlyListSurface)
    }

    private func columnHeader(
        compact: Bool,
        amountsVisible: Bool,
        nameWidth: CGFloat,
        amountWidth: CGFloat,
        dueDateWidth: CGFloat,
        lastPaidWidth: CGFloat
    ) -> some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 42, height: 1)

            resizableColumnHeader(
                "Name",
                width: nameWidth,
                alignment: .leading,
                gesture: nameResizeGesture(currentWidth: nameWidth)
            )

            if amountsVisible {
                resizableColumnHeader(
                    "Amount",
                    width: amountWidth,
                    alignment: .leading,
                    gesture: amountResizeGesture(currentWidth: amountWidth)
                )
            }

            resizableColumnHeader(
                "Due Date",
                width: dueDateWidth,
                alignment: .leading,
                gesture: dueDateResizeGesture(currentWidth: dueDateWidth)
            )

            resizableColumnHeader(
                "Last Paid",
                width: lastPaidWidth,
                alignment: .leading,
                gesture: lastPaidResizeGesture(currentWidth: lastPaidWidth)
            )
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Color.ledgerlyPrimaryText)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .leading)
        .background(Color.ledgerlyToolbar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.ledgerlyDivider)
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.ledgerlyDivider)
                .frame(height: 1)
        }
    }

    private func resizableColumnHeader<G: Gesture>(
        _ title: String,
        width: CGFloat,
        alignment: Alignment,
        gesture: G
    ) -> some View {
        Text(title)
            .frame(width: width, alignment: alignment)
            .overlay(alignment: .trailing) {
                resizeHandle
                    .offset(x: 9)
                    .gesture(gesture)
            }
    }

    private var resizeHandle: some View {
        ZStack {
            Color.clear
                .frame(width: 18, height: 24)
            Rectangle()
                .fill(Color.ledgerlyDivider)
                .frame(width: 1, height: 18)
        }
        .frame(width: 18, height: 24)
        .contentShape(Rectangle())
        .help("Drag to resize column")
    }

    private func nameResizeGesture(currentWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if nameColumnDragStartWidth == nil {
                    nameColumnDragStartWidth = currentWidth
                }
                guard let start = nameColumnDragStartWidth else { return }
                overviewNameColumnWidth = Double(min(max(start + value.translation.width, 190), 420))
            }
            .onEnded { _ in
                nameColumnDragStartWidth = nil
            }
    }

    private func amountResizeGesture(currentWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if amountColumnDragStartWidth == nil {
                    amountColumnDragStartWidth = currentWidth
                }
                guard let start = amountColumnDragStartWidth else { return }
                overviewAmountColumnWidth = Double(min(max(start + value.translation.width, 90), 180))
            }
            .onEnded { _ in
                amountColumnDragStartWidth = nil
            }
    }

    private func dueDateResizeGesture(currentWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dueDateColumnDragStartWidth == nil {
                    dueDateColumnDragStartWidth = currentWidth
                }
                guard let start = dueDateColumnDragStartWidth else { return }
                overviewDueDateColumnWidth = Double(min(max(start + value.translation.width, 120), 240))
            }
            .onEnded { _ in
                dueDateColumnDragStartWidth = nil
            }
    }

    private func lastPaidResizeGesture(currentWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if lastPaidColumnDragStartWidth == nil {
                    lastPaidColumnDragStartWidth = currentWidth
                }
                guard let start = lastPaidColumnDragStartWidth else { return }
                overviewLastPaidColumnWidth = Double(min(max(start + value.translation.width, 110), 240))
            }
            .onEnded { _ in
                lastPaidColumnDragStartWidth = nil
            }
    }
}

struct DesktopBillRow: View {
    let bill: Bill
    let isSelected: Bool
    let compact: Bool
    let amountsVisible: Bool
    let nameWidth: CGFloat
    let amountWidth: CGFloat
    let dueDateWidth: CGFloat
    let lastPaidWidth: CGFloat
    @AppStorage("showAmounts") private var showAmounts = true

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: bill.colorHex).opacity(0.16))
                Image(systemName: categoryIcon)
                    .foregroundStyle(Color(hex: bill.colorHex))
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(bill.name)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(bill.frequency.displayText)
                }
                .font(.caption)
                .foregroundStyle(isSelected ? Color.white.opacity(0.82) : Color.secondary)
            }
            .frame(width: nameWidth, alignment: .leading)

            if amountsVisible {
                Text(bill.amountDisplayText)
                    .fontWeight(.semibold)
                    .frame(width: amountWidth, alignment: .leading)
            }

            HStack(spacing: 9) {
                Capsule()
                    .fill(bill.status.color)
                    .frame(width: 8, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(bill.dueLabel)
                        .fontWeight(.semibold)
                    Text(bill.dueDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.82) : Color.secondary)
                }
            }
            .frame(width: dueDateWidth, alignment: .leading)

            Text(bill.lastPaidDate?.formatted(date: .abbreviated, time: .omitted) ?? "—")
                .foregroundStyle(isSelected ? Color.white.opacity(0.82) : Color.secondary)
                .frame(width: lastPaidWidth, alignment: .leading)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .background(
            isSelected ? Color(hex: "#4E8FD3") : Color.clear,
            in: RoundedRectangle(cornerRadius: 9)
        )
        .contentShape(Rectangle())
    }

    private var categoryIcon: String {
        switch bill.category {
        case "Home": return "house.fill"
        case "Utilities": return "bolt.fill"
        case "Transport": return "car.fill"
        case "Insurance": return "shield.fill"
        case "Subscriptions": return "play.rectangle.fill"
        case "Health": return "cross.case.fill"
        case "Education": return "graduationcap.fill"
        case "Credit Cards": return "creditcard.fill"
        default: return "doc.text.fill"
        }
    }
}

struct MonthlyCalendarPanel: View {
    @EnvironmentObject private var store: BillStore
    let bills: [Bill]
    @State private var month = Date()
    @AppStorage("incomeEnabled") private var incomeEnabled = true
    @AppStorage("showIncomeSummary") private var showIncomeSummary = true

    private var days: [Date?] {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        let range = calendar.range(of: .day, in: .month, for: start)!
        let leading = Array<Date?>(repeating: nil, count: calendar.component(.weekday, from: start) - 1)
        return leading + range.compactMap {
            calendar.date(byAdding: .day, value: $0 - 1, to: start)
        }.map(Optional.some)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(month.formatted(.dateTime.month(.wide).year()))
                        .font(.title3.bold())
                    Text("Monthly calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    month = Calendar.current.date(byAdding: .month, value: -1, to: month)!
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                Button {
                    month = Date()
                } label: {
                    Circle().frame(width: 7, height: 7)
                }
                .buttonStyle(.borderless)
                .help("Current Month")
                Button {
                    month = Calendar.current.date(byAdding: .month, value: 1, to: month)!
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
            }
            .padding(20)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                spacing: 10
            ) {
                ForEach(Calendar.current.veryShortWeekdaySymbols, id: \.self) { weekday in
                    Text(weekday.uppercased())
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        VStack(spacing: 3) {
                            Text(day.formatted(.dateTime.day()))
                                .font(.caption.weight(Calendar.current.isDateInToday(day) ? .bold : .regular))
                                .foregroundStyle(Calendar.current.isDateInToday(day) ? Color.white : Color.primary)
                                .frame(width: 27, height: 27)
                                .background(
                                    Calendar.current.isDateInToday(day) ? Color(hex: "#4E8FD3") : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 7)
                                )
                            HStack(spacing: 2) {
                                ForEach(bills.filter {
                                    Calendar.current.isDate($0.dueDate, inSameDayAs: day)
                                }.prefix(2)) { bill in
                                    Circle()
                                        .fill(Color(hex: bill.colorHex))
                                        .frame(width: 5, height: 5)
                                }
                            }
                            .frame(height: 5)
                        }
                    } else {
                        Color.clear.frame(height: 35)
                    }
                }
            }
            .padding(.horizontal, 18)

            Divider()
                .padding(.horizontal, 18)
                .padding(.top, 20)

            VStack(alignment: .leading, spacing: 12) {
                Text("This month")
                    .font(.headline)
                let monthBills = bills.filter {
                    Calendar.current.isDate($0.dueDate, equalTo: month, toGranularity: .month)
                }
                if monthBills.isEmpty {
                    Text("No bills due in this month.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(monthBills.prefix(5)) { bill in
                        HStack {
                            Circle()
                                .fill(Color(hex: bill.colorHex))
                                .frame(width: 8, height: 8)
                            Text(bill.name)
                                .lineLimit(1)
                            Spacer()
                            Text(bill.dueDate.formatted(.dateTime.day()))
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
            }
            .padding(20)

            Spacer()

            if incomeEnabled && showIncomeSummary && !store.incomes.isEmpty {
                Divider()
                    .padding(.horizontal, 18)

                MonthlyMoneySummary(month: month)
                    .padding(20)
            }
        }
        .background(Color.ledgerlyWorkspace)
    }
}

struct MonthlyMoneySummary: View {
    @EnvironmentObject private var store: BillStore
    let month: Date

    private var plannedIncome: Double {
        store.incomes.reduce(0) { $0 + $1.estimatedAmount(in: month) }
    }

    private var paymentsRecorded: Double {
        store.bills
            .filter { !$0.isArchived }
            .flatMap(\.payments)
            .filter {
                Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month)
            }
            .reduce(0) { $0 + $1.amount }
    }

    private var billsRemaining: Double {
        store.bills
            .filter { !$0.isArchived }
            .reduce(0) { total, bill in
                let paidThisMonth = bill.payments
                    .filter {
                        Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month)
                    }
                    .reduce(0) { $0 + $1.amount }
                return total + max(bill.amountDue(in: month) - paidThisMonth, 0)
            }
    }

    private var afterBillsBalance: Double {
        plannedIncome - paymentsRecorded - billsRemaining
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Monthly money picture")
                .font(.headline)

            summaryRow("Income planned", amount: plannedIncome)
            summaryRow("Payments recorded", amount: paymentsRecorded)
            summaryRow("Bills remaining", amount: billsRemaining)

            Divider()

            summaryRow(
                "After-bills balance",
                amount: afterBillsBalance,
                emphasized: true,
                amountColor: afterBillsBalance < 0 ? .red : Color(hex: "#58A66B")
            )
        }
    }

    private func summaryRow(
        _ title: String,
        amount: Double,
        emphasized: Bool = false,
        amountColor: Color = .primary
    ) -> some View {
        HStack {
            Text(title)
                .font(emphasized ? .subheadline.bold() : .caption)
                .foregroundStyle(emphasized ? Color.primary : Color.secondary)
            Spacer()
            Text(amount.currency)
                .font(emphasized ? .subheadline.bold() : .caption.weight(.semibold))
                .foregroundStyle(amountColor)
                .monospacedDigit()
        }
    }
}

struct BillInspector: View {
    @EnvironmentObject private var store: BillStore
    let bill: Bill
    let onPay: () -> Void
    let onEdit: () -> Void
    let onClose: () -> Void
    @State private var notesDraft = ""
    @State private var notesSaveTask: Task<Void, Never>?
    @State private var showingBillHistory = false
    @State private var websiteBrandImage: NSImage?
    @State private var websiteBrandAccent: Color?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let websiteBrandImage {
                    Image(nsImage: websiteBrandImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill((websiteBrandAccent ?? Color(hex: bill.colorHex)).opacity(0.18))
                        )
                } else {
                    Circle()
                        .fill(websiteBrandAccent ?? Color(hex: bill.colorHex))
                        .frame(width: 16, height: 16)
                }
                Text(bill.name)
                    .font(.title3.bold())
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(.secondary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Close Bill Details")
            }
            .padding(18)
            .background(
                LinearGradient(
                    colors: [
                        (websiteBrandAccent ?? Color(hex: bill.colorHex)).opacity(0.24),
                        Color.ledgerlyInspectorHeader
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(bill.dueLabel)
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                        Text(bill.dueDate.formatted(date: .complete, time: .omitted))
                            .foregroundStyle(.secondary)
                        Text(bill.amountDisplayText)
                            .font(.title3.bold())
                            .foregroundStyle(bill.status.color)
                    }

                    Button("Log Payment", action: onPay)
                        .ledgerlyGlassButton(prominent: true)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)

                    Button("Skip This Occurrence") {
                        store.skip(bill)
                    }
                    .ledgerlyGlassButton()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)

                    Button {
                        showingBillHistory = true
                    } label: {
                        InspectorLink(
                            title: "Payment History",
                            subtitle: bill.payments.isEmpty ? "Never paid" : "\(bill.payments.count) payment\(bill.payments.count == 1 ? "" : "s")",
                            icon: "clock.arrow.circlepath"
                        )
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.headline)
                        TextEditor(text: $notesDraft)
                            .font(.body)
                            .frame(minHeight: 90)
                            .padding(7)
                            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                            .onChange(of: notesDraft) { newValue in
                                scheduleNotesSave(newValue)
                            }
                    }

                    if let websiteURL = bill.websiteURL {
                        Link(destination: websiteURL) {
                            Label("Open Biller Website", systemImage: "safari")
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.ledgerlyInspector)

            Divider()
            HStack {
                Button("Archive") { store.archive(bill) }
                    .disabled(bill.isArchived)
                Spacer()
                Button("Edit", action: onEdit)
            }
            .padding(14)
        }
        .onAppear { notesDraft = bill.notes }
        .onChange(of: bill.id) { _ in
            notesSaveTask?.cancel()
            notesDraft = bill.notes
        }
        .onDisappear {
            notesSaveTask?.cancel()
            if notesDraft != bill.notes {
                store.updateNotes(for: bill, notes: notesDraft)
            }
        }
        .task(id: bill.websiteURL?.absoluteString) {
            await loadWebsiteBrand()
        }
        .sheet(isPresented: $showingBillHistory) {
            BillPaymentHistoryView(bill: bill)
        }
    }

    private func scheduleNotesSave(_ notes: String) {
        notesSaveTask?.cancel()
        notesSaveTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            store.updateNotes(for: bill, notes: notes)
        }
    }

    private func loadWebsiteBrand() async {
        guard let websiteURL = bill.websiteURL else {
            websiteBrandImage = nil
            websiteBrandAccent = nil
            return
        }

        let provider = LPMetadataProvider()
        guard let metadata = await fetchMetadata(provider: provider, url: websiteURL) else {
            websiteBrandImage = nil
            websiteBrandAccent = nil
            return
        }

        if let provider = metadata.iconProvider ?? metadata.imageProvider,
           let image = await loadImage(from: provider) {
            websiteBrandImage = image
            websiteBrandAccent = averageAccentColor(from: image)
        } else {
            websiteBrandImage = nil
            websiteBrandAccent = nil
        }
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
            red: Double(bitmap[0]) / 255.0,
            green: Double(bitmap[1]) / 255.0,
            blue: Double(bitmap[2]) / 255.0
        )
    }
}

struct InspectorLink: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct AttachmentRow: View {
    let attachment: BillAttachment
    let onOpen: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .foregroundStyle(Color(hex: "#4E8FD3"))
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName)
                    .lineLimit(1)
                Text(attachment.addedDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onOpen) {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
        }
        .padding(9)
        .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
            }
            Spacer()
        }
        .padding(17)
        .background(Color.ledgerlyReportCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.ledgerlyDivider)
        }
    }
}

struct MonthCalendar: View {
    let month: Date
    let bills: [Bill]

    private var days: [Date?] {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        let dayRange = calendar.range(of: .day, in: .month, for: start)!
        let weekday = calendar.component(.weekday, from: start)
        let padding = Array<Date?>(repeating: nil, count: weekday - 1)
        return padding + dayRange.compactMap {
            calendar.date(byAdding: .day, value: $0 - 1, to: start)
        }.map(Optional.some)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Monthly calendar")
                        .font(.headline)
                    Text("Colored dots show bills on each due date.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.subheadline.weight(.semibold))
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 7) {
                ForEach(Calendar.current.veryShortWeekdaySymbols, id: \.self) { weekday in
                    Text(weekday.uppercased())
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        CalendarDay(day: day, bills: bills.filter { Calendar.current.isDate($0.dueDate, inSameDayAs: day) })
                    } else {
                        Color.clear.frame(height: 58)
                    }
                }
            }
        }
        .padding(20)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06))
        }
        .shadow(color: .black.opacity(0.04), radius: 18, y: 8)
    }
}

struct CalendarDay: View {
    let day: Date
    let bills: [Bill]

    var body: some View {
        VStack(spacing: 6) {
            Text(day.formatted(.dateTime.day()))
                .font(.subheadline.weight(Calendar.current.isDateInToday(day) ? .bold : .regular))
                .foregroundStyle(Calendar.current.isDateInToday(day) ? .white : .primary)
                .frame(width: 27, height: 27)
                .background(
                    Calendar.current.isDateInToday(day) ? Color(hex: "#4E8FD3") : Color.clear,
                    in: Circle()
                )
            HStack(spacing: 3) {
                ForEach(bills.prefix(3)) { bill in
                    Circle()
                        .fill(Color(hex: bill.colorHex))
                        .frame(width: 6, height: 6)
                }
            }
            .frame(height: 7)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background(bills.isEmpty ? Color.clear : Color(hex: "#FAF2EA"), in: RoundedRectangle(cornerRadius: 10))
    }
}

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
                Text(bill.amountDisplayText)
                    .fontWeight(.bold)
                Text(bill.status.rawValue)
                    .font(.caption2.bold())
                    .foregroundStyle(bill.status.color)
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

struct IncomeView: View {
    @EnvironmentObject private var store: BillStore
    @State private var showingAddIncome = false

    private var monthlyEstimate: Double {
        store.incomes.reduce(0) { $0 + $1.estimatedAmount(in: Date()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Income")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Track expected paychecks and recurring income without connecting a bank.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showingAddIncome = true
                } label: {
                    Label("Add Income", systemImage: "plus")
                }
                .ledgerlyGlassButton(prominent: true)
            }

            HStack(spacing: 16) {
                StatCard(
                    title: "Estimated monthly income",
                    value: monthlyEstimate.currency,
                    icon: "banknote.fill",
                    tint: Color(hex: "#58A66B")
                )
                StatCard(
                    title: "Income sources",
                    value: "\(store.incomes.count)",
                    icon: "building.columns.fill",
                    tint: Color(hex: "#5D82B5")
                )
            }

            if store.incomes.isEmpty {
                EmptyState(
                    title: "No income sources",
                    message: "Add a paycheck, pension, benefit, or other recurring income.",
                    icon: "banknote"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.ledgerlyReportCard, in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18).stroke(Color.ledgerlyDivider)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.incomes.sorted { $0.nextExpectedDate() < $1.nextExpectedDate() }) { income in
                            HStack(spacing: 14) {
                                RoundedRectangle(cornerRadius: 11)
                                    .fill(Color(hex: income.colorHex).opacity(0.18))
                                    .frame(width: 44, height: 44)
                                    .overlay {
                                        Image(systemName: "banknote.fill")
                                            .foregroundStyle(Color(hex: income.colorHex))
                                    }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(income.name).fontWeight(.semibold)
                                    Text(income.frequency.displayText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(income.amount.currency).fontWeight(.bold)
                                    Text("Next \(income.nextExpectedDate().formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Button(role: .destructive) {
                                    store.deleteIncome(income)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(16)
                            if income.id != store.incomes.last?.id {
                                Divider().padding(.leading, 72)
                            }
                        }
                    }
                }
                .background(Color.ledgerlyReportCard, in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18).stroke(Color.ledgerlyDivider)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
        .padding(28)
        .background(Color.ledgerlyWorkspace)
        .sheet(isPresented: $showingAddIncome) {
            IncomeEditorView()
                .environmentObject(store)
        }
    }
}

struct IncomeEditorView: View {
    @EnvironmentObject private var store: BillStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount = 0.0
    @State private var nextDate = Date()
    @State private var frequency: IncomeSource.Frequency = .monthly
    @State private var firstPayday = 15
    @State private var secondPayday = 30
    @State private var notes = ""
    @State private var colorHex = "#58A66B"

    private let colors = ["#58A66B", "#4E8FD3", "#7B6AD8", "#E8B448", "#F2854A"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add income")
                    .font(.title2.bold())
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add Income") {
                    store.addIncome(
                        IncomeSource(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            amount: amount,
                            nextDate: nextDate,
                            frequency: frequency,
                            firstPayday: firstPayday,
                            secondPayday: secondPayday,
                            notes: notes,
                            colorHex: colorHex
                        )
                    )
                    dismiss()
                }
                .ledgerlyGlassButton(prominent: true)
                .disabled(
                    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    amount <= 0 ||
                    (frequency == .twiceMonthly && firstPayday == secondPayday)
                )
            }
            .padding(20)
            Divider()
            Form {
                TextField("Source name", text: $name)
                TextField(
                    frequency == .twiceMonthly ? "Amount per payment" : "Amount",
                    value: $amount,
                    format: .currency(code: Locale.current.currency?.identifier ?? "USD")
                )
                Picker("Repeats", selection: $frequency) {
                    ForEach(IncomeSource.Frequency.allCases) { Text($0.rawValue).tag($0) }
                }
                if frequency == .twiceMonthly {
                    Stepper("First payday: \(firstPayday)", value: $firstPayday, in: 1...31)
                    Stepper("Second payday: \(secondPayday)", value: $secondPayday, in: 1...31)
                    Text("If a payday does not exist in a shorter month, Ledgerly uses the last day of that month.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    DatePicker("Next expected date", selection: $nextDate, displayedComponents: .date)
                }
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
                HStack {
                    Text("Color")
                    Spacer()
                    ForEach(colors, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 22, height: 22)
                            .overlay {
                                if colorHex == hex {
                                    Circle().stroke(Color.primary, lineWidth: 2).padding(-3)
                                }
                            }
                            .onTapGesture { colorHex = hex }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 500, height: frequency == .twiceMonthly ? 560 : 470)
    }
}

struct ForecastView: View {
    @EnvironmentObject private var store: BillStore
    @State private var selectedMonth = Date()
    private let months = (0..<12).compactMap {
        Calendar.current.date(byAdding: .month, value: $0, to: Date())
    }

    private var totals: [Double] {
        months.map { month in
            store.bills
                .filter { !$0.isArchived }
                .reduce(0) { $0 + $1.amountDue(in: month) }
        }
    }

    private var maxTotal: Double { max(totals.max() ?? 1, 1) }

    private var selectedBills: [Bill] {
        store.bills
            .filter { !$0.isArchived && $0.amountDue(in: selectedMonth) > 0 }
            .sorted {
                if $0.dueDate == $1.dueDate {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.dueDate < $1.dueDate
            }
    }

    private var selectedTotal: Double {
        selectedBills.reduce(0) { $0 + $1.amountDue(in: selectedMonth) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("12-month forecast")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Plan ahead for monthly, quarterly, and annual bills.")
                    .foregroundStyle(.secondary)

                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(Array(months.enumerated()), id: \.offset) { index, month in
                        Button {
                            selectedMonth = month
                        } label: {
                            VStack(spacing: 8) {
                                Text(totals[index].currencyCompact)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(
                                        Calendar.current.isDate(
                                            selectedMonth,
                                            equalTo: month,
                                            toGranularity: .month
                                        )
                                            ? Color(hex: "#4E8FD3")
                                            : Color(hex: "#EDB28E")
                                    )
                                    .frame(height: max(8, 250 * totals[index] / maxTotal))
                                Text(month.formatted(.dateTime.month(.narrow)))
                                    .font(.caption.bold())
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .help("Show bills due in \(month.formatted(.dateTime.month(.wide).year()))")
                    }
                }
                .frame(height: 310, alignment: .bottom)
                .padding(24)
                .background(Color.ledgerlyReportCard, in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18).stroke(Color.ledgerlyDivider)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(selectedMonth.formatted(.dateTime.month(.wide).year()))
                                .font(.headline)
                            Text("\(selectedBills.count) bill\(selectedBills.count == 1 ? "" : "s") due")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(selectedTotal.currency)
                            .font(.title3.bold())
                    }

                    Divider()

                    if selectedBills.isEmpty {
                        Text("No bills are projected for this month.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(selectedBills) { bill in
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color(hex: bill.colorHex).opacity(0.18))
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        Circle()
                                            .fill(Color(hex: bill.colorHex))
                                            .frame(width: 9, height: 9)
                                    }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bill.name)
                                        .fontWeight(.semibold)
                                    Text("\(bill.category) · \(bill.frequency.displayText)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(bill.amountDue(in: selectedMonth).currency)
                                    .fontWeight(.semibold)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding(22)
                .background(Color.ledgerlyReportCard, in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18).stroke(Color.ledgerlyDivider)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Monthly set-aside")
                        .font(.headline)
                    ForEach(store.bills.filter {
                        !$0.isArchived && ($0.frequency == .quarterly || $0.frequency == .yearly)
                    }) { bill in
                        HStack {
                            Circle().fill(Color(hex: bill.colorHex)).frame(width: 10, height: 10)
                            Text(bill.name)
                            Spacer()
                            Text("\((bill.amount / (bill.frequency == .yearly ? 12 : 3)).currency) / month")
                                .fontWeight(.semibold)
                        }
                        .padding(.vertical, 4)
                    }
                    if !store.bills.contains(where: {
                        !$0.isArchived && ($0.frequency == .quarterly || $0.frequency == .yearly)
                    }) {
                        Text("Add quarterly or yearly bills to see suggested monthly savings.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(22)
                .background(Color.ledgerlyReportCard, in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18).stroke(Color.ledgerlyDivider)
                }
            }
            .padding(28)
        }
        .background(Color.ledgerlyWorkspace)
    }
}

// Payment History

struct PaymentHistoryView: View {
    @EnvironmentObject private var store: BillStore
    @State private var searchText = ""

    private var entries: [PaymentEntry] {
        store.bills
            .flatMap { bill in bill.payments.map { PaymentEntry(bill: bill, payment: $0) } }
            .filter {
                searchText.isEmpty ||
                $0.bill.name.localizedCaseInsensitiveContains(searchText) ||
                $0.payment.confirmation.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { $0.payment.date > $1.payment.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Payment history")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("A searchable record of every payment and confirmation number.")
                        .foregroundStyle(.secondary)
                    Text("Double-click a payment with an attachment to open it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField("Search payments", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
            }

            if entries.isEmpty {
                EmptyState(
                    title: searchText.isEmpty ? "No payments logged" : "No matching payments",
                    message: searchText.isEmpty ? "Payments you log will appear here." : "Try another bill or confirmation number.",
                    icon: searchText.isEmpty ? "checkmark.seal" : "magnifyingglass"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.ledgerlyReportCard, in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18).stroke(Color.ledgerlyDivider)
                }
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 24) {
                        Text("Bill").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Date").frame(width: 130, alignment: .leading)
                        Text("Amount").frame(width: 130, alignment: .trailing)
                        Text("Confirmation").frame(width: 170, alignment: .leading)
                        Text("Attachment").frame(width: 90, alignment: .center)
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)

                    Divider()

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(entries) { entry in
                                PaymentHistoryRow(entry: entry)
                                if entry.id != entries.last?.id {
                                    Divider().padding(.leading, 54)
                                }
                            }
                        }
                    }
                }
                .background(Color.ledgerlyReportCard, in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18).stroke(Color.ledgerlyDivider)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
        .padding(28)
        .background(Color.ledgerlyWorkspace)
    }
}

struct BillPaymentHistoryView: View {
    @EnvironmentObject private var store: BillStore
    @Environment(\.dismiss) private var dismiss
    let bill: Bill

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(bill.name) history")
                        .font(.title2.bold())
                    Text("\(bill.payments.count) payment\(bill.payments.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            Divider()

            if bill.payments.isEmpty {
                EmptyState(
                    title: "No payments logged",
                    message: "Payments for this bill will appear here.",
                    icon: "clock.arrow.circlepath"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(bill.payments.sorted { $0.date > $1.date }) { payment in
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color(hex: "#58A66B"))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(payment.date.formatted(date: .long, time: .omitted))
                                        .fontWeight(.semibold)
                                    Text(payment.confirmation.isEmpty ? "No confirmation number" : payment.confirmation)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(payment.amount.currency)
                                    .fontWeight(.bold)
                                if !payment.attachments.isEmpty {
                                    Image(systemName: "paperclip.circle.fill")
                                        .foregroundStyle(Color(hex: "#4E8FD3"))
                                }
                            }
                            .padding(16)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                if let attachment = payment.attachments.first {
                                    NSWorkspace.shared.open(store.attachmentURL(attachment))
                                }
                            }
                            Divider().padding(.leading, 50)
                        }

                        if !bill.attachments.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Payment documents")
                                    .font(.headline)
                                ForEach(bill.attachments) { attachment in
                                    Button {
                                        NSWorkspace.shared.open(store.attachmentURL(attachment))
                                    } label: {
                                        HStack {
                                            Image(systemName: "doc.fill")
                                                .foregroundStyle(Color(hex: "#4E8FD3"))
                                            Text(attachment.fileName)
                                                .lineLimit(1)
                                            Spacer()
                                            Image(systemName: "arrow.up.forward.app")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .padding(10)
                                    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                            .padding(16)
                        }
                    }
                }
            }
        }
        .frame(width: 520, height: 440)
        .background(Color.ledgerlyWorkspace)
    }
}

struct PaymentHistoryRow: View {
    @EnvironmentObject private var store: BillStore
    let entry: PaymentEntry

    var body: some View {
        HStack(spacing: 24) {
            HStack(spacing: 11) {
                Circle()
                    .fill(Color(hex: entry.bill.colorHex).opacity(0.18))
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(Color(hex: entry.bill.colorHex))
                    }
                Text(entry.bill.name)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(entry.payment.date.formatted(date: .abbreviated, time: .omitted))
                .frame(width: 130, alignment: .leading)
            Text(entry.payment.amount.currency)
                .fontWeight(.semibold)
                .frame(width: 130, alignment: .trailing)
            Text(entry.payment.confirmation.isEmpty ? "—" : entry.payment.confirmation)
                .foregroundStyle(entry.payment.confirmation.isEmpty ? Color.secondary : Color.primary)
                .lineLimit(1)
                .frame(width: 170, alignment: .leading)
            Group {
                if !entry.payment.attachments.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(hex: "#58A66B"))
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 90, alignment: .center)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if let attachment = entry.payment.attachments.first {
                NSWorkspace.shared.open(store.attachmentURL(attachment))
            }
        }
    }
}

// Settings

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
                LabeledContent("Ledgerly", value: "Version 2.0.2")
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

struct PasswordProtectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let action: PasswordAction
    let onComplete: (Bool) -> Void

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title2.bold())

            if action != .enable {
                SecureField("Current password", text: $currentPassword)
                    .textFieldStyle(.roundedBorder)
            }

            if action != .disable {
                SecureField("New password", text: $newPassword)
                    .textFieldStyle(.roundedBorder)
                SecureField("Confirm new password", text: $confirmation)
                    .textFieldStyle(.roundedBorder)
                Text("Use at least four characters. Ledgerly stores it in the macOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Enter your current password to turn off app locking.")
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button(action == .disable ? "Disable" : "Save") {
                    submit()
                }
                .ledgerlyGlassButton(prominent: true)
            }
        }
        .padding(24)
        .frame(width: 430)
    }

    private var title: String {
        switch action {
        case .enable: return "Enable Password Protection"
        case .change: return "Change Password"
        case .disable: return "Disable Password Protection"
        }
    }

    private func submit() {
        if action != .enable && currentPassword != PasswordKeychain.password {
            errorMessage = "The current password is incorrect."
            return
        }

        if action == .disable {
            guard PasswordKeychain.delete() else {
                errorMessage = "Ledgerly could not remove the password from Keychain."
                return
            }
            onComplete(false)
            dismiss()
            return
        }

        guard newPassword.count >= 4 else {
            errorMessage = "The password must contain at least four characters."
            return
        }
        guard newPassword == confirmation else {
            errorMessage = "The new passwords do not match."
            return
        }
        guard PasswordKeychain.save(newPassword) else {
            errorMessage = "Ledgerly could not save the password to Keychain."
            return
        }

        onComplete(true)
        dismiss()
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title.uppercased())
                .font(.caption.bold())
                .tracking(0.8)
                .foregroundStyle(Color.ledgerlySecondaryText)
            content
        }
        .toggleStyle(.switch)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(Color.ledgerlyReportCard, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.ledgerlyDivider)
        }
    }
}

// Editors

struct BillEditorView: View {
    @EnvironmentObject private var store: BillStore
    @Environment(\.dismiss) private var dismiss

    private let existingBill: Bill?
    @State private var name: String
    @State private var amount: Double
    @State private var isVariableAmount: Bool
    @State private var dueDate: Date
    @State private var frequency: BillFrequency
    @State private var category: String
    @State private var colorHex: String
    @State private var website: String
    @State private var notes: String
    @State private var isReminderEnabled: Bool
    @State private var reminderDays: Int
    @State private var isAutoPay: Bool

    private let categories = ["Home", "Utilities", "Credit Cards", "Transport", "Insurance", "Subscriptions", "Health", "Education", "Other"]
    private let colors = [
        "#F2854A", "#E8B448", "#58A66B", "#4E8FD3", "#7B6AD8",
        "#D85F74", "#2AA198", "#A66B3D", "#8E5EA2", "#64748B"
    ]

    init(existingBill: Bill? = nil) {
        self.existingBill = existingBill
        let savedReminderDays = UserDefaults.standard.object(forKey: "defaultReminderDays") == nil
            ? 3
            : UserDefaults.standard.integer(forKey: "defaultReminderDays")
        _name = State(initialValue: existingBill?.name ?? "")
        _amount = State(initialValue: existingBill?.amount ?? 0)
        _isVariableAmount = State(initialValue: existingBill?.isVariableAmount ?? false)
        _dueDate = State(initialValue: existingBill?.dueDate ?? Date())
        _frequency = State(initialValue: existingBill?.frequency ?? .monthly)
        _category = State(initialValue: existingBill?.category ?? "Utilities")
        _colorHex = State(initialValue: existingBill?.colorHex ?? "#F2854A")
        _website = State(initialValue: existingBill?.website ?? "")
        _notes = State(initialValue: existingBill?.notes ?? "")
        _isReminderEnabled = State(initialValue: existingBill?.isReminderEnabled ?? true)
        _reminderDays = State(initialValue: existingBill?.reminderDays ?? savedReminderDays)
        _isAutoPay = State(initialValue: existingBill?.isAutoPay ?? false)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(existingBill == nil ? "Add a bill" : "Edit bill")
                    .font(.title2.bold())
                Spacer()
                Button("Cancel") { dismiss() }
                Button(existingBill == nil ? "Add Bill" : "Save") { save() }
                    .ledgerlyGlassButton(prominent: true)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || amount < 0)
            }
            .padding(20)

            Divider()

            Form {
                Section("Bill") {
                    TextField("Name", text: $name)
                    Toggle("Variable amount", isOn: $isVariableAmount)
                    TextField(isVariableAmount ? "Estimated amount" : "Amount", value: $amount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                    DatePicker("Due date", selection: $dueDate, displayedComponents: .date)
                    Picker("Repeats", selection: $frequency) {
                        ForEach(BillFrequency.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }
                }

                Section("Appearance") {
                    HStack {
                        Text("Color")
                        Spacer()
                        ForEach(colors, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 22, height: 22)
                                .overlay {
                                    if colorHex == hex {
                                        Circle().stroke(.primary, lineWidth: 2).padding(-3)
                                    }
                                }
                                .onTapGesture { colorHex = hex }
                        }
                    }
                }

                Section("Payment") {
                    Toggle("Automatic payment", isOn: $isAutoPay)
                    Toggle("Reminder", isOn: $isReminderEnabled)
                    if isReminderEnabled {
                        Stepper(
                            "Remind me \(reminderDays) day\(reminderDays == 1 ? "" : "s") before",
                            value: $reminderDays,
                            in: 0...30
                        )
                    }
                    TextField("Biller website (example.com)", text: $website)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 540, height: 650)
    }

    private func save() {
        let bill = Bill(
            id: existingBill?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amount,
            isVariableAmount: isVariableAmount,
            dueDate: dueDate,
            frequency: frequency,
            category: category,
            colorHex: colorHex,
            website: website,
            notes: notes,
            isReminderEnabled: isReminderEnabled,
            reminderDays: reminderDays,
            isAutoPay: isAutoPay,
            payments: existingBill?.payments ?? [],
            attachments: existingBill?.attachments ?? [],
            isArchived: existingBill?.isArchived ?? false
        )
        if existingBill == nil {
            store.add(bill)
        } else {
            store.update(bill)
        }
        dismiss()
    }
}

struct PaymentView: View {
    @EnvironmentObject private var store: BillStore
    @Environment(\.dismiss) private var dismiss
    let bill: Bill
    @State private var amount: Double
    @State private var confirmation = ""
    @State private var attachmentURLs: [URL] = []
    @State private var attachmentError: String?

    init(bill: Bill) {
        self.bill = bill
        _amount = State(initialValue: bill.amount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Log payment")
                .font(.title2.bold())
            Text(bill.name)
                .font(.headline)
            TextField("Amount", value: $amount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
            TextField("Confirmation number (optional)", text: $confirmation)

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Receipt or statement")
                        .font(.headline)
                    Spacer()
                    Button {
                        chooseAttachments()
                    } label: {
                        Label("Attach", systemImage: "paperclip")
                    }
                }

                if attachmentURLs.isEmpty {
                    Text("Optionally attach a receipt, confirmation, PDF, or image to this payment.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(attachmentURLs, id: \.self) { url in
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(Color(hex: "#4E8FD3"))
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                attachmentURLs.removeAll { $0 == url }
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(8)
                        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            Text("The next due date will be calculated automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Mark Paid") {
                    var copiedAttachments: [BillAttachment] = []
                    do {
                        for url in attachmentURLs {
                            copiedAttachments.append(
                                try store.copyPaymentAttachment(from: url)
                            )
                        }
                    } catch {
                        attachmentError = error.localizedDescription
                        return
                    }
                    store.markPaid(
                        bill,
                        amount: amount,
                        confirmation: confirmation,
                        attachments: copiedAttachments
                    )
                    dismiss()
                }
                .ledgerlyGlassButton(prominent: true)
            }
        }
        .padding(24)
        .frame(width: 460)
        .alert("Couldn’t Attach File", isPresented: Binding(
            get: { attachmentError != nil },
            set: { if !$0 { attachmentError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(attachmentError ?? "")
        }
    }

    private func chooseAttachments() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.title = "Attach Files to Payment"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !attachmentURLs.contains(url) {
            attachmentURLs.append(url)
        }
    }
}

// Helpers

struct PaymentEntry: Identifiable {
    let bill: Bill
    let payment: Payment
    var id: UUID { payment.id }
}

struct EmptyState: View {
    let title: String
    let message: String
    let icon: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Double {
    var currency: String {
        formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }

    var currencyCompact: String {
        if self >= 1000 {
            return String(format: "$%.1fk", self / 1000)
        }
        return String(format: "$%.0f", self)
    }
}

extension BillFrequency {
    var displayText: String {
        switch self {
        case .weekly: return "Every week"
        case .monthly: return "Every month"
        case .quarterly: return "Every 3 months"
        case .yearly: return "Every year"
        case .once: return "One time"
        }
    }
}

extension Bill {
    var dueLabel: String {
        let calendar = Calendar.current
        if status == .paid { return "Paid" }
        if calendar.isDateInToday(dueDate) { return "Due today" }
        if calendar.isDateInTomorrow(dueDate) { return "Due tomorrow" }
        if dueDate < calendar.startOfDay(for: Date()) {
            let days = calendar.dateComponents([.day], from: dueDate, to: Date()).day ?? 0
            return "\(days) day\(days == 1 ? "" : "s") overdue"
        }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: Date()),
            to: calendar.startOfDay(for: dueDate)
        ).day ?? 0
        return "Due in \(days) day\(days == 1 ? "" : "s")"
    }
}

extension View {
    @ViewBuilder
    func ledgerlyGlass<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.stroke(Color.white.opacity(0.10), lineWidth: 0.75)
                }
        }
    }

    @ViewBuilder
    func ledgerlyGlassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

extension Color {
    static let ledgerlyPrimaryText = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.94, alpha: 1)
                : NSColor(calibratedWhite: 0.12, alpha: 1)
        }
    )

    static let ledgerlySecondaryText = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.64, alpha: 1)
                : NSColor(calibratedWhite: 0.42, alpha: 1)
        }
    )

    static let ledgerlySidebar = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.09, alpha: 1)
                : NSColor(calibratedRed: 0.94, green: 0.925, blue: 0.90, alpha: 1)
        }
    )

    static let ledgerlyDivider = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.22, alpha: 1)
                : NSColor(calibratedWhite: 0.82, alpha: 1)
        }
    )

    static let ledgerlyWorkspace = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.075, alpha: 1)
                : NSColor(calibratedRed: 0.945, green: 0.922, blue: 0.89, alpha: 1)
        }
    )

    static let ledgerlyListSurface = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.105, alpha: 1)
                : NSColor(calibratedRed: 0.984, green: 0.973, blue: 0.953, alpha: 1)
        }
    )

    static let ledgerlyToolbar = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.125, alpha: 1)
                : NSColor(calibratedRed: 1, green: 0.976, blue: 0.953, alpha: 1)
        }
    )

    static let ledgerlyInspector = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.115, alpha: 1)
                : NSColor(calibratedRed: 1, green: 0.992, blue: 0.976, alpha: 1)
        }
    )

    static let ledgerlyInspectorHeader = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.17, green: 0.14, blue: 0.12, alpha: 1)
                : NSColor(calibratedRed: 1, green: 0.969, blue: 0.929, alpha: 1)
        }
    )

    static let ledgerlyReportCard = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.145, alpha: 1)
                : NSColor(calibratedWhite: 1.0, alpha: 1)
        }
    )

    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var integer: UInt64 = 0
        Scanner(string: value).scanHexInt64(&integer)
        let red = Double((integer >> 16) & 0xFF) / 255
        let green = Double((integer >> 8) & 0xFF) / 255
        let blue = Double(integer & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
