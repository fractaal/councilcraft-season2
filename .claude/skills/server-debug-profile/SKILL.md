---
name: server-debug-profile
description: INVOKE/LOAD WHEN diagnosing the CouncilCraft server — chunk-gen stalls, "Can't keep up" warnings, low TPS, mysterious lag, mod-loading crashes, or any time you want to start a spark profile, run a thread dump, or query server state via RCON. KEYWORDS "spark profile", "thread dump", "jstack", "TPS lag", "Can't keep up", "stall", "crash report", "rcon", "mcrcon", "boot error", "server overloaded", "tick lag", "MSPT", "perf investigation", "what's slow", "is the server overloaded", "FATAL".
---

# Server debug & profile — the source of truth for diagnosing CouncilCraft

The Vanilla Cafe pack runs heavy. When something goes sideways — boot crashes, tick lag, chunk-gen stalls, mysterious "Can't keep up" warnings — this skill walks you through the entire diagnostic toolbelt: spark profiles, jstack bursts, RCON queries, log triage, and post-mortem of crash reports.

The `pack-mod-workflow` skill covers add/remove/sync; this skill covers **what to do once it breaks**.

## Repo facts (relevant subset)

| Fact | Value |
|---|---|
| Server install | `/opt/minecraft-servers/councilcraft-s2/server/` |
| Server runs as | `minecraft` user, systemd unit `councilcraft-s2` |
| Server log | `/opt/minecraft-servers/councilcraft-s2/server/logs/latest.log` |
| Crash reports | `/opt/minecraft-servers/councilcraft-s2/server/crash-reports/` |
| RCON | `127.0.0.1:25575`, password `benchtest` |
| RCON client | `mcrcon` (already installed) |
| Spark mod | `spark-1.10.124-neoforge.jar` (server console: `spark`) |
| Sudo | needed for systemd ops + reading minecraft user files; cached for ~5 min |

## The four diagnostic levels (use in order)

### Level 1 — Quick signal check (no profiling needed)

```bash
# TPS
mcrcon -H 127.0.0.1 -P 25575 -p benchtest "spark tps"

# Health (CPU, memory, GC, MSPT)
mcrcon -H 127.0.0.1 -P 25575 -p benchtest "spark health"

# Last few "Can't keep up" warnings
sudo grep -E "Can't keep up|Running .* behind" /opt/minecraft-servers/councilcraft-s2/server/logs/latest.log | tail -5
```

If TPS is at 20 and no recent "Can't keep up" warnings → server is healthy. If TPS < 18 or you see ms-behind messages → continue to Level 2.

### Level 2 — jstack burst (snapshot diagnostics)

`jstack` captures a thread dump at one moment. **Don't poll faster than ~1Hz** — every jstack causes a JVM safepoint (a brief stop-the-world). Doing it 10× per second would make the server slower.

The provided helper script captures 5 dumps 2s apart and summarizes:

```bash
bash .claude/skills/server-debug-profile/scripts/jstack-burst.sh
```

**Reading the output:**

- If the **same** method appears in 4-5 of the 5 dumps → that's the bottleneck. Single-thing problem, can be fixed by removing/configuring that one mod/feature.
- If stacks **differ** every dump → load is **broad**. No single offender. Either trim multiple mods, accept the cost, or consider hardware.
- If most Worker-Main threads are RUNNABLE during a stall → chunk gen is choking (worldgen-related; check carvers, biome lookups, Lithostitched, ModernFix surface_rules).
- If most workers are PARKED (idle) and Server thread is the one running → bottleneck is on the main tick (entities, datapack functions, mob AI, accessories iteration).

**Common stack signatures and what they mean:**

| Stack signature | Likely culprit |
|---|---|
| `Aquifer.computeFluid` → `MultiNoiseBiomeSource` → `biolith$searchTreeGet` | Wide biome registry; chunk-gen biome lookup expensive |
| `ModernFix.SurfaceRuleOptimizer.optimizeSequenceRule` | Set `mixin.perf.optimize_surface_rules=false` (per memory) |
| `Sable.SubLevelInclusiveLevelEntityGetter.get` from `EntitySelector.findEntities` | Datapack `@e` selector iterating all dimensions/airships — RPG Series scoreboard tracker |
| `Rapier3D.step` (native) | Sable airship physics; expected if airships exist |
| `AccessoriesEventHandler.onLivingEntityTick` | Multiple accessory mods × many entities |
| `LocalMobCapCalculator.getPlayersNear` → `DistanceManager.runAllUpdates` | Vanilla mob spawning calc; unavoidable steady-state cost |
| `Level.getBlockState` → `PalettedContainer.get` from a mod's AI Goal `canUse` | An entity AI goal scanning blocks per-tick (e.g. Hearth's CrowAvoidRepellingBlocksGoal) |
| `Mod requires X` in FATAL | Missing dep — see G-cases in pack-mod-workflow skill |
| `ConcurrentModificationException` in `EveryCompat.forAllModules` | Too many wood-adding mods; remove Every Compat |
| Two modules export package P to module Z | Java module conflict — find the JIJ duplicate provider, remove one consumer |

