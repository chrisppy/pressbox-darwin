// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import Foundation

/// Which file of an episode `Downloads` saves, and what it is called: the
/// parts of downloading that need neither a session nor a device.
enum DownloadFiles {
  /// The enclosure to save: the audio (or the video), not a stream (HLS),
  /// which can't be saved as one file.
  static func enclosure(of item: Item, video: Bool) -> Enclosure? {
    guard let media = item.media else { return nil }
    let files = media.enclosures.filter { !isStream($0) }
    if video { return files.first(where: \.isVideo) }
    return files.first { !$0.isVideo } ?? files.first(where: \.isVideo)
  }

  private static func isStream(_ enclosure: Enclosure) -> Bool {
    let mime = enclosure.mime?.lowercased() ?? ""
    return mime.contains("mpegurl") || enclosure.url.lowercased().contains(".m3u8")
  }

  /// AVPlayer tells a local file's format by its extension.
  static func fileExtension(of enclosure: Enclosure) -> String {
    let ext = URL(string: enclosure.url)?.pathExtension.lowercased() ?? ""
    if !ext.isEmpty, ext.count <= 4, ext.allSatisfy({ $0.isLetter || $0.isNumber }) { return ext }
    switch enclosure.mime?.lowercased() {
    case "audio/mp4", "audio/x-m4a", "audio/aac": return "m4a"
    case "video/mp4": return "mp4"
    case "video/quicktime": return "mov"
    case "audio/ogg", "audio/opus": return "ogg"
    case "audio/wav", "audio/x-wav": return "wav"
    default: return enclosure.isVideo ? "mp4" : "mp3"
    }
  }
}

/// An episode saved on the device.
struct Download: Codable, Hashable {
  enum Kind: String, Codable {
    case audio, video
  }

  let id: Int64
  let kind: Kind
  /// Its name in `Downloads.folder`.
  let file: String
  /// Downloaded because it was among the newest unread, not asked for.
  let automatic: Bool
  let bytes: Int64
  let added: Date
}

/// What a download task is for, kept in its `taskDescription` so it survives
/// the app being closed.
struct TaskInfo: Sendable, Equatable {
  let id: Int64
  let kind: Download.Kind
  let automatic: Bool
  let ext: String

  init(id: Int64, kind: Download.Kind, automatic: Bool, ext: String) {
    self.id = id
    self.kind = kind
    self.automatic = automatic
    self.ext = ext
  }

  /// From `description`: "id kind automatic ext".
  init?(_ text: String?) {
    let parts = text?.split(separator: " ") ?? []
    guard parts.count == 4, let id = Int64(parts[0]),
      let kind = Download.Kind(rawValue: String(parts[1]))
    else { return nil }
    self.init(id: id, kind: kind, automatic: parts[2] == "1", ext: String(parts[3]))
  }

  var description: String { "\(id) \(kind.rawValue) \(automatic ? 1 : 0) \(ext)" }

  var file: String { "\(id)-\(kind.rawValue).\(ext)" }
}
