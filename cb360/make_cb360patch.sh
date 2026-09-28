#!/usr/bin/env bash
# Patch MobIR 1.4.96 for MobIR Air CB360 (body temperature model) and re-sign it.
#
# Patch (cb360_ReadPackageData.patch): add this at the top of McuGuideInterface.ReadPackageData
#   if (mPackageLow == null && mPackageHumanBody != null) enumITARange = ITA_HUMAN_BODY;
# See debug.md sections 7-8.
#
# Needs: java (11+), patch, zip, unzip, curl, sha256sum
# Personal use only. Do not redistribute.

set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] <input.apk> [output.apk]

  input.apk          MobIR_1.4.96_APKPure.apk
  output.apk         output file (default: <input dir>/MobIR_1.4.96_cb360patch.apk)

Options:
  --keep-work        keep the work dir (default: delete it on exit)
  --work-dir DIR     use DIR as the work dir (implies --keep-work)
  --force            continue even if the input SHA-256 does not match
  -h, --help         show this help
EOF
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLS_DIR="$SCRIPT_DIR/tools"

INPUT_SHA256="498540e38490333a4e24429153fa7896dbafded284cf9eaf641ccf3288b3a1d6"  # MobIR_1.4.96_APKPure.apk

APKTOOL_URL="https://github.com/iBotPeaches/Apktool/releases/download/v3.0.3/apktool_3.0.3.jar"
APKTOOL_SHA256="dbf930b076c6b9be08d57c449cacefc3bdd6b71ebd59b3066fc0e1f5b14f9423"
SIGNER_URL="https://github.com/patrickfav/uber-apk-signer/releases/download/v1.3.0/uber-apk-signer-1.3.0.jar"
SIGNER_SHA256="e1299fd6fcf4da527dd53735b56127e8ea922a321128123b9c32d619bba1d835"

PATCH_FILE="$SCRIPT_DIR/cb360_ReadPackageData.patch"
PATCH_MARK="CB360 patch: mPackageLow null, use mPackageHumanBody"

KEEP_WORK=0
WORK_DIR=""
FORCE=0
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-work) KEEP_WORK=1; shift ;;
    --work-dir)  WORK_DIR="$2"; KEEP_WORK=1; shift 2 ;;
    --force)     FORCE=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    -*)          echo "unknown option: $1" >&2; usage; exit 1 ;;
    *)           POSITIONAL+=("$1"); shift ;;
  esac
done

