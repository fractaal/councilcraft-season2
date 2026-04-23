# Vanilla Cafe — Prism Launcher modpack bootstrap

A Minecraft 1.21.1 / NeoForge modpack focused on:
- **ComputerCraft-powered infrastructure** (MRT, automated cargo ships)
- **Create + Create Aeronautics** for automation and airships
- **Cutesy cafe vibes** (Farmer's Delight, Let's Do suite, Create: Confectionery, Vinery)
- **Beautiful worldgen** (Terralith)
- **Hand-drawn cartography** (Antique Atlas — no minimap by design)

## Manual-download mods (CurseForge distribution-denied)

Two mods have their authors' third-party download flag disabled and **must be downloaded by hand on first export:**

1. **Create Aeronautics** — https://www.curseforge.com/minecraft/mc-mods/create-aeronautics/files/7964998
2. **Create: Storage [Neo/Forge]** — https://www.curseforge.com/minecraft/mc-mods/create-storage-neo-forge/files/7965698

Download both `.jar` files, drop them into `~/.cache/packwiz/cache/import/`, then re-run `packwiz modrinth export`. After that, Prism imports the `.mrpack` cleanly.

## How to build the pack

You need [packwiz](https://packwiz.infra.link/installation/) installed.

```bash
cd vanilla-cafe-pack
./bootstrap.sh          # initializes packwiz pack and adds all mods
packwiz modrinth export # produces VanillaCafe.mrpack
```

Then in Prism Launcher: **Add Instance → Import from zip → pick `VanillaCafe.mrpack`**.

## Why packwiz?

Packwiz auto-fetches current versions and hashes for every mod from Modrinth/CurseForge, and the exported `.mrpack` is the format Prism imports natively. You can re-run `packwiz update --all` later to refresh versions.

## What to verify before shipping

The bootstrap script tries Modrinth slugs first and CurseForge IDs as fallback. A few mods have slug ambiguity or are in flux — check the `!! failed` output after running and hand-add any misses.

Known caveats:
- **Create Aeronautics** is still alpha/beta — expect rough edges, stay on the latest release
- **Steam 'n' Rails on 1.21.1** is a community port, not the upstream project
- **TARDIS Refined has no 1.21.1 yet** — the script uses Time Vortex as a substitute; swap to Crimbo's or TARDIS Refined when they land 1.21.1
- **MrCrayfish's Vehicle Mod has no 1.21.1** — Immersive Vehicles fills that role
- **Quark 1.21.1 is alpha (4.1-x series)** — CurseForge-only, not on Modrinth. The old Supplementaries crash is fixed, but alpha churn is still a thing. Pin to a known-good version and disable individual modules in `config/quark-common.toml` if anything misbehaves

## Tweakables inside `bootstrap.sh`

- `NEOFORGE_VERSION` — bump to a newer 1.21.1 build as they release
- Commented-out lines for optional mods (Quark, Aquaculture, Oculus, Create: Overdrive, Biomes O' Plenty)
- JEI vs EMI is a one-line swap
