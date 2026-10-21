#!/bin/bash
# Gegenprobe fuer hooks/memory-auto-commit.sh
#
# Frage: Nimmt der Helper fremde, uncommittete Parallel-Session-Arbeit mit?
#
# Aufbau: Wegwerf-HOME mit den drei Memory-Repos. In jedem liegen zwei Dateien:
# eine "eigene" (gehoert zum Audit) und eine "fremde" (Parallel-Session).
# Der Helper wird NUR mit den eigenen Pfaden aufgerufen.
#
# T1-T3  : neuer Helper darf die fremde Datei NICHT mitnehmen  -> muss GRUEN sein
# T4     : Sabotage — alte Fassung mit pauschalem Stagen       -> muss ROT sein
#          (wenn T4 gruen ist, misst der Test nichts)
# T5     : ohne Pfade und ohne Index -> kein Commit, klare Meldung
# T6     : ohne Pfade, aber Index gefuellt -> committet genau den Index

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="${ROOT}/hooks/memory-auto-commit.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf '  OK   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s  -- %s\n' "$1" "$2"; }

mkrepo() {
  local r="$1"; mkdir -p "$r"; ( cd "$r" && git init -q .
    git config user.email t@t.local; git config user.name Test
    echo start > seed.md; git add seed.md; git commit -q -m seed )
}

setup() {
  FAKE="$TMP/run$1"; mkdir -p "$FAKE/.claude"
  mkrepo "$FAKE/.claude/memory"
  mkrepo "$FAKE/.claude/episodes"
  mkrepo "$FAKE/.claude/projects/ws-a/memory"
  # projects-Repo liegt eine Ebene hoeher (wie im Original)
  rm -rf "$FAKE/.claude/projects/ws-a/memory/.git"
  ( cd "$FAKE/.claude/projects" && git init -q .
    git config user.email t@t.local; git config user.name Test
    mkdir -p ws-a/memory ws-b/memory
    echo start > ws-a/memory/seed.md; echo start > ws-b/memory/seed.md
    git add -A >/dev/null 2>&1; git commit -q -m seed )
  # eigene + fremde Aenderung in jedem Repo
  echo eigen  > "$FAKE/.claude/memory/eigen.md"
  echo fremd  > "$FAKE/.claude/memory/fremd.md"
  echo eigen  > "$FAKE/.claude/episodes/eigen.md"
  echo fremd  > "$FAKE/.claude/episodes/fremd.md"
  echo eigen  > "$FAKE/.claude/projects/ws-a/memory/eigen.md"
  echo fremd  > "$FAKE/.claude/projects/ws-b/memory/fremd.md"
}

# --- T1-T3: neuer Helper, nur eigene Pfade -------------------------------
setup 1
HOME="$FAKE" CLAUDE_CONFIG_DIR="$FAKE/.claude" bash "$HELPER" "test" \
  memory/eigen.md episodes/eigen.md projects/ws-a/memory/eigen.md >/dev/null 2>&1

files=$( cd "$FAKE/.claude/memory" && git show --name-only --format= HEAD )
case "$files" in
  *fremd*) bad "T1 memory-Repo"   "fremde Datei mit-committet" ;;
  *eigen*) ok  "T1 memory-Repo    nur eigene Datei im Commit" ;;
  *)       bad "T1 memory-Repo"   "eigene Datei fehlt im Commit" ;;
esac

files=$( cd "$FAKE/.claude/episodes" && git show --name-only --format= HEAD )
case "$files" in
  *fremd*) bad "T2 episodes-Repo" "fremde Datei mit-committet" ;;
  *eigen*) ok  "T2 episodes-Repo  nur eigene Datei im Commit" ;;
  *)       bad "T2 episodes-Repo" "eigene Datei fehlt im Commit" ;;
esac

files=$( cd "$FAKE/.claude/projects" && git show --name-only --format= HEAD )
case "$files" in
  *ws-b*)  bad "T3 projects-Repo" "fremden Workspace ws-b mit-committet" ;;
  *ws-a*)  ok  "T3 projects-Repo  nur eigener Workspace im Commit" ;;
  *)       bad "T3 projects-Repo" "eigene Datei fehlt im Commit" ;;
