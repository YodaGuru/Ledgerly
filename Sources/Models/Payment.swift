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
