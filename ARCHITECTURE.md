# ARCHITECTURE — FaceKey

## 1. Big picture

```
 screen wakes / locks
        │
        ▼
 TriggerMonitor ──► LockGate (is the screen really locked?) ──no──► stop
        │ yes
        ▼
 CameraService (AVCaptureSession, front camera, frames in memory)
        │
        ▼
 FacePipeline: Vision detect + landmarks + pose ──► align 112×112 crop
        │                                              │
        ▼                                              ▼
 LivenessChecker (blink / movement / quality)    EmbeddingModel (Core ML, 512-d)
        │                                              │
        └───────────────┬──────────────────────────────┘
                        ▼
                 Matcher (cosine similarity vs enrolled templates, threshold)
                        │ match
                        ▼
                 SecretStore ──► password (Touch ID–gated) ──► PasswordTyper (CGEvent)
                        │
                        ▼
                 OverlayController (notch animation, optional)
```

## 2. Modules

| Module | Responsibility | Key APIs |
|---|---|---|
| `App` | Menu bar app, lifecycle, settings window | `NSStatusItem` or SwiftUI `MenuBarExtra`, `LSUIElement`, `SMAppService` |
| `TriggerMonitor` | Detect wake/lock/unlock events | `NSWorkspace.shared.notificationCenter` (`screensDidWakeNotification`, `willSleepNotification`); `DistributedNotificationCenter` for `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` (undocumented but widely used) |
| `LockGate` | Single source of truth: "screen is locked right now" | `CGSessionCopyCurrentDictionary()` key `CGSSessionScreenIsLocked`, cross-checked with the distributed notifications. Default to NOT locked when unsure. |
| `CameraService` | Start/stop capture per scan, deliver frames | `AVCaptureSession`, `AVCaptureVideoDataOutput`; built-in front camera; stop immediately after a scan |
| `FacePipeline` | Detect face, landmarks, pose, quality; align to 112×112 | `VNDetectFaceRectanglesRequest`, `VNDetectFaceLandmarksRequest`, `VNDetectFaceCaptureQualityRequest` |
| `EmbeddingModel` | Face crop → 512-d vector | Core ML model, L2-normalise output |
| `Matcher` | Compare to enrolled templates | cosine similarity, configurable threshold, best-of-N frames |
| `LivenessChecker` | Reject static photos | blink via eye aspect ratio from landmarks, small head-pose change, quality/texture heuristics |
| `Enrollment` | Guided capture of several poses/conditions into profiles | reuses `FacePipeline` + `EmbeddingModel` |
| `SecretStore` | Encrypt/decrypt password and templates | CryptoKit AES-GCM; key in Keychain; Touch ID via `LocalAuthentication` / `SecAccessControl` |
| `PasswordTyper` | Type the password into the lock screen | `CGEvent` keyboard events with `keyboardSetUnicodeString`, posted to the HID event tap; needs Accessibility (`AXIsProcessTrusted`) |
| `OverlayController` | Notch scan animation | borderless `NSPanel` positioned using `NSScreen.auxiliaryTopLeftArea/auxiliaryTopRightArea`/`safeAreaInsets`; window level must be high enough to show over the lock screen (verify in spike) |
| `Settings` | Threshold, triggers, animation on/off, delete data | `UserDefaults` for non-secrets |

## 3. Scan state machine
`idle → triggered → gated (lock check) → capturing → detecting → (liveness) → matching → typing → done`
Any failure or timeout returns to `idle` with no side effects. One automatic retry max. After N consecutive failures within a window, pause face unlock for a cooldown (password still works).

## 4. Data and secrets
- Templates: array of 512-d float vectors per profile, encrypted with AES-GCM. Key stored in Keychain (device-only, not synced).
- Password: encrypted the same way. Decryption gated by Touch ID. Default design (OPEN QUESTION 1): authenticate once per login session, keep the decrypted password in memory only, wipe on logout/quit. Verify the app can still use it after the screen locks within the same session.
- Nothing else is persisted. No photos, no frames.

## 5. Face model choice (OPEN QUESTION 2)
Apple's Vision framework gives face rectangles, landmarks and pose, but no public identity embedding (its whole-image feature print is not identity-tuned). So we need our own embedding model.

| Option | Notes |
|---|---|
| AuraFace-v1 (Core ML conversion exists on Hugging Face, e.g. `TechnoThinker/visuals-models-open`) | ArcFace-style ResNet100, 112×112 in, 512-d out; upstream card says trained for commercial use. Cleanest licence. Larger model. |
| MobileFaceNet Core ML (e.g. `xprilion/photoment-models`) | 128-d, small and fast. Check its licence/provenance before relying on it. |
| InsightFace ArcFace (`w600k_r50`) | Strong, but weights are non-commercial/research. Acceptable for strictly personal use; do not ship it. |

Default recommendation: AuraFace-v1 for licence cleanliness, benchmark against MobileFaceNet for speed. Pre/post-processing must match the model card exactly (AuraFace: RGB, `(pixel/127.5)-1`, then L2-normalise the output).

## 6. Permissions
- Camera (`NSCameraUsageDescription`).
- Accessibility (CGEvent typing). Input Monitoring may be requested depending on how events are posted; test both.
- Login item via `SMAppService.mainApp`.
- Keep the signing identity stable or macOS will re-prompt.

## 7. Risk register (verify in Brief 0 before building more)
| Risk | Why it matters | How we find out |
|---|---|---|
| Camera frames available while the screen is locked / just woken | Without frames there is no face to recognise | Spike: start a session on `screensDidWakeNotification` and log frame counts |
| Typing into the lock screen works | The whole unlock depends on it | Spike: post a harmless test string, then a real unlock on a test account |
| Overlay visible above the lock screen | Only affects the animation (P2) | Spike: show a panel at several window levels |
| Lock-state detection is reliable | Safety gate for typing the password | Spike: log `CGSSessionScreenIsLocked` and notifications across lock/wake/sleep/external display |
| Model latency | Must feel instant | Benchmark on the owner's Mac, Neural Engine vs CPU |
| macOS updates break behaviour | Undocumented notifications, Accessibility rules | Keep the gate conservative; fail closed |

Existing apps (Hey Mac, Mac ID, FaceUnlock) report doing camera + Accessibility typing on current macOS, so this is expected to work, but confirm it on the owner's exact macOS version.

## 8. Repo layout
```
FaceKey/
  FaceKey.xcodeproj
  App/ Trigger/ Camera/ Face/ Liveness/ Secrets/ Typing/ Overlay/ Settings/
  Models/            (Core ML model, not committed if large; script downloads it)
  Tests/
  scripts/install.sh
  docs/manual-tests.md
  CLAUDE.md PRD.md ARCHITECTURE.md BRIEFS.md
```
