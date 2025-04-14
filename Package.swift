// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MapToSDK",
    platforms: [.iOS(.v16)],
    products: [
        .library(
            name: "MapToSDK",
            targets: ["MapToSDK"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/mapbox/mapbox-maps-ios.git",
            from: "11.11.0"
        )
    ],
    targets: [
        .target(
            name: "MapToSDK",
            dependencies: [
                .product(name: "MapboxMaps", package: "mapbox-maps-ios")
            ]
        ),
    ]
)
