// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DuoWorkbench",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DuoWorkbench", targets: ["DuoWorkbench"])],
    targets: [.executableTarget(name: "DuoWorkbench", path: "iPhoneDuoDemo",
        exclude: ["iPhoneDuoDemoApp.swift", "ContentView.swift", "Info.plist", "Assets.xcassets"], resources: [.copy("Resources/Brand")]),
        .testTarget(name: "DuoTransportTests", dependencies: ["DuoWorkbench"], path: "Tests/DuoTransportTests")]
)
