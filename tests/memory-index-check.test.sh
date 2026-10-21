#!/usr/bin/env bash
# Gegenprobe fuer den Memory-Index-Deckel im globalen pre-commit-Hook.
# Faehrt echte Commits in Wegwerf-Repos. Schreibt bewusst per Bash (echo/printf),
# denn genau dieser Weg lief am Werkzeug-Gate vorbei (Audit 2026-10-06).
#   bash tests/memory-index-check.test.sh
#   HOOKS=<ordner> bash ...   # Kandidat statt Live-Stand pruefen
set -u
HOOKS="${HOOKS:-$(cd "$(dirname "$0")/../git-hooks" && pwd)}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/leer"
ok=0; fail=0

lang() { node -e 'process.stdout.write("- [x](x.md) " + "a".repeat(+process.argv[1] - 12))' "$1"; }
umlaut() { node -e 'process.stdout.write("- [x](x.md) " + "ä".repeat(+process.argv[1] - 12))' "$1"; }

neues_repo() {
  R="$TMP/r$RANDOM$RANDOM"; mkdir -p "$R/memory"
  git -C "$R" init -q; git -C "$R" config core.autocrlf false
  git -C "$R" config user.email t@t; git -C "$R" config user.name t
  printf '# Index\n- [alt](alt.md) kurz\n' > "$R/memory/MEMORY.md"
  git -C "$R" add memory/MEMORY.md
  git -C "$R" -c core.hooksPath="$TMP/leer" commit -qm init
}

# commit_erwartet <name> <0=durch|1=blockiert> <datei> ; Inhalt kommt von stdin (wird angehaengt)
pruefe() {
  local name="$1" soll="$2" datei="$3"
  mkdir -p "$(dirname "$R/$datei")"
  cat >> "$R/$datei"
  git -C "$R" add -- "$datei"
  if git -C "$R" -c core.hooksPath="$HOOKS" commit -qm test >/dev/null 2>&1; then ist=0; else ist=1; fi
  if [ "$ist" = "$soll" ]; then ok=$((ok+1)); echo "  ok   $name"; else fail=$((fail+1)); echo "  FEHL $name (soll $soll, ist $ist)"; fi
}

echo "Memory-Index-Deckel am Commit:"
neues_repo; pruefe "T1 neue Zeile 151 Zeichen per Bash -> blockiert" 1 memory/MEMORY.md < <(lang 151; echo)
neues_repo; pruefe "T2 genau 150 Zeichen -> durch" 0 memory/MEMORY.md < <(lang 150; echo)
neues_repo; pruefe "T3 150 Zeichen mit Umlauten (>150 Bytes) -> durch" 0 memory/MEMORY.md < <(umlaut 150; echo)
neues_repo; pruefe "T4 151 Zeichen mit Umlauten -> blockiert" 1 memory/MEMORY.md < <(umlaut 151; echo)
neues_repo; pruefe "T5 lange Zeile in anderer Datei -> durch" 0 memory/notiz.md < <(lang 300; echo)
neues_repo; pruefe "T6 lange Nicht-Eintragszeile -> durch" 0 memory/MEMORY.md < <(printf '%s\n' "Fliesstext $(printf 'b%.0s' $(seq 1 200))")
neues_repo; pruefe "T7 Index im Repo-Wurzelordner (memory-Repo) -> blockiert" 1 MEMORY.md < <(lang 200; echo)
neues_repo; pruefe "T8 Projekt-Schicht ws/memory/MEMORY.md -> blockiert" 1 c--ws/memory/MEMORY.md < <(lang 200; echo)
# Altbestand: lange Zeile ohne Hook committen, danach nur kurze Zeile dazu
neues_repo; { lang 200; echo; } >> "$R/memory/MEMORY.md"; git -C "$R" add memory/MEMORY.md; git -C "$R" -c core.hooksPath="$TMP/leer" commit -qm alt
pruefe "T9 Altbestand lang + neue kurze Zeile -> durch" 0 memory/MEMORY.md < <(printf -- '- [neu](neu.md) kurz\n')

# Sabotage-Probe: Hook ohne den Deckel-Block muss T1 durchlassen, sonst misst die Suite nichts.
SAB="$TMP/sabotage"; mkdir -p "$SAB"; cp "$HOOKS/memory-index-check.js" "$SAB/"
sed '/Memory-Index-Deckel ---/,/^fi$/d' "$HOOKS/pre-commit" > "$SAB/pre-commit"; chmod +x "$SAB/pre-commit"
neues_repo; { lang 151; echo; } >> "$R/memory/MEMORY.md"; git -C "$R" add memory/MEMORY.md
if git -C "$R" -c core.hooksPath="$SAB" commit -qm s >/dev/null 2>&1; then ok=$((ok+1)); echo "  ok   S1 Sabotage: ohne Block laeuft T1 durch (Suite misst den Block)"; else fail=$((fail+1)); echo "  FEHL S1 Sabotage greift nicht"; fi

echo "Ergebnis: $ok gruen / $fail rot"
[ "$fail" = 0 ]
