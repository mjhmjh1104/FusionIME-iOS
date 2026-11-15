// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PortAudit",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../../FusionCore")],
    targets: [.executableTarget(name: "PortAudit", dependencies: [.product(name: "FusionCore", package: "FusionCore")])]
)
