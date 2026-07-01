// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 YodaGuru

import SwiftUI
import UserNotifications
import AppKit
import Security
import LinkPresentation
import CoreImage

struct Payment: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var amount: Double
    var confirmation: String
    var notes: String
    var attachments: [BillAttachment] = []
    var dueDateBeforePayment: Date?

    enum CodingKeys: String, CodingKey {
        case id, date, amount, confirmation, notes, attachments, dueDateBeforePayment
    }

    init(
        id: UUID = UUID(),
        date: Date,
        amount: Double,
        confirmation: String,
        notes: String = "",
        attachments: [BillAttachment] = [],
        dueDateBeforePayment: Date? = nil
    ) {
        self.id = id
        self.date = date
        self.amount = amount
        self.confirmation = confirmation
        self.notes = notes
        self.attachments = attachments
        self.dueDateBeforePayment = dueDateBeforePayment
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try values.decode(Date.self, forKey: .date)
        amount = try values.decode(Double.self, forKey: .amount)
        confirmation = try values.decodeIfPresent(String.self, forKey: .confirmation) ?? ""
        notes = try values.decodeIfPresent(String.self, forKey: .notes) ?? ""
        attachments = try values.decodeIfPresent([BillAttachment].self, forKey: .attachments) ?? []
        dueDateBeforePayment = try values.decodeIfPresent(Date.self, forKey: .dueDateBeforePayment)
    }
}
