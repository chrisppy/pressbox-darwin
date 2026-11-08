// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import SwiftUI
import UIKit

// Birdland colors, from https://github.com/chrisppy/base24-themes: Birdland in
// dark mode, Birdland Light in light mode. Each color is a color set in
// Assets.xcassets holding both values; the comments give its Base24 slot.
// AccentColor (base08, Orioles orange) is the app's tint, so it is not repeated
// here: use `.tint` or `Color.accentColor`.

enum Theme {
  /// base00: screens, lists and the article.
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

  /// CSS custom properties for the article page, light and dark: `--text`,
  /// `--muted` and `--link`. The page background stays transparent so the
  /// view's background shows through.
  static var articleCSS: String {
    func vars(_ style: UIUserInterfaceStyle) -> String {
      let traits = UITraitCollection(userInterfaceStyle: style)
      func hex(_ name: String) -> String {
        UIColor(named: name)?.resolvedColor(with: traits).hexString ?? "inherit"
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
}

extension UIColor {
  /// `#rrggbb`, for CSS.
  fileprivate var hexString: String {
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    getRed(&r, green: &g, blue: &b, alpha: nil)
    let channel = { (v: CGFloat) in Int((min(max(v, 0), 1) * 255).rounded()) }
    return String(format: "#%02x%02x%02x", channel(r), channel(g), channel(b))
  }
}
