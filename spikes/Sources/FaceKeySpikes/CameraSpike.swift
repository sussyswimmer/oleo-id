import AVFoundation
import AppKit
import CoreImage
import CoreMedia
import CoreVideo
import Vision

/// Spike A — does the camera deliver usable frames while the screen is locked or
/// just woken? (BRIEFS.md Brief 0, Spike A; ARCHITECTURE.md risk register row 1.)
///
/// It starts an `AVCaptureSession` on the built-in front camera, counts frames for
/// a fixed window, and for a sample of them runs a Vision face-rectangle request so
/// we know the frames are not just arriving but are actually usable for detection.
/// It records time-to-first-frame, frame count, mean luma (to catch all-black
/// frames some Macs emit briefly after wake) and teardown time.
///
/// Frames are summarised to scalars and dropped immediately. Nothing is written to
/// disk (CLAUDE.md security rule 2).
@MainActor
final class CameraSpike {
    private let log: SpikeLog
    // AVCaptureSession is not Sendable. It is configured on the main actor and
    // then only started/stopped on `sessionQueue`, never concurrently, so we opt
    // out of Sendable checking for it and uphold that discipline by hand.
    nonisolated(unsafe) private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let collector: FrameCollector
    private let sampleQueue = DispatchQueue(label: "dev.facekey.spikes.camera.frames")
    // start/stopRunning block and must NOT run on the sample-buffer queue, or
    // stopRunning can deadlock waiting for that queue to drain.
    private let sessionQueue = DispatchQueue(label: "dev.facekey.spikes.camera.session")
    private var started = false

    init(log: SpikeLog) {
        self.log = log
        self.collector = FrameCollector(log: log)
    }

    /// Run once immediately and then exit.
    func runNow(seconds: Double) {
        log.log("Spike A: run-now, window \(seconds)s")
        requestAccessThenCapture(seconds: seconds) {
            exit(0)
        }
    }

    /// Arm on `screensDidWakeNotification` and capture each time the screen wakes.
    /// Stays resident so the owner can sleep/wake the display repeatedly; Ctrl-C to stop.
    func runOnWake(seconds: Double) {
        log.log("Spike A: armed for screensDidWakeNotification, window \(seconds)s. Sleep then wake the display. Ctrl-C to stop.")
        // Pre-authorise so the first wake doesn't stall on a permission prompt.
        requestAccess { granted in
            if !granted { self.log.log("Camera access denied — grant it in System Settings > Privacy & Security > Camera, then relaunch."); exit(2) }
        }
        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.log.log("--- screensDidWakeNotification ---")
            MainActor.assumeIsolated {
                self.capture(seconds: seconds, completion: {})
            }
        }
        // Also note sleep, purely for correlating the timeline in the log.
        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.log.log("--- screensDidSleepNotification ---") }
    }

    // MARK: - Capture

    private func requestAccess(_ completion: @escaping @Sendable (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { completion($0) }
        default:
            completion(false)
        }
    }

    private func requestAccessThenCapture(seconds: Double, completion: @escaping @Sendable () -> Void) {
        requestAccess { granted in
            Task { @MainActor in
                guard granted else {
                    self.log.log("Camera access denied — grant it in System Settings > Privacy & Security > Camera, then relaunch.")
                    exit(2)
                }
                self.capture(seconds: seconds, completion: completion)
            }
        }
    }

    private func configureIfNeeded() {
        guard !started else { return }
        started = true

        session.beginConfiguration()
        session.sessionPreset = .vga640x480

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .front
        )
        let device = discovery.devices.first { $0.position == .front }
            ?? discovery.devices.first
            ?? AVCaptureDevice.default(for: .video)

        guard let device else {
            log.log("No camera device found."); exit(3)
        }
        log.log("camera: \(device.localizedName) [\(device.deviceType.rawValue)]")

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
        } catch {
            log.log("Could not open camera input: \(error.localizedDescription)"); exit(3)
        }

        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(collector, queue: sampleQueue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
    }

    private func capture(seconds: Double, completion: @escaping @Sendable () -> Void) {
        configureIfNeeded()
        let t0 = DispatchTime.now()
        // reset runs on the frame queue before any frame block can be enqueued
        // (frames only start after startRunning, which runs on the session queue).
        sampleQueue.async { self.collector.reset() }
        sessionQueue.async { self.session.startRunning() }
        log.log("session.startRunning() requested")

        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            self.sessionQueue.async {
                let tStop = DispatchTime.now()
                self.session.stopRunning()
                let teardown = Double(DispatchTime.now().uptimeNanoseconds - tStop.uptimeNanoseconds) / 1_000_000
                // Read the final counters on the frame queue, after the last
                // delegate callback has drained, so the snapshot is consistent.
                self.sampleQueue.async {
                    self.collector.report(windowSeconds: seconds, sinceStartNanos: t0.uptimeNanoseconds)
                    self.log.log(String(format: "stopRunning() returned in %.1f ms (camera light should be off now)", teardown))
                    self.log.log("Spike A window complete.")
                    DispatchQueue.main.async { completion() }
                }
            }
        }
    }
}

