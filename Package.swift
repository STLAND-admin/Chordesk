// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Chordesk",
    platforms: [.macOS("15.2")],
    products: [.executable(name: "ChordeskHost", targets: ["ChordeskHost"])],
    targets: [.binaryTarget(name: "ChordeskTailnet", path: "build/tailnet/ChordeskTailnet.xcframework"),
        .executableTarget(name: "ChordeskHost", dependencies: ["ChordeskTailnet"], path: "ProjectFiles/Chordesk",
        exclude: ["ChordeskApp.swift", "ContentView.swift", "Info.plist", "PrivacyInfo.xcprivacy", "Assets.xcassets"], resources: [.copy("Resources/Brand"), .copy("Resources/Legal")]),
        .testTarget(name: "ChordeskHostTests", dependencies: ["ChordeskHost"], path: "ProjectFiles/Tests/ChordeskHostTests")]
)
