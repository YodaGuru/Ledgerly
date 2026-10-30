// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 YodaGuru

import SwiftUI
import UserNotifications
import AppKit
import Security
import LinkPresentation
import CoreImage

private struct PaymentRequest: Identifiable {
    let id = UUID()
    let bill: Bill
    let mode: PaymentLoggingMode
}

struct OverviewView: View {
    @EnvironmentObject private var store: BillStore
    @Binding var showingAddBill: Bool
    let filter: SidebarItem
    @AppStorage("showAmounts") private var showAmounts = true
    @AppStorage("showPaidBills") private var showPaidBills = true
    @AppStorage("dueSoonDays") private var dueSoonDays = 7
    @AppStorage("showBillerWebsiteIcons") private var showBillerWebsiteIcons = false
    @State private var selectedBillID: UUID?
    @State private var editingBill: Bill?
    @State private var paymentRequest: PaymentRequest?
    @State private var billPendingDeletion: Bill?
    @State private var searchText = ""
    @State private var sortOrder: [KeyPathComparator<Bill>] = [KeyPathComparator(\Bill.dueDate)]

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
            .sorted(using: sortOrder)
    }

    private var selectedBill: Bill? {
        guard let selectedBillID else { return nil }
        return store.bills.first { $0.id == selectedBillID }
    }

    var body: some View {
        billList
            .navigationTitle(filter.rawValue)
            .navigationSubtitle(visibleBills.count == 1 ? "1 bill" : "\(visibleBills.count) bills")
            .searchable(text: $searchText, prompt: "Search bills")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddBill = true
                    } label: {
                        Label("Add Bill", systemImage: "plus")
                    }
                    .help("Add Bill")
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if let bill = selectedBill {
                            paymentRequest = PaymentRequest(bill: bill, mode: .full)
                        }
                    } label: {
                        Label("Log Payment", systemImage: "checkmark.circle")
                    }
                    .keyboardShortcut("l", modifiers: .command)
                    .disabled(selectedBill.map { $0.isArchived || $0.status == .paid } ?? true)
                    .help("Log Payment for the Selected Bill (\u{2318}L)")
                }

            }
            .modifier(BillDetailPane(isPresented: .constant(true)) {
                detailPane
            })
            .sheet(item: $editingBill) { bill in
                BillEditorView(existingBill: bill)
                    .environmentObject(store)
            }
            .sheet(item: $paymentRequest) { request in
                PaymentView(bill: request.bill, mode: request.mode)
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

    // MARK: List

    @ViewBuilder
    private var billList: some View {
        if visibleBills.isEmpty {
            EmptyState(
                title: "No bills here",
                message: "Try another section or add a new bill.",
                icon: filter.icon
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if showAmounts {
            Table(visibleBills, selection: $selectedBillID, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.name) { bill in
                    nameCell(bill)
                }
                .width(min: 190, ideal: 240)

                TableColumn("Amount", value: \.cycleRemainingAmount) { bill in
                    Text(bill.cycleBalanceDisplayText)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
                .width(min: 80, ideal: 120)

                TableColumn("Due Date", value: \.dueDate) { bill in
                    dueDateCell(bill)
                }
                .width(min: 120, ideal: 190)

                TableColumn("Last Paid", value: \.lastPaidSortDate) { bill in
                    lastPaidCell(bill)
                }
                .width(min: 100, ideal: 130)
            }
            .contextMenu(forSelectionType: Bill.ID.self) { ids in
                rowMenu(for: ids)
            } primaryAction: { ids in
                editBill(for: ids)
            }
        } else {
            Table(visibleBills, selection: $selectedBillID, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.name) { bill in
                    nameCell(bill)
                }
                .width(min: 190, ideal: 240)

                TableColumn("Due Date", value: \.dueDate) { bill in
                    dueDateCell(bill)
                }
                .width(min: 120, ideal: 190)

                TableColumn("Last Paid", value: \.lastPaidSortDate) { bill in
                    lastPaidCell(bill)
                }
                .width(min: 100, ideal: 130)
            }
            .contextMenu(forSelectionType: Bill.ID.self) { ids in
                rowMenu(for: ids)
            } primaryAction: { ids in
                editBill(for: ids)
            }
        }
    }

    private func nameCell(_ bill: Bill) -> some View {
        HStack(spacing: 10) {
            BillListIcon(
                bill: bill,
                categoryIcon: Self.categoryIcon(for: bill),
                useWebsiteIcon: showBillerWebsiteIcons,
                size: 32
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(bill.name)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(bill.frequency.displayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private func dueDateCell(_ bill: Bill) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(bill.dueDateColor)
                .frame(width: 6, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(bill.dueLabel)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(bill.dueDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 8)
    }

    private func lastPaidCell(_ bill: Bill) -> some View {
        Text(bill.lastPaidDate?.formatted(date: .abbreviated, time: .omitted) ?? "—")
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    /// Double-click (or Return) on a row opens the editor.
    private func editBill(for ids: Set<Bill.ID>) {
        guard let id = ids.first,
              let bill = store.bills.first(where: { $0.id == id }),
              !bill.isArchived
        else { return }
        editingBill = bill
    }

    @ViewBuilder
    private func rowMenu(for ids: Set<Bill.ID>) -> some View {
        if let id = ids.first, let bill = store.bills.first(where: { $0.id == id }) {
            if bill.isArchived {
                Button("Unarchive") { store.unarchive(bill) }
                Button("Delete Bill…", role: .destructive) { billPendingDeletion = bill }
            } else {
                Button("Edit Bill") { editingBill = bill }
                Button("Log Payment") { paymentRequest = PaymentRequest(bill: bill, mode: .full) }
                Button("Log Partial Payment") { paymentRequest = PaymentRequest(bill: bill, mode: .partial) }
                    .disabled(bill.status == .paid)
                Divider()
                Button("Archive") { store.archive(bill) }
                Button("Delete Bill…", role: .destructive) { billPendingDeletion = bill }
            }
        }
    }

    // MARK: Details pane

    @ViewBuilder
    private var detailPane: some View {
        if let bill = selectedBill {
            BillInspector(
                bill: bill,
                onPay: { paymentRequest = PaymentRequest(bill: bill, mode: .full) },
                onPartialPay: { paymentRequest = PaymentRequest(bill: bill, mode: .partial) },
                onEdit: { editingBill = bill },
                onClose: { selectedBillID = nil }
            )
        } else {
            MonthlyCalendarPanel(bills: store.bills.filter { !$0.isArchived })
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

    private static func categoryIcon(for bill: Bill) -> String {
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

/// Trailing details pane. Uses the system inspector (macOS 14+), which sits in
/// the Liquid Glass layer on macOS 26; falls back to a plain split on macOS 13.
/// Set to false to go back to the system inspector on macOS 26.
private let useFloatingDetailPane = true

private struct BillDetailPane<Pane: View>: ViewModifier {
    @Binding var isPresented: Bool
    let pane: Pane

    init(isPresented: Binding<Bool>, @ViewBuilder pane: () -> Pane) {
        self._isPresented = isPresented
        self.pane = pane()
    }

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), useFloatingDetailPane {
            // Floating glass card matching the sidebar panel.
            let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
            HStack(spacing: 0) {
                content
                if isPresented {
                    pane
                        .frame(width: 330)
                        .clipShape(shape)
                        .glassEffect(.regular, in: shape)
                        .padding(.leading, 4)
                        .padding(.trailing, 10)
                        .padding(.vertical, 10)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.smooth, value: isPresented)
        } else if #available(macOS 14.0, *) {
            content
                .inspector(isPresented: $isPresented) {
                    pane
                        .inspectorColumnWidth(min: 280, ideal: 330, max: 400)
                }
        } else {
            HStack(spacing: 0) {
                content
                if isPresented {
                    Divider()
                    pane
                        .frame(width: 330)
                }
            }
        }
    }
}
private struct BillListIcon: View {
    @EnvironmentObject private var store: BillStore
    let bill: Bill
    let categoryIcon: String
    let useWebsiteIcon: Bool
    var size: CGFloat = 42
    @State private var customLogoImage: NSImage?
    @State private var websiteBrand: WebsiteBrandAsset?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(backgroundColor)

            if let customLogoImage {
                Image(nsImage: customLogoImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.17, style: .continuous))
            } else if useWebsiteIcon, let websiteBrand {
                Image(nsImage: websiteBrand.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.17, style: .continuous))
            } else {
                Image(systemName: categoryIcon)
                    .foregroundStyle(Color(hex: bill.colorHex))
            }
        }
        .frame(width: size, height: size)
        .task(id: taskID) {
            await loadIconAssets()
        }
        .onChange(of: useWebsiteIcon) { _ in
            Task {
                await loadIconAssets()
            }
        }
    }

    private var backgroundColor: Color {
        if customLogoImage != nil {
            return Color.ledgerlyReportCard
        }
        if useWebsiteIcon, let accent = websiteBrand?.accent {
            return accent.opacity(0.18)
        }
        return Color(hex: bill.colorHex).opacity(0.16)
    }

    private var taskID: String {
        "\(bill.customLogo?.storedName ?? "none")-\(useWebsiteIcon)-\(bill.websiteURL?.absoluteString ?? "")"
    }

    private func loadIconAssets() async {
        customLogoImage = store.customLogoImage(for: bill)
        guard customLogoImage == nil else {
            websiteBrand = nil
            return
        }
        guard useWebsiteIcon, let websiteURL = bill.websiteURL else {
            websiteBrand = nil
            return
        }
        websiteBrand = await store.websiteBrand(for: websiteURL)
    }
}
struct MonthlyCalendarPanel: View {
    @EnvironmentObject private var store: BillStore
    let bills: [Bill]
    @State private var month = Date()
    @State private var selectedDate: Date?
    @State private var scope: CalendarBillScope = .fullMonth
    @AppStorage("incomeEnabled") private var incomeEnabled = true
    @AppStorage("showIncomeSummary") private var showIncomeSummary = true

    private var calendar: Calendar {
        Calendar.current
    }

    private var days: [Date?] {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        let range = calendar.range(of: .day, in: .month, for: start)!
        let leading = Array<Date?>(repeating: nil, count: calendar.component(.weekday, from: start) - 1)
        return leading + range.compactMap {
            calendar.date(byAdding: .day, value: $0 - 1, to: start)
        }.map(Optional.some)
    }

    private var monthBills: [Bill] {
        bills
            .filter { calendar.isDate($0.dueDate, equalTo: month, toGranularity: .month) }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var selectedBills: [Bill] {
        guard let selectedDate else { return [] }
        return bills
            .filter { calendar.isDate($0.dueDate, inSameDayAs: selectedDate) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var nextPayDate: Date? {
        guard incomeEnabled, !store.incomes.isEmpty else { return nil }
        return store.incomes
            .map { $0.nextExpectedDate() }
            .min()
    }

    private var scopedBills: [Bill] {
        guard scope == .untilNextPay, let nextPayDate else { return monthBills }
        let today = calendar.startOfDay(for: Date())
        let end = calendar.startOfDay(for: nextPayDate)
        return bills
            .filter {
                let dueDay = calendar.startOfDay(for: $0.dueDate)
                return dueDay >= today && dueDay <= end
            }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var listTitle: String {
        guard let selectedDate else { return "Due this month" }
        return selectedDate.formatted(.dateTime.month(.wide).day())
    }

    private var listedBills: [Bill] {
        selectedDate == nil ? scopedBills : selectedBills
    }

    private var summaryStartDate: Date {
        scope == .untilNextPay ? Date() : month
    }

    private var summaryEndDate: Date? {
        scope == .untilNextPay ? nextPayDate : nil
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
                    month = calendar.date(byAdding: .month, value: -1, to: month)!
                    selectedDate = nil
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                Button {
                    month = Date()
                    selectedDate = nil
                } label: {
                    Circle().frame(width: 7, height: 7)
                }
                .buttonStyle(.borderless)
                .help("Current Month")
                Button {
                    month = calendar.date(byAdding: .month, value: 1, to: month)!
                    selectedDate = nil
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
                // Index as the id: the one-letter symbols repeat (T, T, S, S).
                ForEach(Array(Calendar.current.veryShortWeekdaySymbols.enumerated()), id: \.offset) { _, weekday in
                    Text(weekday.uppercased())
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        Button {
                            selectedDate = day
                        } label: {
                            VStack(spacing: 3) {
                                let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false
                                let isToday = calendar.isDateInToday(day)
                                Text(day.formatted(.dateTime.day()))
                                    .font(.caption.weight(isToday || isSelected ? .bold : .regular))
                                    .foregroundStyle(isToday || isSelected ? Color.white : Color.primary)
                                    .frame(width: 27, height: 27)
                                    .background(
                                        isSelected ? Color(hex: "#7B6AD8") : (isToday ? Color(hex: "#4E8FD3") : Color.clear),
                                        in: RoundedRectangle(cornerRadius: 7)
                                    )
                                HStack(spacing: 2) {
                                    ForEach(bills.filter {
                                        calendar.isDate($0.dueDate, inSameDayAs: day)
                                    }.prefix(3)) { bill in
                                        Circle()
                                            .fill(Color(hex: bill.colorHex))
                                            .frame(width: 5, height: 5)
                                    }
                                }
                                .frame(height: 5)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Show bills due on \(day.formatted(date: .abbreviated, time: .omitted))")
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
                HStack {
                    Text(listTitle)
                        .font(.headline)
                    Spacer()
                    if selectedDate != nil {
                        Button("Show month") {
                            selectedDate = nil
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                }

                if selectedDate == nil {
                    Picker("Bill range", selection: $scope) {
                        ForEach(CalendarBillScope.allCases) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .help("Choose whether this panel shows the full month or only bills due before the next expected income.")
                }

                if scope == .untilNextPay, selectedDate == nil, let nextPayDate {
                    Text("Through \(nextPayDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if listedBills.isEmpty {
                    Text(emptyBillsMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(listedBills) { bill in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(hex: bill.colorHex))
                                        .frame(width: 8, height: 8)
                                    Text(bill.name)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(selectedDate == nil ? bill.dueDate.formatted(.dateTime.day()) : bill.cycleBalanceDisplayText)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)
            .layoutPriority(1)

            if incomeEnabled && showIncomeSummary && !store.incomes.isEmpty {
                Divider()
                    .padding(.horizontal, 18)

                MonthlyMoneySummary(
                    month: month,
                    scope: scope,
                    startDate: summaryStartDate,
                    endDate: summaryEndDate
                )
                    .padding(20)
            }
        }
    }

    private var emptyBillsMessage: String {
        if selectedDate != nil {
            return "No bills due on this day."
        }
        if scope == .untilNextPay {
            return nextPayDate == nil ? "Add income to use this range." : "No bills due before next pay."
        }
        return "No bills due in this month."
    }
}
enum CalendarBillScope: String, CaseIterable, Identifiable {
    case fullMonth = "Full month"
    case untilNextPay = "Until next pay"

    var id: String { rawValue }
}
struct MonthlyMoneySummary: View {
    @EnvironmentObject private var store: BillStore
    let month: Date
    let scope: CalendarBillScope
    let startDate: Date
    let endDate: Date?

    private var calendar: Calendar {
        Calendar.current
    }

    private var plannedIncome: Double {
        switch scope {
        case .fullMonth:
            return store.incomes.reduce(0) { $0 + $1.estimatedAmount(in: month) }
        case .untilNextPay:
            guard let endDate else { return 0 }
            let start = calendar.startOfDay(for: startDate)
            let end = calendar.startOfDay(for: endDate)
            return store.incomes.reduce(0) { total, income in
                let payday = calendar.startOfDay(for: income.nextExpectedDate(from: start))
                return payday >= start && payday <= end ? total + income.amount : total
            }
        }
    }

    private var paymentsRecorded: Double {
        store.bills
            .filter { !$0.isArchived }
            .flatMap(\.payments)
            .filter(paymentIsInScope)
            .reduce(0) { $0 + $1.amount }
    }

    private var billsRemaining: Double {
        if scope == .untilNextPay {
            guard let endDate else { return 0 }
            let start = calendar.startOfDay(for: startDate)
            let end = calendar.startOfDay(for: endDate)
            return store.bills
                .filter { !$0.isArchived }
                .filter {
                    let dueDay = calendar.startOfDay(for: $0.dueDate)
                    return dueDay >= start && dueDay <= end
                }
                .reduce(0) { total, bill in
                    let paidInRange = bill.payments
                        .filter(paymentIsInScope)
                        .reduce(0) { $0 + $1.amount }
                    return total + max(bill.planningAmount - paidInRange, 0)
                }
        }

        return store.bills
            .filter { !$0.isArchived }
            .reduce(0) { total, bill in
                let paidThisMonth = bill.payments
                    .filter {
                        calendar.isDate($0.date, equalTo: month, toGranularity: .month)
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
            VStack(alignment: .leading, spacing: 2) {
                Text(scope == .fullMonth ? "Monthly money picture" : "Until next pay")
                    .font(.headline)
                if scope == .untilNextPay, let endDate {
                    Text("Now through \(endDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

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

    private func paymentIsInScope(_ payment: Payment) -> Bool {
        switch scope {
        case .fullMonth:
            return calendar.isDate(payment.date, equalTo: month, toGranularity: .month)
        case .untilNextPay:
            guard let endDate else { return false }
            let paymentDay = calendar.startOfDay(for: payment.date)
            return paymentDay >= calendar.startOfDay(for: startDate) &&
                paymentDay <= calendar.startOfDay(for: endDate)
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

private extension Bill {
    /// Table sort key; bills that have never been paid sort as oldest.
    var lastPaidSortDate: Date {
        lastPaidDate ?? .distantPast
    }
}
