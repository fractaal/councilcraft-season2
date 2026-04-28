#!/usr/bin/env bash
#
# Build the CouncilCraft distribution zip for new players.
#
# What ships in the zip is intentionally minimal:
#   - A Prism instance config (instance.cfg, mmc-pack.json, icon.png)
#   - The pre-launch.ps1 script + packwiz-installer-bootstrap.jar
#   - Only the CF distribution-denied jars seeded into mods/ (rest sync on first launch)
#
# The bootstrap pulls everything else from the pack repo's pack.toml on first launch.
#
# Two flavors:
#
#   LEAN (default, ~33 MB):
#     Just the bootstrap + the CF distribution-denied seed jars. First launch
#     downloads ~1 GB of mods/shaders from the pack URL. Recommended.
#
#   FAT (--fat, ~1.2 GB):
#     Bundles everything from the local Prism instance (mods, shaderpacks,
#     resourcepacks, config, defaultconfigs, kubejs). First launch is
#     near-instant — the bootstrap still runs and reconciles against the
#     pack repo, but won't have to download anything that's already present.
#     Use when a player has a flaky connection or you want a self-contained
#     archive.
#
# Usage:
#   ./scripts/build-dist-zip.sh                         # lean zip
#   ./scripts/build-dist-zip.sh --fat                   # fat zip (everything)
#   ./scripts/build-dist-zip.sh --with-shaders          # lean + all shaderpacks
#   ./scripts/build-dist-zip.sh --with-shaders bsl,photon,complementary-reimagined
#                                                       # lean + shader subset (.pw.toml stems)
#   ./scripts/build-dist-zip.sh --output /tmp/foo.zip   # custom output path

set -euo pipefail

# ── config ──────────────────────────────────────────────────────────────────
PACK_REPO="${PACK_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PRISM_INSTANCE="${PRISM_INSTANCE:-/home/benjude/.local/share/PrismLauncher/instances/councilcraft-season2}"
SERVER_MODS="${SERVER_MODS:-/opt/minecraft-servers/councilcraft-s2/server/mods}"
USER_MODS="${USER_MODS:-$PRISM_INSTANCE/minecraft/mods}"
USER_SHADERS="${USER_SHADERS:-$PRISM_INSTANCE/minecraft/shaderpacks}"
INSTANCE_NAME="councilcraft-season2"
STAGING_DIR="${STAGING_DIR:-/home/benjude/dist-staging}"
OUTPUT_ZIP="${OUTPUT_ZIP:-/home/benjude/councilcraft-vanilla-cafe.zip}"

# Distribution-denied mods that need pre-seeding (bootstrap can't fetch them).
# If you add another CF API-excluded mod, add its jar filename here.
SEED_JARS=(
  "create-aeronautics-bundled-1.21.1-1.1.3.jar"
  "fxntstorage-1.2.6+mc-1.21.1-neoforge.jar"
)

# ── arg parsing ────────────────────────────────────────────────────────────
WITH_SHADERS=0
SHADER_FILTER=""
FAT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fat) FAT=1 ;;
    --with-shaders)
      WITH_SHADERS=1
      # Optional comma-separated filter list as next arg if it doesn't start with `-`
      if [[ ${2:-} && ! "${2:-}" =~ ^- ]]; then
        SHADER_FILTER="$2"; shift
      fi
      ;;
    --output) OUTPUT_ZIP="$2"; shift ;;
    -h|--help) sed -n '3,30p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

# --fat implies --with-shaders (and includes everything else); reconcile the flags.
if [[ $FAT -eq 1 ]]; then
  if [[ $WITH_SHADERS -eq 1 ]]; then
    echo "note: --fat already includes shaders; --with-shaders is redundant" >&2
  fi
  WITH_SHADERS=0   # disable the lean shader path; --fat handles shaders itself
fi

# ── sanity ─────────────────────────────────────────────────────────────────
[[ -d $PACK_REPO       ]] || { echo "pack repo not found: $PACK_REPO" >&2; exit 1; }
[[ -d $PRISM_INSTANCE  ]] || { echo "Prism instance not found: $PRISM_INSTANCE" >&2; exit 1; }
[[ -f $PACK_REPO/scripts/pre-launch.ps1 ]] || { echo "missing pre-launch.ps1 in pack repo" >&2; exit 1; }
[[ -f $PACK_REPO/scripts/packwiz-installer-bootstrap.jar ]] || { echo "missing bootstrap jar in pack repo" >&2; exit 1; }
command -v zip >/dev/null || { echo "need zip(1) installed" >&2; exit 1; }

# ── stage ──────────────────────────────────────────────────────────────────
echo "[stage] $STAGING_DIR"
rm -rf "$STAGING_DIR"
DEST="$STAGING_DIR/$INSTANCE_NAME"
mkdir -p "$DEST/scripts" "$DEST/minecraft/mods"

# Sanitized instance.cfg — strip everything personal/host-specific, keep the bones.
echo "[stage] writing sanitized instance.cfg"
python3 - "$PRISM_INSTANCE/instance.cfg" "$DEST/instance.cfg" <<'PY'
import sys, configparser
src, dst = sys.argv[1], sys.argv[2]
# Prism uses INI-ish format that is not strict ConfigParser; do a plain line filter instead.
DROP = {
    "JavaPath", "JavaSignature", "JavaArchitecture", "JavaRealArchitecture",
    "JavaVendor", "JavaVersion", "InstanceAccountId",
    "JoinServerOnLaunch", "JoinServerOnLaunchAddress", "JoinWorldOnLaunch",
    "Env", "EnableFeralGamemode", "EnableMangoHud",
    "CustomGLFWPath", "CustomOpenALPath",
    "ExportAuthor", "ExportName", "ExportSummary", "ExportVersion", "ExportOptionalFiles",
    "lastLaunchTime", "lastTimePlayed", "totalTimePlayed",
}
out = []
for line in open(src):
    key = line.split("=", 1)[0].strip() if "=" in line else None
    if key in DROP:
        continue
    out.append(line)
