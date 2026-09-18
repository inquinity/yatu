// swift-tools-version: 5.9
//
// Yatu — a Finder toolbar app that opens a terminal at the folder you are
// looking at. See docs/YATU-PLAN.md.
//
// There is no Xcode project: `bin/build.sh` turns these products into .app
// bundles. The upstream tree (OpenInTerminal*/, OpenInTerminalCore/, the
// .xcodeproj files) is left untouched and is not built by this package —
// except for the single upstream file compiled unchanged by YatuUpstream.

import PackageDescription

let package = Package(
    name: "Yatu",
    platforms: [
        // Settled in docs/YATU-PLAN.md §8.2. Xcode's SDK floor is 12.0; 13.0 is
        // our choice, and buys .formStyle(.grouped) for the settings window.
        .macOS(.v13)
    ],
    products: [
        .executable(name: "YatuTerminal", targets: ["YatuTerminal"]),
        .executable(name: "YatuEditor", targets: ["YatuEditor"]),
        .library(name: "YatuKit", targets: ["YatuKit"]),
    ],
    targets: [
        // Upstream's app catalog, compiled unchanged. See the README in that
        // directory for why our own model types live there too.
        .target(name: "YatuUpstream", exclude: ["README.md"]),

        // Everything Yatu owns.
        .target(name: "YatuKit", dependencies: ["YatuUpstream"]),

        .executableTarget(name: "YatuTerminal", dependencies: ["YatuKit"]),
        .executableTarget(name: "YatuEditor", dependencies: ["YatuKit"]),

        .testTarget(name: "YatuTests", dependencies: ["YatuKit"]),
    ]
)
