#!/usr/bin/env bash
#
# Download the candidate Core ML face-embedding models for Spike D (BRIEFS.md
# Brief 0; ARCHITECTURE.md §5) into ./Models, verifying each file's SHA-256.
#
# Both models are Apache-2.0. This is a DEVELOPER script: it is the only place in
# the project that touches the network. The FaceKey app itself has no network code
# (CLAUDE.md). The downloaded model files are git-ignored.
#
# A Core ML `.mlpackage` is a directory. The AuraFace repo already stores it in
# that layout, so we mirror it. The MobileFaceNet repo stores the three parts as
# flat, prefixed files, so we reconstruct the `.mlpackage` directory from them.
#
# Usage:  scripts/download-models.sh            # download both
#         scripts/download-models.sh auraface   # just one
#         scripts/download-models.sh mobilefacenet
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODELS="$ROOT/Models"
HF="https://huggingface.co"

sha256() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}';
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}';
  else echo "need shasum or sha256sum" >&2; exit 1; fi
}

# fetch <url> <dest> <expected-sha256>
fetch() {
  local url="$1" dest="$2" want="$3"
  mkdir -p "$(dirname "$dest")"
  if [ -f "$dest" ] && [ "$(sha256 "$dest")" = "$want" ]; then
    echo "  ok (cached)  ${dest#"$ROOT"/}"
    return
  fi
  echo "  downloading  ${dest#"$ROOT"/}"
  curl -fL --retry 3 --retry-delay 2 -o "$dest" "$url"
  local got; got="$(sha256 "$dest")"
  if [ "$got" != "$want" ]; then
    echo "  SHA-256 MISMATCH for $dest" >&2
    echo "    expected $want" >&2
    echo "    got      $got" >&2
    rm -f "$dest"
    exit 1
  fi
  echo "  verified     ${dest#"$ROOT"/}"
}

download_auraface() {
  echo "AuraFace-v1 (TechnoThinker/visuals-models-open, Apache-2.0, 512-d)"
  local repo="$HF/TechnoThinker/visuals-models-open/resolve/main"
  local pkg="$MODELS/auraface_v1.mlpackage"
  fetch "$repo/auraface_v1.mlpackage/Manifest.json" \
        "$pkg/Manifest.json" \
        "0ccb49f4d04b75aee1d311ed381a70bcf6b42a66e38c0d82078f6384873d7827"
  fetch "$repo/auraface_v1.mlpackage/Data/com.apple.CoreML/model.mlmodel" \
        "$pkg/Data/com.apple.CoreML/model.mlmodel" \
        "93d1732b646f0449aedd6bf59c46093720a2d44ae3fbe7dd9e4a3ab74c2931ad"
  fetch "$repo/auraface_v1.mlpackage/Data/com.apple.CoreML/weights/weight.bin" \
        "$pkg/Data/com.apple.CoreML/weights/weight.bin" \
        "f762c464d5a7de1b4245bf123e7607c831c10a89561b5ef926078fbe147b58de"
  echo "  -> $pkg"
}

download_mobilefacenet() {
  echo "MobileFaceNet (xprilion/photoment-models, Apache-2.0, 128-d) — reconstructing .mlpackage"
  local repo="$HF/xprilion/photoment-models/resolve/main"
  local pkg="$MODELS/mobilefacenet.mlpackage"
  fetch "$repo/mobilefacenet-Manifest.json" \
        "$pkg/Manifest.json" \
        "81a442aa280d4784c2b638d354d454be187f2438d6c35416cc493784394bde93"
  fetch "$repo/mobilefacenet-model.mlmodel" \
        "$pkg/Data/com.apple.CoreML/model.mlmodel" \
        "2b210e3d6071fbc3e1828b3d62e6f7ecf2a9d79c9f35fb777148a938f4c8653a"
  fetch "$repo/mobilefacenet-weight.bin" \
        "$pkg/Data/com.apple.CoreML/weights/weight.bin" \
        "938f92009df4c9936396a6d282274b5a2d0656aa369e11e826bcacd716c7ff95"
  echo "  -> $pkg"
}

case "${1:-all}" in
  all)            download_auraface; download_mobilefacenet ;;
  auraface)       download_auraface ;;
  mobilefacenet)  download_mobilefacenet ;;
  *) echo "usage: $0 [all|auraface|mobilefacenet]" >&2; exit 64 ;;
esac

echo
echo "Done. Benchmark with, e.g.:"
echo "  (cd spikes && swift run FaceKeySpikes model --path ../Models/auraface_v1.mlpackage --runs 100)"
