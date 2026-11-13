// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import SwiftUI

#if os(iOS)
  import UIKit
#endif

// On iPhone and iPad every screen's controls live in a bottom toolbar, within
// thumb reach, including Back and Home where the navigation bar would have
// them. On Mac they go in the window toolbar, above their column.

/// Leaving a screen from its bottom toolbar. Only set where the split view's
/// columns are stacked (iPhone, or a narrow iPad window); side by side,
/// there is nothing to go back to.
struct Navigation {
  /// Up one screen.
  var back: () -> Void
  /// Straight to the feed list, when that is more than one screen up.
  var home: (() -> Void)?
}

extension EnvironmentValues {
  @Entry var navigation: Navigation?
  /// The screen shows the episode playing above its bottom toolbar: every
  /// screen when the columns are stacked, otherwise only the article's, so
  /// it shows once.
  @Entry var showsMiniPlayer = false
}

extension View {
  /// The screen's controls, together in one group centered in the bottom
  /// toolbar: Back (and Home) first when columns are stacked, then
  /// `buttons`. The group is one piece of glass, and with `search` a search
  /// button sits beside it, opening the field in the bar.
  func bottomControls<Buttons: View>(
    search: Bool = false, @ViewBuilder _ buttons: () -> Buttons
  ) -> some View {
    modifier(BottomControls(search: search, buttons: buttons()))
  }
}

private struct BottomControls<Buttons: View>: ViewModifier {
  @Environment(\.navigation) private var navigation
  @Environment(\.showsMiniPlayer) private var showsMiniPlayer
  let search: Bool
  let buttons: Buttons

  @ViewBuilder func body(content: Content) -> some View {
    #if os(macOS)
      // Columns are always side by side on Mac, so there is no Back or Home,
      // and `.searchable` puts its field in the toolbar by itself.
      content
        .toolbar {
          ToolbarItemGroup(placement: .primaryAction) { buttons }
        }
    #else
      iOSBody(content: content)
    #endif
  }

  #if os(iOS)
    @ViewBuilder private func iOSBody(content: Content) -> some View {
      // Inside the screen, so the mini player sits above its toolbar
      // rather than over it.
      let screen = content.navigationBarBackButtonHidden(navigation != nil)
        .miniPlayerAbove(showsMiniPlayer)
      screen
        .toolbar {
          ToolbarSpacer(.flexible, placement: .bottomBar)
          ToolbarItemGroup(placement: .bottomBar) { allButtons }
          if search {
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
          }
          ToolbarSpacer(.flexible, placement: .bottomBar)
        }
        .searchToolbarBehavior(.minimize)
    }
  #endif

  @ViewBuilder private var allButtons: some View {
    navigationButtons
    buttons
  }

  @ViewBuilder private var navigationButtons: some View {
    if let navigation {
      Button("Back", systemImage: "chevron.backward", action: navigation.back)
      if let home = navigation.home {
        Button("Feeds", systemImage: "house", action: home)
      }
    }
  }
}

#if os(iOS)
  extension View {
    /// The episode playing, along the bottom of the screen, above its
    /// toolbar.
    @ViewBuilder func miniPlayerAbove(_ shown: Bool = true) -> some View {
      if shown {
        safeAreaInset(edge: .bottom, spacing: 0) { MiniPlayer() }
      } else {
        self
      }
    }
  }

  /// Keeps swipe-from-the-edge going back on screens whose navigation-bar Back
  /// button is hidden, which otherwise turns the gesture off.
  extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
      super.viewDidLoad()
      interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      viewControllers.count > 1
    }
  }
#endif
