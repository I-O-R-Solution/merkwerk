#!/bin/bash
# memory-auto-commit.sh — Commit-Helper fuer Memory, Episodic + Projekt-Memory
# Aufgerufen von /merkwerk:memory-audit (Schritt 5) und vom Skill session-ende (1.7).
#
# Verhalten:
# - Committet NUR explizit genannte Pfade (oder, ohne Pfade, nur den bereits
#   gestageten Index). NIE pauschal.
# - Commit-Message enthaelt Datum + Trigger-Label
# - Silent ausser bei tatsaechlichen Commits (Output mit Hash)
# - Best-effort Remote-Backup: push nur wenn origin existiert; silent fail bei
#   offline — Backup darf nie blockieren
#
# Nutzung:
#   bash memory-auto-commit.sh "audit-2026-07-25" memory/a.md projects/x/memory/b.md
#   bash memory-auto-commit.sh "audit-2026-07-25"      # committet nur den Index
#
# Pfade duerfen absolut sein oder relativ zu CLAUDE_HOME (Default ~/.claude). Sie werden automatisch dem
# richtigen der drei Repos zugeordnet; Pfade ausserhalb aller drei werden gemeldet
# und ignoriert.
#
# WARUM KEIN `git add -A` (geaendert 2026-07-25, memory-audit):
# An den Memory-Repos arbeiten oft mehrere Sessions gleichzeitig. Das
# projects-Repo umfasst ~17 Workspaces — ein pauschales Stagen zog dort fremde,
# uncommittete Arbeit anderer Sessions in den Audit-Commit. Das verstiess gegen
# die Commit-Disziplin bei parallelen Sessions, also gegen genau die Regel, die der
# Audit durchsetzt.

set -u

CLAUDE_HOME="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
MEMORY_REPO="${CLAUDE_HOME}/memory"
EPISODES_REPO="${CLAUDE_HOME}/episodes"
# Projekt-Memory-Schicht, versioniert seit 2026-07-19. Eigenes Repo mit
# strikter Whitelist (nur */memory/**) und BEWUSST ohne Remote — die
# Projekt-Memories tragen typischerweise Betriebsinterna (Server, Kunden, Preise).
# Erzwungen statt nur dokumentiert, seit ein versehentlich angebundenes Remote
# wochenlang Push-Ziel war: der Push-Zweig unten schliesst dieses Repo hart aus,
# egal ob ein origin existiert.
PROJECTS_REPO="${CLAUDE_HOME}/projects"

TRIGGER="${1:-audit}"
shift || true
TODAY=$(date +%Y-%m-%d)

