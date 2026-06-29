// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 YodaGuru

import SwiftUI
import UserNotifications
import AppKit
import Security
import LinkPresentation
import CoreImage

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
