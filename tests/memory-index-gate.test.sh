#!/bin/bash
# memory-index-gate.test.sh — Gegenprobe zu hooks/memory-index-gate.js
#
# WARUM DIESE DATEI EXISTIERT
#   Eine gruene eigene Suite belegt nichts: sie stammt vom Autor des Gates und
#   teilt dessen Annahmen. Zweimal belegt — 34/34 gruen bei 4 offenen
#   Schadensformen, 52/52 gruen bei zwei Formen, die real Schaden gemacht
#   hatten. Deshalb hier ZWEI Dinge, die eine
#   normale Suite nicht hat:
#     1) Instrument-Kontrolle VOR den Faellen (bricht ab, wenn sie schon faellt)
#     2) Sabotage-Proben: das Gate wird absichtlich kaputtgemacht, und die Suite
#        MUSS das merken. Eine Suite, die auch am kaputten Gate gruen bleibt,
#        misst nicht das Gate.
#   Zusaetzlich ist der eigentliche Wirkungsbeleg NICHT diese Datei, sondern der
#   Lauf ueber alle vorhandenen MEMORY.md des Bestands (unten, Abschnitt
#   KORPUS): real ueber Monate entstandene Verstoesse, fremde Herkunft.
#   Eskalationsleiter Punkt 3, docs/memory-protocol.md.
#
# Aufruf:
#   bash tests/memory-index-gate.test.sh
#   GATE=/pfad/zum/kandidat.js bash tests/memory-index-gate.test.sh
#   bash tests/memory-index-gate.test.sh --korpus   (nur Korpus-Lauf)

set -u

