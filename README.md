# FaceKey

A personal-use macOS menu bar app that unlocks the owner's **own** Mac lock
screen with their face: on-device face recognition, then the stored password is
typed into the lock screen. Fully offline, no network code. This is a
convenience layer — the Mac password remains the real lock.

See `PRD.md` (what), `ARCHITECTURE.md` (how), `BRIEFS.md` (ordered work) and
`CLAUDE.md` (ground rules). Work proceeds one brief at a time.

> Not affiliated with any commercial product. No third-party names, icons,
> marketing copy or code are used — only the functionality is reimplemented
> (see `CLAUDE.md`).

## Status

**Brief 0 — feasibility spikes (GO / NO-GO).** Two of the spikes are built here;
the lock-screen-touching ones are run separately:

| Spike | What | State |
|---|---|---|
| A | Camera frames while locked / just woken | **implemented** (`spikes/`) |
| B | Lock-state detection reliability | owner to run |
| C | Typing into the lock screen via CGEvent | owner to run |
| D | Core ML face-model latency (ANE vs CPU) | **implemented** (`spikes/`) |
| E | Overlay visible above the lock screen (optional) | owner to run |

Nothing here has been compiled — the project is developed on Linux and built on
the Mac.

## Running the spikes (on a Mac, macOS 15+, Swift 6)

```sh
# Spike A — camera on wake
cd spikes
./build-app.sh
open FaceKeySpikes.app --args camera --now        # baseline
open FaceKeySpikes.app --args camera --on-wake     # lock/sleep then wake
# logs: ~/Library/Logs/FaceKeySpikes/

# Spike D — model latency
cd ..
scripts/download-models.sh
cd spikes
swift run -c release FaceKeySpikes model --path ../Models/auraface_v1.mlpackage  --runs 100
swift run -c release FaceKeySpikes model --path ../Models/mobilefacenet.mlpackage --runs 100
```

Record outcomes in `docs/spike-results.md`. Candidate models and their licences
are in `Models/README.md`.

## Layout

```
spikes/     Brief 0 feasibility spikes (SwiftPM executable, throwaway)
scripts/    download-models.sh (the only networked code; dev-only)
Models/     Core ML models (git-ignored; see Models/README.md)
docs/       spike-results.md, manual-tests.md
```
