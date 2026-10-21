#!/bin/bash
# memory-read-stamp.test.sh — Gegenprobe fuer den Burst-Filter
#
# Laeuft vollstaendig in einem Temp-HOME: keine echte Memory wird angefasst.
# Enthaelt eine SABOTAGE-Probe (T10) — sie beweist, dass der Burst-Test
# ueberhaupt rot werden KANN. Ohne sie waere gruen wertlos
# (eine Suite, die nie rot werden kann, misst nichts).
#
# Aufruf: bash tests/memory-read-stamp.test.sh

set -u
SRC_HOME="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
TODAY=$(date +%Y-%m-%d)

red()  { echo "  ROT  $*"; FAIL=$((FAIL+1)); }
green(){ echo "  gruen $*"; PASS=$((PASS+1)); }
chk()  { if [ "$2" = "$3" ]; then green "$1"; else red "$1 (erwartet '$3', war '$2')"; fi; }

# --- isolierte Umgebung aufbauen --------------------------------------------
setup() {
  TMP=$(mktemp -d)
  export HOME="$TMP"
  mkdir -p "$TMP/.claude/hooks/lib" "$TMP/.claude/memory" "$TMP/.claude/.cache"
  cp "$SRC_HOME/hooks/lib/trigger-map.sh" "$TMP/.claude/hooks/lib/"
  cp "$SRC_HOME/hooks/memory-read-stamp.sh" "$TMP/.claude/hooks/"
  HOOK="$TMP/.claude/hooks/memory-read-stamp.sh"
  MEM="$TMP/.claude/memory"
}
teardown() { [ -n "${TMP:-}" ] && rm -rf "$TMP"; export HOME="$REAL_HOME"; }
REAL_HOME="$HOME"

# mkmem <name> [last_used-wert]  — legt eine Memory mit Frontmatter an
mkmem() {
  local f="$MEM/$1.md"
  { echo "---"
    echo "name: $1"
    echo "type: feedback"
    echo "verified: 2026-01-01"
    [ -n "${2:-}" ] && echo "last_used: $2"
    echo "---"
    echo ""
    echo "RUMPF-KANARIENVOGEL $1"
  } > "$f"
  echo "$f"
}
# read_hook <pfad> — simuliert einen PostToolUse(Read)
read_hook() { printf '{"tool_input":{"file_path":"%s"}}' "$1" | bash "$HOOK" >/dev/null 2>&1; }
lu() { sed -n 's/^last_used:[[:space:]]*//p' "$1" | head -n1; }

echo "=== Burst-Filter Gegenprobe ==="

# T1 — Einzel-Read stempelt
setup
f=$(mkmem solo "2026-01-05"); read_hook "$f"
chk "T1 Einzel-Read stempelt" "$(lu "$f")" "$TODAY"

# T2 — Throttle: zweiter Read am selben Tag schreibt nicht erneut
before=$(md5sum < "$f"); read_hook "$f"; after=$(md5sum < "$f")
chk "T2 Throttle, kein zweiter Rewrite" "$([ "$before" = "$after" ] && echo gleich || echo geaendert)" "gleich"
teardown

# T3 — 10 Reads bleiben unter der Schwelle und werden alle gestempelt
setup; export MEMORY_BURST_MAX=10 MEMORY_BURST_WINDOW=900
ok=ja
for i in $(seq 1 10); do f=$(mkmem "m$i" "2026-01-05"); read_hook "$f"
  [ "$(lu "$f")" = "$TODAY" ] || ok=nein; done
chk "T3 10 Reads alle gestempelt" "$ok" "ja"

# T4 — der 11. loest den Burst aus: nicht gestempelt UND die 10 zurueckgerollt
f11=$(mkmem m11 "2026-01-05"); read_hook "$f11"
chk "T4a 11. Read nicht gestempelt" "$(lu "$f11")" "2026-01-05"
rolled=ja
for i in $(seq 1 10); do [ "$(lu "$MEM/m$i.md")" = "2026-01-05" ] || rolled=nein; done
chk "T4b die ersten 10 zurueckgerollt" "$rolled" "ja"

# T5 — Ruecknahme stellt den ALTEN Wert her, loescht ihn nicht
chk "T5 alter Wert wiederhergestellt" "$(lu "$MEM/m1.md")" "2026-01-05"

