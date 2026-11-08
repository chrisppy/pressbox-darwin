// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import SwiftUI
import UIKit

// Every screen's controls live in a bottom toolbar, within thumb reach,
// including Back and Home where the navigation bar would have them.

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
}

extension View {
  /// The screen's controls in the bottom toolbar: Back (and Home) first when
  /// columns are stacked, then two clusters at either end. On iOS 26 each is
  /// its own glass group, and with `search` the search field sits between
  /// the clusters, as a button until tapped; before that it stays at the top.
  func bottomControls<Leading: View, Trailing: View>(
    search: Bool = false,
    @ViewBuilder leading: () -> Leading,
    @ViewBuilder trailing: () -> Trailing
  ) -> some View {
    modifier(BottomControls(search: search, leading: leading(), trailing: trailing()))
  }
}

private struct BottomControls<Leading: View, Trailing: View>: ViewModifier {
  @Environment(\.navigation) private var navigation
  let search: Bool
  let leading: Leading
  let trailing: Trailing

  @ViewBuilder func body(content: Content) -> some View {
    let screen = content.navigationBarBackButtonHidden(navigation != nil)
    if #available(iOS 26, *) {
      screen
        .toolbar {
          if navigation != nil {
            ToolbarItemGroup(placement: .bottomBar) { navigationButtons }
            ToolbarSpacer(.fixed, placement: .bottomBar)
          }
          ToolbarItemGroup(placement: .bottomBar) { leading }
          if search {
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
          } else {
            ToolbarSpacer(.flexible, placement: .bottomBar)
          }
          ToolbarItemGroup(placement: .bottomBar) { trailing }
        }
        // With Back in the bar there's no room for a full search field.
        .searchToolbarBehavior(navigation != nil ? .minimize : .automatic)
    } else {
      screen
        .toolbar {
          ToolbarItemGroup(placement: .bottomBar) {
            navigationButtons
            leading
            Spacer()
            trailing
          }
        }
    }
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
