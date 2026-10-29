// swift-tools-version:5.5
// Paket nur für die plattformunabhängige Z21-Protokollschicht, damit sie
// mit `swift test` (macOS oder Linux) ohne iPad geprüft werden kann.
// Die App selbst wird über ProfiFahrpult.xcodeproj gebaut.
import PackageDescription

let package = Package(
    name: "Z21Kit",
    platforms: [.macOS(.v10_13), .iOS(.v12)],
    products: [
        .library(name: "Z21Kit", targets: ["Z21Kit"])
    ],
    targets: [
        .target(name: "Z21Kit", path: "ProfiFahrpult/Z21"),
        .testTarget(name: "Z21KitTests", dependencies: ["Z21Kit"], path: "Tests/Z21KitTests")
    ]
)
