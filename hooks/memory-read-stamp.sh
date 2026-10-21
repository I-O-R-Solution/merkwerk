#!/bin/bash
# memory-read-stamp.sh — PostToolUse(Read) hook
#
# Stempelt last_used: <today> wenn eine Memory-Datei GELESEN wird (Lazy-Load).
# Schliesst die Messluecke der Kalte-Kandidaten-Regel: vorher stempelte NUR der
# Trigger-Router, also sahen lazy ueber den Index geladene Memories "nie
# benutzt" aus — die Kalte-Regel mass auf fast leerem Signal. Jetzt erzeugt
# jeder Read ein Signal. Damit misst die Regel Realitaet.
#
# Advisory, silent, exit 0. Throttle: max 1 Frontmatter-Rewrite pro Datei/Tag.
#
# BURST-FILTER (31.07.2026): Massenlesen ist kein Gebrauch. Ein Audit-, Budget-
# oder Healthcheck-Lauf liest ALLE Memories in Minuten und stempelte damit das
# Signal zu, das er selbst auswerten soll — die Kalte-Kandidaten-Regel mass am
# Ende den Pruefer statt die Arbeit. Gemessen am 31.07.: Audit-Tage 64/55/41
# Stempel, hoechster normaler Arbeitstag 13 (ueber 24 h, nicht 15 min).
# Ab BURST_MAX verschiedenen Memories in BURST_WINDOW wird nicht mehr gestempelt
# UND der bereits gesetzte Teil des Schwungs zurueckgenommen. Der Filter braucht
# keinen Schalter und kein Sonderwissen ueber den Audit: er erkennt jeden Sweep
# am einzigen Merkmal, das ihn vom Gebrauch unterscheidet — der Breite.
# Gegenprobe: tests/memory-read-stamp.test.sh

set -u

# Ueberschreibbar NUR fuer die Gegenprobe (memory-read-stamp.test.sh) — im
# Normalbetrieb setzt niemand diese Variablen.
BURST_MAX="${MEMORY_BURST_MAX:-10}"        # verschiedene Memories ...
BURST_WINDOW="${MEMORY_BURST_WINDOW:-900}" # ... in 15 Minuten

CLAUDE_HOME="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${HERE}/lib/trigger-map.sh"
# Explizites if statt `&& ||` (Letzteres faellt bei Source-Exit!=0 faelschlich
# in den exit-Zweig). Ohne Lib kein Stempel — advisory.
if [ -f "$LIB" ]; then . "$LIB"; else exit 0; fi

# Pfad der gelesenen Datei aus dem PostToolUse-JSON (tool_input.file_path)
INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{try{process.stdout.write(JSON.parse(d).tool_input?.file_path||'')}catch{process.stdout.write('')}})" 2>/dev/null)
[ -z "$FILE" ] && exit 0

# Windows-Backslashes vereinheitlichen, damit grep/sed die Datei oeffnen koennen
FILE="${FILE//\\//}"

# Nur echte Memory-Dateien: unter einem memory/-Ordner und .md ...
case "$FILE" in
  */memory/*.md) ;;
  *) exit 0 ;;
esac
# ... aber NICHT die Index-/Routing-/Audit-Dateien (keine Memories)
case "$FILE" in
  */memory/audits/*)            exit 0 ;;
  */MEMORY.md|*/trigger_map.md) exit 0 ;;
esac

[ -f "$FILE" ] || exit 0
# Nur Frontmatter-Dateien anfassen (erste Zeile ---), sonst kein Stempel-Ziel
head -n1 "$FILE" 2>/dev/null | grep -qE '^---\r?$' || exit 0

TODAY=$(date +%Y-%m-%d)

# Throttle: heute schon gestempelt -> nichts tun (kein Rewrite, kein Git-Noise).
# Bleibt VOR dem Burst-Log, sonst fuellt sich das Log mit No-Ops.
grep -qE "^last_used: ${TODAY}\r?$" "$FILE" && exit 0

# --- Burst-Filter -----------------------------------------------------------
CACHE_DIR="${CLAUDE_HOME}/.cache"
BURST_LOG="${CACHE_DIR}/read_burst.log"      # epoch <TAB> pfad <TAB> alter_wert
BURST_MARK="${CACHE_DIR}/read_burst.undone"  # epoch der letzten Ruecknahme
mkdir -p "$CACHE_DIR" 2>/dev/null

NOW=$(date +%s)
CUTOFF=$(( NOW - BURST_WINDOW ))

# Ein awk-Pass: Log auf das Fenster beschneiden UND verschiedene Pfade zaehlen
# (kein Subprozess pro Zeile — unter Git-Bash kostet jeder Prozessstart spuerbar).
DISTINCT=0
if [ -f "$BURST_LOG" ]; then
  DISTINCT=$(awk -F'\t' -v cut="$CUTOFF" -v keep="${BURST_LOG}.tmp" '
    $1 >= cut { print > keep; seen[$2]=1 }
    END { print length(seen) }
  ' "$BURST_LOG" 2>/dev/null)
  [ -f "${BURST_LOG}.tmp" ] && mv "${BURST_LOG}.tmp" "$BURST_LOG" || : > "$BURST_LOG"
fi
[ -z "$DISTINCT" ] && DISTINCT=0

# Traegt der aktuelle Pfad noch nicht zum Fenster bei, zaehlt er jetzt mit
grep -qF "	${FILE}	" "$BURST_LOG" 2>/dev/null || DISTINCT=$(( DISTINCT + 1 ))

if [ "$DISTINCT" -gt "$BURST_MAX" ]; then
  # Sweep erkannt: nicht stempeln. Den bereits gesetzten Teil einmal pro
  # Fenster zurueckrollen (Marker verhindert Mehrfach-Ruecknahme).
  UNDONE=0
  [ -f "$BURST_MARK" ] && UNDONE=$(cat "$BURST_MARK" 2>/dev/null)
  case "$UNDONE" in ''|*[!0-9]*) UNDONE=0 ;; esac
  if [ "$UNDONE" -lt "$CUTOFF" ]; then
    while IFS=$'\t' read -r _ts path prev; do
      [ -n "${path:-}" ] && tm_unstamp_last_used "$path" "${prev:-}"
    done < "$BURST_LOG"
    printf '%s' "$NOW" > "$BURST_MARK"
  fi
  exit 0
fi

# Unter der Schwelle: alten Wert sichern, dann stempeln
PREV=$(tm_read_last_used "$FILE")
printf '%s\t%s\t%s\n' "$NOW" "$FILE" "$PREV" >> "$BURST_LOG"

tm_stamp_last_used "$FILE" "$TODAY"
exit 0
