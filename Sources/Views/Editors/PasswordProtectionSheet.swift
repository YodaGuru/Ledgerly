// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 YodaGuru

import SwiftUI
import UserNotifications
import AppKit
import Security
import LinkPresentation
import CoreImage

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
