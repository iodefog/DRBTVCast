// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DRBTVCast",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "DRBTVCast", targets: ["DRBTVCast"])
    ],
    dependencies: [
        .package(url: "https://github.com/googlecast/google-cast-ios-sdk", from: "4.8.6")
    ],
    targets: [
        .target(
            name: "DRBTVCast",
            dependencies: [
                .product(name: "GoogleCastDynamic", package: "google-cast-ios-sdk")
            ],
            path: "DRBTVCast/Classes"
        )
    ]
)
