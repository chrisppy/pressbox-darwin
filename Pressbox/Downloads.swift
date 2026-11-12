// SPDX-FileCopyrightText: 2026 Chris Palmer <chris@red-oxide.org>
// SPDX-License-Identifier: MPL-2.0

import Foundation
import Observation

/// Episodes saved on the device, to play without a connection.
///
/// Downloads go through a background `URLSession`, so they carry on (and
/// finish) with the app suspended or closed. Audio is downloaded unless video
/// is asked for. With `automatic` on, each refresh downloads the newest unread
/// episodes. Cleanup: a download goes once its episode is read (finished here
/// or anywhere else), and an automatic one also once it is no longer among the
/// newest unread.
@MainActor
@Observable
final class Downloads {
  static let shared = Downloads()

  static let sessionID = "org.red-oxide.pressbox.downloads"
  /// How many of the newest unread episodes are downloaded automatically.
  static let automaticLimit = 10

  /// Saved episodes, by item id.
  private(set) var saved: [Int64: Download] = [:]
  /// Downloads under way: their progress, 0 to 1.
  private(set) var progress: [Int64: Double] = [:]
  /// Downloads that failed, and why.
  private(set) var failures: [Int64: String] = [:]

  /// Download the newest unread episodes after each refresh.
  var automatic: Bool {
    didSet { UserDefaults.standard.set(automatic, forKey: "downloadAutomatically") }
  }
  /// Download over cellular (and other expensive networks, like a personal
  /// hotspot) as well as Wi-Fi.
  var cellular: Bool {
    didSet { UserDefaults.standard.set(cellular, forKey: "downloadOverCellular") }
  }

