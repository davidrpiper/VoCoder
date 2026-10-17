// swift-tools-version: 6.2
// VoCoder package layout: DESIGN.md §4.1. Dependencies: ADR 0004.
import Foundation
import PackageDescription

// FTXUI ships tests and fuzzers next to its sources; SwiftPM excludes don't glob, so list them.
let ftxuiRoot = Context.packageDirectory + "/Vendor/FTXUI"
let ftxuiSourceDirs = [
  "src/ftxui/screen", "src/ftxui/dom", "src/ftxui/component", "src/ftxui/util",
]
let ftxuiExcludes: [String] =
  ftxuiSourceDirs.flatMap { dir in
    ((try? FileManager.default.contentsOfDirectory(atPath: ftxuiRoot + "/" + dir)) ?? [])
      .filter {
        $0.hasSuffix("_test.cpp") || $0.hasSuffix("_fuzzer.cpp") || $0.hasSuffix("_benchmark.cpp")
          || $0 == "meson.build"
      }
      .map { dir + "/" + $0 }
  } + [
    // Stale duplicate of the Loop implementation in app.cpp; not in FTXUI's CMake source list.
    "src/ftxui/component/loop.cpp"
  ]

// Embedded Info.plist (DESIGN §4.8): gives the CLI a bundle id, version and usage descriptions.
let infoPlist = Context.packageDirectory + "/Sources/vocoder/Info.plist"

let package = Package(
  name: "VoCoder",
  platforms: [.macOS("26.4")],
  products: [
    .executable(name: "vocoder", targets: ["vocoder"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2"),
    .package(url: "https://github.com/dduan/TOMLDecoder", from: "0.4.5"),
  ],
  targets: [
    .target(
      name: "CFTXUI",
      path: "Vendor/FTXUI",
      exclude: ftxuiExcludes,
      sources: ftxuiSourceDirs,
      publicHeadersPath: "include",
      cxxSettings: [.headerSearchPath("src")]
    ),
    .target(
      name: "VoCoderUIBridge",
      dependencies: ["CFTXUI"],
      // FTXUI's private headers (terminal input parser, used by `injectInput:`).
      cxxSettings: [.headerSearchPath("../../Vendor/FTXUI/src")]
    ),
    .target(
      name: "VoCoderCore",
      dependencies: [.product(name: "TOMLDecoder", package: "TOMLDecoder")]
    ),
    .target(name: "VoCoderUI", dependencies: ["VoCoderCore", "VoCoderUIBridge"]),
    .target(name: "VoCoderVoice", dependencies: ["VoCoderCore"]),
    // In-memory fakes of every Core protocol: tests, snapshot fixtures and `vocoder --demo`.
    .target(name: "VoCoderFakes", dependencies: ["VoCoderCore"]),
    // Contract test suites (imports Swift Testing; test-only).
    .target(name: "VoCoderTestSupport", dependencies: ["VoCoderCore", "VoCoderFakes"]),
    // Snapshot helper for view tests; separate so Core tests don't link FTXUI.
    .target(name: "VoCoderUITestSupport", dependencies: ["VoCoderUI", "VoCoderUIBridge"]),

    // Modules (DESIGN §4.10): depend on Core (and UI for tabs), never on each other.
    .target(name: "GitModule", dependencies: ["VoCoderCore"], path: "Sources/Modules/GitModule"),
    .target(
      name: "ClaudeCodeModule",
      dependencies: ["VoCoderCore", "VoCoderUI"],
      path: "Sources/Modules/ClaudeCodeModule"
    ),
    .target(
      name: "EventKitCalendarModule",
      dependencies: ["VoCoderCore"],
      path: "Sources/Modules/EventKitCalendarModule"
    ),
    .target(
      name: "LinearModule",
      dependencies: ["VoCoderCore"],
      path: "Sources/Modules/LinearModule"
    ),
    .target(
      name: "NotionModule",
      dependencies: ["VoCoderCore"],
      path: "Sources/Modules/NotionModule"
    ),

    // Demo contributions for `vocoder --demo`; the only module allowed to use the fakes.
    .target(
      name: "DemoModule",
      dependencies: ["VoCoderCore", "VoCoderUI", "VoCoderFakes"],
      path: "Sources/Modules/DemoModule"
    ),

    .executableTarget(
      name: "vocoder",
      dependencies: [
        "VoCoderCore", "VoCoderUI", "VoCoderUIBridge", "VoCoderVoice", "VoCoderFakes",
        "GitModule", "ClaudeCodeModule", "EventKitCalendarModule", "LinearModule", "NotionModule",
        "DemoModule",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      exclude: ["Info.plist"],
      linkerSettings: [
        .unsafeFlags([
          "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
          "-Xlinker", infoPlist,
        ])
      ]
    ),

    .testTarget(
      name: "VoCoderCoreTests",
      dependencies: ["VoCoderCore", "VoCoderFakes", "VoCoderTestSupport"]
    ),
    .testTarget(name: "VoCoderUIBridgeTests", dependencies: ["VoCoderUIBridge"]),
    .testTarget(
      name: "VoCoderUITests",
      dependencies: [
        "VoCoderUI", "VoCoderUIBridge", "VoCoderUITestSupport", "VoCoderFakes",
        "VoCoderTestSupport",
      ],
      exclude: ["__Snapshots__"]
    ),
    // Every compiled-in module runs the module contract; the demo module end to end.
    .testTarget(
      name: "ModuleTests",
      dependencies: [
        "VoCoderCore", "VoCoderUI", "VoCoderFakes", "VoCoderTestSupport", "VoCoderUITestSupport",
        "GitModule", "ClaudeCodeModule", "EventKitCalendarModule", "LinearModule", "NotionModule",
        "DemoModule",
      ],
      exclude: ["__Snapshots__"],
      // Claude Code stream-json transcripts recorded by the P0-04 spike (replay tests).
      resources: [.copy("Fixtures")]
    ),
    .testTarget(name: "VoCoderVoiceTests", dependencies: ["VoCoderVoice"]),
  ],
  cxxLanguageStandard: .cxx20
)
