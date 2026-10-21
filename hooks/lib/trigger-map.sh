#!/bin/bash
# trigger-map.sh — gemeinsame Parse-/Stempel-Bibliothek (KEIN ausfuehrbarer Hook)
#
# Single Source of Truth fuer das trigger_map.md-Format UND die last_used-
# Stempelung. Vorher lebte beides doppelt (Parser-Zwilling in
# memory-trigger-router.sh + memory-system-healthcheck.sh; Stempel inline im
# Router). Bei Format-Aenderung war "beide anfassen" Pflicht — Drift-Risiko.
# Diese Lib loest das: Format/Stempel an EINER Stelle, Konsumenten source-n sie.
#
# Konsumenten:
#   - hooks/memory-trigger-router.sh   (tm_parse + tm_stamp_last_used)
#   - hooks/memory-system-healthcheck.sh (tm_parse + tm_eval_pairs)
#   - hooks/memory-read-stamp.sh        (tm_stamp_last_used)
#
# Format-SSoT bleibt der Kopf von memory/trigger_map.md. Aendert sich das
# Format, NUR diese Lib anfassen.

# --- tm_parse <trigger_map.md> ----------------------------------------------
# Gibt die rohen Mapping-Zeilen aus: jede Zeile innerhalb eines ```-Codeblocks
# die " ||| " enthaelt. Identisch zum frueheren Inline-awk des Routers.
tm_parse() {
  awk '
    /^```$/ { in_block = !in_block; next }
    in_block && / \|\|\| / { print }
  ' "$1"
}

# --- tm_eval_pairs <trigger_map.md> -----------------------------------------
# Gibt pro "# eval:"-Zeile (Soll-Prompt) eine Zeile "pattern<TAB>prompt" aus.
# pattern = erste Spalte der zuletzt gesehenen Mapping-Zeile im selben Block.
# Fuer den Healthcheck-Selbsttest (matcht das Pattern seinen Soll-Prompt?).
tm_eval_pairs() {
  awk '
    /^```$/ { in_block = !in_block; current_pattern=""; next }
    in_block && / \|\|\| / {
      n = index($0, " ||| ")
      pat = substr($0, 1, n-1)
      sub(/[[:space:]]+$/, "", pat)
      current_pattern = pat
      next
    }
    in_block && /^# eval:/ {
      prompt = $0
      sub(/^# eval:[[:space:]]*/, "", prompt)
      if (current_pattern != "" && prompt != "")
        print current_pattern "\t" prompt
    }
  ' "$1"
}

# --- tm_stamp_last_used <memory-file> <today> -------------------------------
# Setzt last_used: <today> idempotent in der Memory-Frontmatter:
#   - Feld existiert  -> Datum ersetzen
#   - kein Feld, aber verified: -> danach einfuegen
#   - kein verified:  -> vor schliessendem --- des Frontmatter einfuegen
# Verbatim aus dem frueheren Router-Inline-Block extrahiert.
# --- tm_read_last_used <memory-file> ----------------------------------------
# Gibt den aktuellen last_used-Wert aus, oder nichts wenn das Feld fehlt.
# Wird VOR dem Stempeln gerufen, damit ein Burst zurueckgenommen werden kann.
tm_read_last_used() {
  [ -f "$1" ] || return 0
  sed -n 's/^last_used:[[:space:]]*\([0-9-]*\).*/\1/p' "$1" | head -n1
}

# --- tm_unstamp_last_used <memory-file> [alter-wert] ------------------------
# Macht EINEN Stempel rueckgaengig: setzt last_used auf den alten Wert zurueck,
# oder entfernt die Zeile ganz, wenn das Feld vorher nicht existierte.
# Fasst ausschliesslich die last_used-Zeile an — nie den Rumpf der Memory.
tm_unstamp_last_used() {
  local abs_path="$1" prev="${2:-}"
  [ -f "$abs_path" ] || return 1
  grep -q '^last_used:' "$abs_path" || return 0
  if [ -n "$prev" ]; then
    sed -i.bak "s/^last_used:.*/last_used: ${prev}/" "$abs_path" && rm -f "${abs_path}.bak"
  else
    sed -i.bak '/^last_used:/d' "$abs_path" && rm -f "${abs_path}.bak"
  fi
}

tm_stamp_last_used() {
  local abs_path="$1" today="$2"
  [ -f "$abs_path" ] || return 1
  if grep -q '^last_used:' "$abs_path"; then
    sed -i.bak "s/^last_used:.*/last_used: ${today}/" "$abs_path" && rm -f "${abs_path}.bak"
  elif grep -q '^verified:' "$abs_path"; then
    sed -i.bak "/^verified:/a last_used: ${today}" "$abs_path" && rm -f "${abs_path}.bak"
  else
    awk -v today="$today" '
      BEGIN { count=0; inserted=0 }
      /^---$/ { count++; if (count==2 && !inserted) { print "last_used: " today; inserted=1 } print; next }
      { print }
    ' "$abs_path" > "${abs_path}.tmp" && mv "${abs_path}.tmp" "$abs_path"
  fi
}
