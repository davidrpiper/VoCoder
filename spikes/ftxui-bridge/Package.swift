// swift-tools-version: 6.2
// P0-01 spike: FTXUI compiled by SwiftPM (no CMake), driven from Swift through an ObjC++ bridge.
import Foundation
import PackageDescription

// FTXUI ships tests and fuzzers next to its sources; SwiftPM excludes don't glob, so list them.
let ftxuiRoot = Context.packageDirectory + "/Vendor/FTXUI"
let ftxuiSourceDirs = ["src/ftxui/screen", "src/ftxui/dom", "src/ftxui/component", "src/ftxui/util"]
let ftxuiExcludes: [String] = ftxuiSourceDirs.flatMap { dir in
  ((try? FileManager.default.contentsOfDirectory(atPath: ftxuiRoot + "/" + dir)) ?? [])
    .filter { $0.hasSuffix("_test.cpp") || $0.hasSuffix("_fuzzer.cpp") || $0.hasSuffix("_benchmark.cpp") || $0 == "meson.build" }
    .map { dir + "/" + $0 }
} + [
  // Stale duplicate of the Loop implementation in app.cpp; not in FTXUI's CMake source list.
  "src/ftxui/component/loop.cpp"
]

let package = Package(
  name: "ftxui-bridge",
  platforms: [.macOS(.v26)],
  targets: [
    .target(
      name: "CFTXUI",
      path: "Vendor/FTXUI",
      exclude: ftxuiExcludes,
      sources: ftxuiSourceDirs,
      publicHeadersPath: "include",
      cxxSettings: [
        .headerSearchPath("src")
      ]
    ),
    .target(
      name: "VCBridge",
      dependencies: ["CFTXUI"]
    ),
    .executableTarget(
      name: "ftxui-spike",
      dependencies: ["VCBridge"]
    ),
  ],
  cxxLanguageStandard: .cxx20
)
