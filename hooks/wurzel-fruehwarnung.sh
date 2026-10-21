#!/usr/bin/env bash
# Wurzel-Typ-Fruehwarnung — aufgerufen vom Skill session-ende (Schritt 1.6).
# Scannt die **Reibung/Wurzel**-Zeilen der Episoden SEIT DEM LETZTEN AUDIT
# (deterministisch; *_blocked_*-Episoden ausgenommen; Session = erste 8 Zeichen
# nach dem Datum im Dateinamen). Meldet Wurzel-Typen mit >=3 Treffern aus >=2
# verschiedenen Sessions (identisch zu /merkwerk:memory-audit Achse 7b).
# Kein Output = nichts auffaellig.
#
# Ein-Pass-Implementierung (1x grep + 1x awk statt Schleife mit ~10 Prozessen
# pro Datei) — die alte Datei-fuer-Datei-Schleife lief auf Windows/Git-Bash
# in den 2-Minuten-Timeout.
#
# Startpunkt: der Tag des juengsten Audits, NICHT starr 30 Tage (geaendert
# 2026-09-10). Grund: ein Audit wertet die Episoden bis zu seinem Lauf bereits
# aus — ein festes 30-Tage-Fenster meldet danach genau diese Daten noch einmal
# und verlangt einen Audit, der gerade lief. Am 10.09. gemessen, zwei Tage nach
# dem Audit vom 08.09.: das alte Fenster meldete 42x angenommen-statt-gelesen,
# real neu waren 4. Der Audit-Tag selbst zaehlt MIT — Episoden, die nach dem
# Audit-Lauf am selben Tag entstehen, sollen nicht durchfallen; die Meldung
# nennt den Bezugspunkt, damit die Zahl einzuordnen ist.
# Faellt zurueck auf 30 Tage, wenn kein datierter Audit vorliegt (Erstlauf).

CLAUDE_HOME="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"

audit=$(ls -1 "$CLAUDE_HOME/memory/audits"/????-??-??.md 2>/dev/null \
        | sed 's|.*/||; s|\.md$||' | sort | tail -1)
cutoff="${audit:-$(date -d '30 days ago' +%F)}"
bezug="${audit:+dem Audit vom $audit}"
bezug="${bezug:-den letzten 30 Tagen}"

find "$CLAUDE_HOME/episodes" -mindepth 1 -maxdepth 3 -name '????-??-??_*.md' ! -name '*_blocked_*' -print0 \
  | xargs -0 -r grep -m1 -H '^\*\*Reibung/Wurzel\*\*' \
  | awk -v cutoff="$cutoff" -v bezug="$bezug" '
    BEGIN {
      ntypes = split("angenommen-statt-gelesen kontext-uebersehen zu-frueh-committet wunsch-ueber-beleg scope-missverstanden regel-vergessen oberflaechlich-geprueft", types, " ")
    }
    {
      # grep -H liefert "pfad:zeile"; Pfad unter Git-Bash colonfrei (/c/...)
      path = $0; sub(/:.*$/, "", path)
      line = substr($0, length(path) + 2)
      n = split(path, parts, "/"); b = parts[n]; sub(/\.md$/, "", b)
      d = substr(b, 1, 10)
      if (d < cutoff) next
      sess = substr(b, 12, 8)
      for (i = 1; i <= ntypes; i++) {
        t = types[i]
        # aequivalent zu PCRE \b<typ>\b (Bindestrich zaehlt als Nicht-Wort-Zeichen)
        if (line ~ ("(^|[^[:alnum:]_])" t "([^[:alnum:]_]|$)")) {
          h[t]++
          if (!seen[t SUBSEP sess]++) s[t]++
          if (m[t] == "" || d < m[t]) m[t] = d
        }
      }
    }
    END {
      for (t in h) if (h[t] >= 3 && s[t] >= 2)
        printf "Wurzel-Typ %s laeuft auf (%dx aus %d Sessions seit %s) — /merkwerk:memory-audit vorziehen?\n", t, h[t], s[t], bezug
    }
  ' | sort
