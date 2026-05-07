// swift-tools-version: 5.9
// MuPDFKit — local Swift Package wrapping libmupdf 1.27 (static build)
// Static libraries live in Sources/MuPDFCore/lib/ — no Homebrew dylib at runtime.

import PackageDescription

#if arch(arm64)
let brewPrefix = "/opt/homebrew"
#else
let brewPrefix = "/usr/local"
#endif

let staticLibDir = "/Users/jonasgunklach/Documents/XCode/Folio/MuPDFKit/Sources/MuPDFCore/lib"

let package = Package(
    name: "MuPDFKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MuPDFKit", targets: ["MuPDFKit"]),
    ],
    targets: [
        // ── C wrapper around libmupdf (statically linked) ──────────────────
        .target(
            name: "MuPDFCore",
            path: "Sources/MuPDFCore",
            exclude: ["lib"],
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-I\(brewPrefix)/include"]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "\(staticLibDir)/libmupdf.a",
                    "\(staticLibDir)/libmupdf-third.a",
                ]),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
        // ── Swift API ──────────────────────────────────────────────────────
        .target(
            name: "MuPDFKit",
            dependencies: ["MuPDFCore"],
            path: "Sources/MuPDFKit"
        ),
    ]
)
