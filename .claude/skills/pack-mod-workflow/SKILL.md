---
name: pack-mod-workflow
description: INVOKE/LOAD WHEN adding, removing, or updating mods in the CouncilCraft Season 2 ("Vanilla Cafe") pack — or syncing the server / restarting it. Encodes the packwiz-add → push → bootstrap-sync → restart loop with all the gotchas surfaced from the field. KEYWORDS "add a mod", "remove this mod", "update the pack", "sync server", "restart server", "boot the pack", "councilcraft", "vanilla cafe", "packwiz".
---

# Pack mod workflow — the source of truth for this repo

The repo is a [packwiz](https://packwiz.infra.link/) pack feeding both a Prism client and a systemd-managed dedicated server. Adding/removing mods is a well-rehearsed loop — but only because we tripped most of the gotchas at least once. This skill captures both the happy path and the failure modes.

## Repo facts

| Fact | Value |
|---|---|
| Pack name | `Vanilla Cafe` |
| Loader | NeoForge 1.21.1 |
| Pack repo | `/home/benjude/src/councilcraft-season2/` |
| Server install | `/opt/minecraft-servers/councilcraft-s2/server/` |
| Client install | `/home/benjude/.local/share/PrismLauncher/instances/councilcraft-season2/minecraft/` |
| `packwiz` binary | `/home/benjude/go/bin/packwiz` |
| Systemd unit | `councilcraft-s2` (server runs as `minecraft` user) |
| Git remote | `https://github.com/fractaal/councilcraft-season2` (branch `main`) |
| Server pack URL | `https://raw.githubusercontent.com/fractaal/councilcraft-season2/main/pack.toml` |

## Workflow — the happy path

```bash
cd /home/benjude/src/councilcraft-season2
PACKWIZ=/home/benjude/go/bin/packwiz

# 1. ADD (Modrinth-first, CurseForge fallback)
$PACKWIZ mr add <slug> --yes        # prefer this
$PACKWIZ cf add <slug> --yes        # only if MR doesn't have it

# Resource packs go in resourcepacks/ instead of mods/
$PACKWIZ mr add <slug> --meta-folder resourcepacks --yes

# 2. SIDE AUDIT — packwiz often picks the wrong side from Modrinth metadata
grep -lE 'side = "server"' mods/*.pw.toml
# Most mods marked server should be "both" — the only legitimate server-only mod
# we have is `servercore`. Worldgen libs, structure mods, and anything that
# touches the registry MUST be side="both" or clients fail registry sync.
sed -i 's/^side = "server"$/side = "both"/' mods/<offender>.pw.toml

# 3. REFRESH index
$PACKWIZ refresh

# 4. COMMIT + PUSH
git add -A
git commit -m "<meaningful message>"
git push origin main

# 5. SYNC SERVER (need sudo — see Sudo dance below)
sudo systemctl stop councilcraft-s2
cd /opt/minecraft-servers/councilcraft-s2/server
sudo -u minecraft java -jar packwiz-installer-bootstrap.jar -g -s server \
    "https://raw.githubusercontent.com/fractaal/councilcraft-season2/main/pack.toml?cb=$(date +%s%N)"
sudo systemctl start councilcraft-s2

# 6. WATCH BOOT
LOG=/opt/minecraft-servers/councilcraft-s2/server/logs/latest.log
timeout 240 bash -c "tail -f '$LOG' | grep -m1 -E 'Done \([0-9.]+s\)|FATAL.*pre-loading|requires.*above|Failed to wait for future'"
grep -E "FATAL|requires.*above" "$LOG" | head -10

# 7. The CLIENT auto-syncs on next Prism launch (pre-launch script runs the same
#    bootstrap). User reloads Prism to pick up changes.
```

The user's friend on a separate client also auto-syncs via the same bootstrap, so any side misconfig surfaces there fast.

## Side classification rules of thumb

| Mod type | Side |
|---|---|
| ServerCore-style server-only perf libs | `server` |
| Worldgen libs (Lithostitched, Biolith, TerraBlender, Oh The Trees You'll Grow) | **both** |
| Structure mods (YUNG's, Repurposed Structures, WDA, Villages&Pillages) | **both** |
| Biome mods (Terralith, Tectonic, OTBWG, Regions Unexplored, Nature's Spirit) | **both** |
| Animation/cosmetic-only client mods (Mo' Bends, Not Enough Animations, Camerapture, Controlling) | `client` |
| Sound mods (Sound Physics, AmbientSounds, Presence Footsteps) | `client` |
| Particle-only mods (Better Combat Particle, Subtle Effects) | `client` |
| Render-side input (Controlify) | `client` |
| Resource packs (`--meta-folder resourcepacks`) | `client` (auto) |
| Everything else (recipe, block, entity, item content) | `both` |

When unsure, default to `both` — wrong way to err is `server` because clients fail with confusing dep errors.

## Gotcha catalog

### G1 — CurseForge API-excluded mods
Some CF authors disable third-party API access. `packwiz cf add` succeeds, refresh succeeds, but `packwiz-installer-bootstrap` errors:
```
<Mod>: java.lang.Exception: This mod is excluded from the CurseForge API
```
This blocks the **entire** sync — every mod fails. Recovery:
1. `packwiz remove <slug>`, refresh, push
2. If bootstrap still trips on it (caching), `sudo rm /opt/minecraft-servers/councilcraft-s2/server/packwiz.json` and re-run bootstrap from scratch.

Known offender: `cool-rain`. Always test bootstrap immediately after a `cf add`.

### G2 — packwiz default-side is often wrong
Modrinth marks structure/lib mods as `client_side: optional, server_side: required` and packwiz turns that into `side = "server"`. Friend's fresh client install then fails with `Mod X requires Y, but Y is not installed` because Y was skipped on his sync. Always run the side-audit step after batch-adding.

### G3 — version resolution: `1.3 < 1.2.11.4`
NeoForge does Maven-style version comparison, padding components with zero. `1.3` parses as `[1, 3, 0, 0]` and is **less than** `[1, 2, 11, 4]`. When packwiz auto-picks the "latest" version of a lib (e.g. Platform), it might pick a version string that fails dep constraints. Pin to the explicit version that satisfies the requirement:
```bash
$PACKWIZ mr add --project-id <id> --version-id <version-id> --yes
```

### G4 — bootstrap cache poisoning
After a failed sync (G1, dep error, etc), the bootstrap's `packwiz.json` on the server can hold stale state. Symptoms: bootstrap says "already up to date" but jars are missing. Fix:
```bash
sudo cp /opt/minecraft-servers/councilcraft-s2/server/packwiz.json{,.bak_$(date +%s)}
sudo -u minecraft rm /opt/minecraft-servers/councilcraft-s2/server/packwiz.json
# then re-run bootstrap — full re-sync
```

### G5 — manual jar drop as a last resort
If the bootstrap is being weird and refuses to pull a specific jar, you can extract the URL from the `.pw.toml` and curl it directly:
```bash
URL=$(grep '^url = ' mods/<slug>.pw.toml | sed 's/url = "//;s/"$//')
sudo -u minecraft curl -sSL "$URL" -o /opt/minecraft-servers/councilcraft-s2/server/mods/<filename>.jar
```
Use sparingly; prefer fixing the bootstrap state. CF mods don't have a `url =` line — they use `mode = "metadata:curseforge"`.

### G6 — Sudo dance
Bash tool can't prompt for sudo. When you need sudo (server stop/start, jar drops to server/mods/), check first:
```bash
sudo -n true 2>/dev/null && echo "cached" || echo "expired — ask user"
```
If expired, ask the user to run `sudo -v` in a real terminal, then continue.

### G7 — slugs that fail
- Slug guessing: try Modrinth search if `mr add <slug>` fails. Common slug hyphenation issues: `notenoughanimations` vs `not-enough-animations`, `mythicupgrades` vs `mythic-upgrades`, `idens-deco` (the user-given URL slug) vs `idens-decor` (the actual MR slug).
- Family-prefixed slugs: many Let's Do compat variants are `lets-do-X-farmcharm-compat` not `lets-do-X`.

### G8 — Fabric-only on 1.21.1
Many cozy/RPG mods exist for 1.21.1 only on Fabric/Quilt and never got NeoForge ports. We currently *do* have **Sinytra Connector** in the pack (auto-pulled as a transitive dep), which technically allows loading Fabric mods on NeoForge. **But avoid using it for new adds** — it's a real failure surface and existing Fabric mods may bring their own issues. Consider it a last resort.

### G9 — World wipe needed when dropping worldgen mods
When removing a biome / surface-rule mod (e.g. Terralith), existing chunks have biomes baked in that no longer exist → players will see worldgen errors when loading old chunks. Wipe `world/`, `world_nether/`, `world_the_end/` after such changes. The user marks these as playtest-phase wipes — confirm with them first.

## Memory-aligned defaults (read these memories!)

- `feedback_terralith_nonnegotiable.md` — spectacular worldgen aesthetic is the rule, not Terralith specifically. Don't recommend BoP / OTBYG / RU as *anchors*. (User has overridden case-by-case.)
- `feedback_no_c2me_no_chunky.md` — never propose C2ME or Chunky for this pack (Sable + DH conflict).
- `feedback_packwiz_remove_silent.md` — `packwiz remove` no-ops on unknown slugs. Re-grep `index.toml` after removes.
- `feedback_packwiz_cf_excluded.md` — full G1 documentation.
- `feedback_antique_atlas.md` — Antique Atlas is the preferred map mod (over Xaero's/JourneyMap).
- `feedback_sudo_no_tty.md` — full G6 documentation.

## Boot log signals

After server restart, the log produces one of these in 4-30 seconds:

| Signal | Meaning |
|---|---|
| `Done (Ns)! For help, type "help"` | ✅ Healthy boot. Note time. |
| `FATAL ... Error during pre-loading phase: Mod X requires Y or above` | ❌ Missing or wrong-version dep. Add Y. |
| `FATAL ... Failed to wait for future Mod Construction, N errors found` | ❌ A mod crashed in its constructor. Read the crash report at `crash-reports/`. |
| `FATAL ... Modules X and Y export package P to module Z` | ❌ Java module conflict (typically two providers of the same JIJ). Remove one. |

## Anti-patterns I've fallen into and you shouldn't

- Adding a mod and saying "done" without testing the bootstrap sync. **Always sync immediately.**
- Bumping `pack.toml` version manually without `packwiz refresh`. **Refresh always.**
- Using `git add -A && git commit -m "stuff"` on the server install directly. **The repo is the source of truth — never edit `/opt/minecraft-servers/.../mods` configs manually except for one-shot jar drops.**
- Confidently asserting a mod is "in the pack" from memory. **Always `ls mods/ | grep -iE` first.**
- Forgetting that the friend's client install is a separate failure surface — side misconfigs that work on the user's client (jars accumulated from prior syncs) **break for fresh installs**.