### Level 3 — Spark profile (statistical sampling)

Spark samples Server-thread + worker stacks while you reproduce the issue. Use it when load is broad (jstack burst showed different stacks each dump) or you need a clean call-tree breakdown.

**ALWAYS run with `--force-java-sampler`** on this server. It's mandatory, not optional — see the "Why" footnote below if curious.

```bash
# Start a profile that auto-stops after 60s
mcrcon -H 127.0.0.1 -P 25575 -p benchtest \
  "spark profiler --force-java-sampler --timeout 60 --interval 4"

# Watch the log for the upload URL
sudo tail -f /opt/minecraft-servers/councilcraft-s2/server/logs/latest.log | grep -E "spark.lucko.me/[a-zA-Z0-9]+"
```

The log will show `Profiler is now running! (built-in java)` — that's correct. If you ever see `(async)`, you forgot the flag and the profile will be empty.

The URL takes the form `https://spark.lucko.me/<id>`. The user can open it in browser (full GUI), and you can also fetch the underlying binary for local analysis.

**Fetching the binary (Whalebone DNS workaround):**

The CDN `bytebin.lucko.me` is intercepted by Whalebone DNS on this host. Use DoH to bypass:

```bash
ID=<spark-id-from-log>
curl -sSLk --doh-url "https://1.1.1.1/dns-query" \
     -H "User-Agent: spark" \
     -H "Accept: application/x-spark-sampler" \
     "https://bytebin.lucko.me/$ID" -o /tmp/spark.bin
```

**Analyzing the binary:**

```bash
python3 .claude/skills/server-debug-profile/scripts/analyze-spark.py /tmp/spark.bin
```

The analyzer prints:
1. Profile metadata (creator, platform, thread count, sampling interval)
2. Per-thread total sample time
3. For Server thread + chunk Workers: top 15 packages, top 15 classes, top 20 methods, root frames
4. The top hotspots tell you exactly what to trim or fix

**The skill auto-builds proto bindings on first run.** Requires `protoc` + `python-protobuf` packages (already installed; install via `sudo pacman -S protobuf python-protobuf` if missing).

#### Why `--force-java-sampler` is mandatory (footnote)

The server runs Java 25. Spark 1.10.124 (the latest NeoForge 1.21.1 build) bundles an async-profiler that pre-dates Java 25 and can't walk Java 25 stack frames. Without `--force-java-sampler`, spark silently uses async-profiler, the library loads, the log says `Profiler is now running! (async)`, but **zero stack samples are recorded** — the resulting profile is empty in both `analyze-spark.py` and the spark.lucko.me web viewer ("No Data — This profile doesn't contain any data!").

`--force-java-sampler` switches to the JVM's built-in `ThreadMXBean` sampler, which works on any JVM. Slightly less accurate than async-profiler (safepoint-based, ~30Hz vs ~100Hz signal-based) but produces real, parseable profiles. Good enough for any practical diagnosis.

**Things that look like fixes but aren't:**
- `--mode java` — silently ignored in spark 1.10.124. Don't waste your time.
- `kernel.perf_event_paranoid=1` — doesn't help (the issue is JVM-level, not kernel-level).
- DoH-bypass for Whalebone DNS — works for the fetch but the empty binary is genuinely what spark uploaded.

### Level 4 — Crash report post-mortem

When the server crashes during boot or runtime:

```bash
# Latest crash report
ls -t /opt/minecraft-servers/councilcraft-s2/server/crash-reports/ | head -1

# Read the full thing
cat /opt/minecraft-servers/councilcraft-s2/server/crash-reports/$(ls -t /opt/minecraft-servers/councilcraft-s2/server/crash-reports/ | head -1) | head -100
```

