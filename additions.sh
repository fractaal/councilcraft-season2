#!/usr/bin/env bash
# Incremental additions to the Vanilla Cafe pack — adventure layer + vibe-match
# Run AFTER bootstrap.sh has completed successfully.

set -uo pipefail
export PATH="$HOME/go/bin:$PATH"

add() {
  local src="$1"; shift
  local slug="$1"; shift
  case "$src" in
    mr) echo "  + [MR] $slug"
        packwiz modrinth add "$slug" -y 2>&1 | tail -2 || echo "    !! failed: $slug" ;;
    cf) echo "  + [CF] $slug"
        packwiz curseforge add "$slug" -y 2>&1 | tail -2 || echo "    !! failed: $slug" ;;
  esac
}

echo "==> Bosses + RPG progression"
add mr l_enders-cataclysm
add cf apotheosis
add mr apothic-attributes
add mr simply-swords
add mr artifacts
add mr bettercombat                  # Better Combat

echo
echo "==> Mobs"
add cf alexs-mobs                    # Official CF listing; 1.21.1 unofficial port
add mr friends-and-foes
add mr deeperdarker                  # Deeper and Darker
add cf born-in-chaos

echo
echo "==> YUNG's full suite (you have all of these on current server)"
add mr yungs-better-desert-temples
add mr yungs-better-dungeons
add mr yungs-better-end-island
add mr yungs-better-jungle-temples
add mr yungs-better-mineshafts
add mr yungs-better-nether-fortresses
add mr yungs-better-ocean-monuments
add mr yungs-better-strongholds
add mr yungs-better-witch-huts
add mr yungs-bridges
add mr yungs-cave-biomes
add mr yungs-extras

echo
echo "==> Structures / adventure content"
add mr when-dungeons-arise
add cf dungeon-and-taverns
add mr explorers-compass
add mr structory

echo
echo "==> Nether + End overhauls (Stardust Labs — matches Terralith vibe)"
add mr incendium
add mr nullscape

echo
echo "==> Distant Horizons (you have it; defining visual feature)"
add mr distanthorizons

echo
echo "==> Cozy furniture / decor expansions"
add mr handcrafted
add mr dramatic-doors
add mr immersive-lanterns
add mr comforts
add mr mcw-paintings                 # Macaw's Paintings (missed in first pass)
add mr suppsquared                   # Supplementaries Squared

echo
echo "==> Farmer's Delight expansion pack"
add mr delightful
add mr nethers-delight
add mr oceans-delight
add mr cultural-delights
add cf farm-and-charm                # Let's Do: Farm & Charm (successor to Bakery/Candlelight)

echo
echo "==> Loot / inventory / QoL"
add mr lootr
add mr carry-on
add mr sophisticated-backpacks
add mr curios                        # NeoForge's Trinkets equivalent
add mr veinminer
add mr mythicmetals

echo
echo "==> Social"
add mr simple-voice-chat
add mr emotecraft

echo
echo "============================================="
echo "Additions done. Review '!! failed' lines above."
echo "Export: packwiz modrinth export"
echo "============================================="
