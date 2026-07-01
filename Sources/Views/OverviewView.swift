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
    @AppStorage("overviewRightPaneWidth") private var overviewRightPaneWidth = 350.0
    @AppStorage("overviewNameColumnWidth") private var overviewNameColumnWidth = 320.0
    @AppStorage("overviewAmountColumnWidth") private var overviewAmountColumnWidth = 110.0
    @AppStorage("overviewDueDateColumnWidth") private var overviewDueDateColumnWidth = 160.0
    @AppStorage("overviewLastPaidColumnWidth") private var overviewLastPaidColumnWidth = 140.0
    @State private var selectedBillID: UUID?
    @State private var editingBill: Bill?
    @State private var paymentRequest: PaymentRequest?
    @State private var billPendingDeletion: Bill?
    @State private var searchText = ""
    @State private var nameColumnDragStartWidth: CGFloat?
    @State private var amountColumnDragStartWidth: CGFloat?
    @State private var dueDateColumnDragStartWidth: CGFloat?
    @State private var lastPaidColumnDragStartWidth: CGFloat?
    @State private var horizontalScrollOffset: CGFloat = 0
    @State private var horizontalDragStartOffset: CGFloat?

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
            let minimumListWidth: CGFloat = 420
            let preferredSideWidth: CGFloat = min(max(CGFloat(overviewRightPaneWidth), 280), 340)
            let dividerWidth: CGFloat = 10
            let showSidePane = !compact && geometry.size.width >= minimumListWidth + preferredSideWidth + dividerWidth
            let sideWidth: CGFloat = showSidePane ? min(preferredSideWidth, max(280, geometry.size.width - minimumListWidth - dividerWidth)) : 0
            let amountsVisible = showAmounts
            let activeDividerWidth: CGFloat = showSidePane ? dividerWidth : 1
            let listPaneWidth = max(1, geometry.size.width - sideWidth - activeDividerWidth)
            let preferredNameWidth: CGFloat = min(max(CGFloat(overviewNameColumnWidth), 190), 420)
            let preferredAmountWidth: CGFloat = min(max(CGFloat(overviewAmountColumnWidth), 90), 180)
            let preferredDueDateWidth: CGFloat = min(max(CGFloat(overviewDueDateColumnWidth), 120), 240)
            let preferredLastPaidWidth: CGFloat = min(max(CGFloat(overviewLastPaidColumnWidth), 110), 240)
            let columnSpacing = CGFloat(amountsVisible ? 4 : 3) * 8
            let fixedColumnWidth = 42 + (amountsVisible ? 0 : 0) + columnSpacing
            let availableColumnWidth = max(1, listPaneWidth - 40 - fixedColumnWidth)
            let preferredFlexibleWidth = preferredNameWidth +
                (amountsVisible ? preferredAmountWidth : 0) +
                preferredDueDateWidth +
                preferredLastPaidWidth
            let compression = min(1, availableColumnWidth / max(preferredFlexibleWidth, 1))
            let nameWidth: CGFloat = max(130, preferredNameWidth * compression)
            let amountWidth: CGFloat = amountsVisible ? max(76, preferredAmountWidth * compression) : 0
            let dueDateWidth: CGFloat = max(118, preferredDueDateWidth * compression)
            let lastPaidWidth: CGFloat = max(82, preferredLastPaidWidth * compression)
            let columnContentWidth = 42 + nameWidth + (amountsVisible ? amountWidth : 0)
                + dueDateWidth + lastPaidWidth + columnSpacing
            let tableWidth = max(listPaneWidth, columnContentWidth + 40)
            let rowWidth = max(1, tableWidth - 20)
            let maxHorizontalOffset = max(0, tableWidth - listPaneWidth)

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    listToolbar(compact: compact)
                    VStack(spacing: 0) {
                        ZStack(alignment: .topLeading) {
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
                                                    desktopBillButton(
                                                        bill,
                                                        compact: compact,
                                                        amountsVisible: amountsVisible,
                                                        nameWidth: nameWidth,
                                                        amountWidth: amountWidth,
                                                        dueDateWidth: dueDateWidth,
                                                        lastPaidWidth: lastPaidWidth,
                                                        rowWidth: rowWidth
                                                    )
                                                }
                                            }
                                            .padding(10)
                                            .frame(width: rowWidth, alignment: .topLeading)
                                        }
                                        .frame(width: rowWidth, alignment: .topLeading)
                                        .frame(minHeight: geometry.size.height - 125, alignment: .topLeading)
                                    }
                                }
                            }
                            .frame(width: tableWidth, height: geometry.size.height - (maxHorizontalOffset > 0 ? 72 : 54), alignment: .top)
                            .offset(x: -min(horizontalScrollOffset, maxHorizontalOffset))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .clipped()
                        .gesture(horizontalTableDragGesture(maxOffset: maxHorizontalOffset))

                        if maxHorizontalOffset > 0 {
                            HorizontalTableScrollBar(
                                offset: $horizontalScrollOffset,
                                maxOffset: maxHorizontalOffset
                            )
                            .padding(.horizontal, 18)
                            .padding(.vertical, 5)
                            .background(Color.ledgerlyListSurface)
                            .overlay(alignment: .top) {
                                Rectangle()
                                    .fill(Color.ledgerlyDivider)
                                    .frame(height: 1)
                            }
                        }
                    }
                    .onChange(of: maxHorizontalOffset) { newValue in
                        horizontalScrollOffset = min(horizontalScrollOffset, newValue)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity)
                .background(Color.ledgerlyListSurface)

                if !showSidePane {
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
                                    overviewRightPaneWidth = Double(min(max(proposed, 280), 340))
                                }
                        )
                }

                if showSidePane {
                    if let bill = selectedBill {
                        BillInspector(
                        bill: bill,
                        onPay: { paymentRequest = PaymentRequest(bill: bill, mode: .full) },
                        onPartialPay: { paymentRequest = PaymentRequest(bill: bill, mode: .partial) },
                        onEdit: { editingBill = bill },
                        onClose: { selectedBillID = nil }
                    )
                        .frame(width: sideWidth)
                    } else {
                        MonthlyCalendarPanel(bills: store.bills.filter { !$0.isArchived })
                            .frame(width: sideWidth)
                    }
                }
            }
        }
        .background(Color.ledgerlyWorkspace)
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

    private func desktopBillButton(
        _ bill: Bill,
        compact: Bool,
        amountsVisible: Bool,
        nameWidth: CGFloat,
        amountWidth: CGFloat,
        dueDateWidth: CGFloat,
        lastPaidWidth: CGFloat,
        rowWidth: CGFloat
    ) -> some View {
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
                lastPaidWidth: lastPaidWidth,
                rowWidth: rowWidth
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
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

    private func horizontalTableDragGesture(maxOffset: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if horizontalDragStartOffset == nil {
                    horizontalDragStartOffset = horizontalScrollOffset
                }
                guard let start = horizontalDragStartOffset else { return }
                horizontalScrollOffset = min(max(start - value.translation.width, 0), maxOffset)
            }
            .onEnded { _ in
                horizontalDragStartOffset = nil
            }
    }
}
struct DesktopBillRow: View {
    @EnvironmentObject private var store: BillStore
    let bill: Bill
    let isSelected: Bool
    let compact: Bool
    let amountsVisible: Bool
    let nameWidth: CGFloat
    let amountWidth: CGFloat
    let dueDateWidth: CGFloat
    let lastPaidWidth: CGFloat
    let rowWidth: CGFloat
    @AppStorage("showAmounts") private var showAmounts = true
    @AppStorage("showBillerWebsiteIcons") private var showBillerWebsiteIcons = false

