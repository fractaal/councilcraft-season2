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

- **CurseForge distribution-denied mods** (currently: Create Aeronautics, Create: Storage [Neo/Forge]): seeded directly into `minecraft/mods/` of the distribution zip because the bootstrap can't fetch them via CF API. If you add a NEW distribution-denied mod, also add its filename to the `SEED_JARS` array in `scripts/build-dist-zip.sh` and rebuild the zip.
- **Loader compatibility**: This pack is NeoForge-only. Don't add Fabric-only mods unless you also add Sinytra Connector (and expect flakiness). Prefer NeoForge-native alternatives.
- **Version pinning**: If you pin a mod, add a note in the commit message about WHY, so whoever unpins later understands the regression risk.

## How players install the pack

1. Owner produces a distribution zip via `scripts/build-dist-zip.sh` (see below).
2. Player extracts it into Prism Launcher's `instances/` directory.
3. Player refreshes Prism — a `councilcraft-season2` instance appears.
4. On every launch, the instance's `PreLaunchCommand` runs `scripts/pre-launch.ps1`, which invokes `packwiz-installer-bootstrap.jar` against the pack repo's raw `pack.toml` URL. That syncs mods, shaders, configs, resourcepacks against the live state of `main`.
5. Game launches.

The zip exists for new-player installs only. Once a player is set up, day-to-day mod changes (add/remove/bump) only require pushing to `main` — players auto-sync on next launch. The zip does NOT need rebuilding for mod-version bumps.

