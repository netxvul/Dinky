// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "kex",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/dduan/TOMLDecoder", exact: "0.4.4"),
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
    ],
    targets: [
        // Private SkyLight and CGS calls. Objective-C, capability checked, nothing else lives here.
        .target(
            name: "KexPrivate",
            // The scripting addition (osax/payload.m, osax/loader.m) is built and injected into Dock separately,
            // by scripts/build-sa.sh; only its wire protocol (osax/common.h) is shared with the client here.
            exclude: ["osax/payload.m", "osax/loader.m"],
            linkerSettings: [
                .unsafeFlags(["-F/System/Library/PrivateFrameworks", "-framework", "SkyLight"]),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
            ]
        ),
        // Pure layout engine: trees, rectangles, no AppKit. Fully unit tested.
        .target(
            name: "KexLayout",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "KexLayoutTests",
            dependencies: ["KexLayout"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The command vocabulary shared by bindings, CLI and menu: parsing and reference. Unit tested.
        .target(
            name: "KexCommands",
            dependencies: ["KexLayout", "KexConfig"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "KexCommandsTests",
            dependencies: ["KexCommands", "KexConfig", .product(name: "TOMLDecoder", package: "TOMLDecoder")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Config types and TOML loading. No AppKit; Carbon.HIToolbox for the key codes only. Unit tested.
        .target(
            name: "KexConfig",
            dependencies: [.product(name: "TOMLDecoder", package: "TOMLDecoder")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "KexConfigTests",
            dependencies: ["KexConfig"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The app and CLI.
        .executableTarget(
            name: "kex",
            dependencies: [
                "KexPrivate", "KexLayout", "KexConfig", "KexCommands",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)],
            // The app bundle carries Sparkle.framework in Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
    ]
)
