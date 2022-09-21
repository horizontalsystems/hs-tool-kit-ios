// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "HsToolKit",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(
            name: "HsToolKit",
            targets: ["HsToolKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", .upToNextMajor(from: "5.6.1")),
        .package(url: "https://github.com/ReactiveX/RxSwift.git", .exact("6.5.0")),
        .package(url: "https://github.com/tristanhimmelman/ObjectMapper.git", .upToNextMajor(from: "4.1.0")),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.0.0"),

    ],
    targets: [
        .target(
            name: "HsToolKit",
            dependencies: [
                "Alamofire",
                "RxSwift",
                "ObjectMapper",
                .product(name: "NIOWebSocket", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
            ]),
    ]
)