**When the zip DOES need rebuilding:**
- A new CF distribution-denied mod was added to the pack (bootstrap can't fetch it; must be seeded).
- A new player is joining and you want to give them a fat zip so they don't wait ~1 GB on first launch.
- The Prism instance scaffolding (mmc-pack.json, instance.cfg shape, scripts/) changed.

## Building the distribution zip

The build script lives at `scripts/build-dist-zip.sh`. Two flavors:

| Flavor | Flag | Size | Contents | First-launch download |
|---|---|---|---|---|
| **Lean** (default) | *(none)* | ~33 MB | Bootstrap + 2 distribution-denied seed jars + Prism instance scaffolding | ~1 GB (mods + shaders) |
| **Fat** | `--fat` | ~1.1 GB | Lean + entire local Prism instance content (`mods/`, `shaderpacks/`, `resourcepacks/`, `config/`, `defaultconfigs/`, `kubejs/`) | ~0 (bootstrap only reconciles hashes) |

Lean is recommended. Fat is for players with flaky networks or when you want a self-contained archive that doesn't depend on GitHub being up at first-launch time.

There's also a middle option: `--with-shaders` adds just the shaderpack zips (~90 MB) on top of the lean default, optionally filtered by a comma-separated list of `.pw.toml` stems. Examples below.

### Inputs the script reads

| Variable | Default | What it is |
|---|---|---|
| `PACK_REPO` | the dir this script lives in (`..`) | The pack repo. Must contain `pack.toml`, `index.toml`, `scripts/pre-launch.ps1`, `scripts/packwiz-installer-bootstrap.jar`. |
| `PRISM_INSTANCE` | `~/.local/share/PrismLauncher/instances/councilcraft-season2` | Source of truth for the Prism instance scaffolding (`instance.cfg`, `mmc-pack.json`, `icon.png`) and, in `--fat` mode, the bundled content. |
| `SERVER_MODS` | `/opt/minecraft-servers/councilcraft-s2/server/mods` | Fallback source for distribution-denied seed jars. |
| `STAGING_DIR` | `/home/benjude/dist-staging` | Where the zip is assembled. Wiped on each run. |
| `OUTPUT_ZIP` | `/home/benjude/councilcraft-vanilla-cafe.zip` | Output path. Override with `--output`. |

### What the script strips from `instance.cfg`

The local Prism instance config has host-specific lines that must NOT travel with the zip. The script drops:

- `JavaPath`, `JavaSignature`, `JavaArchitecture`, `JavaRealArchitecture`, `JavaVendor`, `JavaVersion` — replaced with `AutomaticJava=true` so the new player's Prism picks Java itself.
- `InstanceAccountId` — owner's MC account.
- `Env` — host-specific env vars (e.g. gamescope wrappers).
- `JoinServerOnLaunch*`, `JoinWorldOnLaunch` — owner's quick-join state.
- `EnableFeralGamemode`, `EnableMangoHud`, `CustomGLFWPath`, `CustomOpenALPath`, `Use*` toggles for performance tweaks specific to the owner's machine.
- `Export*` fields (Prism's own export tracking).
- `lastLaunchTime`, `lastTimePlayed`, `totalTimePlayed` — owner's vanity stats.

The crucial line that's PRESERVED:

```
PreLaunchCommand=pwsh -NoProfile -ExecutionPolicy Bypass -File $INST_DIR/scripts/pre-launch.ps1
```

That's what makes the bootstrap run on every launch. If you ever change the Prism scaffolding, make sure this line survives.

### Distribution-denied seed jars

Defined as a bash array near the top of the script:

```bash
SEED_JARS=(
  "create-aeronautics-bundled-1.21.1-1.1.3.jar"
  "fxntstorage-1.2.6+mc-1.21.1-neoforge.jar"
)
```

Add to this list when a new mod's CF API distribution flag is disabled. The script copies these from `SERVER_MODS` first, falling back to the local Prism instance's `mods/`. If neither has the jar, the build aborts.

### Common invocations

```bash
# Lean zip — the default. Recommended for distribution.
./scripts/build-dist-zip.sh

# Fat zip — self-contained, ~1.1 GB.
./scripts/build-dist-zip.sh --fat

# Lean + all 45 shader zips (~120 MB).
./scripts/build-dist-zip.sh --with-shaders

# Lean + just a few popular shaders.
./scripts/build-dist-zip.sh --with-shaders bsl-shaders,photon-shader,complementary-reimagined,bliss-shader

# Custom output path.
./scripts/build-dist-zip.sh --output /tmp/cc.zip
```

### What the player sees on first launch

- Prism extracts the instance from the zip.
- Prism launches; `PreLaunchCommand` fires `pre-launch.ps1` (Windows or PowerShell-Core anywhere).
- The script shows a splash window ("CouncilCraft Mods Sync") while `packwiz-installer-bootstrap.jar` runs.
- Bootstrap reads the live `pack.toml` from GitHub raw, downloads any missing mods/shaders/configs, removes anything no longer in the index.
- Splash shows count + names of new updates, or "I'm up to date!" if nothing changed.
- Minecraft launches.

If the network is down or the bootstrap fails, the splash turns red, says "Sync failed (exit N). Launching with existing mods..." and starts the game anyway with whatever's already there. This is intentional — a bad sync shouldn't lock the player out.

### Adding a new distribution-denied mod (full workflow)

1. `packwiz curseforge add <slug>` — adds the metafile to the pack repo.
2. Manually download the jar from the mod's CF page.
3. Drop the jar into your local Prism instance's `mods/` folder so the server and your client can run.
4. Also drop it into `/opt/minecraft-servers/councilcraft-s2/server/mods/` (server side).
5. Add the jar filename to `SEED_JARS` in `scripts/build-dist-zip.sh`.
6. `./scripts/build-dist-zip.sh` — rebuilds the lean zip with the new seed.
7. Distribute the new zip to anyone setting up fresh. Existing players already have it (you put it in their `mods/` via... wait, they don't. They need a manual drop OR a fat-zip update OR you can ship the jar separately.) → Yes, this case is awkward. For existing players, they have to manually grab the jar OR you ship them a fat zip.

### For the pack owner only

- **Bump pack version in `pack.toml`** on significant changes so you have a timeline.

## Principles

1. **The pack is the repo.** No state lives outside version control (except the distribution zip, which is a build output).
2. **Packwiz commands only.** No shell scripts that wrap mod adds. Every deviation is a smell.
3. **Commit messages describe intent**, not mechanics. "Add Create: Diesel Generators" is good. "packwiz modrinth add create-diesel-generators" is noise.
4. **If packwiz picks the wrong thing, remove + re-add with `--project-id`.** Don't hand-edit `.pw.toml` files.
5. **Test in your own Prism. Ship to players.** The packwiz protocol is the guardrail — if it syncs cleanly and launches cleanly on your machine, it will for theirs.
