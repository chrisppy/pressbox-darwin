// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import SwiftUI
import WebKit

struct ArticleView: View {
  @Environment(Store.self) private var store
  let item: Item
  @State private var full: Item?

  /// The list's copy, so read/starred changes show immediately.
  private var current: Item { store.item(item.id) ?? item }

  var body: some View {
    Group {
      if let full {
        HTMLView(
          html: Self.page(for: full, feedTitle: store.feedTitle(full.feedId)),
          baseURL: full.link)
      } else {
        ProgressView()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .themedScreen()
    .navigationBarTitleDisplayMode(.inline)
    .task(id: item.id) {
      full = nil
      full = await store.open(item)
    }
    .bottomControls {
      Button(
        current.starred ? "Unstar" : "Star",
        systemImage: current.starred ? "star.fill" : "star"
      ) {
        Task { await store.setStarred(current, !current.starred) }
      }
      Button(
        current.read ? "Mark unread" : "Mark read",
        systemImage: current.read ? "circle" : "circle.fill"
      ) {
        Task { await store.setRead(current, !current.read) }
      }
      if let link = current.link {
        ShareLink(item: link)
        Link(destination: link) {
          Label("Open in Safari", systemImage: "safari")
        }
      }
    }
  }

  private static func escape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }

  static func page(for item: Item, feedTitle: String) -> String {
    let date = item.publishedDate.formatted(date: .abbreviated, time: .shortened)
    let meta = [feedTitle, item.author, date]
      .compactMap { $0 }
      .map(escape)
      .joined(separator: " · ")
    let title =
      item.link.map { "<a href=\"\(escape($0.absoluteString))\">\(escape(item.title))</a>" }
      ?? escape(item.title)
    let body = item.content ?? item.summary ?? ""
    return """
      <!DOCTYPE html>
      <html><head>
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <meta http-equiv="Content-Security-Policy" content="script-src 'none'">
      <style>
        :root { color-scheme: light dark; }
        \(Theme.articleCSS)
        body { font: -apple-system-body; line-height: 1.5; margin: 20px; max-width: 42em;
               word-wrap: break-word; color: var(--text); }
        h1 { font: -apple-system-title1; font-weight: 700; line-height: 1.2; margin: 0 0 6px; }
        h1 a { color: inherit; text-decoration: none; }
        .meta { color: var(--muted); font: -apple-system-footnote; margin-bottom: 20px; }
        img, video, iframe { max-width: 100%; height: auto; }
        pre { overflow-x: auto; }
        a { color: var(--link); }
      </style></head>
      <body><h1>\(title)</h1><div class="meta">\(meta)</div>\(body)</body></html>
      """
  }
}

/// Renders article HTML with JavaScript off; links open in Safari.
struct HTMLView: UIViewRepresentable {
  let html: String
  let baseURL: URL?

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeUIView(context: Context) -> WKWebView {
    let config = WKWebViewConfiguration()
    config.defaultWebpagePreferences.allowsContentJavaScript = false
    config.dataDetectorTypes = [.link]
    let view = WKWebView(frame: .zero, configuration: config)
    view.navigationDelegate = context.coordinator
    view.isOpaque = false
    view.backgroundColor = .clear
    return view
  }

  func updateUIView(_ view: WKWebView, context: Context) {
    guard context.coordinator.loaded != html else { return }
    context.coordinator.loaded = html
    view.loadHTMLString(html, baseURL: baseURL)
  }

  @MainActor
  final class Coordinator: NSObject, WKNavigationDelegate {
    var loaded: String?

    func webView(
      _ webView: WKWebView, decidePolicyFor action: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
      guard action.navigationType == .linkActivated, let url = action.request.url else {
        return .allow
      }
      await UIApplication.shared.open(url)
      return .cancel
    }
  }
}
