// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DuoWorkbench",
    platforms: [.macOS("15.2")],
    products: [.executable(name: "DuoWorkbench", targets: ["DuoWorkbench"])],
    targets: [.binaryTarget(name: "ChordeskTailnet", path: "build/tailnet/ChordeskTailnet.xcframework"),
        .executableTarget(name: "DuoWorkbench", dependencies: ["ChordeskTailnet"], path: "iPhoneDuoDemo",
        exclude: ["iPhoneDuoDemoApp.swift", "ContentView.swift", "Info.plist", "PrivacyInfo.xcprivacy", "Assets.xcassets"], resources: [.copy("Resources/Brand"), .copy("Resources/Legal")]),
        .testTarget(name: "DuoTransportTests", dependencies: ["DuoWorkbench"], path: "Tests/DuoTransportTests")]
)