  @ObservationIgnored private let delegate = SessionDelegate()
  @ObservationIgnored private lazy var session: URLSession = {
    let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionID)
    configuration.sessionSendsLaunchEvents = true
    // Downloads someone asked for shouldn't wait for iOS to find a good
    // moment; the network settings are per request.
    configuration.isDiscretionary = false
    return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
  }()
  /// The tasks under way, by item id.
  @ObservationIgnored private var tasks: [Int64: (task: URLSessionDownloadTask, info: TaskInfo)] =
    [:]
  @ObservationIgnored private var eventsDone: CheckedContinuation<Void, Never>?
  @ObservationIgnored private var eventsFinished = false

  private init() {
    let defaults = UserDefaults.standard
    automatic = defaults.object(forKey: "downloadAutomatically") as? Bool ?? true
    cellular = defaults.bool(forKey: "downloadOverCellular")
    saved = Self.loadIndex()
    // Drop entries whose file is gone (deleted by hand, or the OS).
    saved = saved.filter { FileManager.default.fileExists(atPath: Self.url(of: $0.value).path) }
    Task { await reconnect() }
  }

  // MARK: Asking

  enum State: Equatable {
    case none
    case downloading(Double)
    case saved(Download)
    case failed(String)
  }

  func state(_ id: Int64) -> State {
    if let p = progress[id] { return .downloading(p) }
    if let d = saved[id] { return .saved(d) }
    if let f = failures[id] { return .failed(f) }
    return .none
  }

  /// The saved file to play: for audio any download of the episode (a video
  /// file plays its sound too), for video only a video one.
  func file(for id: Int64, video: Bool) -> URL? {
    guard let download = saved[id], !video || download.kind == .video else { return nil }
    return Self.url(of: download)
  }

  var bytesUsed: Int64 { saved.values.reduce(0) { $0 + $1.bytes } }

  /// Whether an episode can be saved as `kind`: it has a file of that kind
  /// that isn't a stream.
  static func canDownload(_ item: Item, video: Bool = false) -> Bool {
    enclosure(of: item, video: video) != nil
  }

  // MARK: Downloading

  /// Saves an episode's audio, or its video. A download already saved or
  /// under way is left alone, unless this asks for video and that is audio.
  func download(_ item: Item, video: Bool = false, automatic: Bool = false) {
    let kind: Download.Kind = video ? .video : .audio
    guard let enclosure = Self.enclosure(of: item, video: video),
      let url = URL(string: enclosure.url)
    else { return }
    if let existing = saved[item.id], existing.kind == kind || kind == .audio { return }
    if let current = tasks[item.id] {
      if current.info.kind == kind || kind == .audio { return }
      current.task.cancel()
    }
    var request = URLRequest(url: url)
    request.allowsCellularAccess = cellular
    request.allowsExpensiveNetworkAccess = cellular
    let info = TaskInfo(
      id: item.id, kind: kind,
      automatic: automatic && saved[item.id] == nil,
      ext: Self.fileExtension(of: enclosure))
    let task = session.downloadTask(with: request)
    task.taskDescription = info.description
    if let length = enclosure.length, length > 0 {
      task.countOfBytesClientExpectsToReceive = length
    }
    tasks[item.id] = (task, info)
    progress[item.id] = 0
    failures[item.id] = nil
    task.resume()
  }

  /// Cancels or deletes an episode's download.
  func remove(_ id: Int64) {
    tasks.removeValue(forKey: id)?.task.cancel()
    progress[id] = nil
    failures[id] = nil
    if let download = saved.removeValue(forKey: id) {
      try? FileManager.default.removeItem(at: Self.url(of: download))
      saveIndex()
    }
  }

  func removeAll() {
    for id in Set(saved.keys).union(tasks.keys).union(failures.keys) { remove(id) }
    try? FileManager.default.removeItem(at: Self.folder)
  }

  /// After a refresh: downloads the newest unread episodes (if `automatic`),
  /// and removes downloads that are done with. `unread` is the newest unread
  /// episodes, newest first.
  func sync(unread: [Item], api: APIClient) async {
    let wanted = unread.filter { Self.canDownload($0) }.prefix(Self.automaticLimit)
    let wantedIDs = Set(wanted.map(\.id))
    let unreadIDs = Set(unread.map(\.id))
    // Automatic downloads no longer among the newest unread.
    for (id, entry) in tasks where entry.info.automatic && !wantedIDs.contains(id) { remove(id) }
    for download in saved.values where download.automatic && !wantedIDs.contains(download.id) {
      remove(download.id)
    }
    // Ones asked for: gone once read, here or anywhere else.
    for download in saved.values where !download.automatic && !unreadIDs.contains(download.id) {
      do {
        if try await api.item(download.id).read { remove(download.id) }
      } catch APIError.notFound {
        remove(download.id)
      } catch {
        // Offline: check again next time.
      }
    }
    if automatic {
      for item in wanted { download(item, automatic: true) }
    }
  }

  /// For the app's background URL session task: wakes the session and waits
  /// until it has delivered what finished while the app was away.
  func handleBackgroundEvents() async {
    _ = session
    if eventsFinished {
      eventsFinished = false
      return
    }
    await withCheckedContinuation { eventsDone = $0 }
  }

  // MARK: From the session

  /// Picks up downloads that were under way when the app last stopped.
  private func reconnect() async {
    for task in await session.allTasks {
      guard let task = task as? URLSessionDownloadTask,
        let info = TaskInfo(task.taskDescription)
      else {
        task.cancel()
        continue
      }
      tasks[info.id] = (task, info)
      progress[info.id] = task.progress.fractionCompleted
    }
  }

  fileprivate func wrote(_ info: TaskInfo, fraction: Double) {
    guard tasks[info.id] != nil else { return }
    progress[info.id] = fraction
  }

  fileprivate func finished(_ info: TaskInfo, file: String, bytes: Int64) {
    tasks[info.id] = nil
    progress[info.id] = nil
    failures[info.id] = nil
    // Video replacing audio.
    if let old = saved[info.id], old.file != file {
      try? FileManager.default.removeItem(at: Self.url(of: old))
    }
    saved[info.id] = Download(
      id: info.id, kind: info.kind, file: file, automatic: info.automatic, bytes: bytes,
      added: Date())
    saveIndex()
  }

  fileprivate func failed(_ info: TaskInfo, message: String) {
    tasks[info.id] = nil
    progress[info.id] = nil
    failures[info.id] = message
  }

  fileprivate func backgroundEventsFinished() {
    if let eventsDone {
      self.eventsDone = nil
      eventsDone.resume()
    } else {
      eventsFinished = true
    }
  }

  // MARK: Files

  /// Application Support/Episodes, kept out of backups: the files can be
  /// downloaded again.
  nonisolated static var folder: URL {
    let base =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return base.appending(path: "Episodes", directoryHint: .isDirectory)
  }

  nonisolated static func url(of download: Download) -> URL {
    folder.appending(path: download.file)
  }

  private static var indexURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
      .appending(path: "pressbox-downloads.json")
  }

  private static func loadIndex() -> [Int64: Download] {
    guard let data = try? Data(contentsOf: indexURL),
      let list = try? JSONDecoder().decode([Download].self, from: data)
    else { return [:] }
    return Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
  }

  private func saveIndex() {
    guard let data = try? JSONEncoder().encode(Array(saved.values)) else { return }
    try? data.write(to: Self.indexURL, options: .atomic)
  }

  /// The enclosure to save: the audio (or the video), not a stream (HLS),
  /// which can't be saved as one file.
  private static func enclosure(of item: Item, video: Bool) -> Enclosure? {
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
  private static func fileExtension(of enclosure: Enclosure) -> String {
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
private struct TaskInfo: Sendable {
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

/// The background session's delegate. Its callbacks come on the session's
/// queue; a finished file has to be moved before `didFinishDownloadingTo`
/// returns, the rest goes to `Downloads` on the main actor.
private final class SessionDelegate: NSObject, URLSessionDownloadDelegate {
  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard let info = TaskInfo(downloadTask.taskDescription) else { return }
    if let response = downloadTask.response as? HTTPURLResponse,
      !(200..<300).contains(response.statusCode)
    {
      let message = "The server returned HTTP \(response.statusCode)."
      Task { @MainActor in Downloads.shared.failed(info, message: message) }
      return
    }
    let fileManager = FileManager.default
    var folder = Downloads.folder
    let destination = folder.appending(path: info.file)
    do {
      try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try? folder.setResourceValues(values)
      try? fileManager.removeItem(at: destination)
      try fileManager.moveItem(at: location, to: destination)
    } catch {
      let message = error.localizedDescription
      Task { @MainActor in Downloads.shared.failed(info, message: message) }
      return
    }
    let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    let bytes = Int64(size)
    let file = info.file
    Task { @MainActor in Downloads.shared.finished(info, file: file, bytes: bytes) }
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) {
    guard let info = TaskInfo(downloadTask.taskDescription), totalBytesExpectedToWrite > 0 else {
      return
    }
    let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
    Task { @MainActor in Downloads.shared.wrote(info, fraction: fraction) }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let error, let info = TaskInfo(task.taskDescription) else { return }
    if (error as? URLError)?.code == .cancelled { return }
    let message = error.localizedDescription
    Task { @MainActor in Downloads.shared.failed(info, message: message) }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    Task { @MainActor in Downloads.shared.backgroundEventsFinished() }
  }
}
