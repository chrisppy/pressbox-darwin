// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import Foundation

/// `m:ss`, or `h:mm:ss` from an hour.
func formatTime(_ seconds: Double) -> String {
  let s = Int(max(0, seconds.isFinite ? seconds : 0))
  let (h, m, sec) = (s / 3600, s / 60 % 60, s % 60)
  return h > 0
    ? String(format: "%d:%02d:%02d", h, m, sec)
    : String(format: "%d:%02d", m, sec)
}
