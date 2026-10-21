---
name: session-ende
description: Session-Ende-Protokoll. Triggert bei Schluss/Ende/Feierabend (Session-Ende, nicht Aktion-Ende).
---

# Session-Ende-Protokoll

## Trigger

**JA** wenn der User die Arbeits-Session beendet:
"Schluss", "Ende", "Feierabend", "das war's fuer heute", "fuer heute reicht's", "wir hoeren auf", "ich bin raus", "ich gehe offline"

**NEIN** wenn das Wort sich auf eine Aktion bezieht:
"ende den Code-Block", "Schluss mit dem Refactor", "beende die Funktion", "ende des Skripts"

Im Zweifel: kurz nachfragen ("Session-Ende oder nur diese Aktion?").

## Pfade

`CLAUDE_HOME` = `$CLAUDE_CONFIG_DIR`, sonst `~/.claude`. Die Skripte liegen im Plugin: `${CLAUDE_PLUGIN_ROOT}/hooks/`.

## Ablauf — Schritte in Reihenfolge

### 1. Memory-Check (Pflicht-Output)

Pruefe was in dieser Session gelernt wurde, das cross-session gespeichert werden sollte:

- **Feedback-Patterns** (Korrekturen des Users)
- **Neue Projekt-Fakten** (Status, Entscheidungen, Stakeholder)
- **Referenzen** zu externen Systemen

Routing-Regeln: `${CLAUDE_PLUGIN_ROOT}/docs/memory-protocol.md` → `## Memory-Routing`.

**Output (immer):**
- Wenn Memories geschrieben → Liste der angelegten/aktualisierten Dateinamen
- Wenn keine → ein Satz "Keine neuen Memories noetig"

### 1.5 Episode-Write (Pflicht-Output, automatisch)

Schreibe eine Session-Episode in den Episodic Memory Layer. Dient als Sammelbecken, aus dem `/merkwerk:memory-audit` Achse 7 spaeter Promotion-Kandidaten ableitet.

**Pfad**: `CLAUDE_HOME/episodes/YYYY-MM/YYYY-MM-DD_<session-id-prefix-8>.md`

- `YYYY-MM` aus heutigem Datum, Verzeichnis ggf. anlegen mit `mkdir -p`
- `session-id-prefix-8` = erste 8 Zeichen der aktuellen Session-ID (aus Konversations-Kontext, falls nicht ermittelbar: `unknown`)
- **Idempotent**: existierendes File mit gleichem Pfad ueberschreiben (nicht doppeln)

**Format** (genau diese Abschnitte, keine Frontmatter):

```markdown
# YYYY-MM-DD — Session <session-id-prefix-8>

**Was passierte**: <1-2 Saetze: Hauptarbeit dieser Session>

**Was gelernt**: <1-2 Saetze: konkrete Erkenntnis, neue Heuristik, korrigierte Annahme. "Nichts Neues" ist valider Output>

**Reibung/Wurzel**: <Wo musste der User nachsteuern oder blockte ein Hook? Wurzel-Typ (Taxonomie: docs/memory-protocol.md §Korrektur-Reflex-Loop) + ein Satz. Wurzel-Typ als EXAKTES Taxonomie-Token schreiben — die Fruehwarnung in 1.6 zaehlt nur woertliche Treffer. Beleg-basiert — nur was die Session real zeigte, nichts erfinden. "Keine Reibung" ist valider Output>

**Offen**: <kurz: was bleibt offen, oder "nichts">

**Workspace**: <slug aus pwd, gleiche Konvention wie Audit-Command Schritt 1>
```

**Output**: ein-Zeilen-Bestaetigung "Episode geschrieben: `<pfad>`" oder bei Fehler "Episode-Write fehlgeschlagen: `<grund>`" (kein Crash, nur Hinweis).

### 1.6 Wurzel-Typ-Fruehwarnung (automatisch, read-only)

Scanne NACH dem Episode-Write die `**Reibung/Wurzel**`-Zeilen aller Episoden **seit dem letzten Audit** (ohne datierten Audit: letzte 30 Tage):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/wurzel-fruehwarnung.sh"
```

Die Scan-Logik lebt vollstaendig im Script (Source of Truth, nicht hier duplizieren).

- Schwelle: **>=3 Treffer aus >=2 verschiedenen Sessions** pro Wurzel-Typ (identisch zu Audit-Achse 7b) → Kommando-Output 1:1 uebernehmen, eine Hinweis-Zeile pro Typ
- Kein Auto-Fix, kein eigenmaechtiger Audit-Lauf — nur Hinweis, der User entscheidet
- **Output**: die Hinweis-Zeile(n); leerer Kommando-Output → kein Output, keine Erwaehnung (silent-by-default wie Schritt 4)

### 1.7 Sichern (Pflicht, nach 1.5)

Committe die eigenen Schreibpfade dieser Session sofort — sonst sichert erst der naechste Audit, Wochen spaeter:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/memory-auto-commit.sh" "ende" <pfad> [<pfad> ...]
```

- **Pfadliste = alles, was DIESE Session unter `CLAUDE_HOME/memory/`, `CLAUDE_HOME/episodes/` oder `CLAUDE_HOME/projects/*/memory/` angelegt, geaendert oder geloescht hat** — die Episode aus 1.5, die Memories aus 1, Memories aus frueheren Zuegen der Session und jede dabei mitgeaenderte `MEMORY.md`. Quelle: die eigenen Write/Edit-Aufrufe dieser Session, nicht `git status` — dort steht auch die Arbeit paralleler Sessions.
- Nie ohne Pfade aufrufen: ohne Pfade committet der Helper den gestageten Index, und der kann einer Parallel-Session gehoeren.
- Der Helper pusht `memory` und `episodes` zu ihrem origin (falls vorhanden), `projects` bewusst nie.
- **Output**: die Commit-Zeilen des Helpers. Exit != 0 → Zeile "Sichern fehlgeschlagen: <Meldung>" — nicht als gesichert melden.

### 2. Lokale Erweiterung (optional)

Existiert `CLAUDE_HOME/session-ende.local.md`, lies die Datei und fuehre ihre Schritte jetzt aus. Dort stehen die persoenlichen Zusatzschritte des Users (z.B. ein Projekt-Tagebuch), die nicht zum Plugin gehoeren. Fehlt die Datei: nichts tun, nichts erwaehnen.

### 3. Offene Punkte (festes Output-Format)

Liefere immer in diesem Format:

```markdown
## Heute erledigt
- <Stichpunkt mit Datei/Pfad falls relevant>

## Offen
- [ ] <Task> (Datei/Pfad falls relevant)

## Naechster Schritt
<ein Satz>
```

### 4. Integritaets-Check (silent-by-default)

Nur in Git-Repos mit Commits von heute. Output NUR wenn auffaellig.

**Regressions-Check:**
Pruefe via `git log --since=midnight --name-status`:
Datei wurde heute mit netto **<-50 Zeilen** committet UND in einem **spaeteren** Commit mit netto **>+30 Zeilen** ergaenzt → Warnung mit Hash des Kuerzungs-Commits. (Schwellwerte verhindern False-Positives bei normalen Edits.)

Wenn nichts auffaellig: kein Output, keine Erwaehnung.
