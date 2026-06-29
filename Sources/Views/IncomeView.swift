// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 YodaGuru

import SwiftUI
import UserNotifications
import AppKit
import Security
import LinkPresentation
import CoreImage

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
