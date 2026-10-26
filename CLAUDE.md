# CLAUDE.md — FaceKey (working name)

Personal-use macOS menu bar app that unlocks the Mac lock screen with the user's face. It reimplements the *functionality* described on the Oleo ID product page (face unlock, fully offline, menu bar, multiple face profiles, liveness check, notch scan animation). It is for the owner's own Mac only.

## Ground rules
- Do NOT copy anything from Oleo Club: no name, icon, marketing copy, images, or code. Functionality is fair game, assets are not. Pick our own name and icon.
- Read `PRD.md` (what), `ARCHITECTURE.md` (how), `BRIEFS.md` (ordered work). Work one brief at a time, in order. Brief 0 is a go/no-go spike; stop and report after it.
- Ask before deciding anything marked "OPEN QUESTION" in the docs.

## Stack
- Swift 6, SwiftUI + AppKit, macOS 15+ target, universal build if the toolchain allows, Apple Silicon first.
- AVFoundation (camera), Vision (face detection, landmarks, pose), Core ML (face embedding model), CryptoKit + Security (encryption, Keychain), LocalAuthentication (Touch ID), CoreGraphics (CGEvent for typing).
- Not sandboxed (needs Accessibility + CGEvent). Not for the App Store. No notarization needed for personal use.
- `LSUIElement = YES` (menu bar only, no Dock icon).
- No network code at all. No analytics, no crash reporters, no third-party networking dependencies.

## Security rules (non-negotiable)
1. Never log, print, or persist the password or raw embeddings in plaintext. No `print(password)`, ever, including in debug builds.
2. Never save camera frames to disk. Frames live in memory only for the duration of one scan.
3. Only type the password when the screen is confirmed locked (see ARCHITECTURE.md, "Lock gate"). Typing a password into the wrong focused app would leak it. If the lock state is unknown, do nothing.
4. Face data is stored as embeddings (numbers), encrypted at rest. Settings must offer "Delete face data" and "Delete password".
5. This is a convenience layer. The Mac password remains the real lock. Document this in the app's About screen.

## Build and run
- Create an Xcode project `FaceKey` (macOS App, SwiftUI lifecycle). Build with `xcodebuild -scheme FaceKey -configuration Debug build`.
- Sign with a stable self-signed code-signing certificate ("FaceKey Dev") so Camera and Accessibility permissions persist across rebuilds. A changed signing identity makes macOS treat it as a new app and re-prompt.
- Run the installed copy from `/Applications/FaceKey.app` when testing permissions or login-item behaviour; permissions bind to that copy.
- Put a `make` target or `scripts/install.sh` in the repo that builds, signs, and copies to `/Applications`.

## Conventions
- Small commits, one per task. Conventional commit messages.
- Unit tests for pure logic (similarity scoring, template matching, liveness math, state machine). Anything touching the lock screen is verified manually and written up in `docs/manual-tests.md`.
- Keep modules small and behind protocols so the camera, model, and typer can be faked in tests.
- Settings live in `UserDefaults` (non-secret) and Keychain (secret). Nothing else.

## Definition of done (per brief)
Acceptance criteria in the brief pass, tests pass, `docs/manual-tests.md` updated, no TODOs left that touch security rules, short summary of what changed and any decisions taken.
