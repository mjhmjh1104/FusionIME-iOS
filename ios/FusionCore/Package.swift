// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "FusionCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "FusionCore", targets: ["FusionCore"])],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "CPinyin", publicHeadersPath: "Public"),
        .target(name: "CLatin", publicHeadersPath: "Public", cxxSettings: [.headerSearchPath("Engine")]),
        .binaryTarget(name: "CChewing", path: "Native/CChewing.xcframework"),
        .binaryTarget(name: "CMozc", path: "Native/CMozc.xcframework"),
        .target(name: "FusionCore", dependencies: ["CSQLite", "CPinyin", "CLatin", "CChewing", "CMozc"], resources: [.copy("Resources")], linkerSettings: [.linkedLibrary("c++"), .linkedLibrary("iconv"), .linkedLibrary("z"), .linkedFramework("Security"), .linkedFramework("Foundation"), .linkedFramework("UIKit",.when(platforms:[.iOS])), .linkedFramework("AppKit",.when(platforms:[.macOS])), .linkedFramework("IOKit",.when(platforms:[.macOS])), .linkedFramework("CoreServices",.when(platforms:[.macOS])), .linkedFramework("CoreGraphics",.when(platforms:[.macOS]))]),
        .testTarget(name: "FusionCoreTests", dependencies: ["FusionCore"],resources:[.copy("Fixtures")])
    ],
    cxxLanguageStandard: .cxx17
)