# T9 — der Rumpf blieb unangetastet
chk "T9 Rumpf unversehrt" "$(grep -c 'RUMPF-KANARIENVOGEL m1' "$MEM/m1.md")" "1"
teardown

# T6 — Datei OHNE last_used: Ruecknahme entfernt die Zeile wieder
setup; export MEMORY_BURST_MAX=3 MEMORY_BURST_WINDOW=900
for i in 1 2 3; do read_hook "$(mkmem "n$i")"; done
read_hook "$(mkmem n4)"
chk "T6 Feld wieder entfernt" "$(grep -c '^last_used:' "$MEM/n1.md")" "0"
teardown

# T7 — nach Fenster-Ablauf wird wieder gestempelt (alte Log-Eintraege zaehlen nicht)
setup; export MEMORY_BURST_MAX=3 MEMORY_BURST_WINDOW=900
old=$(( $(date +%s) - 5000 ))
for i in 1 2 3 4 5; do printf '%s\t%s\t\n' "$old" "$MEM/alt$i.md" >> "$TMP/.claude/.cache/read_burst.log"; done
f=$(mkmem frisch "2026-01-05"); read_hook "$f"
chk "T7 nach Fenster wieder gestempelt" "$(lu "$f")" "$TODAY"
teardown

# T8 — Nicht-Memory-Dateien werden ignoriert
setup
mkdir -p "$TMP/.claude/memory/audits"
printf -- "---\nname: x\n---\n" > "$TMP/.claude/memory/audits/2026-01-01.md"
read_hook "$TMP/.claude/memory/audits/2026-01-01.md"
chk "T8a audits/ ignoriert" "$(grep -c '^last_used:' "$TMP/.claude/memory/audits/2026-01-01.md")" "0"
printf -- "---\nname: i\n---\n" > "$MEM/MEMORY.md"
read_hook "$MEM/MEMORY.md"
chk "T8b MEMORY.md ignoriert" "$(grep -c '^last_used:' "$MEM/MEMORY.md")" "0"
teardown

# T10 — SABOTAGE: Filter ausgehebelt, T4 MUSS jetzt rot werden.
# Beweist, dass der Burst-Test ueberhaupt fehlschlagen kann.
setup; export MEMORY_BURST_MAX=100000 MEMORY_BURST_WINDOW=900
for i in $(seq 1 10); do read_hook "$(mkmem "s$i" "2026-01-05")"; done
f=$(mkmem s11 "2026-01-05"); read_hook "$f"
if [ "$(lu "$f")" = "$TODAY" ]; then
  green "T10 Sabotage-Probe: ohne Filter wird gestempelt (Test kann rot werden)"
else
  red "T10 Sabotage-Probe wirkungslos — der Burst-Test beweist nichts"
fi
teardown

# T11 — ZWEITE SABOTAGE, gezielt gegen die Ruecknahme: tm_unstamp_last_used
# wird zum No-Op entkernt. T4b MUSS jetzt rot werden. Ohne diese Probe waere
# T4b auch dann gruen, wenn das Zurueckrollen nie gelaufen ist — die Schwellen-
# Sabotage (T10) deckt genau diesen Teil NICHT ab.
setup; export MEMORY_BURST_MAX=3 MEMORY_BURST_WINDOW=900
cat >> "$TMP/.claude/hooks/lib/trigger-map.sh" <<'SABOEOF'
tm_unstamp_last_used() { return 0; }   # SABOTAGE
SABOEOF
for i in 1 2 3; do read_hook "$(mkmem "u$i" "2026-01-05")"; done
read_hook "$(mkmem u4 "2026-01-05")"
if [ "$(lu "$MEM/u1.md")" = "$TODAY" ]; then
  green "T11 Ruecknahme-Sabotage: ohne sie bleibt der Stempel stehen (T4b beweist etwas)"
else
  red "T11 Ruecknahme-Sabotage wirkungslos — T4b wuerde auch ohne Zurueckrollen gruen"
fi
teardown

unset MEMORY_BURST_MAX MEMORY_BURST_WINDOW
echo
echo "=== $PASS gruen, $FAIL rot ==="
[ "$FAIL" -eq 0 ] || exit 1
