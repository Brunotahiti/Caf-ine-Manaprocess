// swift-tools-version: 5.9
import PackageDescription

var targets: [Target] = [
    .target(name: "CafeineCore"),
    .testTarget(name: "CafeineCoreTests", dependencies: ["CafeineCore"]),
]

// L'application dépend de SwiftUI et d'IOKit : elle n'existe que sous macOS.
// Le cœur et ses tests se compilent aussi sous Linux.
#if os(macOS)
targets.append(.executableTarget(name: "Cafeine", dependencies: ["CafeineCore"]))
#endif

let package = Package(
    name: "Cafeine",
    platforms: [.macOS(.v13)],
    targets: targets
)
