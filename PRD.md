# PRD — FaceKey (personal rebuild of Oleo ID's functionality)

## 1. What the original is (observed)
Source: the Oleo Club product page for "Oleo ID App" (oleoclub.store/products/oleo-id), fetched 26 Oct 2026.

- A **macOS menu bar app** that looks for your face when the Mac wakes, recognises you, and unlocks the session. Sold as a one-time download, €5.99 (listed at €19.99), Shopify store, no account, no subscription.
- Requirements stated: macOS 15 (Sequoia) or later, a Mac with a camera. Universal build (Apple Silicon and Intel).
- Claims: recognition runs locally, nothing is sent anywhere; face stored as an encrypted mathematical fingerprint, not a photo; password encrypted and unlocked with Touch ID; both deletable from settings.
- Features listed: face unlock fully offline; multiple face profiles (glasses, lighting, expressions); liveness check that rejects a printed photo; menu bar on/off; scan animation around the notch that can be turned off (then the app is invisible).
- Not stated on the page (so unknown): exactly how it types the password, how the camera works while locked, the model used, the liveness method. The briefs below fill these in using standard techniques.

Note: the page does not describe its internals. Existing free apps that do the same thing (e.g. Hey Mac, FaceUnlock, both on GitHub/AlternativeTo) describe the same mechanism: on-device face recognition, then the saved password is typed into the lock screen via Accessibility. Use them as references for ideas; do not copy code without checking their licences.

## 2. Goal
A free app, for the owner's own Mac, that unlocks the lock screen when it recognises the owner's face, falling back silently to the normal password if it does not.

## 3. Requirements

### P0 — must work
- Menu bar app with status item, on/off toggle, settings window, quit.
- First-run setup: grant Camera and Accessibility, enrol face, store login password.
- Guided face enrolment capturing several poses; stored as encrypted embeddings; no photos.
- Trigger a scan when the screen wakes or locks; recognise the owner locally (target under ~1.5 s).
- On a match, type the stored password into the lock screen and press Return.
- On no match or timeout, do nothing; the user types the password as usual.
- Lock gate: only ever type when the screen is confirmed locked.
- Password stored encrypted; unlocking it requires Touch ID (see OPEN QUESTION 1).
- "Delete face data" and "Delete password" in settings.

### P1 — should have
- Multiple face profiles (glasses off/on, lighting).
- Basic liveness: blink and/or slight head movement, plus a texture/quality check; rejects a static photo.
- Adjustable match threshold and scan duration; one automatic retry.
- Start at login (SMAppService).
- Fail-safe: lock out face unlock for a period after repeated failures; always keep password fallback.

### P2 — nice to have
- Notch-hugging scan animation (on/off), subtle success/failure feedback.
- Trigger options: on wake, on lock, on Space key.
- External display handling.
- Optional app-lock mode (out of scope for v1).

### Non-goals
- Selling or distributing it. If that ever changes: new name and icon, check model licences, add notarization, legal review.
- Defeating Face ID-grade security. A 2D Mac camera cannot match Touch ID/Face ID. This is a convenience feature and the docs/UI must say so.
- Cloud anything.
- Replacing FileVault pre-boot login (not possible this way); reboots still need the password.

## 4. Threat model (short)
- Protects against: casual shoulder-walk-up use of an unattended Mac when the owner's face is not present.
- Does not protect against: someone with a video or good photo of the owner on a screen, look-alikes, or an attacker with local admin access. Liveness reduces but does not eliminate this.
- The stored password is the sensitive asset. Mitigations: encrypted at rest, key gated by Touch ID, never logged, typed only when locked.

## 5. Success criteria
1. From a locked, awake Mac, looking at the camera unlocks it in under ~1.5 s at least 9 out of 10 tries in normal light.
2. A photo of the owner on a phone does not unlock it in 10 out of 10 tries with liveness on.
3. Another person's face does not unlock it in 10 out of 10 tries.
4. When unrecognised, the lock screen behaves exactly as without the app.
5. No network connections made (verify with Little Snitch or `nettop`).

## 6. Open questions
1. OPEN QUESTION: Password handling. Default: decrypt once per login session with Touch ID and hold it in memory, because requiring Touch ID at every unlock defeats the point. Alternative: store it with a device-only Keychain key and no Touch ID gate (simpler, weaker). Decide before Brief 5.
2. OPEN QUESTION: Which face model? Default: an ArcFace-style Core ML model with a licence that allows personal use (see ARCHITECTURE.md). Decide after Brief 0.
3. OPEN QUESTION: Intel support? Default: Apple Silicon only (Neural Engine). Add Intel only if the owner's Mac needs it.
