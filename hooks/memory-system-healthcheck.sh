#!/bin/bash
# memory-system-healthcheck.sh — SessionStart hook
# Selbsttest der Memory-Betriebsschicht. Silent ausser bei Befund.
#
# Lehre aus einem Rechner-Umzug: tote Hooks und fehlende Interpreter blieben
# tagelang unbemerkt, weil nichts den eigenen Betrieb prueft. Dieser Hook macht
# stille Ausfaelle laut.
#
# Checks:
#   1. Bestand angelegt (memory/, episodes/ als Git-Repos) — sonst install.sh
#   2. node + python/jq lauffaehig (Interpreter der anderen Hooks)
#   3. trigger_map.md: jedes Mapping-Ziel existiert + jede "# eval:"-Zeile
#      (Soll-Prompt) matcht ihr Pattern — faengt False Negatives wie
#      "committe" vs \bcommit\b
#   4. episodes/_promoted.txt: tote Eintraege (Drift-Fruehwarnung)
#   5. memory-/episodes-Repo: Commit ueberfaellig, Push-Rueckstand;
#      projects-Repo: pro Workspace ueberfaellig, UND ein origin ist dort ein
#      Befund (Projekt-Memories bleiben lokal)
#   6. Index-Deckel am Commit erreichbar (core.hooksPath je Repo)
#
# Advisory only — exit 0 immer. Jeder Check defensiv, Gesamtlaufzeit <2s.

set -u

CLAUDE_HOME="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${HERE}/.." && pwd)"
issues=()

# Gemeinsame trigger_map-Lib (Format-SSoT, kein Parser-Zwilling). Fehlt sie,
# ist der trigger_map-Check blind — als Befund melden, aber weiterlaufen.
LIB="${HERE}/lib/trigger-map.sh"
if [ -f "$LIB" ]; then . "$LIB"; LIB_OK=1; else LIB_OK=0; fi
EP_LIB="${HERE}/lib/episodes.sh"
if [ -f "$EP_LIB" ]; then . "$EP_LIB"; EP_LIB_OK=1; else EP_LIB_OK=0; fi

# --- 1. Bestand angelegt? ------------------------------------------------------
for repo in memory episodes; do
  if [ ! -d "${CLAUDE_HOME}/${repo}/.git" ]; then
    issues+=("${repo}/ ist kein Git-Repo — Bestand nicht eingerichtet. Einmalig: bash \"${PLUGIN_ROOT}/install.sh\"")
  fi
done

# --- 2. Interpreter ----------------------------------------------------------
if ! command -v node >/dev/null 2>&1; then
  issues+=("node fehlt im PATH — Index-Deckel und Prompt-Parsing der Hooks laufen nicht")
fi
if ! python -c "import sys" >/dev/null 2>&1 && ! command -v jq >/dev/null 2>&1; then
  issues+=("weder python noch jq gefunden — Trigger-Router-Fenster ohne Persistenz (Reminder feuern bei jedem Treffer)")
fi

# --- 3. trigger_map: tote Ziele + eval-Soll-Prompts ---------------------------
TM="${CLAUDE_HOME}/memory/trigger_map.md"
if [ ! -f "$TM" ]; then
  issues+=("memory/trigger_map.md fehlt — Trigger-Routing tot (Vorlage: templates/memory/trigger_map.md)")
elif [ "$LIB_OK" -ne 1 ]; then
  issues+=("hooks/lib/trigger-map.sh fehlt — Router-/Healthcheck-Parser tot, trigger_map ungeprueft")
else
  while IFS= read -r line; do
    mempath=$(printf '%s' "$line" | awk -F' \\|\\|\\| ' '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -n "$mempath" ] && [ ! -f "${CLAUDE_HOME}/${mempath}" ]; then
      issues+=("trigger_map: totes Ziel ${mempath} — Mapping greift ins Leere")
    fi
  done < <(tm_parse "$TM")

  while IFS=$'\t' read -r pattern prompt; do
    [ -n "$pattern" ] && [ -n "$prompt" ] || continue
    if ! printf '%s' "$prompt" | grep -Pqi -- "$pattern" 2>/dev/null; then
      issues+=("trigger_map: Soll-Prompt matcht NICHT: \"${prompt}\" (Pattern beginnt: ${pattern:0:45}…)")
    fi
  done < <(tm_eval_pairs "$TM")
fi

# --- 4. _promoted.txt Drift ----------------------------------------------------
PROM="${CLAUDE_HOME}/episodes/_promoted.txt"
if [ -f "$PROM" ] && [ "$EP_LIB_OK" -eq 1 ]; then
  dead=0
  while IFS= read -r e; do
    case "$e" in ''|'#'*) continue ;; esac
    ep_exists "$e" || dead=$(( dead + 1 ))
  done < "$PROM"
  if [ "$dead" -gt 0 ]; then
    issues+=("_promoted.txt: ${dead} tote Eintraege — beim naechsten /merkwerk:memory-audit pruefen (Cleanup bereinigt <20% automatisch)")
  fi