Look for:
- `-- Mod loading issue for: <modid> --` → that mod failed during construction
- `Caused by: <ExceptionType>` → the actual error type
- `at <package>.<class>.<method>` → the failing call site

If a mod is repeatedly failing in construction, the workaround is usually to remove it (per `pack-mod-workflow` skill) and report to upstream.

## RCON — interactive server queries

`mcrcon` is the right client. **Don't use `-t` flag** unless you want an interactive REPL (the `-t` makes it interactive instead of one-shot, and Bash automation breaks).

```bash
# One-shot command, normal use
mcrcon -H 127.0.0.1 -P 25575 -p benchtest "<command>"

# Wait longer for response
mcrcon -H 127.0.0.1 -P 25575 -p benchtest -w 3 "<command>"
```

Useful commands beyond spark:

| Command | What it does |
|---|---|
| `list` | Connected players |
| `data get entity @p Pos` | Player coordinates |
| `forge tps` (NeoForge) | Per-dimension TPS |
| `spark tps` | Better TPS readout via spark |
| `spark health` | Memory, GC, threading summary |
| `spark profiler --info` | Active profiler status |
| `spark profiler stop` | Cancel an active profile |
| `time set day` | Skip night (debugging) |
| `weather clear` | Clear weather (debugging) |

## Common diagnostic playbooks

### Playbook A — "Can't keep up" warnings during exploration

1. Quick check via Level 1 — confirm warnings are recent
2. Run jstack burst (Level 2) **while user is still teleporting/exploring**
3. Look at Worker-Main thread states: many RUNNABLE = chunk gen is the load
4. If Server thread is busy: read its top frames across 5 dumps to identify the hot mod
5. If load is broad: spark profile (Level 3) with `--only-ticks-over 100ms` to focus on the bad ticks

### Playbook B — Server boots OK then a crash mid-play

1. `journalctl -u councilcraft-s2 --since "10 minutes ago" -n 200`
2. Find the FATAL line, read backwards for the actual exception
3. Crash report (Level 4) — the "Mod loading issue" or top frame names the offender
4. Often: a mod's tick handler threw because of unexpected state. Look for "Caused by" chain.
5. Neruina mod catches some entity tick crashes; check `neuria.handler.TickHandler` mentions in log

### Playbook C — World won't load / load times exploding

1. Check `mods/` directory for any new mods added since last successful boot
2. Compare: `git log --oneline -20` in the pack repo
3. Most likely a worldgen mod causing first-time-chunk slowness. Check ModernFix's `optimize_surface_rules` setting.
4. If using Terralith: ensure `optimize_surface_rules=false` in `config/modernfix-mixins.properties`
5. Worst-case: revert the most recent mod adds, retry, then bisect.

### Playbook D — A specific mod is suspect

1. **Don't** remove it blindly. Get a thread dump first to confirm.
2. If jstack shows the mod's class repeatedly: confirmed culprit
3. Check if the mod has a config to disable the heavy feature
4. If not, remove via `packwiz remove <slug>` (see pack-mod-workflow)
5. After removal: restart, do another jstack burst to confirm the bottleneck moved or shrunk

## Anti-patterns

- **Don't** poll jstack faster than 1Hz — each one causes a safepoint
- **Don't** run a fresh spark profile while another is still running (cancel first)
- **Don't** use `-t` flag with mcrcon for one-shot commands (makes it interactive)
- **Don't** assume "spark profile shows nothing" means the server is fine — check `threads: 0` in analyzer output, that means the profiler failed to capture
- **Don't** remove a mod after one bad-looking jstack — load can be transient. Confirm with 3-5 dumps over time, or use spark for statistical confidence.

## Memory cross-references

- `feedback_terralith_nonnegotiable.md` — `optimize_surface_rules=false` is the fix for Terralith stalls (was THE chunk gen pathology). Aesthetic principle: spectacular worldgen, not specifically Terralith.
- `feedback_no_c2me_no_chunky.md` — never propose C2ME or Chunky as fixes. They break against Sable + DH.
- `feedback_packwiz_cf_excluded.md` — boot-time mystery sync failures often trace to a CF mod that opted out of the API.
- `feedback_sudo_no_tty.md` — sudo dance protocol; ask user to run `sudo -v` if cached out.

## Related skills

- `pack-mod-workflow` — adding/removing/syncing mods (the source of most boot crashes)
