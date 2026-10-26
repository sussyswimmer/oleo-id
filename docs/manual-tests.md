# Manual tests

Things that can't be unit-tested (camera, lock screen, Core ML on real hardware)
are verified by hand and recorded here. One section per brief.

## Brief 0 — feasibility spikes

Prerequisites: a Mac with a camera, macOS 15+, Xcode / Swift 6 toolchain.

### Spike A — camera frames on wake / while locked  *(implemented)*

1. `cd spikes && ./build-app.sh`
   - Expect: builds `FaceKeySpikes.app`, signs with "FaceKey Dev" if present
     (else ad-hoc with a warning).
2. `open FaceKeySpikes.app --args camera --now --seconds 3`
   - First run: approve the Camera prompt.
   - Expect in `~/Library/Logs/FaceKeySpikes/camera-<date>.log`: a non-zero
     frame count, a time-to-first-frame, mean luma well above 0, and the camera
     light turning off within ~1 s of the "stopRunning() returned" line.
3. `open FaceKeySpikes.app --args camera --on-wake` (leave it running)
   - Lock the screen (Ctrl-Cmd-Q) or let the display sleep; wait a few seconds;
     wake it. Repeat a couple of times. Ctrl-C to stop.
   - Expect: a `screensDidWakeNotification` block per wake, with frames counted
     while the screen was locked. **Zero frames or near-black frames is the
     important negative result** — record it in `spike-results.md`.
4. Confirm no image files appear anywhere (the spike never writes frames to disk).

### Spike D — Core ML model latency  *(implemented)*

1. `scripts/download-models.sh`
   - Expect: `Models/auraface_v1.mlpackage` and `Models/mobilefacenet.mlpackage`,
     each file "verified" against its SHA-256.
2. `cd spikes && swift run -c release FaceKeySpikes model --path ../Models/auraface_v1.mlpackage --runs 100`
   then the same for `../Models/mobilefacenet.mlpackage`.
   - Expect: a line per compute unit (`cpuOnly`, `cpuAndGPU`,
     `cpuAndNeuralEngine`, `all`) with load time, median/p90 latency, output
     dim (512 for AuraFace, 128 for MobileFaceNet) and output L2 norm.
3. Copy the numbers into `spike-results.md` and note the fastest acceptable config.

### Spikes B, C, E — not covered in this session

Lock-state detection (B), typing into the lock screen (C) and the lock-screen
overlay (E) are run separately — they are the lock-screen-touching risks. See
`spike-results.md` for what each must show. **Do not proceed past Brief 1 into
the typing work (Brief 5) until B and C pass.**

### Security checks for this brief

- `grep -ri password spikes/ scripts/` → no password handling exists yet (there
  is none to leak at this stage).
- Confirm the spikes write only to `~/Library/Logs/FaceKeySpikes/` and never
  write image/frame data.
