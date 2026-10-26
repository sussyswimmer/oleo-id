import CoreML
import CoreVideo
import Foundation

/// Spike D — how fast is a candidate Core ML face-embedding model, and on which
/// compute unit? (BRIEFS.md Brief 0, Spike D; ARCHITECTURE.md §5 and risk register.)
///
/// It compiles the model if needed, inspects the input description so it works for
/// both model shapes we're evaluating — AuraFace takes an `MLMultiArray [1,3,112,112]`,
/// MobileFaceNet takes a 112×112 image — builds a synthetic input of the right kind,
/// then for each `MLComputeUnits` option does a few warm-up runs followed by N timed
/// runs. It reports load time, median and p90 latency, the output dimension and the
/// output's L2 norm (so we can see whether the model already returns a unit vector).
///
/// Security rule 1: the embedding vector itself is never logged — only its length
/// and norm. The input is synthetic, so no real face is involved.
enum ModelSpike {
    static func run(modelPath: String, runs: Int, log: SpikeLog) {
        let src = URL(fileURLWithPath: (modelPath as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: src.path) else {
            log.log("Model not found at \(src.path). Run scripts/download-models.sh first."); exit(4)
        }
        log.log("Spike D: model=\(src.lastPathComponent)  runs=\(runs)")

        // Compile .mlmodel / .mlpackage to a temporary .mlmodelc; pass .mlmodelc through.
        let compiled: URL
        if src.pathExtension == "mlmodelc" {
            compiled = src
        } else {
            do {
                compiled = try MLModel.compileModel(at: src)
                log.log("compiled to \(compiled.lastPathComponent)")
            } catch {
                log.log("compileModel failed: \(error.localizedDescription)"); exit(4)
            }
        }

        let units: [(String, MLComputeUnits)] = [
            ("cpuOnly", .cpuOnly),
            ("cpuAndGPU", .cpuAndGPU),
            ("cpuAndNeuralEngine", .cpuAndNeuralEngine),
            ("all", .all),
        ]

        for (name, unit) in units {
            let config = MLModelConfiguration()
            config.computeUnits = unit

            let loadStart = DispatchTime.now()
            let model: MLModel
            do {
                model = try MLModel(contentsOf: compiled, configuration: config)
            } catch {
                log.log("[\(name)] load failed: \(error.localizedDescription)")
                continue
            }
            let loadMs = ms(since: loadStart)

            guard let provider = makeInput(for: model, log: log) else {
                log.log("[\(name)] could not build a synthetic input for this model's signature."); return
            }

            // Warm up (first prediction includes one-time graph/ANE setup).
            for _ in 0..<5 { _ = try? model.prediction(from: provider) }

            var samples: [Double] = []
            samples.reserveCapacity(runs)
            var lastOut: MLFeatureProvider?
            for _ in 0..<runs {
                let t = DispatchTime.now()
                guard let out = try? model.prediction(from: provider) else {
                    log.log("[\(name)] prediction failed."); break
                }
                samples.append(ms(since: t))
                lastOut = out
            }
            guard !samples.isEmpty else { continue }
            samples.sort()
            let median = samples[samples.count / 2]
            let p90 = samples[min(samples.count - 1, Int(Double(samples.count) * 0.9))]
            let (dim, norm) = describeOutput(lastOut)
            log.log(String(format: "[%@] load=%.1fms  median=%.2fms  p90=%.2fms  min=%.2fms  outDim=%d  outL2=%.4f",
                           name, loadMs, median, p90, samples.first ?? 0, dim, norm))
        }
        log.log("Spike D complete. Record the fastest acceptable compute unit and model in docs/spike-results.md.")
        log.log("Note: .cpuAndNeuralEngine / .all may silently fall back to CPU/GPU if the model can't map to the ANE — compare the numbers, don't assume the ANE ran.")
    }

    // MARK: - Synthetic input

    private static func makeInput(for model: MLModel, log: SpikeLog) -> MLFeatureProvider? {
        var features: [String: Any] = [:]
        for (name, desc) in model.modelDescription.inputDescriptionsByName {
            switch desc.type {
            case .multiArray:
                guard let c = desc.multiArrayConstraint,
                      let array = try? MLMultiArray(shape: c.shape, dataType: c.dataType) else {
                    return nil
                }
                // Fill with 0.0 — a valid value in AuraFace's (pixel/127.5)-1 range.
                // Content is irrelevant to latency.
                let count = array.count
                for i in 0..<count { array[i] = 0 }
                features[name] = MLFeatureValue(multiArray: array)
                log.log("input \"\(name)\": multiArray shape=\(c.shape) dtype=\(c.dataType.rawValue)")
            case .image:
                guard let c = desc.imageConstraint,
                      let pixels = grayPixelBuffer(width: c.pixelsWide, height: c.pixelsHigh,
                                                   format: c.pixelFormatType) else {
                    return nil
                }
                features[name] = MLFeatureValue(pixelBuffer: pixels)
                log.log("input \"\(name)\": image \(c.pixelsWide)x\(c.pixelsHigh) format=\(c.pixelFormatType)")
            default:
                log.log("input \"\(name)\": unsupported type \(desc.type.rawValue)")
                return nil
            }
        }
        return try? MLDictionaryFeatureProvider(dictionary: features)
    }

    private static func grayPixelBuffer(width: Int, height: Int, format: OSType) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs: [String: Any] = [kCVPixelBufferCGImageCompatibilityKey as String: true]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, format,
                                  attrs as CFDictionary, &pb) == kCVReturnSuccess,
              let buffer = pb else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let bytes = CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer)
            memset(base, 128, bytes) // mid-gray
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    // MARK: - Output stats (never logs the vector itself)

    private static func describeOutput(_ provider: MLFeatureProvider?) -> (dim: Int, l2: Double) {
        guard let provider,
              let name = provider.featureNames.first(where: {
                  provider.featureValue(for: $0)?.multiArrayValue != nil
              }),
              let array = provider.featureValue(for: name)?.multiArrayValue else {
            return (0, 0)
        }
        var sumSq = 0.0
        for i in 0..<array.count {
            let v = array[i].doubleValue
            sumSq += v * v
        }
        return (array.count, sumSq.squareRoot())
    }

    private static func ms(since start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }
}
