#!/usr/bin/env python3
"""
analyze-spark.py — read a spark profile binary, dump the top hotspots per thread.

Usage:
    analyze-spark.py <path-to-profile.bin>
    analyze-spark.py /tmp/spark.bin

The .bin file is the body POSTed to bytebin.lucko.me — fetch via:
    curl -sSLk --doh-url https://1.1.1.1/dns-query \
         -H "User-Agent: spark" -H "Accept: application/x-spark-sampler" \
         "https://bytebin.lucko.me/<spark-id>" -o /tmp/spark.bin

The DoH bypass is needed because Whalebone DNS intercepts bytebin.lucko.me.

Spark proto schema notes:
- SamplerData has: metadata (1), threads (2), class_sources (3), time_windows (...)
- ThreadNode.children is a FLAT ARRAY of all stack nodes for that thread.
- Each node's `times` is per-time-window sample counts (× sampling interval = ms).
- `children_refs` indices into the same flat array tell you the call tree
  if you want full hierarchy.
- For a top-N hotspot pass, just aggregating by (class, method) over the flat
  array is sufficient — you get inclusive time at every observed call site.
"""
import os, sys

# Find the proto-bindings dir relative to this script
HERE = os.path.dirname(os.path.abspath(__file__))
SKILL_DIR = os.path.dirname(HERE)
PROTO_DIR = os.path.join(SKILL_DIR, "proto-py")
sys.path.insert(0, PROTO_DIR)

# Auto-build proto python bindings if missing
if not os.path.exists(os.path.join(PROTO_DIR, "spark", "spark_sampler_pb2.py")):
    import subprocess
    proto_src = os.path.join(SKILL_DIR, "proto")  # contains spark/*.proto
    os.makedirs(os.path.join(PROTO_DIR, "spark"), exist_ok=True)
    open(os.path.join(PROTO_DIR, "spark", "__init__.py"), "w").close()
    for f in ("spark.proto", "spark_sampler.proto", "spark_heap.proto", "spark_ws.proto"):
        if os.path.exists(os.path.join(proto_src, "spark", f)):
            subprocess.check_call(
                ["protoc", f"--python_out={PROTO_DIR}", f"--proto_path={proto_src}", f"spark/{f}"]
            )

from spark import spark_sampler_pb2


def fmt_pct(ms, total):
    return f"{(ms / total * 100):>5.1f}%" if total else "  --  "


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    path = sys.argv[1]
    raw = open(path, "rb").read()
    print(f"file size: {len(raw)} bytes")

    d = spark_sampler_pb2.SamplerData()
    d.ParseFromString(raw)

    md = d.metadata
    print(f"creator: {md.creator}".replace("\n", " ").strip())
    print(f"platform: {md.platform_metadata.name} {md.platform_metadata.version}")
    print(f"threads: {len(d.threads)}")
    print(f"time_windows: {len(list(d.time_windows))}")
    print(f"class_sources: {len(d.class_sources)}")
    print()

    if len(d.threads) == 0:
        print("⚠️  No thread/stack data in this profile — async-profiler captured 0 samples.")
        print("   Causes:")
        print("    • kernel.perf_event_paranoid >= 2 blocks unprivileged perf sampling")
        print("      → fix: sudo sysctl kernel.perf_event_paranoid=1")
        print("    • profile started during a crisis where signal delivery was suppressed")
        print("    • use spark profiler --mode java as a fallback (built-in JVM sampling)")
        return

    interval_ms = (md.interval / 1000) if md.interval else 1.0  # interval is microseconds

    for t in d.threads:
        total = sum(t.times) if t.times else 0
        print(f"=== Thread: {t.name!r}  total_time={total:.0f}ms  nodes={len(t.children)} ===")
        # All threads listed; only deep-dive on Server thread + chunk workers
        if t.name not in ("Server thread",) and not t.name.startswith("Worker-Main"):
            continue

        by_method, by_class, by_pkg = {}, {}, {}
        for n in t.children:
            ms = sum(n.times) if n.times else 0
            if ms <= 0:
                continue
            mk = f"{n.class_name}.{n.method_name}"
            by_method[mk] = by_method.get(mk, 0) + ms
            by_class[n.class_name] = by_class.get(n.class_name, 0) + ms

            parts = n.class_name.split(".")
            if len(parts) >= 2:
                if parts[0] == "net" and parts[1] in ("minecraft", "neoforged"):
                    pk = f"{parts[0]}.{parts[1]}"
                elif parts[0] in ("java", "jdk", "sun"):
                    pk = "jvm/stdlib"
                elif f"{parts[0]}.{parts[1]}" in ("com.mojang", "com.google", "io.netty",
                                                  "it.unimi", "org.apache"):
                    pk = "libs"
                else:
                    pk = ".".join(parts[:3])
                by_pkg[pk] = by_pkg.get(pk, 0) + ms

        print("\n--- Top 15 packages (mod-level rollup) ---")
        for k, ms in sorted(by_pkg.items(), key=lambda x: -x[1])[:15]:
            print(f"  {ms:>10.0f} ms  {fmt_pct(ms, total)}  {k}")

        print("\n--- Top 15 classes ---")
        for k, ms in sorted(by_class.items(), key=lambda x: -x[1])[:15]:
            print(f"  {ms:>10.0f} ms  {fmt_pct(ms, total)}  {k}")

        print("\n--- Top 20 methods ---")
        for k, ms in sorted(by_method.items(), key=lambda x: -x[1])[:20]:
            print(f"  {ms:>10.0f} ms  {fmt_pct(ms, total)}  {k}")

        # Roots: nodes nothing references via children_refs
        refd = set()
        for n in t.children:
            refd.update(n.children_refs)
        roots = [(sum(n.times) if n.times else 0, n)
                 for i, n in enumerate(t.children) if i not in refd]
        if roots:
            print("\n--- Root frames (top 10) — high-level tick breakdown ---")
            for ms, n in sorted(roots, key=lambda x: -x[0])[:10]:
                print(f"  {ms:>10.0f} ms  {fmt_pct(ms, total)}  {n.class_name}.{n.method_name}")
        print()


if __name__ == "__main__":
    main()
