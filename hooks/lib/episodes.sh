#!/bin/bash
# episodes.sh — gemeinsame Helfer fuer den Episodic Layer (KEIN Hook).
#
# Kanonisches _promoted.txt-Format: relativ zu CLAUDE_HOME MIT episodes/-Praefix,
# z.B. "episodes/2026-05/2026-05-20_x.md" (genau das schreiben die Audits).
#
# Frueher rieten episode-cleanup.sh + healthcheck Check 4 drei Pfad-Formate per
# OR-Kette — und der Beinahe-Unfall 2026-06-13 kam genau daher (Lauf mit
# cwd=episodes/ liess alle Eintraege "tot" aussehen). Wurzel-Fix: NIE raten,
# sondern auf kanonisch NORMALISIEREN und dann EINEN cwd-unabhaengigen Check.
#
# Konsumenten: hooks/episode-cleanup.sh, hooks/memory-system-healthcheck.sh

: "${CLAUDE_HOME:=${CLAUDE_CONFIG_DIR:-${HOME}/.claude}}"

# ep_canon <entry> -> kanonische Form (relativ zu ~/.claude, episodes/-Praefix)
ep_canon() {
  local e="$1"
  e="${e#"${CLAUDE_HOME}"/}"          # absoluter CLAUDE_HOME-Pfad -> relativ
  case "$e" in
    episodes/*) ;;                    # schon kanonisch
    /*)         ;;                    # fremder absoluter Pfad: unveraendert
    *)          e="episodes/$e" ;;    # episodes-relativ -> Praefix dazu
  esac
  printf '%s' "$e"
}

# ep_exists <entry> -> exit 0 wenn die Episode existiert (cwd-unabhaengig)
ep_exists() {
  local c; c="$(ep_canon "$1")"
  case "$c" in
    /*) [ -f "$c" ] ;;                      # absoluter Fremdpfad
    *)  [ -f "${CLAUDE_HOME}/${c}" ] ;;      # kanonisch unter CLAUDE_HOME
  esac
}
