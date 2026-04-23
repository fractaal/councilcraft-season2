# CouncilCraft — Vanilla Cafe (modpack source)

Authoritative source for the modpack. Minecraft **1.21.1 / NeoForge 21.1.227**.

Players' Prism instances run `scripts/pre-launch.ps1` on every launch, which calls `packwiz-installer-bootstrap.jar` against this repo's raw URL. Changes here → players get them on next launch.

## Pack URL
```
https://raw.githubusercontent.com/fractaal/councilcraft-season2/main/pack.toml
```
If this moves, update `scripts/pre-launch.ps1` and rebuild the distribution zip.

## Repo layout
```
pack.toml                 Pack metadata (name, MC/loader versions, pointers to index)
index.toml                Hash index — DO NOT edit by hand; `packwiz refresh` regenerates it
mods/*.pw.toml            One file per mod — each points at a Modrinth/CF project + version + hash
scripts/
  pre-launch.ps1          Splash UI + bootstrap invocation. Runs on every player launch.
  packwiz-installer-bootstrap.jar
CLAUDE.md / AGENTS.md     This file — workflow for humans + AI assistants
README.md                 Player-facing instructions (what goes in the distribution zip)
```

## Adding a mod — the ONE workflow

```bash
cd /path/to/vanilla-cafe-pack

# Modrinth (preferred — better metadata, more mods):
packwiz modrinth add <slug-or-url-or-search-term>

# CurseForge (for mods not on Modrinth):
packwiz curseforge add <slug-or-url>

# Commit + push:
git commit -am "Add <Mod Name>"
git push
```

That's it. Players get the mod on next launch. No .sh scripts, no manual zipping, no bootstrap ceremony.

### Pin a specific version (when latest breaks)

```bash
# Find the version ID:
curl -s "https://api.modrinth.com/v2/project/<slug>/version" \
  | jq '.[] | select(.game_versions | index("1.21.1")) | select(.loaders | index("neoforge")) | {version_number, id}'

# Then:
packwiz modrinth add --project-id <slug> --version-id <version-id>
packwiz pin <mod-name>
git commit -am "Pin <Mod Name> to <version> (<reason>)"
git push
```

Pinning prevents `packwiz update` from bumping it. Unpin with `packwiz unpin <name>`.

## Removing a mod

```bash
packwiz remove <mod-name>
git commit -am "Remove <Mod Name>"
git push
```

## Updating mods

```bash
packwiz update --all
git commit -am "Bump mod versions"
git push
```

## Testing your change

Two paths:

**Fast (trust packwiz)**: just push. Launch your own Prism instance. Pre-launch script syncs; if the game loads, you're good.

**Rigorous (autonomous harness, owner-only)**: `/root/tools/one-iteration.sh` builds the pack, syncs into a Prism instance, launches, and monitors for crashes for 180s. Returns 0 on clean launch, 1 on crash. Used during development — the Create guy doesn't need this for normal mod adds.

## Diagnosing crashes

Player crash → look at `<instance>/minecraft/crash-reports/*.txt`. File names:

- `*-fml.txt` = mod loading failure. Common causes: missing dep, version conflict, mixin target changed. Search the report for `Failure message:`.
- `*-client.txt` = runtime crash after mods loaded. Look at the top `Caused by:` chain.

Patterns we've hit (for reference):

| Symptom | Fix |
|---|---|
| `Mod X requires Y` | `packwiz modrinth add Y` |
| `Mod X is incompatible with Embeddium` | Swap Embeddium → Sodium-NeoForge (Embeddium breaks Veil/Sable/Create Aeronautics) |
| `Mod X requires connector any` | That's a Fabric mod via Sinytra Connector. Either remove it or add Sinytra Connector — recommend remove. |
| `requires unionlib 12.0.18 or above, and below 12.1.0` | Pin unionlib to 12.0.18-NeoForge (latest 12.2 is out of range) |
| DH `SingletonInjector.get() returned null` | DH 3.0.1-b has a known auto-updater bug. Pin to DH 2.3.6-b instead. |

## Caveats

- **CurseForge distribution-denied mods** (Create Aeronautics, Create: Storage currently): pre-loaded in the player zip as `overrides/`. When bootstrap syncs updates, it can't auto-fetch these. If you add a NEW distribution-denied mod, players will get a browser prompt on next sync. Not ideal but not a blocker for small groups.
- **Loader compatibility**: This pack is NeoForge-only. Don't add Fabric-only mods unless you also add Sinytra Connector (and expect flakiness). Prefer NeoForge-native alternatives.
- **Version pinning**: If you pin a mod, add a note in the commit message about WHY, so whoever unpins later understands the regression risk.

## For the pack owner only

- **Rebuild distribution zip** (when CF distribution-denied mod set changes or for new-player installs): see `/root/tools/` — the staging dir at `/root/councilcraft-dist-staging/` gets rezipped to `/root/councilcraft-vanilla-cafe.zip`. Day-to-day mod adds don't require rebuilding the zip.
- **Bump pack version in `pack.toml`** on significant changes so you have a timeline.

## Principles

1. **The pack is the repo.** No state lives outside version control (except the distribution zip, which is a build output).
2. **Packwiz commands only.** No shell scripts that wrap mod adds. Every deviation is a smell.
3. **Commit messages describe intent**, not mechanics. "Add Create: Diesel Generators" is good. "packwiz modrinth add create-diesel-generators" is noise.
4. **If packwiz picks the wrong thing, remove + re-add with `--project-id`.** Don't hand-edit `.pw.toml` files.
5. **Test in your own Prism. Ship to players.** The packwiz protocol is the guardrail — if it syncs cleanly and launches cleanly on your machine, it will for theirs.