GATE="${GATE:-$(cd "$(dirname "$0")/.." && pwd)/hooks/memory-index-gate.js}"
[ -f "$GATE" ] || { echo "FEHLT: $GATE"; exit 1; }
command -v node >/dev/null || { echo "node fehlt — Gate nicht pruefbar"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ok=0; fail=0

# --- Bausteine ---------------------------------------------------------------
# Zeilen exakter Zeichenlaenge per node bauen. Bash-${#var} zaehlt auf Windows
# BYTES und haette bei Umlauten falsch gemessen — genau der Fall A10/A11.
# ACHTUNG: bei `node -e` beginnen die Argumente bei argv[1], nicht bei argv[2]
# wie bei einer Skript-Datei. Erste Fassung dieser Datei las argv[2]/[3] und
# baute damit leere Zeilen — die Instrument-Kontrolle hat es gefangen.
zeile() { # $1 = Ziel-Zeichenzahl, $2 = optionales Fuellzeichen
  node -e '
    const n=+process.argv[1], f=process.argv[2]||"x";
    const kopf="- [T](f.md) - ";
    let s=kopf; while([...s].length<n) s+=f;
    process.stdout.write([...s].slice(0,n).join(""));
  ' "$1" "${2:-x}"
}

mk() { # $1=tool $2=file_path $3=inhalt/new_string
  node -e '
    const [,tool,fp,txt]=process.argv;
    const ti={file_path:fp};
    if(tool==="Write"){ ti.content=txt; }
    else if(tool==="Edit"){ ti.old_string="ALT"; ti.new_string=txt; }
    else if(tool==="MultiEdit"){ ti.edits=[
      {old_string:"a", new_string:"- [kurz](k.md) - ok"},
      {old_string:"b", new_string:txt},
    ]; }
    process.stdout.write(JSON.stringify({tool_name:tool,tool_input:ti}));
  ' "$1" "$2" "$3"
}

pruefe() { # $1=Name $2=erwarteter Exit $3=Payload  [$4=env-Zuweisung]
  local out rc env_prefix="${4:-}"
  if [ -n "$env_prefix" ]; then
    out=$(printf '%s' "$3" | env "$env_prefix" node "$GATE" 2>&1); rc=$?
  else
    out=$(printf '%s' "$3" | node "$GATE" 2>&1); rc=$?
  fi
  if [ "$rc" = "$2" ]; then
    ok=$((ok+1))
  else
    fail=$((fail+1))
    echo "  ROT  $1 — erwartet exit $2, war $rc"
    [ -n "$out" ] && echo "       ${out%%$'\n'*}"
  fi
  # BLOCKIERT-Zeugen-Pflicht: exit 2 ohne Begruendungstext ist ein stiller Block
  if [ "$2" = "2" ] && [ "$rc" = "2" ] && ! printf '%s' "$out" | grep -q 'BLOCKIERT'; then
    fail=$((fail+1)); echo "  ROT  $1 — exit 2 ohne BLOCKIERT-Zeugen im Text"
  fi
}

IDX="$TMP/memory/MEMORY.md"
mkdir -p "$TMP/memory" "$TMP/memory/audits"
L151="$(zeile 151)"; L150="$(zeile 150)"
U150="$(zeile 150 'ä')"; U151="$(zeile 151 'ä')"
# ZWEI verschiedene lange Zeilen, das ist wichtig: L151B liegt im Bestand der
# Datei, L151 nicht. Erste Fassung nutzte fuer beides dieselbe Zeile — dann war
# der Muss-Fall korrekt "nicht neu" und lief durch, und die Instrument-Kontrolle
# brach ab. Das Gate hatte recht, der Test war falsch.
L151B="$(zeile 151 'z')"
printf '# Index\n- [kurz](k.md) - ok\n%s\n' "$L151B" > "$IDX"

# --- Instrument-Kontrolle ----------------------------------------------------
echo "Instrument-Kontrolle:"
c1=$(printf '%s' "$(mk Write "$IDX" "$L151")" | node "$GATE" >/dev/null 2>&1; echo $?)
c2=$(printf '%s' "$(mk Write "$IDX" "$L150")" | node "$GATE" >/dev/null 2>&1; echo $?)
c3=$(printf '%s' "$(mk Write "$TMP/README.md" "$L151")" | node "$GATE" >/dev/null 2>&1; echo $?)
if [ "$c1" != "2" ] || [ "$c2" != "0" ] || [ "$c3" != "0" ]; then
  echo "  ABBRUCH — Kontrollen falsch (151=$c1 soll 2, 150=$c2 soll 0, fremd=$c3 soll 0)."
  echo "  Das Messwerkzeug ist defekt. Kein Befund aus dieser Datei ist gueltig."
  exit 2
fi
echo "  ok (blockt 151, laesst 150, ignoriert fremde Datei)"

# --- A: muss blocken ---------------------------------------------------------
echo "A — muss blocken:"
pruefe "A1  Write, neue Zeile 151 Zeichen"        2 "$(mk Write "$IDX" "$L151")"
pruefe "A2  Edit, new_string 151 Zeichen"         2 "$(mk Edit "$IDX" "$L151")"
pruefe "A3  MultiEdit, zweiter Edit 151"          2 "$(mk MultiEdit "$IDX" "$L151")"
pruefe "A4  Umlaute, 151 Zeichen"                 2 "$(mk Write "$IDX" "$U151")"
# Bewusst NICHT der echte Index-Pfad: der Test darf nicht vom Inhalt einer
# echten Datei abhaengen, sonst misst er morgen etwas anderes.
pruefe "A5  Windows-Pfad mit Backslashes"         2 "$(mk Write 'C:\kein\ordner\memory\MEMORY.md' "$L151")"
pruefe "A5b gemischte + doppelte Trenner"         2 "$(mk Write 'C:\kein\\ordner/memory//MEMORY.md' "$L151")"
pruefe "A6  Projekt-Schicht statt Cross"          2 "$(mk Write "/c/x/projects/slug/memory/MEMORY.md" "$L151")"
pruefe "A7  Bestandszeile geaendert, jetzt 151"   2 "$(mk Write "$IDX" "${L151}y")"
pruefe "A8  Sternchen-Liste statt Bindestrich"    2 "$(mk Write "$IDX" "$(printf '%s' "$L151" | sed 's/^- /* /')")"

# --- B: darf NICHT blocken ---------------------------------------------------
echo "B — darf nicht blocken:"
pruefe "B1  genau 150 Zeichen"                    0 "$(mk Write "$IDX" "$L150")"
pruefe "B2  Umlaute, genau 150 Zeichen"           0 "$(mk Write "$IDX" "$U150")"
pruefe "B3  lange BESTANDSzeile unveraendert"     0 "$(mk Write "$IDX" "$(cat "$IDX")")"
pruefe "B4  trigger_map.md"                       0 "$(mk Write "$TMP/memory/trigger_map.md" "$L151")"
pruefe "B5  memory/audits-Datei"                  0 "$(mk Write "$TMP/memory/audits/2026-01-01.md" "$L151")"
pruefe "B6  Ueberschrift, 200 Zeichen"            0 "$(mk Write "$IDX" "## $(zeile 200)")"
pruefe "B7  Prosa ohne Listenpunkt, 200 Zeichen"  0 "$(mk Write "$IDX" "$(zeile 200 | sed 's/^- //')")"
pruefe "B8  fremde Datei README.md"               0 "$(mk Write "$TMP/README.md" "$L151")"
pruefe "B9  Bash-Werkzeug"                        0 '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
pruefe "B10 kaputter Payload"                     0 'kein json'
pruefe "B11 leerer Payload"                       0 ''
pruefe "B12 Statuswort unter dem Deckel"          0 "$(mk Write "$IDX" '- [T](f.md) - offen, erledigt, live')"
pruefe "B13 Read-Werkzeug"                        0 "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$IDX\"}}"

# --- C: Abschalter (muss laut sein, aber durchlassen) ------------------------
echo "C — Abschalter:"
pruefe "C1  MEMORY_INDEX_GATE=off laesst durch"   0 "$(mk Write "$IDX" "$L151")" "MEMORY_INDEX_GATE=off"
outc=$(printf '%s' "$(mk Write "$IDX" "$L151")" | env MEMORY_INDEX_GATE=off node "$GATE" 2>&1)
if printf '%s' "$outc" | grep -q 'ABGESCHALTET'; then ok=$((ok+1)); else
  fail=$((fail+1)); echo "  ROT  C2 — Abschalten war STILL. Ein stiller Abschalter ist eine Luecke."
fi

# --- S: Sabotage-Proben ------------------------------------------------------
# Zweck: beweisen, dass die Faelle oben WIRKLICH dieses Gate messen. Wird das
# Gate kaputtgemacht, MUSS A1 durchlaufen. Bleibt A1 dann rot, misst die Suite
# etwas anderes — dann sind alle Befunde oben wertlos.
echo "S — Sabotage (kaputtes Gate muss auffallen):"
sab1="$TMP/sab-limit.js"; sed 's/^const LIMIT = 150;/const LIMIT = 100000;/' "$GATE" > "$sab1"
grep -q 'const LIMIT = 100000;' "$sab1" || { echo "  ROT  S1 — Sabotage griff nicht (Marker nicht getroffen)"; fail=$((fail+1)); }
r1=$(printf '%s' "$(mk Write "$IDX" "$L151")" | node "$sab1" >/dev/null 2>&1; echo $?)
if [ "$r1" = "0" ]; then ok=$((ok+1)); echo "  ok  S1 — Deckel verbogen, 151 laeuft durch (Suite misst den Deckel)"; else
  fail=$((fail+1)); echo "  ROT  S1 — Deckel auf 100000 verbogen und 151 blockt TROTZDEM (exit $r1)"; fi

sab2="$TMP/sab-scope.js"; sed 's/^  return norm.endsWith.*$/  return false;/' "$GATE" > "$sab2"
r2=$(printf '%s' "$(mk Write "$IDX" "$L151")" | node "$sab2" >/dev/null 2>&1; echo $?)
if [ "$r2" = "0" ]; then ok=$((ok+1)); echo "  ok  S2 — Datei-Erkennung ausgehebelt, 151 laeuft durch"; else
  fail=$((fail+1)); echo "  ROT  S2 — Datei-Erkennung aus und 151 blockt TROTZDEM (exit $r2)"; fi

sab3="$TMP/sab-neu.js"; sed 's/^    return neu.filter.*$/    return neu;/' "$GATE" > "$sab3"
r3=$(printf '%s' "$(mk Write "$IDX" "$(cat "$IDX")")" | node "$sab3" >/dev/null 2>&1; echo $?)
if [ "$r3" = "2" ]; then ok=$((ok+1)); echo "  ok  S3 — Bestands-Schutz aus, unveraenderte Datei blockt (B3 misst ihn wirklich)"; else
  fail=$((fail+1)); echo "  ROT  S3 — Bestands-Schutz aus und B3 laeuft TROTZDEM durch (exit $r3)"; fi

echo
echo "Ergebnis: $ok gruen / $fail rot"
[ "$fail" = "0" ] || exit 1
echo
echo "KORPUS — der eigentliche Wirkungsbeleg (fremde Herkunft):"
GATE_PATH="$GATE" node -e '
  const fs=require("fs"), path=require("path"), os=require("os");
  const H=process.env.CLAUDE_CONFIG_DIR||path.join(os.homedir(),".claude");
  const src=fs.readFileSync(process.env.GATE_PATH,"utf8");
  const m=src.match(/^const LIMIT = (\d+);/m);
  if(!m){console.log("  Deckel im Gate nicht gefunden — Korpus uebersprungen"); process.exit(0);}
  const LIMIT=+m[1];                       // aus der Datei gelesen, nicht verdrahtet
  const idx=[path.join(H,"memory","MEMORY.md")];
  const pj=path.join(H,"projects");
  if(fs.existsSync(pj)) for(const d of fs.readdirSync(pj)){
    const p=path.join(pj,d,"memory","MEMORY.md"); if(fs.existsSync(p)) idx.push(p);
  }
  let ges=0;
  for(const p of idx){
    const L=fs.readFileSync(p,"utf8").split("\n").map(z=>z.replace(/\r$/,""));
    const e=L.filter(z=>/^\s*[-*]\s*\[/.test(z));
    const ue=e.filter(z=>[...z.replace(/\s+$/,"")].length>LIMIT);
    if(e.length) ges+=ue.length;
    const lang=e.length?Math.max(...e.map(z=>[...z].length)):0;
    console.log(`  ${String(ue.length).padStart(4)} von ${String(e.length).padStart(4)} ueber ${LIMIT}  (laengste ${String(lang).padStart(5)})  ${p.replace(H,"CLAUDE_HOME")}`);
  }
  console.log(`  Summe Verstoesse im Bestand: ${ges}  (Deckel ${LIMIT}, aus der Gate-Datei gelesen)`);
' || echo "  Korpus-Lauf fehlgeschlagen"