[[ ${#POSITIONAL[@]} -ge 1 ]] || { usage; exit 1; }
INPUT="$(realpath "${POSITIONAL[0]}")"
OUTPUT="${POSITIONAL[1]:-$(dirname "$INPUT")/MobIR_1.4.96_cb360patch.apk}"
OUTPUT="$(realpath -m "$OUTPUT")"

log() { echo "[$(date +%H:%M:%S)] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

for cmd in java patch zip unzip curl sha256sum; do
  command -v "$cmd" >/dev/null || die "$cmd not found"
done
[[ -f "$INPUT" ]] || die "input APK not found: $INPUT"
[[ -f "$PATCH_FILE" ]] || die "patch file not found: $PATCH_FILE"

# --- work dir ---
if [[ -z "$WORK_DIR" ]]; then
  if [[ $KEEP_WORK -eq 1 ]]; then
    WORK_DIR="$SCRIPT_DIR/work/$(date +%Y%m%d-%H%M%S)"
  else
    WORK_DIR="$(mktemp -d)"
  fi
fi
mkdir -p "$WORK_DIR"
WORK_DIR="$(realpath "$WORK_DIR")"

cleanup() {
  local rc=$?
  if [[ $KEEP_WORK -eq 1 ]]; then
    log "work dir kept: $WORK_DIR"
  else
    rm -rf "$WORK_DIR"
  fi
  if [[ $rc -ne 0 ]]; then
    echo "FAILED (exit $rc)" >&2
    [[ $KEEP_WORK -eq 1 ]] || echo "To debug, run again with --keep-work" >&2
  fi
  exit $rc
}
trap cleanup EXIT

# --- 1. get tools ---
fetch_tool() {  # url sha256 dest
  local url="$1" sha="$2" dest="$3"
  if [[ -f "$dest" ]] && echo "$sha  $dest" | sha256sum -c --status; then
    return
  fi
  log "download: $url"
  curl -fsSL -o "$dest.tmp" "$url"
  echo "$sha  $dest.tmp" | sha256sum -c --status || die "SHA-256 mismatch: $url"
  mv "$dest.tmp" "$dest"
}
mkdir -p "$TOOLS_DIR"
APKTOOL="$TOOLS_DIR/apktool_3.0.3.jar"
SIGNER="$TOOLS_DIR/uber-apk-signer-1.3.0.jar"
fetch_tool "$APKTOOL_URL" "$APKTOOL_SHA256" "$APKTOOL"
fetch_tool "$SIGNER_URL" "$SIGNER_SHA256" "$SIGNER"

# --- 2. check input ---
if ! echo "$INPUT_SHA256  $INPUT" | sha256sum -c --status; then
  [[ $FORCE -eq 1 ]] || die "input SHA-256 does not match 1.4.96 (APKPure). Use --force to continue"
  log "WARN: SHA-256 mismatch, continue because of --force"
fi

# --- 3. decode to smali ---
log "apktool d"
java -Xmx4g -jar "$APKTOOL" d -r -f -o "$WORK_DIR/smali" "$INPUT" >"$WORK_DIR/apktool_d.log" 2>&1

# dex name comes from the path in the patch file: smali_classes2/... -> classes2.dex
SMALI_DIR="$(sed -nE 's#^\+\+\+ b/([^/]+)/.*#\1#p' "$PATCH_FILE" | head -1)"
if [[ "$SMALI_DIR" == "smali" ]]; then DEX_NAME="classes.dex"; else DEX_NAME="${SMALI_DIR#smali_}.dex"; fi
log "target dex: $DEX_NAME"

# --- 4. patch ---
log "patch smali"
patch --dry-run -p1 -d "$WORK_DIR/smali" < "$PATCH_FILE" >/dev/null || die "patch does not apply"
patch -p1 -d "$WORK_DIR/smali" < "$PATCH_FILE"

# --- 5. rebuild ---
log "apktool b"
java -Xmx4g -jar "$APKTOOL" b -o "$WORK_DIR/built.apk" "$WORK_DIR/smali" >"$WORK_DIR/apktool_b.log" 2>&1

# --- 6. replace dex (keep other entries as in the original, drop old signature) ---
log "replace $DEX_NAME"
UNSIGNED="$WORK_DIR/unsigned.apk"
cp "$INPUT" "$UNSIGNED"
chmod u+w "$UNSIGNED"   # copy from a Windows drive can be read-only
# remove old signature files (*.SF, *.RSA, *.EC, *.DSA, MANIFEST.MF)
mapfile -t SIG_FILES < <(unzip -Z1 "$UNSIGNED" | grep -E '^META-INF/[^/]+\.(SF|RSA|EC|DSA|MF)$' || true)
[[ ${#SIG_FILES[@]} -eq 0 ]] || zip -q -d "$UNSIGNED" "${SIG_FILES[@]}"
# take the new dex from the rebuilt APK and put it in (other entries are not changed)
mkdir -p "$WORK_DIR/dex"
unzip -q -o "$WORK_DIR/built.apk" "$DEX_NAME" -d "$WORK_DIR/dex"
(cd "$WORK_DIR/dex" && zip -q -X "$UNSIGNED" "$DEX_NAME")

# --- 7. zipalign + sign ---
log "sign"
java -jar "$SIGNER" -a "$UNSIGNED" -o "$WORK_DIR/signed" >"$WORK_DIR/signer.log" 2>&1
grep -q "signature verified" "$WORK_DIR/signer.log" || die "signature check failed ($WORK_DIR/signer.log)"
SIGNED="$(find "$WORK_DIR/signed" -name '*.apk' | head -1)"

# --- 8. check patch ---
# use grep -c (not -q) so unzip is not killed by SIGPIPE under pipefail
HITS="$(unzip -p "$SIGNED" "$DEX_NAME" | grep -ac "$PATCH_MARK" || true)"
[[ "$HITS" -gt 0 ]] || die "patch not found in output APK"
log "patch verified"

mkdir -p "$(dirname "$OUTPUT")"
cp "$SIGNED" "$OUTPUT"
log "output: $OUTPUT"
sha256sum "$OUTPUT"
log "done. See README.md for how to install."
