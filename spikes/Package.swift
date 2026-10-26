// swift-tools-version: 6.0
import PackageDescription

// FaceKeySpikes — throwaway Brief 0 feasibility spikes. See ../BRIEFS.md "Brief 0".
// Not part of the shipping app; kept in the repo as evidence for the GO/NO-GO decision.
//
// The executable embeds an Info.plist into its __TEXT,__info_plist section so a
// plain command-line binary can carry NSCameraUsageDescription. For camera
// permission to bind to a stable identity (and not to Terminal), run the signed
// .app produced by build-app.sh rather than the bare binary — see that script.
let package = Package(
    name: "FaceKeySpikes",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "FaceKeySpikes",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Resources/Info.plist",
                ])
            ]
        )
    ]
)