esac

# --- T4: Sabotage-Probe. Alte Fassung MUSS die fremde Arbeit einsammeln ---
setup 4
SAB="$TMP/sabotage.sh"
{ echo '#!/bin/bash'
  echo 'cd "$HOME/.claude/memory" || exit 1'
  echo 'git add' '-A'
  echo 'git commit -q -m sabotage'
} > "$SAB"
HOME="$FAKE" CLAUDE_CONFIG_DIR="$FAKE/.claude" bash "$SAB" >/dev/null 2>&1
files=$( cd "$FAKE/.claude/memory" && git show --name-only --format= HEAD )
case "$files" in
  *fremd*) ok  "T4 Sabotage-Probe pauschales Stagen zieht Fremdarbeit (Test misst)" ;;
  *)       bad "T4 Sabotage-Probe" "TEST IST BLIND - auch die alte Fassung war sauber" ;;
esac

# --- T5: ohne Pfade, nichts gestaged -> kein Commit ----------------------
setup 5
before=$( cd "$FAKE/.claude/memory" && git rev-parse HEAD )
out=$(HOME="$FAKE" CLAUDE_CONFIG_DIR="$FAKE/.claude" bash "$HELPER" "test" 2>&1)
after=$( cd "$FAKE/.claude/memory" && git rev-parse HEAD )
if [ "$before" = "$after" ] && printf '%s' "$out" | grep -q 'nichts committet'; then
  ok "T5 ohne Pfade     kein Commit + klare Meldung"
else
  bad "T5 ohne Pfade" "hat committet oder schweigt: $out"
fi

# --- T6: ohne Pfade, aber Index gefuellt -> genau der Index --------------
setup 6
( cd "$FAKE/.claude/memory" && git add eigen.md )
HOME="$FAKE" CLAUDE_CONFIG_DIR="$FAKE/.claude" bash "$HELPER" "test" >/dev/null 2>&1
files=$( cd "$FAKE/.claude/memory" && git show --name-only --format= HEAD )
case "$files" in
  *fremd*) bad "T6 Index-Modus" "fremde Datei mit-committet" ;;
  *eigen*) ok  "T6 Index-Modus   committet genau den gestageten Stand" ;;
  *)       bad "T6 Index-Modus" "nichts committet" ;;
esac

# --- T7: GELOESCHTER Pfad in der Liste ----------------------------------
# Regressionstest. Dieser Fall fehlte im ersten Wurf und ist beim ersten
# Echtlauf am 25.07. sofort aufgeschlagen: `git add -- a b c` scheitert
# komplett, wenn EIN Pfad nicht mehr existiert ("pathspec did not match"),
# und staged dann auch a und b nicht. Eine geloeschte Memory ist bei einer
# Konsolidierung der Normalfall.
setup 7
( cd "$FAKE/.claude/memory" && git add eigen.md && git commit -q -m vorlauf )
rm "$FAKE/.claude/memory/eigen.md"           # geloescht, aber getrackt
echo neu > "$FAKE/.claude/memory/neu.md"     # gueltiger Nachbar-Pfad
HOME="$FAKE" CLAUDE_CONFIG_DIR="$FAKE/.claude" bash "$HELPER" "test" memory/eigen.md memory/neu.md >/dev/null 2>&1
# --name-status, NICHT "--name-only --status" (das ist kein gueltiges git-Argument und
# liefert leer -> der Pruefer meldete Rot, obwohl der Helper korrekt war).
files=$( cd "$FAKE/.claude/memory" && git show --name-status --format= HEAD )
if printf '%s' "$files" | grep -q 'neu.md' && printf '%s' "$files" | grep -qE '^D.*eigen.md'; then
  ok "T7 geloeschter Pfad Loeschung + Nachbar-Pfad beide im Commit"
else
  bad "T7 geloeschter Pfad" "Commit unvollstaendig: $files"
fi

