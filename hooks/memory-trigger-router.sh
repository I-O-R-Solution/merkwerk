#!/bin/bash
# memory-trigger-router.sh — UserPromptSubmit hook
# Liest ~/.claude/memory/trigger_map.md, matcht Patterns gegen Prompt,
# zeigt Memory-Pfade als Reminder, stempelt last_used: <today> in Memories.
#
# Hintergrund: Solo-Memories (Pattern lebt nur in der Memory) werden per
# Lazy-Load sonst nie geladen. Der Router macht sie zur richtigen Zeit sichtbar.
#
# Verhalten:
# - Cross-Workspace aktiv (kein cwd-Filter)
# - Max 3 Treffer pro Prompt
# - Eine Memory triggert max 1x pro 30 Min (State in .cache/trigger_history.json)
# - Bei Match: last_used: <today> in Memory-Frontmatter setzen
# - Advisory only — kein Block

set -u

CLAUDE_HOME="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
TRIGGER_MAP="${CLAUDE_HOME}/memory/trigger_map.md"
CACHE_DIR="${CLAUDE_HOME}/.cache"
HISTORY_FILE="${CACHE_DIR}/trigger_history.json"
HITS_LOG="${CACHE_DIR}/trigger_hits.log"  # append-only Treffer-Log: "timestamp|memory_pfad" (Beleg-Quelle Audit Achse 4/6)
WINDOW_SECONDS=1800  # 30 Min
MAX_HITS=3

# Gemeinsame Parse-/Stempel-Lib (Format-SSoT). Fehlt sie -> advisory aussteigen.
# Explizites if statt `&& ||`: Letzteres wuerde bei Source-Exit!=0 faelschlich
# den ||-Zweig feuern (Hook still aus, obwohl Lib geladen).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${HERE}/lib/trigger-map.sh"
if [ -f "$LIB" ]; then
  # shellcheck source=lib/trigger-map.sh
  . "$LIB"
else
  echo "WARN: ${LIB} fehlt — Trigger-Routing inaktiv." >&2
  exit 0
fi

# Trigger-Map muss existieren
[ -f "$TRIGGER_MAP" ] || exit 0

# Capability-Check: ohne jq UND ohne python kann das 30-Min-Window nicht
# persistieren -> Trigger wuerden silent jedes Mal wieder feuern.
# Loud-fail einmalig + Window-Pruefung wird dann uebersprungen.
HISTORY_BACKEND=""
if command -v jq >/dev/null 2>&1; then
  HISTORY_BACKEND="jq"
elif command -v python >/dev/null 2>&1; then
  HISTORY_BACKEND="python"
else
  echo "" >&2
  echo "WARN: memory-trigger-router benoetigt jq oder python — 30-Min-Window deaktiviert." >&2
  echo "      Trigger werden bis Setup-Fix bei jedem Match feuern (kein Block, advisory)." >&2
  echo "" >&2
fi

# Cache-Dir lazy anlegen
mkdir -p "$CACHE_DIR" 2>/dev/null
[ -f "$HISTORY_FILE" ] || echo '{}' > "$HISTORY_FILE"

# Prompt aus stdin (UserPromptSubmit-Hook erhaelt JSON)
INPUT=$(cat)
PROMPT=$(echo "$INPUT" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{try{const j=JSON.parse(d);process.stdout.write((j.prompt||'').toLowerCase())}catch{process.stdout.write('')}})" 2>/dev/null)
[ -z "$PROMPT" ] && exit 0

NOW=$(date +%s)
TODAY=$(date +%Y-%m-%d)

# Mappings parsen via Lib (tm_parse) — Format-SSoT lebt jetzt zentral in
# hooks/lib/trigger-map.sh. Healthcheck nutzt dieselbe Funktion (kein Zwilling).
mapfile -t MAPPINGS < <(tm_parse "$TRIGGER_MAP")

