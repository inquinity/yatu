// swift-tools-version: 5.9
//
// Yatu — a Finder toolbar app that opens a terminal at the folder you are
// looking at. See docs/DESIGN.md.
//
// There is no Xcode project: `bin/build.sh` turns these products into .app
// bundles. The three files Yatu compiles from OpenInTerminal are vendored in
// Sources/YatuUpstream, each with a provenance header; see docs/UPSTREAM.md.

import PackageDescription

let package = Package(
    name: "Yatu",
    platforms: [
        // Settled in docs/DESIGN.md §8.2. Xcode's SDK floor is 12.0; 13.0 is
        // our choice, and buys .formStyle(.grouped) for the settings window.
        .macOS(.v13)
    ],
    products: [
        .executable(name: "YatuTerminal", targets: ["YatuTerminal"]),
        .executable(name: "YatuFinderSync", targets: ["YatuFinderSync"]),
        .library(name: "YatuKit", targets: ["YatuKit"]),
    ],
    targets: [
        // OpenInTerminal's app catalog and ScriptingBridge interfaces, compiled
        // unchanged. See the README in that directory for why our own model
        // types live there too.
        .target(name: "YatuUpstream", exclude: ["README.md"]),

        // Everything Yatu owns.
        .target(name: "YatuKit", dependencies: ["YatuUpstream"]),

        .executableTarget(name: "YatuTerminal", dependencies: ["YatuKit"]),

        // The Finder toolbar button. Built as an executable and assembled into
        // an .appex by bin/build.sh; it reports Finder's context and stops.
        .executableTarget(name: "YatuFinderSync", dependencies: ["YatuKit"],
                          linkerSettings: [.linkedFramework("FinderSync")]),

        .testTarget(name: "YatuTests", dependencies: ["YatuKit"]),
    ]
)
