// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct SettingsView: View {
  @Environment(Store.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var server = ""
  @State private var deviceName = UIDevice.current.name
  @State private var manualToken = ""
  @State private var approveCode = ""
  @State private var approveUser = ""
  @State private var approveStatus: String?
  @State private var confirmForget = false

  var body: some View {
    @Bindable var store = store
    NavigationStack {
      Form {
        if store.isConfigured {
          Section("Server") {
            LabeledContent("Address", value: store.server)
            if let version = store.serverVersion {
              LabeledContent("Version", value: "pressboxd \(version.version)")
            }
            if let me = store.me {
              LabeledContent("Signed in as", value: me.admin ? "\(me.user) (admin)" : me.user)
              if let device = me.device {
                LabeledContent("This device", value: device)
              }
            }
          }
          approveSection
          Section {
            Toggle("Require Face ID", isOn: $store.lockEnabled)
            Toggle("Mark as read when scrolled past", isOn: $store.markReadOnScroll)
            Toggle(
              "Unread count on app icon",
              isOn: Binding(
                get: { store.badgeEnabled },
                set: { value in Task { await store.setBadgeEnabled(value) } }))
          } footer: {
            Text(
              "Scrolled past means off the top of the list while you scroll. The badge is updated in the background from time to time; iOS decides how often."
            )
          }
          Section {
            Button("Forget this device", role: .destructive) { confirmForget = true }
          } footer: {
            Text(
              "Removes the token and saved items. Revoke it on the server with `pressboxctl revoke`."
            )
          }
        } else {
          pairSection
        }
        if let message = store.errorMessage {
          Section {
            Text(message).foregroundStyle(Theme.error)
          }
        }
      }
      .themedScreen()
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
            .disabled(!store.isConfigured)
        }
      }
      .confirmationDialog("Forget this device?", isPresented: $confirmForget) {
        Button("Forget", role: .destructive) { store.forget() }
      }
      .onAppear { server = store.server }
      .onDisappear { store.cancelPairing() }
    }
    .interactiveDismissDisabled(!store.isConfigured)
  }

  @ViewBuilder private var pairSection: some View {
    Section {
      TextField("https://rss.example.org", text: $server)
        .keyboardType(.URL)
        .textContentType(.URL)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      TextField("Device name", text: $deviceName)
    } header: {
      Text("Connect to pressbox")
    } footer: {
      Text(
        "Plain http only works for local network addresses; use https otherwise, for example with tailscale serve."
      )
    }
    Section {
      if let code = store.pairCode {
        VStack(alignment: .leading, spacing: 8) {
          Text(code)
            .font(.system(size: 40, weight: .bold, design: .monospaced))
            .textSelection(.enabled)
          Text(
            "Approve it on the server with `pressboxctl approve \(code)`, or from another paired device."
          )
          .font(.callout)
        }
        Button("Cancel", role: .cancel) { store.cancelPairing() }
      } else {
        Button("Pair this device") {
          store.startPairing(server: server, name: deviceName)
        }
        .disabled(server.trimmingCharacters(in: .whitespaces).isEmpty)
      }
      if let status = store.pairStatus {
        Text(status).foregroundStyle(.secondary)
      }
    }
    Section {
      DisclosureGroup("Use a token instead") {
        SecureField("Token from pressboxctl add-device", text: $manualToken)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        Button("Use token") {
          store.server = server.trimmingCharacters(in: .whitespacesAndNewlines)
          store.token = manualToken.trimmingCharacters(in: .whitespacesAndNewlines)
          Task {
            await store.reload()
            if store.errorMessage == nil { dismiss() }
          }
        }
        .disabled(manualToken.isEmpty || server.isEmpty)
      }
    }
  }

  @ViewBuilder private var approveSection: some View {
    Section {
      HStack {
        TextField("Code, e.g. K7W-4QX", text: $approveCode)
          .textInputAutocapitalization(.characters)
          .autocorrectionDisabled()
          .font(.body.monospaced())
        Button("Approve") {
          Task {
            if let paired = await store.approve(code: approveCode, user: approveUser) {
              approveStatus = "Paired \(paired)."
              approveCode = ""
              approveUser = ""
            }
          }
        }
        .secondaryButtonStyle()
        .disabled(approveCode.trimmingCharacters(in: .whitespaces).count < 6)
      }
      if store.me?.admin == true {
        TextField("For user (blank: you)", text: $approveUser)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
      }
      if let approveStatus {
        Text(approveStatus).foregroundStyle(.secondary)
      }
    } header: {
      Text("Approve a device")
    } footer: {
      Text(
        "Enter the code another device shows while pairing. It's added to your account unless you name another user."
      )
    }
  }
}
