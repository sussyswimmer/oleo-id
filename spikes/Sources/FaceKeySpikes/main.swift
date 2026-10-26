import Foundation

// FaceKeySpikes — Brief 0 feasibility spikes (see ../BRIEFS.md).
// In Swift 6, top-level code in main.swift is MainActor-isolated, so we can call
// the @MainActor CameraSpike directly here.
//
// Usage:
//   FaceKeySpikes camera [--now | --on-wake] [--seconds 3]
//   FaceKeySpikes model  --path <model.mlpackage> [--runs 100]
//
// Spikes B (lock state), C (typing) and E (overlay) are not implemented in this
// package — they touch the lock screen and are run separately. See docs/spike-results.md.

func value(_ flag: String, in args: [String]) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func printUsageAndExit() -> Never {
    FileHandle.standardError.write(Data("""
    FaceKeySpikes — Brief 0 feasibility spikes

      camera [--now | --on-wake] [--seconds N]   Spike A: frames on wake / while locked
      model  --path <model> [--runs N]           Spike D: Core ML latency per compute unit

    Examples:
      FaceKeySpikes camera --now --seconds 3
      FaceKeySpikes camera --on-wake
      FaceKeySpikes model --path ../Models/auraface_v1.mlpackage --runs 100

    """.utf8))
    exit(64) // EX_USAGE
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { printUsageAndExit() }

switch command {
case "camera":
    let seconds = Double(value("--seconds", in: args) ?? "") ?? 3.0
    let log = SpikeLog(spike: "camera")
    log.log("FaceKeySpikes camera — log: \(log.path)")
    let spike = CameraSpike(log: log)
    if args.contains("--on-wake") {
        spike.runOnWake(seconds: seconds)
    } else {
        spike.runNow(seconds: seconds)
    }
    // Service DispatchQueue.main timers and NSWorkspace notifications.
    RunLoop.main.run()

case "model":
    guard let path = value("--path", in: args) else {
        FileHandle.standardError.write(Data("model: --path <model> is required\n".utf8))
        printUsageAndExit()
    }
    let runs = Int(value("--runs", in: args) ?? "") ?? 100
    let log = SpikeLog(spike: "model")
    log.log("FaceKeySpikes model — log: \(log.path)")
    ModelSpike.run(modelPath: path, runs: runs, log: log)
    exit(0)

case "-h", "--help", "help":
    printUsageAndExit()

default:
    FileHandle.standardError.write(Data("Unknown command: \(command)\n".utf8))
    printUsageAndExit()
}