/// Receives sample buffers off the capture queue, derives scalar stats, drops the pixels.
/// `@unchecked Sendable`: every mutable field is only touched from the single serial
/// `sampleQueue` the delegate is installed on, plus a final `report(...)` call made
/// after `stopRunning()` has returned (no more delegate callbacks can race it).
final class FrameCollector: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let log: SpikeLog
    private let ciContext = CIContext(options: [.workingColorSpace: NSNull()])

    private var frames = 0
    private var firstFrameNanos: UInt64?
    private var lumaSum = 0.0
    private var lumaSamples = 0
    private var facesSeen = 0
    private var faceChecks = 0

    init(log: SpikeLog) { self.log = log; super.init() }

    func reset() {
        frames = 0; firstFrameNanos = nil
        lumaSum = 0; lumaSamples = 0
        facesSeen = 0; faceChecks = 0
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        frames += 1
        if firstFrameNanos == nil { firstFrameNanos = DispatchTime.now().uptimeNanoseconds }

        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Mean luma on a sample of frames, to catch all-black frames after wake.
        if frames % 3 == 0 {
            if let luma = meanLuma(pixels) { lumaSum += luma; lumaSamples += 1 }
        }

        // Vision face check on a sparser sample — confirms the frames are usable,
        // not merely present.
        if frames % 5 == 0 {
            faceChecks += 1
            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up)
            try? handler.perform([request])
            if let results = request.results, !results.isEmpty { facesSeen += 1 }
        }
        // `pixels`/`sampleBuffer` go out of scope here — nothing retained, nothing stored.
    }

    private func meanLuma(_ pixels: CVPixelBuffer) -> Double? {
        let image = CIImage(cvPixelBuffer: pixels)
        let extent = image.extent
        guard !extent.isInfinite else { return nil }
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image,
            kCIInputExtentKey: CIVector(cgRect: extent),
        ])
        guard let out = filter?.outputImage else { return nil }
        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(out,
                         toBitmap: &bitmap,
                         rowBytes: 4,
                         bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                         format: .RGBA8,
                         colorSpace: nil)
        // Rec. 601 luma from the 1x1 average.
        return 0.299 * Double(bitmap[0]) + 0.587 * Double(bitmap[1]) + 0.114 * Double(bitmap[2])
    }

    func report(windowSeconds: Double, sinceStartNanos: UInt64) {
        let ttf: String
        if let first = firstFrameNanos {
            ttf = String(format: "%.1f ms", Double(first - sinceStartNanos) / 1_000_000)
        } else {
            ttf = "no frame"
        }
        let fps = windowSeconds > 0 ? Double(frames) / windowSeconds : 0
        let meanLuma = lumaSamples > 0 ? lumaSum / Double(lumaSamples) : 0
        log.log(String(format: "frames=%d  fps≈%.1f  time-to-first-frame=%@  meanLuma(0-255)=%.1f  faceChecks=%d facesSeen=%d",
                       frames, fps, ttf, meanLuma, faceChecks, facesSeen))
        if frames == 0 {
            log.log("RESULT: NO frames while screen was locked/asleep — Spike A would be a FAIL on this Mac.")
        } else if lumaSamples > 0 && meanLuma < 5 {
            log.log("RESULT: frames arrived but are near-black (meanLuma<5) — camera may be blocked while locked. Inspect.")
        } else {
            log.log("RESULT: usable frames arrived. Record this in docs/spike-results.md (Spike A).")
        }
    }
}
