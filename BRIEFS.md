# BRIEFS — paste one at a time into Claude Code

Read `CLAUDE.md`, `PRD.md` and `ARCHITECTURE.md` first. Do the briefs in order. After each one: summarise what changed, update `docs/manual-tests.md`, then stop and wait unless told to continue.

---

## Brief 0 — Feasibility spikes (GO / NO-GO)

**Goal:** prove the four risky things work on this Mac and macOS version before building the app.

**Tasks**
1. Create a throwaway command-line or tiny menu bar target `Spikes` (kept in the repo under `spikes/`).
2. Spike A, camera on wake: on `NSWorkspace.screensDidWakeNotification` and on the `com.apple.screenIsLocked` distributed notification, start an `AVCaptureSession` and log how many frames arrive in 3 seconds, with the screen locked.
3. Spike B, lock state: log `CGSessionCopyCurrentDictionary()["CGSSessionScreenIsLocked"]` plus the distributed notifications through: lock via menu, lid/display sleep and wake, external display connected. Report whether the value is reliable.
4. Spike C, typing: with Accessibility granted, post a harmless test string via `CGEvent` while the screen is locked and report whether it reaches the password field. Then, on a throwaway local test account only (not the owner's main account), try a real password and Return.
5. Spike D, model speed: load the candidate Core ML face model (see ARCHITECTURE.md section 5), embed a static image 100 times, report median latency on Neural Engine vs CPU.
6. Optional Spike E: show an `NSPanel` at the notch at several window levels and report which are visible over the lock screen.

**Acceptance:** a short `docs/spike-results.md` with a pass/fail and evidence for A–D (E optional), and a recommendation. Stop here and ask the owner before Brief 1 if any of A–C fail.

---

## Brief 1 — App skeleton and permissions

**Goal:** a signed menu bar app that requests and displays permission state.

**Tasks**
- Xcode project `FaceKey`, `LSUIElement`, status item with menu: Enabled toggle, Settings…, Quit.
- Settings window (SwiftUI) with a Permissions section: Camera and Accessibility status, buttons that open the right System Settings panes.
- `scripts/install.sh`: build, sign with the stable self-signed cert, copy to `/Applications`, relaunch.
- Start-at-login toggle via `SMAppService`.

**Acceptance:** app launches with no Dock icon; permission states update live; rebuilding does not reset granted permissions.

---

## Brief 2 — Camera and face pipeline

**Goal:** reliable face detection, alignment and a live debug preview.

**Tasks**
- `CameraService` (start/stop, frame delivery, front camera selection, clean teardown).
- `FacePipeline`: Vision detect + landmarks + pose + quality; choose the largest/most central face; 5-point similarity-transform alignment to a 112×112 crop.
- Debug window showing the preview, bounding box, landmarks and pose (debug builds only).
- Unit tests for the alignment math with fixture landmarks.

**Acceptance:** stable detection at normal laptop distance; camera light turns off within 1 s of stopping; no frame ever written to disk.

---

## Brief 3 — Embedding, enrolment and matching

**Goal:** enrol the owner and recognise them offline.

**Tasks**
- `EmbeddingModel` wrapping the chosen Core ML model with exact preprocessing; L2-normalised 512-d output. Model download script in `scripts/` (not committed if large).
- Guided `Enrollment` flow: centre, left, right, up, down, plus a "with glasses" / "different lighting" re-enrol option; multiple profiles.
- `SecretStore` v1 for templates only: AES-GCM, Keychain key.
- `Matcher`: cosine similarity vs all templates, best-of-N frames, configurable threshold; debug screen showing live score.
- Unit tests for matcher and encryption round-trip.

**Acceptance:** owner scores clearly above threshold, 3 other people clearly below, in normal and dim light; templates on disk are unreadable without the key; "Delete face data" works.

**OPEN QUESTION to ask me:** which model won the benchmark and what threshold to default to.

---

## Brief 4 — Liveness

**Goal:** reject a static photo cheaply.

**Tasks**
- `LivenessChecker` with selectable levels: Off, Basic (quality/texture + small natural movement), Strict (also requires a blink or slight head turn).
- Blink detection via eye aspect ratio from landmarks, with smoothing and tests on recorded landmark fixtures.
- Report in the debug screen which check passed or failed.

**Acceptance:** a printed photo and a photo on a phone screen are rejected 10/10 at Basic or Strict; normal use passes without feeling slow. Document plainly in the UI that video replays may still pass.

---

## Brief 5 — Password and typing

**Goal:** store the password safely and type it only on the lock screen.

**Tasks**
- Settings → Password: enter once (secure field), store encrypted. Implement the decision from PRD OPEN QUESTION 1 (default: Touch ID once per login session, held in memory, wiped on quit/logout). "Delete password" button.
- `LockGate` as in ARCHITECTURE.md: fail closed.
- `PasswordTyper` using `CGEvent` unicode string events, then Return; small randomised inter-key delay; never log the string.
- Tests with a fake typer to prove the gate blocks typing when unlocked or unknown.

**Acceptance:** with the screen locked, typing works; with the screen unlocked, a forced trigger types nothing; grep of the repo and logs finds no password strings.

---

## Brief 6 — Triggers, orchestration and failure behaviour

**Goal:** end-to-end unlock that fails safe.

**Tasks**
- State machine from ARCHITECTURE.md section 3 wiring `TriggerMonitor → LockGate → Camera → Pipeline → Liveness → Matcher → Typer`.
- Triggers: on wake, on lock, optional on Space; scan timeout (default ~3 s), one auto-retry.
- Failure cooldown after repeated misses; face unlock disabled and clearly indicated in the menu bar during cooldown.
- Camera and model released between scans so idle CPU is near zero.

**Acceptance:** success criteria 1, 3 and 4 in PRD section 5 pass; an unrecognised face leaves the lock screen untouched; idle CPU under 1%.

---

## Brief 7 — Notch animation (P2) and polish

**Goal:** the scan feels native; the app can also be invisible.

**Tasks**
- `OverlayController` with a subtle scan animation hugging the notch, success and failure states, haptic optional. Include "Animation off" mode.
- Handle Macs without a notch and external displays gracefully (small top-centre pill).
- Settings polish: threshold, scan duration, triggers, liveness level, delete data buttons, About screen with the "convenience, not security" statement.
- Own app icon and name (not the original product's).

**Acceptance:** animation visible during a lock-screen scan if Spike E passed (otherwise cleanly skipped); turning it off changes nothing else.

---

## Brief 8 — Hardening and docs

**Tasks:** run a network check to prove zero connections; review for any logging of secrets; write `README.md` with setup, permissions, how to recover if the app misbehaves (you can always type the password; disable via menu bar or delete from `/Applications`); final pass on `docs/manual-tests.md`.

**Acceptance:** PRD success criteria 1–5 verified and recorded.
