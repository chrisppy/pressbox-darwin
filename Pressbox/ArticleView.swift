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
    VStack(spacing: 0) {
      if current.isEpisode {
        EpisodeHeader(item: current)
      }
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
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .themedScreen()
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .task(id: item.id) {
      full = nil
      full = await store.open(item)
    }
    .bottomControls {
      if current.isEpisode {
        // An episode's bar is for listening; the rest goes in More.
        PlayButton(item: current)
        if store.hasQueue {
          UpNextButton(item: current)
        }
        DownloadButton(item: current)
        Menu("More", systemImage: "ellipsis.circle") {
          itemActions
        }
      } else {
        itemActions
      }
    }
  }

  /// Star, read, share and open: the bar for an article, More for an episode.
  @ViewBuilder private var itemActions: some View {
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
        Label(Self.openInBrowser, systemImage: "safari")
      }
    }
  }

  #if os(macOS)
    private static let openInBrowser = "Open in Browser"
  #else
    private static let openInBrowser = "Open in Safari"
  #endif

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

/// Renders article HTML with JavaScript off; links open in the default
/// browser (Safari on iPhone and iPad).
@MainActor
struct HTMLView {
  let html: String
  let baseURL: URL?

  func makeCoordinator() -> Coordinator { Coordinator() }

  private func makeWebView(coordinator: Coordinator) -> WKWebView {
    let config = WKWebViewConfiguration()
    config.defaultWebpagePreferences.allowsContentJavaScript = false
    #if os(iOS)
      config.dataDetectorTypes = [.link]
    #endif
    let view = WKWebView(frame: .zero, configuration: config)
    view.navigationDelegate = coordinator
    // A transparent page, so the screen's background shows through.
    #if os(macOS)
      view.setValue(false, forKey: "drawsBackground")
      view.underPageBackgroundColor = .clear
    #else
      view.isOpaque = false
      view.backgroundColor = .clear
    #endif
    return view
  }

  private func update(_ view: WKWebView, coordinator: Coordinator) {
    guard coordinator.loaded != html else { return }
    coordinator.loaded = html
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
      #if os(macOS)
        NSWorkspace.shared.open(url)
      #else
        await UIApplication.shared.open(url)
      #endif
      return .cancel
    }
  }
}

#if os(macOS)
  extension HTMLView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
      makeWebView(coordinator: context.coordinator)
    }

    func updateNSView(_ view: WKWebView, context: Context) {
      update(view, coordinator: context.coordinator)
    }
  }
#else
  extension HTMLView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
      makeWebView(coordinator: context.coordinator)
    }

    func updateUIView(_ view: WKWebView, context: Context) {
      update(view, coordinator: context.coordinator)
    }
  }
#endif