# --- T8: unbekannter Pfad darf die gueltigen nicht kippen ----------------
setup 8
out=$(HOME="$FAKE" CLAUDE_CONFIG_DIR="$FAKE/.claude" bash "$HELPER" "test" memory/gibtsnicht.md memory/eigen.md 2>&1)
files=$( cd "$FAKE/.claude/memory" && git show --name-only --format= HEAD )
if printf '%s' "$files" | grep -q 'eigen.md' && printf '%s' "$out" | grep -q 'gibtsnicht'; then
  ok "T8 unbekannter Pfad gueltiger Pfad committet + Warnung"
else
  bad "T8 unbekannter Pfad" "gueltiger Pfad verschluckt oder keine Warnung: $out"
fi

# --- T9: Pfade nur fuer EIN Repo -> fremder Index im anderen bleibt liegen --
# Astra-Review 2026-10-21: ein /ende-Lauf nennt nur seine Episode; der Index-
# Modus durfte dann im memory-Repo den Index einer Parallel-Session committen.
setup 9
( cd "$FAKE/.claude/memory" && git add fremd.md )
before=$( cd "$FAKE/.claude/memory" && git rev-parse HEAD )
HOME="$FAKE" CLAUDE_CONFIG_DIR="$FAKE/.claude" bash "$HELPER" "test" episodes/eigen.md >/dev/null 2>&1
after=$( cd "$FAKE/.claude/memory" && git rev-parse HEAD )
epi=$( cd "$FAKE/.claude/episodes" && git show --name-only --format= HEAD )
if [ "$before" = "$after" ] && printf '%s' "$epi" | grep -q eigen.md; then
  ok "T9 Pfade fuer ein Repo fremder Index im Nachbar-Repo unberuehrt"
else
  bad "T9 Pfade fuer ein Repo" "memory-Index mit-committet oder Episode fehlt"
fi

# --- T10: gescheiterter Commit -> Exit-Code != 0 --------------------------
setup 10
printf '#!/bin/sh\nexit 1\n' > "$FAKE/.claude/memory/.git/hooks/pre-commit"
chmod +x "$FAKE/.claude/memory/.git/hooks/pre-commit"
HOME="$FAKE" CLAUDE_CONFIG_DIR="$FAKE/.claude" bash "$HELPER" "test" memory/eigen.md >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then
  ok "T10 Commit-Fehler   Exit-Code $rc statt stummem Erfolg"
else
  bad "T10 Commit-Fehler" "Exit 0 trotz geblocktem Commit"
fi

# --- T11: projects-Repo mit origin -> wird NICHT gepusht -------------------
setup 11
git init -q --bare "$TMP/remote11.git"
( cd "$FAKE/.claude/projects" && git remote add origin "$TMP/remote11.git" )
( cd "$FAKE/.claude/memory"   && git remote add origin "$TMP/remote11.git" )
HOME="$FAKE" CLAUDE_CONFIG_DIR="$FAKE/.claude" bash "$HELPER" "test" projects/ws-a/memory/eigen.md >/dev/null 2>&1
n=$( git --git-dir="$TMP/remote11.git" rev-list --all 2>/dev/null | wc -l )
if [ "$n" -eq 0 ]; then
  ok "T11 projects-Push   Betriebsinterna bleiben lokal trotz origin"
else
  bad "T11 projects-Push" "$n Commits landeten im Remote"
fi
# Gegenprobe: memory-Repo MIT origin wird gepusht (sonst misst T11 nichts)
HOME="$FAKE" CLAUDE_CONFIG_DIR="$FAKE/.claude" bash "$HELPER" "test" memory/eigen.md >/dev/null 2>&1
n=$( git --git-dir="$TMP/remote11.git" rev-list --all 2>/dev/null | wc -l )
if [ "$n" -gt 0 ]; then
  ok "T11b memory-Push    Gegenprobe: normales Repo pusht weiter"
else
  bad "T11b memory-Push" "TEST IST BLIND - auch memory pusht nicht"
fi

echo "================================"
echo "  bestanden: $PASS   durchgefallen: $FAIL"
[ "$FAIL" -eq 0 ] && echo "  ALLE FAELLE TRAGEN" || echo "  NICHT ALLE FAELLE TRAGEN"
exit "$FAIL"
