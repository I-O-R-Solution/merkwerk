#!/bin/bash
# episode-cleanup.sh — Episodic Memory Layer Verfall
# Loescht Episoden hart wenn aelter als 90 Tage UND nicht in _promoted.txt.
# Wird vom /merkwerk:memory-audit (apply) ausgefuehrt, NICHT vom Hook-System.
#
# Hintergrund: Two-Tier Memory Plan, Komponente 3 Verfall-Mechanik.
# Konsistent mit Forgetting-Curve — was nicht promoted wurde, war Rauschen.
#
# Output: silent ausser bei Loeschungen + Drift-Hinweisen. Anzahl loeschungen
# auf stdout — Audit-Skill nutzt das fuer "Episodic-Cleanup"-Sektion.

set -u

CLAUDE_HOME="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
EPISODES_DIR="${CLAUDE_HOME}/episodes"
PROMOTED_INDEX="${EPISODES_DIR}/_promoted.txt"
MAX_AGE_DAYS=90

# Gemeinsamer Episodic-Helfer (ep_canon/ep_exists, cwd-unabhaengig). Fehlt er,
# NICHT raten und NICHT loeschen — sicher aussteigen. Explizites if statt
# `&& ||` (Letzteres faellt bei Source-Exit!=0 faelschlich in den exit-Zweig).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${HERE}/lib/episodes.sh"
if [ -f "$LIB" ]; then
  . "$LIB"
else
  echo "Episodic-Cleanup: lib/episodes.sh fehlt — abgebrochen (kein Risiko-Loeschen)." >&2
  exit 0
fi

[ -d "$EPISODES_DIR" ] || exit 0
[ -f "$PROMOTED_INDEX" ] || touch "$PROMOTED_INDEX"

deleted=0
drift_cleaned=0

# 1. Drift-Schutz: Eintraege in _promoted.txt deren File nicht mehr existiert
#    silent entfernen (verhindert dass tote Pfade ueberleben)
#    Schwellen-Guard (2026-06-13): wirken >20% der Eintraege tot, ist das fast
#    sicher ein Bug/Pfadproblem (Beinahe-Unfall heute Nacht: alle 15 Eintraege
#    "tot" durch cwd-Drift) — dann NICHT entfernen, nur warnen.
#    Ein Durchlauf: baut den bereinigten Index in tmp UND zaehlt tot/total.
#    Existenz-Check toleriert drei Formate und darf NIE vom cwd abhaengen
#    (Vorfall 2026-06-13: Lauf mit cwd=episodes/ liess alle 15 gueltigen
#    Eintraege "tot" aussehen): relativ zu episodes/ ("2026-05/abc.md"),
#    relativ zu ~/.claude ("episodes/2026-05/abc.md" — das real von allen
#    Audits geschriebene Format), absolut.
if [ -s "$PROMOTED_INDEX" ]; then
  tmp_index=$(mktemp)
  total_entries=0
  dead_entries=0
  while IFS= read -r line; do
    case "$line" in ''|'#'*) echo "$line" >> "$tmp_index"; continue ;; esac
    total_entries=$(( total_entries + 1 ))
    if ep_exists "$line"; then
      echo "$(ep_canon "$line")" >> "$tmp_index"   # Survivor kanonisch normalisieren
    else
      dead_entries=$(( dead_entries + 1 ))
    fi
  done < "$PROMOTED_INDEX"

  # Schwellen-Guard: wirken >20% der Eintraege tot, ist das fast sicher ein
  # Bug/Pfadproblem (Beinahe-Unfall heute Nacht) — dann NICHTS entfernen.
  if [ "$total_entries" -gt 0 ] && [ $(( dead_entries * 5 )) -gt "$total_entries" ]; then
    rm -f "$tmp_index"
    echo "Episodic-Cleanup WARNUNG: ${dead_entries}/${total_entries} _promoted.txt-Eintraege wirken tot (>20%) — wahrscheinlich Bug/Pfadproblem, NICHTS entfernt. Manuell pruefen."
    exit 0
  fi

  drift_cleaned=$dead_entries
  mv "$tmp_index" "$PROMOTED_INDEX"
fi

# 2. Episoden iterieren — alle Files mit Pattern YYYY-MM-DD_*.md, egal ob in
#    YYYY-MM/-Subordner oder lose im Root. Format-Filter schuetzt README.md
#    und _promoted.txt vor versehentlicher Loeschung.
shopt -s nullglob 2>/dev/null

while IFS= read -r -d '' file; do
  # Promotion-Schutz: kanonische Form gegen den (in Phase 1 normalisierten)
  # Index. EIN Check statt drei Rate-Varianten — kein cwd-Einfluss mehr.
  rel="${file#${EPISODES_DIR}/}"
  if grep -Fxq "$(ep_canon "$rel")" "$PROMOTED_INDEX" 2>/dev/null; then
    continue
  fi

  # Alter pruefen via mtime (date-Kommando portable)
  if [ -n "$(find "$file" -mtime +${MAX_AGE_DAYS} -print 2>/dev/null)" ]; then
    rm -f "$file"
    deleted=$(( deleted + 1 ))
  fi
done < <(find "$EPISODES_DIR" -mindepth 1 -maxdepth 3 -type f -name '????-??-??_*.md' -print0 2>/dev/null)

# 3. Leere Monats-Subordner aufraeumen
find "$EPISODES_DIR" -mindepth 1 -maxdepth 1 -type d -empty -delete 2>/dev/null

# 4. Output (nur wenn was passiert ist)
if [ "$deleted" -gt 0 ] || [ "$drift_cleaned" -gt 0 ]; then
  msgs=()
  [ "$deleted" -gt 0 ] && msgs+=("$deleted Episoden geloescht (>${MAX_AGE_DAYS} Tage, nicht promoted)")
  [ "$drift_cleaned" -gt 0 ] && msgs+=("$drift_cleaned tote Eintraege aus _promoted.txt entfernt")
  echo "Episodic-Cleanup: $(IFS=' | '; echo "${msgs[*]}")"
fi

exit 0
