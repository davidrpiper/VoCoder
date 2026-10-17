import Foundation

/// Version information, read from the Info.plist embedded in the `vocoder` executable
/// (`-sectcreate __TEXT __info_plist`). The plist is the single source of the version.
public struct BuildInfo: Sendable, Equatable {
  public let version: String
  public let build: String

  public init(version: String, build: String) {
    self.version = version
    self.build = build
  }

  /// Reads the main bundle's info dictionary; `nil` when no Info.plist is embedded.
  public static func fromMainBundle() -> BuildInfo? {
    guard let info = Bundle.main.infoDictionary,
      let version = info["CFBundleShortVersionString"] as? String,
      let build = info["CFBundleVersion"] as? String
    else { return nil }
    return BuildInfo(version: version, build: build)
  }

  public var displayString: String { "\(version) (\(build))" }
}