# Pfade den Repos zuordnen. Ein Eintrag pro Zeile, relativ zum jeweiligen Repo.
MEM_PATHS=""
EPI_PATHS=""
PRJ_PATHS=""
ORPHANS=""
# Wurde ueberhaupt ein Pfad genannt? Steuert, ob der Index-Modus erlaubt ist.
ANY_PATHS=0
[ $# -gt 0 ] && ANY_PATHS=1

for raw in "$@"; do
  # auf absoluten Pfad bringen
  case "$raw" in
    /*) abs="$raw" ;;
    "$CLAUDE_HOME"*) abs="$raw" ;;
    *) abs="${CLAUDE_HOME}/${raw}" ;;
  esac

  case "$abs" in
    "${MEMORY_REPO}"/*)   MEM_PATHS="${MEM_PATHS}${abs#"${MEMORY_REPO}"/}"$'\n' ;;
    "${EPISODES_REPO}"/*) EPI_PATHS="${EPI_PATHS}${abs#"${EPISODES_REPO}"/}"$'\n' ;;
    "${PROJECTS_REPO}"/*) PRJ_PATHS="${PRJ_PATHS}${abs#"${PROJECTS_REPO}"/}"$'\n' ;;
    *) ORPHANS="${ORPHANS}  ${raw}"$'\n' ;;
  esac
done

commit_repo() {
  local repo="$1"
  local label="$2"
  local paths="$3"

  [ -d "$repo/.git" ] || {
    echo "WARN: $repo ist kein git-Repo, skip" >&2
    return 0
  }

  cd "$repo" || return 1

  if [ -n "$paths" ]; then
    # Pathspec-Modus: nur die genannten Pfade stagen und committen.
    # mapfile waere schoener, ist aber in aelteren Bash-Fassungen unter MSYS nicht
    # ueberall da — deshalb IFS-Split auf Zeilen.
    local IFS=$'\n'
    local arr=()
    local p
    for p in $paths; do [ -n "$p" ] && arr+=("$p"); done
    unset IFS
    [ ${#arr[@]} -gt 0 ] || return 0

    # WICHTIG: pro Pfad einzeln stagen, NICHT alle in einem `git add` (gelernt beim
    # ersten Echtlauf 25.07.): ein einziger nicht mehr existierender Pfad laesst
    # `git add -- a b c` komplett scheitern ("pathspec did not match any files") und
    # staged dann GAR NICHTS — inklusive der gueltigen Pfade. Eine geloeschte Datei ist
    # aber ein voellig normaler Audit-Fall (Konsolidierung, Demotion).
    # `staged` sammelt NUR die Pfade, die git wirklich kennt. Diese Liste geht danach
    # an `git diff --cached` UND an `git commit` — beide brechen sonst am selben
    # unbekannten Pfad ab wie das `git add`. (Zweiter Fehler beim Echtlauf 25.07.:
    # das `add` war schon repariert, das `commit` bekam weiterhin die Rohliste.)
    local p
    local staged=()
    for p in "${arr[@]}"; do
      if [ -e "$p" ]; then
        if git add -- "$p"; then staged+=("$p")
        else echo "WARN: ${repo}: konnte $p nicht stagen" >&2; fi
      elif git ls-files --error-unmatch -- "$p" >/dev/null 2>&1; then
        # Pfad ist weg, aber getrackt -> Loeschung stagen
        if git add -u -- "$p"; then staged+=("$p")
        else echo "WARN: ${repo}: konnte Loeschung von $p nicht stagen" >&2; fi
      else
        echo "WARN: ${repo}: $p existiert nicht und ist nicht getrackt - ignoriert" >&2
      fi
    done

    [ ${#staged[@]} -gt 0 ] || return 0

    # Traegt einer der Pfade ueberhaupt eine Aenderung?
    if git diff --cached --quiet -- "${staged[@]}"; then
      return 0  # silent: nichts zu committen
    fi

    if git commit -q -m "${TRIGGER} ${TODAY}: ${label}" -- "${staged[@]}"; then
      echo "  ${label}: committed $(git rev-parse --short HEAD) (${#staged[@]} Pfade)"
    else
      echo "WARN: commit in $repo fehlgeschlagen" >&2
      return 1
    fi
  else
    # Pfade fuer ANDERE Repos genannt, fuer dieses keine: nichts tun. Der
    # Index-Modus gilt nur fuer einen Aufruf ganz ohne Pfade — sonst committet
    # ein /ende-Lauf, der nur seine Episode nennt, im memory-Repo den Index,
    # den eine Parallel-Session gerade vorbereitet.
    [ "$ANY_PATHS" -eq 0 ] || return 0
    # Kein Pfad genannt: NUR den bereits gestageten Index committen.
    if git diff --cached --quiet; then
      return 0  # silent: nichts gestaged, nichts zu tun
    fi
    if git commit -q -m "${TRIGGER} ${TODAY}: ${label}"; then
      echo "  ${label}: committed $(git rev-parse --short HEAD) (Index)"
    else
      echo "WARN: commit in $repo fehlgeschlagen" >&2
      return 1
    fi
  fi

  # Remote-Backup: nur wenn origin verbunden ist (den Erst-Push macht der
  # User manuell). Best-effort.
  # Projekt-Memory nie: Betriebsinterna bleiben auf dieser Maschine.
  if [ "$repo" = "$PROJECTS_REPO" ]; then
    git remote get-url origin >/dev/null 2>&1 && \
      echo "  WARN: ${label}: origin ist angebunden, wird bewusst NICHT gepusht (Betriebsinterna)" >&2
    return 0
  fi
  if git remote get-url origin >/dev/null 2>&1; then
    if git push --quiet origin HEAD 2>/dev/null; then
      echo "  ${label}: gepusht zu origin"
    else
      echo "  WARN: ${label}: push zu origin fehlgeschlagen (offline?)" >&2
    fi
  fi
}

echo "Memory Auto-Commit (Trigger: ${TRIGGER}):"

if [ -n "$ORPHANS" ]; then
  echo "WARN: diese Pfade liegen in keinem der drei Memory-Repos und wurden ignoriert:" >&2
  printf '%s' "$ORPHANS" >&2
fi

# Exit-Code traegt das Ergebnis: ein gescheiterter Commit (z.B. pre-commit-Gate)
# darf nicht als "gesichert" durchrutschen. Push-Fehler bleiben Warnung — offline
# sein ist kein Datenverlust, der Commit liegt lokal.
RC=0
commit_repo "$MEMORY_REPO"   "memory"         "$MEM_PATHS" || RC=1
commit_repo "$EPISODES_REPO" "episodes"       "$EPI_PATHS" || RC=1
commit_repo "$PROJECTS_REPO" "projekt-memory" "$PRJ_PATHS" || RC=1

# Hinweis nur wenn gar nichts uebergeben wurde UND nirgends etwas gestaged war.
if [ -z "${MEM_PATHS}${EPI_PATHS}${PRJ_PATHS}" ]; then
  staged_any=0
  for r in "$MEMORY_REPO" "$EPISODES_REPO" "$PROJECTS_REPO"; do
    [ -d "$r/.git" ] || continue
    ( cd "$r" && git diff --cached --quiet ) || staged_any=1
  done
  if [ "$staged_any" -eq 0 ]; then
    echo "  nichts committet: keine Pfade uebergeben und kein Index gefuellt." >&2
    echo "  Aufruf mit Pfaden: bash memory-auto-commit.sh \"${TRIGGER}\" memory/x.md projects/<slug>/memory/y.md" >&2
  fi
fi

if [ "$RC" -ne 0 ]; then
  echo "FEHLER: mindestens ein Commit ist gescheitert - NICHT alles gesichert (Details oben)." >&2
fi
exit "$RC"
