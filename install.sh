#!/usr/bin/env bash
# merkwerk — Bestand einrichten (einmalig, idempotent).
#
# Das Plugin selbst installiert Claude Code (siehe README). Dieses Skript legt
# an, was ein Plugin nicht kann: die drei Memory-Repos unter CLAUDE_HOME und
# den Index-Deckel am Commit.
#
#   CLAUDE_HOME/memory/     Cross-Workspace-Memories, Index, trigger_map, Audits
#   CLAUDE_HOME/episodes/   Episoden pro Session, _promoted.txt
#   CLAUDE_HOME/projects/   nur */memory/** (Whitelist), bewusst ohne Remote
#
# CLAUDE_HOME = $CLAUDE_CONFIG_DIR, sonst ~/.claude. Bestehende Dateien werden
# nie ueberschrieben. Aufruf:  bash install.sh

set -eu

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
T="${HERE}/templates"

say() { printf '  %s\n' "$*"; }
put() { # put <quelle> <ziel>: kopiert nur, wenn das Ziel fehlt
  if [ -e "$2" ]; then say "vorhanden: ${2#"${CLAUDE_HOME}"/}"; else mkdir -p "$(dirname "$2")"; cp "$1" "$2"; say "angelegt:  ${2#"${CLAUDE_HOME}"/}"; fi
}
repo() { # repo <dir> <label>: git init + Index-Deckel per core.hooksPath
  local d="$1"
  mkdir -p "$d"
  if [ ! -d "$d/.git" ]; then git -C "$d" init -q; say "git init:  ${d#"${CLAUDE_HOME}"/}"; fi
  git -C "$d" config core.hooksPath "${HERE}/git-hooks"
}

echo "merkwerk: Bestand unter ${CLAUDE_HOME}"
mkdir -p "${CLAUDE_HOME}"

# --- memory/ -----------------------------------------------------------------
repo "${CLAUDE_HOME}/memory"
put "$T/memory/MEMORY.md"             "${CLAUDE_HOME}/memory/MEMORY.md"
put "$T/memory/trigger_map.md"        "${CLAUDE_HOME}/memory/trigger_map.md"
[ -e "${CLAUDE_HOME}/memory/feedback_beispiel_git.md" ] || [ "$(ls -A "${CLAUDE_HOME}/memory" | grep -c '\.md$')" -gt 2 ] \
  || put "$T/memory/feedback_beispiel_git.md" "${CLAUDE_HOME}/memory/feedback_beispiel_git.md"
mkdir -p "${CLAUDE_HOME}/memory/audits"

# --- episodes/ ---------------------------------------------------------------
repo "${CLAUDE_HOME}/episodes"
put "$T/episodes/README.md"           "${CLAUDE_HOME}/episodes/README.md"
[ -e "${CLAUDE_HOME}/episodes/_promoted.txt" ] || { : > "${CLAUDE_HOME}/episodes/_promoted.txt"; say "angelegt:  episodes/_promoted.txt"; }

# --- projects/ ---------------------------------------------------------------
repo "${CLAUDE_HOME}/projects"
put "$T/projects/gitignore"           "${CLAUDE_HOME}/projects/.gitignore"
if git -C "${CLAUDE_HOME}/projects" remote get-url origin >/dev/null 2>&1; then
  say "WARNUNG: projects/ hat ein origin-Remote. Projekt-Memories sollen lokal bleiben:"
  say "         git -C \"${CLAUDE_HOME}/projects\" remote remove origin"
fi

# --- Erst-Commits, damit die Repos einen HEAD haben --------------------------
for r in memory episodes projects; do
  d="${CLAUDE_HOME}/${r}"
  if ! git -C "$d" rev-parse HEAD >/dev/null 2>&1; then
    case "$r" in
      memory)   git -C "$d" add -- MEMORY.md trigger_map.md $( [ -e "$d/feedback_beispiel_git.md" ] && echo feedback_beispiel_git.md ) ;;
      episodes) git -C "$d" add -- README.md _promoted.txt ;;
      projects) git -C "$d" add -- .gitignore ;;
    esac
    git -C "$d" -c user.name="${GIT_AUTHOR_NAME:-merkwerk}" -c user.email="${GIT_AUTHOR_EMAIL:-merkwerk@localhost}" \
      commit -q -m "merkwerk: Bestand angelegt" && say "commit:    ${r}"
  fi
done

echo
echo "Fertig. Pruefen:  bash \"${HERE}/hooks/memory-system-healthcheck.sh\""
echo "Optional: privates Remote fuer memory/ und episodes/ (git remote add origin ...), nie fuer projects/."
echo "Tipp fuer die CLAUDE.md: 'Memory-Regeln: ${HERE}/docs/memory-protocol.md (bei Bedarf lesen).'"