    var body: some View {
        HStack(spacing: 8) {
            BillListIcon(
                bill: bill,
                categoryIcon: categoryIcon,
                useWebsiteIcon: showBillerWebsiteIcons
            )
            .environmentObject(store)

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
                Text(bill.cycleBalanceDisplayText)
                    .fontWeight(.semibold)
                    .frame(width: amountWidth, alignment: .leading)
            }

            HStack(spacing: 9) {
                Capsule()
                    .fill(bill.dueDateColor)
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
        .frame(width: rowWidth, alignment: .leading)
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
private struct HorizontalTableScrollBar: View {
    @Binding var offset: CGFloat
    let maxOffset: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let thumbWidth = max(54, min(geometry.size.width, geometry.size.width * 0.34))
            let travel = max(1, geometry.size.width - thumbWidth)
            let progress = maxOffset <= 0 ? 0 : min(max(offset / maxOffset, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.ledgerlyDivider.opacity(0.45))
                    .frame(height: 7)

                Capsule()
                    .fill(Color.ledgerlySecondaryText.opacity(0.78))
                    .frame(width: thumbWidth, height: 7)
                    .offset(x: travel * progress)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let next = min(max(value.location.x - thumbWidth / 2, 0), travel)
                        offset = min(maxOffset, max(0, (next / travel) * maxOffset))
                    }
            )
        }
        .frame(height: 14)
        .help("Drag to view more bill columns.")
    }
}
private struct BillListIcon: View {
    @EnvironmentObject private var store: BillStore
    let bill: Bill
    let categoryIcon: String
    let useWebsiteIcon: Bool
    @State private var customLogoImage: NSImage?
    @State private var websiteBrand: WebsiteBrandAsset?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(backgroundColor)

            if let customLogoImage {
                Image(nsImage: customLogoImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else if useWebsiteIcon, let websiteBrand {
                Image(nsImage: websiteBrand.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                Image(systemName: categoryIcon)
                    .foregroundStyle(Color(hex: bill.colorHex))
            }
        }
        .frame(width: 42, height: 42)
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
            return Color.ledgerlyToolbar
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
                ForEach(Calendar.current.veryShortWeekdaySymbols, id: \.self) { weekday in
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
        .background(Color.ledgerlyWorkspace)
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
