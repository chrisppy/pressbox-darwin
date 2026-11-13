// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import SwiftUI

/// A haptic confirming something the user did, played by `ContentView` (on
/// iPhone; Macs and most iPads have no haptics). Each is new, with its own
/// id, so the same kind twice in a row plays twice.
struct Feedback: Equatable {
  enum Kind {
    /// Read or unread, starred or not: a light tick.
    case toggle
    /// Added to Up Next.
    case added
    /// Mark all as read.
    case done
    /// Undo.
    case undo
  }

  let kind: Kind
  let id = UUID()

  var sensory: SensoryFeedback {
    switch kind {
    case .toggle: .selection
    case .added: .impact(weight: .light)
    case .done: .success
    case .undo: .impact(weight: .medium)
    }
  }
}

extension Store {
  /// Plays a haptic for an action the user took. Only for their own taps
  /// and swipes: not for changes from the server, or items marked read by
  /// scrolling, which would buzz all the way down a list.
  func haptic(_ kind: Feedback.Kind) {
    feedback = Feedback(kind: kind)
  }
}
