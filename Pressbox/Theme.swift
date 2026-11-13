// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import SwiftUI

// Birdland colors, from https://github.com/red-oxide/base24-themes: Birdland in
// dark mode, Birdland Light in light mode. Each color is a color set in
// Assets.xcassets holding both values; the comments give its Base24 slot.
// AccentColor (base08, Orioles orange) is the app's tint, so it is not repeated
// here: use `.tint` or `Color.accentColor`.

enum Theme {
  /// base00: screens, lists and the article (not sheets: see
  /// `themedSheet`).
  static let background = Color("Background")
  /// base05: primary text.
  static let text = Color("Text")
  /// base04: secondary text.
  static let mutedText = Color("MutedText")
  /// base12: errors.
  static let error = Color("BrightOrange")
  /// base0A: stars.
  static let star = Color("Brass")
  /// base0B: the read/unread swipe action.
  static let read = Color("CamdenGreen")
  /// base0D: links in articles.
  static let link = Color("WarehouseOrange")
  /// The accent (Orioles orange): the Up Next swipe action.
  static let upNext = Color.accentColor

  /// CSS custom properties for the article page, light and dark: `--text`,
  /// `--muted` and `--link`. The page background stays transparent so the
  /// view's background shows through.
  static var articleCSS: String {
    func vars(_ scheme: ColorScheme) -> String {
      var environment = EnvironmentValues()
      environment.colorScheme = scheme
      func hex(_ name: String) -> String {
        Color(name).resolve(in: environment).hexString ?? "inherit"
      }
      let text = hex("Text")
      let muted = hex("MutedText")
      let link = hex("WarehouseOrange")
      return "--text: \(text); --muted: \(muted); --link: \(link);"
    }
    return """
      :root { \(vars(.light)) }
      @media (prefers-color-scheme: dark) { :root { \(vars(.dark)) } }
      """
  }
}

extension View {
  /// Birdland background and text for a screen: base00 behind lists and
  /// forms, base05 text and base04 secondary text.
  func themedScreen() -> some View {
    self
      .scrollContentBackground(.hidden)
      .background(Theme.background)
      .foregroundStyle(Theme.text, Theme.mutedText)
  }

  /// Birdland text for a sheet, over the sheet's own background: Liquid
  /// Glass at partial height, letting the screen beneath show around it,
  /// and more opaque at full height. A background of our own would hide
  /// that.
  func themedSheet() -> some View {
    self
      .scrollContentBackground(.hidden)
      .foregroundStyle(Theme.text, Theme.mutedText)
  }
}

extension Color.Resolved {
  /// `#rrggbb`, for CSS. `Color.Resolved` holds linear values, so this goes
  /// through `cgColor` to get the gamma-encoded sRGB that CSS expects.
  fileprivate var hexString: String? {
    guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
      let color = cgColor.converted(to: sRGB, intent: .defaultIntent, options: nil),
      let c = color.components, c.count >= 3
    else { return nil }
    let channel = { (v: CGFloat) in Int((min(max(v, 0), 1) * 255).rounded()) }
    return String(format: "#%02x%02x%02x", channel(c[0]), channel(c[1]), channel(c[2]))
  }
}
