# Models

The Core ML face-embedding models used by Spike D (and later by the app's
`EmbeddingModel`) are **not committed** — they are large and are downloaded by
`scripts/download-models.sh`, which verifies each file's SHA-256. Only this
README is tracked.

Both candidates are permissively licensed (**Apache-2.0**), which satisfies the
"personal use, licence-clean" requirement in ARCHITECTURE.md §5. Their contracts
were read directly from the Core ML model specifications.

| | AuraFace-v1 | MobileFaceNet |
|---|---|---|
| Source repo | `TechnoThinker/visuals-models-open` | `xprilion/photoment-models` |
| Upstream weights | `fal/AuraFace-v1` (glintr100 / ArcFace ResNet100) | Qualcomm AI Hub MobileFaceNet |
| Licence | Apache-2.0 | Apache-2.0 |
| Local path after download | `Models/auraface_v1.mlpackage` | `Models/mobilefacenet.mlpackage` |
| Input | `data`: `MLMultiArray [1,3,112,112]` Float32, **RGB, NCHW**, `(pixel/127.5)-1` | `face`: **image** 112×112 RGB (Core ML handles the pixel buffer) |
| Output | `embedding`: Float32 `[1,512]`, **not L2-normalised** (normalise downstream) | `embedding`: Float16 `[1,128]`, unit vector |
| Size on disk | ~124 MB | ~2 MB |

Notes:

- **The two models have different input kinds.** AuraFace expects a preprocessed
  `MLMultiArray` (you align the 112×112 crop, convert to RGB planar float, and
  apply `(pixel/127.5)-1` yourself). MobileFaceNet takes an image input, so Core
  ML/Vision can hand it a `CVPixelBuffer` directly. The alignment + preprocessing
  code in Brief 2/3 must branch on whichever model wins Spike D.
- A `.mlpackage` is a directory. AuraFace is published in that layout; the
  MobileFaceNet repo stores the three parts as flat `mobilefacenet-*` files, so
  the download script reconstructs the directory.
- The AuraFace card carries an upstream fairness note: training data "may not
  extensively cover all ethnicities." Fine for a single-owner personal app;
  worth remembering if scope ever changes.

The **OPEN QUESTION** of which model to ship (ARCHITECTURE.md §5, PRD §6)
is decided by the owner after Spike D's latency numbers and Brief 3's accuracy
check — not here.