# Force AutomaticJava=true so Prism picks Java itself rather than the host's path.
out = [("AutomaticJava=true\n" if l.startswith("AutomaticJava=") else l) for l in out]
open(dst, "w").writelines(out)
PY

cp "$PRISM_INSTANCE/mmc-pack.json" "$DEST/mmc-pack.json"
[[ -f $PRISM_INSTANCE/minecraft/icon.png ]] && cp "$PRISM_INSTANCE/minecraft/icon.png" "$DEST/icon.png" || true

# Scripts (always from pack repo — the in-instance copy may have local edits)
cp "$PACK_REPO/scripts/pre-launch.ps1" "$DEST/scripts/pre-launch.ps1"
cp "$PACK_REPO/scripts/packwiz-installer-bootstrap.jar" "$DEST/scripts/packwiz-installer-bootstrap.jar"

# Player README so they know what they downloaded
cat > "$DEST/README.md" <<EOF
# CouncilCraft — Season 2

Drop this folder into your Prism Launcher \`instances\` directory and refresh
Prism. The instance auto-syncs all mods on first launch via packwiz.

First launch will download ~1 GB of mods + shaders. Be patient.

Pack URL: https://raw.githubusercontent.com/fractaal/councilcraft-season2/main/pack.toml
EOF

if [[ $FAT -eq 1 ]]; then
  # Bundle everything from the local Prism instance that should travel with
  # the pack. Allow-list (not deny-list) — we explicitly name what's safe to
  # ship, and silently skip anything else (logs, world saves, caches, etc.).
  echo "[stage] --fat: copying full instance content from $PRISM_INSTANCE/minecraft"
  for item in mods shaderpacks resourcepacks config defaultconfigs kubejs icon.png; do
    src="$PRISM_INSTANCE/minecraft/$item"
    if [[ -e $src ]]; then
      cp -r "$src" "$DEST/minecraft/"
      printf "    + %-16s (%s)\n" "$item" "$(du -sh "$src" | cut -f1)"
    fi
  done
  # Sanity: seed jars must be in the bundled mods/. If they aren't, the local
  # instance is out of sync with the pack — fall back to copying from server.
  for jar in "${SEED_JARS[@]}"; do
    if [[ ! -f $DEST/minecraft/mods/$jar ]]; then
      echo "    fixing missing seed jar: $jar (from server)"
      cp "$SERVER_MODS/$jar" "$DEST/minecraft/mods/$jar"
    fi
  done
else
  # Lean: only seed CF distribution-denied jars (bootstrap can't fetch them).
  echo "[stage] seeding distribution-denied jars"
  for jar in "${SEED_JARS[@]}"; do
    if   [[ -f $SERVER_MODS/$jar ]]; then cp "$SERVER_MODS/$jar" "$DEST/minecraft/mods/$jar"
    elif [[ -f $USER_MODS/$jar ]];   then cp "$USER_MODS/$jar"   "$DEST/minecraft/mods/$jar"
    else
      echo "!! seed jar missing on both server and local: $jar" >&2
      exit 1
    fi
    echo "    + $jar"
  done
fi

# Optional shader bundling (lean only — --fat already includes them)
if [[ $WITH_SHADERS -eq 1 ]]; then
  mkdir -p "$DEST/minecraft/shaderpacks"
  if [[ -z $SHADER_FILTER ]]; then
    echo "[stage] bundling ALL shaderpacks"
    cp "$USER_SHADERS"/*.zip "$DEST/minecraft/shaderpacks/"
  else
    echo "[stage] bundling shaderpacks matching: $SHADER_FILTER"
    IFS=',' read -ra wanted <<< "$SHADER_FILTER"
    for stem in "${wanted[@]}"; do
      tomlf="$USER_SHADERS/${stem}.pw.toml"
      [[ -f $tomlf ]] || { echo "!! no .pw.toml stem matches: $stem" >&2; continue; }
      zip_name=$(grep -E "^filename" "$tomlf" | sed -E "s/.*= *['\"]([^'\"]+)['\"].*/\1/")
      [[ -f $USER_SHADERS/$zip_name ]] || { echo "!! shader zip missing: $zip_name" >&2; continue; }
      cp "$USER_SHADERS/$zip_name" "$DEST/minecraft/shaderpacks/"
      echo "    + $zip_name"
    done
  fi
fi

# ── zip ────────────────────────────────────────────────────────────────────
echo "[zip] $OUTPUT_ZIP"
rm -f "$OUTPUT_ZIP"
( cd "$STAGING_DIR" && zip -rq "$OUTPUT_ZIP" "$INSTANCE_NAME" )

# ── report ─────────────────────────────────────────────────────────────────
size=$(du -h "$OUTPUT_ZIP" | cut -f1)
echo
echo "✓ built $OUTPUT_ZIP ($size)"
echo "  staging kept at $STAGING_DIR (rerun to overwrite)"
unzip -l "$OUTPUT_ZIP" | tail -25
