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
  /// The screen's controls, together in one group centered in the bottom
  /// toolbar: Back (and Home) first when columns are stacked, then
  /// `buttons`. On iOS 26 the group is one piece of glass, and
  /// with `search` a search button sits beside it, opening the field in the
  /// bar; before iOS 26 the field stays at the top.
  func bottomControls<Buttons: View>(
    search: Bool = false, @ViewBuilder _ buttons: () -> Buttons
  ) -> some View {
    modifier(BottomControls(search: search, buttons: buttons()))
  }
}

private struct BottomControls<Buttons: View>: ViewModifier {
  @Environment(\.navigation) private var navigation
  let search: Bool
  let buttons: Buttons

  @ViewBuilder func body(content: Content) -> some View {
    let screen = content.navigationBarBackButtonHidden(navigation != nil)
    if #available(iOS 26, *) {
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
    } else {
      screen
        .toolbar {
          ToolbarItemGroup(placement: .bottomBar) {
            Spacer()
            allButtons
            Spacer()
          }
        }
    }
  }

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
