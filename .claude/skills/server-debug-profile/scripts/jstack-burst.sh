#!/usr/bin/env bash
# jstack-burst.sh — capture 5 jstacks 2s apart, summarize Server-thread top frames.
# Use when the server is stalling and you want to know if it's stuck on one thing
# or broadly busy. Run this — if the same method appears in 4-5 of 5 dumps, you
# found the bottleneck. If stacks differ each dump, the load is broad.
#
# Usage: jstack-burst.sh [pid]
#   pid is autodetected from the minecraft user's java process if omitted.
set -euo pipefail

PID="${1:-}"
if [ -z "$PID" ]; then
  PID=$(sudo ps -u minecraft -o pid,cmd | grep -E "java.*neoforge" | head -1 | awk '{print $1}')
fi
if [ -z "$PID" ]; then
  echo "ERROR: no minecraft java process found" >&2
  exit 1
fi
echo "PID: $PID"

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

for i in 1 2 3 4 5; do
  sudo -u minecraft jstack "$PID" > "$DIR/js_$i.txt" 2>&1
  echo "  dump $i captured ($(wc -l < "$DIR/js_$i.txt") lines)"
  [ "$i" -lt 5 ] && sleep 2
done

echo
echo "=== Top frame of Server thread across 5 dumps ==="
for i in 1 2 3 4 5; do
  echo "--- dump $i ---"
  awk '/^"Server thread"/{flag=1; getline; print; next} /^[ \t]/&&flag{print; if(/^\s*$/) flag=0}' "$DIR/js_$i.txt" | head -8
done

echo
echo "=== Aggregate: which method does the Server thread keep landing in? ==="
for i in 1 2 3 4 5; do
  awk '/^"Server thread"/{flag=1; next} flag&&/^\tat /{print; flag=0; exit}' "$DIR/js_$i.txt"
done | sort | uniq -c | sort -rn

echo
echo "=== Worker-Main thread states (chunk gen workers) ==="
for i in 1 2 3 4 5; do
  RUNNABLE=$(awk '/^"Worker-Main-/{name=$0} /java.lang.Thread.State: RUNNABLE/{print name}' "$DIR/js_$i.txt" | wc -l)
  WAITING=$(awk '/^"Worker-Main-/{name=$0} /WAITING|TIMED_WAITING/{print name}' "$DIR/js_$i.txt" | wc -l)
  echo "  dump $i: RUNNABLE=$RUNNABLE WAITING=$WAITING"
done

echo
echo "All 5 dumps preserved at $DIR (cleaned on script exit; copy now if you want to keep them)."
read -t 5 -p "Keep dumps? [y/N] " keep || keep=N
if [[ "${keep,,}" == "y" ]]; then
  KEEP=$(mktemp -d -p "$HOME" jstack-burst-XXXX)
  cp "$DIR"/* "$KEEP/"
  echo "kept at: $KEEP"
fi