[ ${#MAPPINGS[@]} -eq 0 ] && exit 0

matched_lines=()
hits=0

for line in "${MAPPINGS[@]}"; do
  [ "$hits" -ge "$MAX_HITS" ] && break

  # Spalten splitten an " ||| " (drei Pipes mit Space-Padding) — eindeutig auch bei Regex-Alternationen
  pattern=$(printf '%s' "$line" | awk -F' \\|\\|\\| ' '{print $1}' | sed 's/[[:space:]]*$//')
  mempath=$(printf '%s' "$line" | awk -F' \\|\\|\\| ' '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  anlass=$(printf '%s' "$line"  | awk -F' \\|\\|\\| ' '{print $3}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  [ -z "$pattern" ] && continue
  [ -z "$mempath" ] && continue

  # Pattern match (case-insensitive, Perl-Regex fuer Word-Boundaries \b)
  if echo "$PROMPT" | grep -Pqi -- "$pattern"; then
    abs_path="${CLAUDE_HOME}/${mempath}"

    # Memory-File muss existieren — sonst skip (toter Trigger)
    [ -f "$abs_path" ] || continue

    # 30-Min-Window check via History-File. Backend wurde am Hook-Start gesetzt
    # (jq | python | leer). Bei leerem Backend: Window-Pruefung uebersprungen,
    # Trigger feuert (Warnung kam einmalig oben).
    last_fired=0
    if [ "$HISTORY_BACKEND" = "jq" ]; then
      last_fired=$(jq -r --arg key "$mempath" '.[$key] // 0' "$HISTORY_FILE" 2>/dev/null)
    elif [ "$HISTORY_BACKEND" = "python" ]; then
      if command -v cygpath >/dev/null 2>&1; then
        py_history=$(cygpath -w "$HISTORY_FILE")
      else
        py_history="$HISTORY_FILE"
      fi
      last_fired=$(python -c "
import json
try:
  d=json.load(open(r'$py_history'))
  print(d.get(r'$mempath', 0))
except Exception:
  print(0)
" 2>/dev/null)
    fi
    [ -z "$last_fired" ] && last_fired=0

    # Window-Check nur wenn Backend persistiert. Sonst durchlassen.
    if [ -n "$HISTORY_BACKEND" ]; then
      elapsed=$(( NOW - last_fired ))
      if [ "$elapsed" -lt "$WINDOW_SECONDS" ]; then
        continue  # noch im Window, skip
      fi
    fi

    # History updaten (nur wenn Backend verfuegbar)
    if [ "$HISTORY_BACKEND" = "jq" ]; then
      tmp=$(mktemp)
      jq --arg key "$mempath" --argjson ts "$NOW" '.[$key] = $ts' "$HISTORY_FILE" > "$tmp" && mv "$tmp" "$HISTORY_FILE"
    elif [ "$HISTORY_BACKEND" = "python" ]; then
      # Python-Fallback. Pfad nach Windows-Style konvertieren (Python auf Win
      # versteht /c/... nicht), sonst FileNotFoundError.
      if command -v cygpath >/dev/null 2>&1; then
        py_history=$(cygpath -w "$HISTORY_FILE")
      else
        py_history="$HISTORY_FILE"
      fi
      python -c "
import json
p=r'$py_history'
try:
  d=json.load(open(p))
except Exception:
  d={}
d[r'$mempath']=$NOW
json.dump(d,open(p,'w'))
" 2>/dev/null
    fi

    # last_used in Memory-Frontmatter setzen (idempotent) — zentral in der Lib
    tm_stamp_last_used "$abs_path" "$TODAY"

    # Treffer-Log: nur echte Fires (nach Window-Check). Der Log belegt
    # "Reminder gezeigt", nicht "Regel befolgt" — Zaehl-Quelle fuer den Audit.
    # Logging darf den Router nie brechen -> fehlertolerant.
    printf '%s|%s\n' "$(date '+%Y-%m-%dT%H:%M')" "$mempath" >> "$HITS_LOG" 2>/dev/null || true

    matched_lines+=("  - ${anlass} → ${mempath}")
    hits=$(( hits + 1 ))
  fi
done

# Wenn nichts matched: silent exit
[ ${#matched_lines[@]} -eq 0 ] && exit 0

# Reminder ausgeben
echo ""
echo "Memory-Trigger (siehe ${TRIGGER_MAP}):"
for line in "${matched_lines[@]}"; do
  echo "$line"
done
echo ""

exit 0
