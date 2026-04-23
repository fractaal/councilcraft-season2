#!/usr/bin/env bash
# Vanilla Cafe modpack bootstrap — Minecraft 1.21.1 / NeoForge
#
# Run from inside an empty pack directory. Produces pack.toml + index.toml + mods/*.pw.toml.
# After it finishes:
#     packwiz modrinth export     # -> VanillaCafe.mrpack for Prism Launcher
#
# Requires packwiz on PATH. (This script adds ~/go/bin if packwiz was go-installed there.)

set -uo pipefail
export PATH="$HOME/go/bin:$PATH"

MC_VERSION="1.21.1"
PACK_NAME="Vanilla Cafe"
PACK_AUTHOR="${USER:-you}"
PACK_VERSION="0.1.0"

echo "==> Initializing packwiz pack: ${PACK_NAME}"
packwiz init \
  --name "${PACK_NAME}" \
  --author "${PACK_AUTHOR}" \
  --version "${PACK_VERSION}" \
  --mc-version "${MC_VERSION}" \
  --modloader neoforge \
  --neoforge-latest \
  -y

# add <mr|cf> <slug-or-url>
add() {
  local src="$1"; shift
  local slug="$1"; shift
  case "$src" in
    mr) echo "  + [MR] $slug"
        packwiz modrinth add "$slug" -y 2>&1 | tail -3 || echo "    !! failed: $slug" ;;
    cf) echo "  + [CF] $slug"
        packwiz curseforge add "$slug" -y 2>&1 | tail -3 || echo "    !! failed: $slug" ;;
  esac
}

echo
echo "==> Core non-negotiables (ComputerCraft + Create + Aeronautics)"
add mr cc-tweaked
add mr create
add cf create-aeronautics
add cf sable
add mr advancedperipherals

echo
echo "==> Trains"
add mr create-steam-n-rails-1.21.1

echo
echo "==> Create addons"
add mr create-dreams-and-desires
add mr create-confectionery
add mr createaddition
add cf create-storage-neo-forge
add mr numismatics

echo
echo "==> TARDIS + road vehicles"
add mr time-vortex-neoforge
add cf minecraft-transport-simulator
add cf transport-simulator-official-vehicle-set

echo
echo "==> Cafe / cooking / winery stack"
add mr farmers-delight
add mr chefs-delight
add mr more-delight
# lets-do-bakery      — ARCHIVED by author, no 1.21+ support. Consider Farm & Charm or Delightful instead.
# lets-do-candlelight — ARCHIVED by author, no 1.21+ support.
add mr lets-do-vinery
add mr lets-do-herbalbrews
add mr lets-do-meadow
add mr brewin-and-chewin

echo
echo "==> Building / aesthetic blocks"
add cf chisels-bits
add mr macaws-furniture
add mr macaws-roofs
add mr macaws-windows
add mr macaws-doors
add mr macaws-trapdoors
add mr macaws-fences-and-walls
add mr macaws-paths-and-pavings
add mr macaws-bridges
add mr macaws-lights-and-lamps
add mr chipped
add mr supplementaries
add mr amendments
add mr every-compat
add mr framedblocks

echo
echo "==> Map (Antique Atlas)"
add mr antique-atlas-4
add mr surveyor

echo
echo "==> Worldgen (Terralith anchored)"
add mr terralith
add mr terrablender
add mr expanded-ecosphere

echo
echo "==> QoL"
add mr jei
add mr jade
add mr appleskin

echo
echo "==> Performance"
add mr embeddium
add mr ferrite-core

echo
echo "==> Vanilla+ spice"
add cf quark

echo
echo "==============================================="
echo "Done. Next: packwiz modrinth export -> .mrpack"
echo "==============================================="
