// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import SwiftUI

struct SettingsView: View {
  @Environment(Store.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @State private var server = ""
  @State private var deviceName = Self.defaultDeviceName
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
            Toggle(Self.lockLabel, isOn: $store.lockEnabled)
            Toggle("Mark as read when scrolled past", isOn: $store.markReadOnScroll)
            Toggle(
              "Unread count on app icon",
              isOn: Binding(
                get: { store.badgeEnabled },
                set: { value in Task { await store.setBadgeEnabled(value) } }))
            if store.badgeEnabled && !store.badgeAllowed {
              badgeBlocked
            }
          } footer: {
            Text(Self.optionsFooter)
          }
          downloadsSection
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
        aboutSection
      }
      .themedScreen()
      .navigationTitle("Settings")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
            .disabled(!store.isConfigured)
          }
        }
      #else
        // The Settings window: closing it is Done.
        .formStyle(.grouped)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 480)
      #endif
      .confirmationDialog("Forget this device?", isPresented: $confirmForget) {
        Button("Forget", role: .destructive) { store.forget() }
      }
      .onAppear { server = store.server }
      .task { await store.checkBadgeAllowed() }
      .onDisappear { store.cancelPairing() }
    }
    .interactiveDismissDisabled(!store.isConfigured)
  }

  @ViewBuilder private var pairSection: some View {
    Section {
      TextField("https://rss.example.org", text: $server)
        .urlEntry()
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
          .plainEntry()
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
          .codeEntry()
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
          .plainEntry()
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

extension SettingsView {
  /// The badge is on here but off in the system's settings, so it doesn't
  /// show: say so, with the way there.
  @ViewBuilder fileprivate var badgeBlocked: some View {
    #if os(iOS)
      VStack(alignment: .leading, spacing: 8) {
        Label(
          "Badges are off for pressbox in the Settings app, so the count doesn't show.",
          systemImage: "exclamationmark.triangle.fill"
        )
        .foregroundStyle(Theme.error)
        Button("Turn On Badges in Settings") {
          if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            openURL(url)
          }
        }
      }
    #else
      Label(
        "Badges are off for pressbox in System Settings › Notifications, so the count doesn't show.",
        systemImage: "exclamationmark.triangle.fill"
      )
      .foregroundStyle(Theme.error)
    #endif
  }

  /// Episodes saved to play offline: automatic downloads, the network they
  /// use, and the space they take.
  @ViewBuilder fileprivate var downloadsSection: some View {
    @Bindable var downloads = Downloads.shared
    Section {
      Toggle("Download new episodes", isOn: $downloads.automatic)
      #if os(iOS)
        Picker("Download over", selection: $downloads.cellular) {
          Text("Wi-Fi only").tag(false)
          Text("Wi-Fi and cellular").tag(true)
        }
      #endif
      LabeledContent(
        "Saved",
        value: downloads.saved.isEmpty
          ? "None"
          : "\(downloads.saved.count) episodes, "
            + ByteCountFormatter.string(fromByteCount: downloads.bytesUsed, countStyle: .file))
      Button("Remove All Downloads", role: .destructive) { downloads.removeAll() }
        .disabled(downloads.saved.isEmpty && downloads.progress.isEmpty)
    } header: {
      Text("Downloads")
    } footer: {
      Text(Self.downloadsFooter)
    }
  }

  fileprivate static let downloadsFooter =
    "The audio of the \(Downloads.automaticLimit) newest unread episodes is downloaded as they come in; download video, or any other episode, from its page. Downloads are removed once an episode is finished or read, and automatic ones once they're no longer among the newest unread."

  /// The app's version and build, which tells TestFlight builds apart.
  @ViewBuilder fileprivate var aboutSection: some View {
    Section {
      LabeledContent("Version") {
        Text(Self.appVersion).textSelection(.enabled)
      }
      Link("Source code", destination: Self.repository)
      Link("Changelog", destination: Self.repository.appending(path: "blob/master/CHANGELOG.md"))
      Link("red-oxide.org", destination: URL(string: "https://red-oxide.org")!)
    } header: {
      Text("About")
    } footer: {
      Text(
        "pressbox is free software, under the [Mozilla Public License 2.0](https://mozilla.org/MPL/2.0/)."
      )
    }
  }

  fileprivate static let repository = URL(string: "https://github.com/red-oxide/pressbox-darwin")!

  /// "2026.11.0 (20261100.4)": the version, then the build.
  fileprivate static var appVersion: String {
    let info = Bundle.main.infoDictionary
    let version = info?["CFBundleShortVersionString"] as? String ?? "?"
    let build = info?["CFBundleVersion"] as? String ?? "?"
    return "\(version) (\(build))"
  }

  fileprivate static var defaultDeviceName: String {
    #if os(macOS)
      Host.current().localizedName ?? "Mac"
    #else
      UIDevice.current.name
    #endif
  }

  #if os(macOS)
    fileprivate static let lockLabel = "Require Touch ID"
    fileprivate static let optionsFooter =
      "Scrolled past means off the top of the list while you scroll. The Dock badge is updated every 15 minutes while pressbox is open."
  #else
    fileprivate static let lockLabel = "Require Face ID"
    fileprivate static let optionsFooter =
      "Scrolled past means off the top of the list while you scroll. The badge is updated in the background from time to time; iOS decides how often."
  #endif
}

// Keyboard hints for the text fields. The Mac has no on-screen keyboard or
// auto-capitalization, so there they only turn off autocorrection.
extension View {
  /// A server address.
  fileprivate func urlEntry() -> some View {
    #if os(iOS)
      self
        .keyboardType(.URL)
        .textContentType(.URL)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    #else
      self.autocorrectionDisabled()
    #endif
  }

  /// A token or user name, typed as is.
  fileprivate func plainEntry() -> some View {
    #if os(iOS)
      self
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    #else
      self.autocorrectionDisabled()
    #endif
  }

  /// A pairing code, in capitals.
  fileprivate func codeEntry() -> some View {
    #if os(iOS)
      self
        .textInputAutocapitalization(.characters)
        .autocorrectionDisabled()
    #else
      self.autocorrectionDisabled()
    #endif
  }
}