fi

# --- 5. Repos: Commit-Drift + Backup-Kette -------------------------------------
AUTOCOMMIT="bash \"${PLUGIN_ROOT}/hooks/memory-auto-commit.sh\" \"drift\" <pfade>"
for repo in memory episodes; do
  RDIR="${CLAUDE_HOME}/${repo}"
  [ -d "${RDIR}/.git" ] || continue
  if [ -n "$(git -C "$RDIR" status --porcelain 2>/dev/null)" ]; then
    last_commit=$(git -C "$RDIR" log -1 --format=%ct 2>/dev/null || echo 0)
    if [ "$last_commit" -gt 0 ]; then
      age_days=$(( ( $(date +%s) - last_commit ) / 86400 ))
      if [ "$age_days" -ge 7 ]; then
        issues+=("${repo}-Repo: uncommittete Aenderungen, letzter Commit vor ${age_days} Tagen — /merkwerk:memory-audit oder: ${AUTOCOMMIT}")
      fi
    fi
  fi
  if git -C "$RDIR" remote get-url origin >/dev/null 2>&1; then
    unpushed=$(git -C "$RDIR" rev-list --count @{u}..HEAD 2>/dev/null || echo 0)
    if [ "${unpushed:-0}" -ge 1 ]; then
      issues+=("${repo}-Repo: ${unpushed} Commit(s) nicht gepusht — Remote-Backup hinkt (git -C \"${RDIR}\" push)")
    fi
  fi
done

# projects-Repo (Projekt-Memory): pro Workspace pruefen, nicht pro Repo. Ein
# Audit-Commit in einem anderen Workspace setzt das Repo-Alter zurueck, waehrend
# ein Workspace wochenlang ungesichert liegt.
PDIR="${CLAUDE_HOME}/projects"
if [ -d "${PDIR}/.git" ]; then
  while IFS= read -r ws; do
    [ -n "$ws" ] || continue
    last_ws=$(git -C "$PDIR" log -1 --format=%ct -- "$ws/memory" 2>/dev/null)
    [ -n "$last_ws" ] || last_ws=0
    age_days=$(( ( $(date +%s) - last_ws ) / 86400 ))
    if [ "$age_days" -ge 7 ]; then
      n_ws=$(git -C "$PDIR" status --porcelain -- "$ws/memory" 2>/dev/null | grep -c .)
      issues+=("projects/${ws}: ${n_ws} uncommittete Notiz-Dateien, letzter Commit vor ${age_days} Tagen — ${AUTOCOMMIT}")
    fi
  done < <(git -C "$PDIR" status --porcelain 2>/dev/null | sed -E 's/^.{3}//; s/^"//' | grep '/memory/' | cut -d/ -f1 | sort -u)
  # Projekt-Memories tragen Betriebsinterna und bleiben lokal. Ein origin ist
  # hier kein Backup, sondern ein Leck — der Auto-Commit pusht es nie, aber ein
  # Hand-Push wuerde.
  if git -C "$PDIR" remote get-url origin >/dev/null 2>&1; then
    issues+=("projects-Repo hat ein origin-Remote — Projekt-Memories sollen lokal bleiben (git -C \"${PDIR}\" remote remove origin)")
  fi
fi

# --- 6. Index-Deckel am Commit erreichbar? ------------------------------------
# install.sh setzt je Repo core.hooksPath auf git-hooks/ des Plugins. Zeigt die
# Einstellung ins Leere (Plugin verschoben, Ordner geloescht), faellt der Deckel
# lautlos aus — genau die Ausfall-Klasse dieses Checks.
for repo in memory episodes projects; do
  RDIR="${CLAUDE_HOME}/${repo}"
  [ -d "${RDIR}/.git" ] || continue
  hp=$(git -C "$RDIR" config core.hooksPath 2>/dev/null || true)
  [ -z "$hp" ] && hp=$(git config --global core.hooksPath 2>/dev/null || true)
  if [ -z "$hp" ]; then
    issues+=("${repo}-Repo: core.hooksPath nicht gesetzt — Index-Deckel am Commit inaktiv: git -C \"${RDIR}\" config core.hooksPath \"${PLUGIN_ROOT}/git-hooks\"")
  elif [ ! -f "${hp}/pre-commit" ]; then
    issues+=("${repo}-Repo: core.hooksPath zeigt auf ${hp} — dort liegt kein pre-commit, Deckel inaktiv")
  fi
done

# --- Output: silent ausser bei Befund ------------------------------------------
[ ${#issues[@]} -eq 0 ] && exit 0

echo ""
echo "Memory-System-Healthcheck (${#issues[@]} Befund(e)):"
for i in "${issues[@]}"; do
  echo "  - $i"
done
echo ""

exit 0
