import CoreServices
import Foundation
import Synchronization

/// When a debounced burst fires: `quiet` after the last signal, but no later than `maxDelay`
/// after the first, so a long burst (a build writing files) still ticks now and then. Pure, so
/// tests drive it with explicit instants.
struct DebounceSchedule {
  let quiet: Duration
  let maxDelay: Duration
  private(set) var first: ContinuousClock.Instant?
  private(set) var last: ContinuousClock.Instant?

  init(quiet: Duration, maxDelay: Duration) {
    self.quiet = quiet
    self.maxDelay = maxDelay
  }

  mutating func signal(at now: ContinuousClock.Instant) {
    if first == nil { first = now }
    last = now
  }

  /// When the pending burst fires; nil when nothing is pending.
  var deadline: ContinuousClock.Instant? {
    guard let first, let last else { return nil }
    return min(last + quiet, first + maxDelay)
  }

  /// Whether the burst is due at `now`; if so it is consumed.
  mutating func fire(at now: ContinuousClock.Instant) -> Bool {
    guard let deadline, now >= deadline else { return false }
    first = nil
    last = nil
    return true
  }
}

/// Calls `action` once per burst of `signal()`s, following a `DebounceSchedule`.
final class Debouncer: Sendable {
  private struct State {
    var schedule: DebounceSchedule
    var driving = false
    var cancelled = false
  }

  private let state: Mutex<State>
  private let action: @Sendable () -> Void

  init(quiet: Duration, maxDelay: Duration, action: @escaping @Sendable () -> Void) {
    state = Mutex(State(schedule: DebounceSchedule(quiet: quiet, maxDelay: maxDelay)))
    self.action = action
  }

  func signal() {
    let start = state.withLock { state -> Bool in
      guard !state.cancelled else { return false }
      state.schedule.signal(at: .now)
      guard !state.driving else { return false }
      state.driving = true
      return true
    }
    if start { Task.detached { await self.drive() } }
  }

  /// Drops a pending burst; later signals are ignored.
  func cancel() { state.withLock { $0.cancelled = true } }

  private func drive() async {
    while true {
      let deadline = state.withLock { state -> ContinuousClock.Instant? in
        guard !state.cancelled, let deadline = state.schedule.deadline else {
          state.driving = false
          return nil
        }
        return deadline
      }
      guard let deadline else { return }
      try? await Task.sleep(until: deadline, clock: .continuous)
      let due = state.withLock { !$0.cancelled && $0.schedule.fire(at: .now) }
      if due { action() }
    }
  }
}

/// Watches directory trees with FSEvents (file-level events) and reports paths `isRelevant`
/// accepts by calling `onChange` (on a private queue).
final class FileWatcher: Sendable {
  private final class Box: Sendable {
    let isRelevant: @Sendable (String) -> Bool
    let onChange: @Sendable () -> Void

    init(
      isRelevant: @escaping @Sendable (String) -> Bool, onChange: @escaping @Sendable () -> Void
    ) {
      self.isRelevant = isRelevant
      self.onChange = onChange
    }
  }

  /// `FSEventStreamRef` isn't Sendable; it's only touched under the lock.
  private struct Stream: @unchecked Sendable {
    let ref: FSEventStreamRef
  }

  private let box: Box
  private let paths: [String]
  private let stream = Mutex<Stream?>(nil)
  private let queue = DispatchQueue(label: "dev.vocoder.git.watcher")

  init(
    paths: [String], isRelevant: @escaping @Sendable (String) -> Bool,
    onChange: @escaping @Sendable () -> Void
  ) {
    self.paths = paths
    box = Box(isRelevant: isRelevant, onChange: onChange)
  }

  deinit { stop() }

  /// Starts watching; returns false if FSEvents refused (the path is gone).
  @discardableResult
  func start() -> Bool {
    stream.withLock { stream in
      guard stream == nil else { return true }
      var context = FSEventStreamContext(
        version: 0, info: Unmanaged.passUnretained(box).toOpaque(), retain: nil, release: nil,
        copyDescription: nil)
      let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
        guard let info else { return }
        let box = Unmanaged<Box>.fromOpaque(info).takeUnretainedValue()
        let array = unsafeBitCast(paths, to: NSArray.self)
        for index in 0..<count {
          let mustScan =
            flags[index] & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0
          if mustScan || (array[index] as? String).map(box.isRelevant) == true {
            box.onChange()
            return
          }
        }
      }
      let flags = FSEventStreamCreateFlags(
        kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
          | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot)
      guard
        let ref = FSEventStreamCreate(
          kCFAllocatorDefault, callback, &context, paths as CFArray,
          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.05, flags)
      else { return false }
      FSEventStreamSetDispatchQueue(ref, queue)
      guard FSEventStreamStart(ref) else {
        FSEventStreamInvalidate(ref)
        FSEventStreamRelease(ref)
        return false
      }
      stream = Stream(ref: ref)
      return true
    }
  }

  /// Stops watching; no `onChange` call starts afterwards. Idempotent.
  func stop() {
    guard
      let ref = stream.withLock({ stream in
        defer { stream = nil }
        return stream?.ref
      })
    else { return }
    FSEventStreamStop(ref)
    FSEventStreamInvalidate(ref)
    // Wait for a callback in flight, so `box` outlives every use.
    queue.sync {}
    FSEventStreamRelease(ref)
  }
}

/// Which paths in a repository matter for its status: anything in the work tree outside the
/// git directory, and in the git directory only HEAD, the index and refs (not objects, logs or
/// lock files).
struct GitPathFilter: Sendable {
  let root: String
  let gitDir: String

  static let gitFiles: Set<String> = [
    "HEAD", "index", "packed-refs", "MERGE_HEAD", "REBASE_HEAD", "CHERRY_PICK_HEAD",
    "ORIG_HEAD",
  ]

  func isRelevant(_ path: String) -> Bool {
    if path == gitDir || path.hasPrefix(gitDir + "/") {
      let inside = path.dropFirst(gitDir.count + 1)
      guard !inside.hasSuffix(".lock") else { return false }
      return Self.gitFiles.contains(String(inside)) || inside.hasPrefix("refs/")
        || inside.hasPrefix("rebase-merge/") || inside.hasPrefix("rebase-apply/")
    }
    return path == root || path.hasPrefix(root + "/")
  }
}
