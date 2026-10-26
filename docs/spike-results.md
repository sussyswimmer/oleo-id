# Brief 0 — spike results (GO / NO-GO)

This is the evidence sheet for the Brief 0 feasibility spikes. Fill in the
**Result** and **Evidence** rows on the owner's Mac. The acceptance bar
(BRIEFS.md Brief 0): A–D need a pass/fail with evidence; **stop and reconsider
before Brief 1 if any of A–C fail.**

- Mac model / chip: _____
- macOS version: _____
- Date run: _____

---

## Spike A — camera frames while locked / just woken  *(implemented)*

**How to run**

```
cd spikes
./build-app.sh
open FaceKeySpikes.app --args camera --now --seconds 3     # baseline, screen awake
# then, for the real test:
open FaceKeySpikes.app --args camera --on-wake             # leave running
#   -> lock the screen (Ctrl-Cmd-Q) or let the display sleep, wait, then wake it
#   -> read ~/Library/Logs/FaceKeySpikes/camera-<date>.log
```

The log records, per window: time-to-first-frame, frame count, approx fps, mean
luma (to catch all-black frames after wake) and how many sampled frames Vision
found a face in.

| | |
|---|---|
| Result | ☐ PASS ☐ FAIL |
| Frames in 3 s while locked | _____ |
| Time to first frame | _____ ms |
| Mean luma (0–255) | _____ |
| Faces seen / checks | _____ |
| Camera light off within ~1 s of stop | ☐ yes ☐ no |

**Evidence (paste the RESULT lines from the log):**

```
(paste here)
```

---

## Spike B — lock-state detection  *(not covered in this session — owner to run)*

Not implemented in the `spikes` package. This spike reads
`CGSessionCopyCurrentDictionary()["CGSSessionScreenIsLocked"]` and the
`com.apple.screenIsLocked` / `...Unlocked` distributed notifications across
lock, display sleep/wake, and external-display connect, and reports whether the
value is reliable (ARCHITECTURE.md "LockGate"). It is the safety gate for
typing, so it must be done before Brief 5.

| | |
|---|---|
| Result | ☐ PASS ☐ FAIL ☐ not yet run |

**Evidence:** _____

---

## Spike C — typing into the lock screen  *(not covered in this session — owner to run)*

Not implemented here. With Accessibility granted, post a harmless test string
via `CGEvent` while the screen is locked and confirm it reaches the password
field; then try a real password + Return **on a throwaway local test account
only**. This is the make-or-break risk for the whole app.

| | |
|---|---|
| Result | ☐ PASS ☐ FAIL ☐ not yet run |

**Evidence:** _____

---

## Spike D — model latency (Neural Engine vs CPU)  *(implemented)*

**How to run**

```
scripts/download-models.sh
cd spikes
swift run -c release FaceKeySpikes model --path ../Models/auraface_v1.mlpackage --runs 100
swift run -c release FaceKeySpikes model --path ../Models/mobilefacenet.mlpackage --runs 100
```

Reports load time, median/p90 latency, output dimension and output L2 norm for
each of `cpuOnly`, `cpuAndGPU`, `cpuAndNeuralEngine`, `all`. (A compute unit may
silently fall back if the model can't map to it — compare the numbers.)

**AuraFace-v1 (512-d)**

| Compute unit | load (ms) | median (ms) | p90 (ms) | out dim | out L2 |
|---|---|---|---|---|---|
| cpuOnly | | | | | |
| cpuAndGPU | | | | | |
| cpuAndNeuralEngine | | | | | |
| all | | | | | |

**MobileFaceNet (128-d)**

| Compute unit | load (ms) | median (ms) | p90 (ms) | out dim | out L2 |
|---|---|---|---|---|---|
| cpuOnly | | | | | |
| cpuAndGPU | | | | | |
| cpuAndNeuralEngine | | | | | |
| all | | | | | |

| | |
|---|---|
| Result | ☐ PASS ☐ FAIL |
| Fastest acceptable config | _____ |

Target: embedding one frame should be a few ms to low tens of ms so the full
scan stays well under the PRD's ~1.5 s.

---

## Spike E — overlay above the lock screen  *(optional — not covered this session)*

Not implemented here. Show an `NSPanel` at the notch at several window levels and
report which are visible over the lock screen. Affects only the P2 animation.

| | |
|---|---|
| Result | ☐ PASS ☐ FAIL ☐ skipped |

---

## Recommendation

_Fill in after A–D. Example shape: "A and D pass on this Mac (frames arrive
within X ms of wake; AuraFace embeds in Y ms on the ANE). B and C still to be
run before proceeding past Brief 1 / into Brief 5. Model recommendation: ___."_
