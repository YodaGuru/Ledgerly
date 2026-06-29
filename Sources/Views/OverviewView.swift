// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 YodaGuru

import SwiftUI
import UserNotifications
import AppKit
import Security
import LinkPresentation
import CoreImage

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
