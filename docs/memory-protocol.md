# Memory-Protokoll

Vollstaendige Regeln zum Memory-System. Die `CLAUDE.md` des Users verweist auf diesen Pfad — die Datei wird bei Bedarf gelesen, nicht per `@`-Import eingebunden (sie ist zu lang fuer Always-On).

`CLAUDE_HOME` meint im ganzen Dokument `$CLAUDE_CONFIG_DIR`, sonst `~/.claude`.

## Memory-Routing

Zwei Schichten:

- **Cross-workspace gueltig** (User-Profil, Feedback-Patterns, externe Referenzen) → `CLAUDE_HOME/memory/` + `MEMORY.md`-Index dort
- **Workspace-Project-Fakten** (Status, Brand, Team, Zahlen eines konkreten Projekts) → `CLAUDE_HOME/projects/<workspace-id>/memory/` + `MEMORY.md`-Index dort (Auto-Memory, system-konform)

Projekt-spezifische Tooling-Regeln (Limits, Dateipfade, Trigger) gehoeren NICHT in eine eigene Memory-Schicht, sondern direkt in die `CLAUDE.md` im jeweiligen Projekt-Ordner.

Vor jedem Memory-Write: pruefen ob es schon eine ueberlappende Memory gibt (update statt duplizieren).

## Index-Schema (beide MEMORY.md identisch)

```markdown
# Memory Index

## User
- [Title](file.md) — One-Liner-Hook

## Project
...
## Reference
...
## Feedback
...
```

Index-Eintraege: max 150 Zeichen, eine Zeile, Markdown-Link + Gedankenstrich + Hook.

**Durchgesetzt von `hooks/memory-index-gate.js`** (PreToolUse auf Write/Edit/MultiEdit) und am Commit von `git-hooks/pre-commit`: eine NEUE Eintragszeile ueber 150 Zeichen wird abgelehnt, der Bestand bleibt unangetastet. Grund fuer ein Gate statt einer weiteren Textregel: als reine Regel wurde der Deckel in einem gemessenen System binnen zwei Monaten 391-mal gerissen, der Cross-Index wuchs ohne einen einzigen Schrumpf-Schritt, und eine Handkuerzung stand vier Wochen spaeter ueber ihrem Ausgangswert. Der Ausloeser ist deterministisch erkennbar, damit greift Eskalationsleiter Punkt 2.

**Der Index traegt Thema und dauerhafte Fallen, KEINE Laufzustaende.** Ein Zustand („offen", „erledigt", „live", „gemerged", „faellig") veraltet in dem Moment, in dem jemand die Sache anfasst — und wer sie anfasst, hat keinen Grund, die Notiz aufzuschlagen. Eine dauerhafte Falle („`activeElement` ist im `change`-Handler schon BODY") veraltet nicht. Laufzustaende gehoeren in eine Status-Datei des Projekts, die den Ist-Stand ERSETZT statt ihn zu ergaenzen. Das Gate warnt bei Statuswoertern, blockt aber nicht — eine Wortliste ist eine Aufzaehlung und damit unvollstaendig.

## Lazy-Load-Konvention (Kontext-Sparen)

**Default**: Nur die `MEMORY.md`-Indizes sind "always-on" im Kontext. **Memory-Files selbst werden NICHT automatisch geladen** — Claude liest ein File erst, wenn der Hook im Index zur aktuellen Aufgabe passt.

Drei-Stufen-Retrieval:

1. **Index-Scan** (immer, ~30 Tokens pro Eintrag): Hooks aus `MEMORY.md` mit Task abgleichen
2. **On-Demand-Read**: Wenn Hook matcht → einzelnes File via `Read` laden
3. **Aktualisierung**: Bei Erkenntnis aus Session → Edit auf File + ggf. Index-Hook anpassen

Ausnahme: Auto-Memory-Schicht (`CLAUDE_HOME/projects/<id>/memory/`) wird von Claude Code teilautomatisch geladen — dort gilt der Lazy-Load-Default nur fuer manuelle Memory-Files.

## Body-Struktur

Memory-Files haben Frontmatter + freien Body. Pflicht-Struktur fuer `feedback` und `project`:

- **Regel/Fakt** in 1-2 Saetzen
- **Why:** der Grund (warum die Regel existiert — meist ein Vorfall)
- **How to apply:** wann/wo die Regel greift

Ohne Why veraltet jede Memory schnell.

## Frontmatter

```yaml
---
name: {{Memory-Name}}
description: {{One-Liner — wird fuer Relevanz-Pruefung benutzt}}
type: user | feedback | project | reference
verified: YYYY-MM-DD       # Pflicht fuer type:project, optional sonst
stale_after_days: N        # Pflicht fuer type:project; user/reference je nach Volatilitaet
last_used: YYYY-MM-DD      # automatisch gestempelt (Trigger-Router + Read-Stamp)
critical: true             # optional. Schutz vor "kalt"-Flag (siehe Stale-Check). Default: false
confidence: 0.3 | 0.6 | 0.9  # optional, nur fuer feedback. Default: 0.6
domain: <slug>             # optional, nur fuer feedback. z.B. communication, copy, git, security
evidence: <kurz>           # optional, nur fuer feedback. Was hat die Memory ausgeloest
---
```

**Schema-Konvention:** Haus-Schema ist FLACH — `type:`, `verified:` etc. direkt auf oberster Ebene. Auto-Memory-Files, die Claude Code selbst anlegt, tragen system-konform einen `metadata:`-Block; das ist als Rohzustand ok. Beim naechsten Kuratieren einer solchen Datei auf flach normalisieren (Audit-Greps und Stale-Mathematik lesen die flachen Felder). KEINE Massen-Migration.

### Confidence-Skala (nur fuer `type: feedback`)

Optional aber empfohlen — macht Anti-Memory-Tracking schaerfer:

- **0.3 (tentativ)** — einmalige Beobachtung, koennte Einzelfall sein. Memory wird geschrieben aber niedrig gewichtet.
- **0.6 (validiert)** — Default. Pattern wurde mindestens zweimal gesehen ODER explizit vom User bestaetigt.
- **0.9 (gehaertet)** — Pattern wurde mehrfach angewandt UND nie gebrochen. Kandidat fuer Hochzug nach CLAUDE.md.

Confidence steigt durch Anwendung, faellt durch Anti-Memory-Verstoesse. Der Audit (Achse 4) berechnet sie nicht autonom — der User entscheidet.

### Domain-Tags

Optional, machen Index-Scan schaerfer. Beispiele:

- `communication` — wie der User angesprochen werden will
- `copy` — Texte, Tonalitaet
- `git` — Commit-Konventionen, Branch-Naming
- `memory` — Memory-System selbst (meta)
- `security` — Hooks, Permissions, Backups
- `workflow` — Vorgehen, Pre-Decision, Self-Review

Frei waehlbar, aber konsistent halten — bei Audits hilft's, Cluster zu erkennen.

## Stale-Check

Vor Verwendung einer Memory mit `stale_after_days`: Datum pruefen. Wenn `(today - verified) > stale_after_days`: im Output flaggen statt blind verwenden.

Beispiel: "Memory `project_x` ist 45 Tage alt (stale_after: 30) — Status koennte veraltet sein, bitte verifizieren."

Empfehlungen fuer `stale_after_days`:

- Aktive Projekte mit Status: 30
- Konzept-/Strategie-Projekte: 60-90
- System-/Architektur-Memories: 180
- Feedback-Patterns: meist ohne (Patterns altern langsam)

### Kalte-Kandidaten-Regel (additiv zu Stale-Check)

Eine Memory, die seit > 60 Tagen weder durch den Trigger-Router gefeuert noch gelesen wurde, ist ein "kalter Kandidat" — Karteileiche-Verdacht.

Konkret im Audit (Achse 3) flaggen wenn ALLE drei Bedingungen erfuellt:

- `last_used` fehlt **ODER** `(today - last_used) > 60`
- `(today - verified) > 60`
- **NICHT** `critical: true`

**Schutz**: Memories, die selten ausgeloest werden, aber bei Verstoss Schaden anrichten (z.B. Secret-Handling), bekommen `critical: true` und sind damit vom kalt-Flag ausgenommen. Manuelle Setzung — Auditor entscheidet.

Aktion bei Flag: re-verify, Stale verlaengern, oder archivieren. Niemals autonom loeschen.

## Memory-Types

- **user** — wer der User ist, Rolle, Praeferenzen
- **feedback** — verallgemeinerte Verhaltens-Pattern (aus Korrektur ODER Bestaetigung)
- **project** — Projekt-Fakten, die nicht aus Code/Git ableitbar sind
- **reference** — Pointer zu externen Quellen/Repos/Dashboards

Andere Types (`playbook`, `trigger`) wurden bewusst weggelassen — Disziplin auf 4 Types haelt das System lesbar.

## Session-Start

Bei non-trivialen Tasks: Index-Hooks der letzten 5 Feedback-Memories quer-lesen — verhindert Wiederholung bekannter Fehler. Hooks reichen, Files nur bei Match laden.

## Write-Trigger

- "Save" → sofort alle wichtigen Session-Learnings speichern
- Jede Korrektur des Users → Pattern als Feedback-Memory speichern (verallgemeinert, nicht der konkrete Fall)
- Jede ungewoehnliche Bestaetigung des Users ("genau richtig", "perfekt so") bei einer nicht-offensichtlichen Entscheidung → ebenfalls als Feedback-Memory (validiertes Pattern)
- Session-Ende → Skill `session-ende` triggert auf "Schluss"/"Ende"/"Feierabend" (oder `/merkwerk:ende`)

## Audit-Mechanismus (Lernen ueber Lernen)

`/merkwerk:memory-audit` reviewt das gesamte Memory-System auf acht Achsen (+ Unter-Scan 7b):

1. **Konsolidierung** — Memories, die thematisch ueberlappen und zu einer verdichtet werden koennen
2. **Meta-Patterns** — 3+ Memories, die Spezialfaelle einer noch nicht ausgesprochenen uebergeordneten Regel sind
3. **Stale-Lifecycle** — `verified + stale_after_days` ueberfaellig, Kalte-Kandidaten-Regel
4. **Anti-Memories** — Patterns, die formuliert sind, aber wiederholt gebrochen wurden — Optionen: schaerfen / Hook / CLAUDE.md-Hochzug
5. **Hygiene** — Routing-Verstoesse, Index-Drift, Body-Disziplin, Doc-Memory-Konfusion
6. **Cross-System-Coverage** — wo lebt jedes Pattern? CLAUDE.md / Skill / Command / Solo-Memory. Inkl. Trigger-Map-Wartung. Cap: 2 Aktionen pro Audit.
7. **Promotion** — Episoden-Cluster reif fuer echte Memory (§Episodic Layer); Unter-Scan **7b** aggregiert Wurzel-Typen zu Denkfehler-Clustern
8. **Demotion** — Memories, die wiederholt als "vage" entlarvt wurden, zurueck in den Episodic Layer

Dazu Schritt 0.5: Betriebsschicht-Healthcheck (`hooks/memory-system-healthcheck.sh`) laeuft bei jedem Audit mit.

Closed-Loop: jeder Audit liest die letzten 3 Audit-Files in `CLAUDE_HOME/memory/audits/` und schreibt selbst eines am Ende. Doppelt-Vorschlag-Verbot fuer abgelehnte Vorschlaege; Anti-Memory-Verfolgung prueft "greift die geschaerfte Regel jetzt?".

Ausfuehren: alle 4-6 Wochen oder wenn die Episoden-Zahl seit dem letzten Audit ueber 30 steigt (der SessionStart-Hook `memory-audit-reminder.sh` erinnert), beim Schreiben einer neuen Memory ein Ueberlapp gefuehlt wird, oder ein Anti-Memory bemerkt wird.

Ergebnis ist Befund + nummerierte Aktions-Liste — Ausfuehrung NUR auf explizite Bestaetigung. Memories werden nie autonom geloescht oder gemerged.

### Eskalationsleiter — was nachweislich wirkt

Destilliert aus sechs Audits eines produktiven Systems. SSoT fuer Achse-4-Vorschlaege; die Gesamtdaten fuehrt der Audit in `CLAUDE_HOME/memory/audits/LERNKURVE.md` fort.

1. **Textstufe wirkt hoechstens 2x pro Klasse.** Beleg: eine Regel vier Stufen flach nachgeschaerft (23 % → 13 % → 24 % → 29 % Reibung). Ab der dritten Stufe ist ein weiterer Text Selbstberuhigung, kein Vorschlag mehr.
2. **Deterministisch erkennbarer Ausloeser → direkt Gate**, keine dritte Textstufe. Beleg: ein Byte-Deckel am Commit toetete die Klasse `zu-frueh-committet` 9→0 und hielt ueber 150 Folge-Episoden.
3. **Gate-Wirkung nur mit fremder Herkunft messen.** Beleg: zweimal gruene eigene Suite bei offenen Schadensformen — die Testdatei des Gate-Autors teilt dessen Annahmen. Zeugen aus der belegten Realitaet ziehen (reflog, Commit-Betreffs, Ausfall-Logs), nie aus der eigenen Vorstellung.
4. **Bruch trotz Gate → Gate reparieren, keine neue Stufe.** Erst die Fehlerform am Gate NACHFAHREN (Payload bauen, Exit lesen).
5. **Semantische Ausloeser sind per Hook nicht erreichbar.** Dort bleiben nur Textstufe (max 2, siehe 1.) und das einzige, was in den Belegen je gefangen hat: eine **unabhaengige Zweitmessung**.
6. **Vor dem Bau eines Gates die echten Wege messen, dann dort pruefen, wo alle zusammenlaufen.** Ein Gate an einem Werkzeug deckt nur die Wege, die sich der Autor vorgestellt hat. Pflicht vor dem Bau: aus den Sitzungsprotokollen (`projects/*/*.jsonl`) zaehlen, ueber welche Werkzeuge die Fehlerform real entsteht. Pruefpunkt dann am Zusammenlaufpunkt: am Artefakt, am Commit (`git-hooks/pre-commit`) oder am echten Zustand, nicht an der Befehlsform. Beleg: der Index-Deckel sass an Write/Edit, alle 13 Verstoesse eines Monats kamen ueber Bash.

Und die Grenze des Ganzen, aus der Lernkurve: die Gesamtreibungsrate blieb ueber sechs Fenster FLACH (~85 %) — Gates toeten Klassen dauerhaft, aber der Blindfleck wandert zu abstrakteren Klassen weiter. Die Leiter senkt Schaden pro Klasse, nicht Reibung insgesamt.

### Korrektur-Reflex-Loop (Lernen aus echten Reibungspunkten)

An echten Reibungspunkten — der User korrigiert/widerspricht, ein Hook blockt, Claude muss ≥3x nachbessern, oder ein Tool-Fehler entstand durch eine falsche Annahme — haelt Claude sofort einen kurzen Reflex mit einem **Wurzel-Typ** fest (max 3 Zeilen: Denkfehler konkret, Wurzel-Typ, was ihn verhindert haette). Der Fluss: Reibungspunkt → Episode-Zeile `Reibung/Wurzel` (gebuendelt am Session-Ende; nur bei grobem Fehler an wichtiger Stelle sofort Feedback-Memory) → Audit aggregiert wiederkehrende Wurzel-Typen zu Blindflecken (Achse 7b) → gehaertete Regel (Feedback-Memory / CLAUDE.md / Hook).

Empfohlene Zeile fuer die `CLAUDE.md` des Users: *"Korrektur-Reflex nur an echten Reibungspunkten: max 3 Zeilen — Denkfehler konkret, Wurzel-Typ, was ihn verhindert haette — dann weiterarbeiten. Taxonomie: `<pfad zu dieser Datei>` §Korrektur-Reflex-Loop."*

**Wurzel-Typ-Taxonomie** (klein halten, neue Typen nur via Audit; die Zaehl-Liste in `hooks/wurzel-fruehwarnung.sh` mitpflegen): `angenommen-statt-gelesen` · `kontext-uebersehen` · `zu-frueh-committet` · `wunsch-ueber-beleg` · `scope-missverstanden` · `regel-vergessen` · `oberflaechlich-geprueft` · `keine-reibung`

`keine-reibung` ist bewusst KEIN Denkfehler-Typ, sondern das Gegenteil: der Anlass war eine Werkzeug-, Umgebungs- oder Ressourcengrenze (Tool-Limit, externe Quelle nicht erreichbar, Guardrail greift korrekt), nicht eine Fehlannahme. Ohne dieses Label werden solche Faelle ersatzweise unter `angenommen-statt-gelesen` gezaehlt und verzerren die Blindfleck-Statistik nach oben. NICHT als Ausrede fuer echte Denkfehler nutzen; im Zweifel den inhaltlichen Typ nehmen.

**Harte Grenze**: Reflexion NUR an realen Anlaessen, nie freie Introspektion ("finde deine Denkfehler") — das wuerde konfabulieren. Verdichtung vor Volumen: der Reflex ist max 3 Zeilen, nicht ein Gruebel-Essay.

## Trigger-Routing (Memory automatisch zur richtigen Zeit aktivieren)

Solo-Memories (Pattern lebt nur in der Memory, nicht in CLAUDE.md oder Skill) haben hohes Anti-Memory-Risiko — Lazy-Load laedt sie nur bei manuellem Hook-Match. Loesung: **Trigger-Router** matcht User-Prompts gegen Regex-Patterns und zeigt die passende Memory als Reminder an, plus stempelt `last_used: <today>` in der Memory.

**Komponenten**:

- `CLAUDE_HOME/memory/trigger_map.md` — Single Source of Truth fuer Patterns. Format `<regex> ||| <memory_pfad> ||| <anlass>`, Trenner `|||` weil Regex selbst Pipes enthaelt. Optional unter einer Mapping-Zeile `# eval: <Soll-Prompt>` — der Healthcheck prueft, dass das Pattern diesen Prompt trifft
- `hooks/memory-trigger-router.sh` — `UserPromptSubmit`-Hook, max 3 Treffer pro Prompt, 30-Min-Fenster pro Memory (State in `CLAUDE_HOME/.cache/trigger_history.json`)
- `CLAUDE_HOME/.cache/trigger_hits.log` — append-only Treffer-Log (`timestamp|memory_pfad`), eine Zeile je realem Fire. Beleg-Quelle fuer die Audit-Zaehlung. Semantik: belegt "Reminder gezeigt", nicht "Regel befolgt"

**Wartung**: Bei jedem Audit (Achse 6) pruefen, ob neue Solo-Memories im Trigger-Map fehlen, ob Patterns False-Positives produzieren, ob Memories noch existieren (toter Trigger).

**Beifang fuer Stale-Check**: Memories, die durch Trigger gefeuert werden, bekommen `last_used: <today>` automatisch — die Kalte-Kandidaten-Regel sieht sie als "frisch".

## Episodic Layer (Two-Tier Memory)

| Schicht | Ort | Was | Lifecycle |
|---|---|---|---|
| **Semantic** | `CLAUDE_HOME/memory/` + `CLAUDE_HOME/projects/<id>/memory/` | kuratierte verallgemeinerte Patterns | indefinite, Stale-Check |
| **Episodic** | `CLAUDE_HOME/episodes/YYYY-MM/` | Sammelbecken pro Session, 5-Zeilen-Markdown | Hart-Loeschung nach 90 Tagen wenn nicht promoted |

**Schreib-Trigger Episodic**: Skill `session-ende` Schritt 1.5 schreibt automatisch beim Session-Ende. Format ist 5 Pflicht-Abschnitte (Was passierte, Was gelernt, Reibung/Wurzel, Offen, Workspace) — kein Frontmatter, kein Tag-System. Der Wurzel-Typ steht als EXAKTES Taxonomie-Token in der Zeile. Schritt 1.7 committet danach die eigenen Schreibpfade der Session ueber `hooks/memory-auto-commit.sh`.

**Fruehwarnung (Loop-Latenz)**: Skill-Schritt 1.6 (`hooks/wurzel-fruehwarnung.sh`) zaehlt beim Session-Ende deterministisch die Wurzel-Typen seit dem letzten Audit (Schwelle wie Achse 7b: ≥3 Treffer aus ≥2 Sessions) und weist auf auflaufende Denkfehler-Typen hin, statt auf den naechsten Audit zu warten. Nur Hinweis, kein Auto-Fix.

**Promotion-Loop**: Audit Achse 7 erkennt Episoden-Cluster und schlaegt Promotion zu echter Memory vor. Schwelle: Confidence-tiered (hoch=2, mittel=3, niedrig=5 Episoden) + Mindest-Session-Distance ≥2 (verhindert, dass eine lange Session zu 3 Episoden fuehrt). Bewertung beim Audit, nicht beim Schreiben.

**Demotion-Loop**: Achse 8 erkennt Memories, die durch Adversarial Probing wiederholt als "vage" entlarvt werden (2x in Folge in zwei verschiedenen Audits). Vorschlag: Memory zerlegen, original Why als Episode erhalten, semantische Memory loeschen.

**Verfall**: `hooks/episode-cleanup.sh` (vom Audit im `apply`-Modus aufgerufen, kein automatischer Hook). Loescht Episoden hart wenn `(today - file_mtime) > 90` UND nicht in `CLAUDE_HOME/episodes/_promoted.txt` gelistet. Hart-Loeschung statt Archiv — konsistent mit der Forgetting-Curve.

**Promoted-Index**: `CLAUDE_HOME/episodes/_promoted.txt`. Eine Zeile pro Episode-Pfad, die zu Memory wurde (kanonisch: relativ zu `CLAUDE_HOME`, mit `episodes/`-Praefix). Audit haengt automatisch an. Schutz vor Drift: Cleanup prueft Existenz — Eintrag ohne Datei wird entfernt, aber nur, wenn weniger als 20 % der Eintraege tot wirken (sonst Pfadproblem-Verdacht, nichts anfassen).

**Eleganz-Prinzip**: Markdown bleibt Source-of-Truth in beiden Layern. Bidirektionaler Lifecycle (Promotion + Demotion) — das System kann sich irren und korrigieren. Volumen ist nur im Episodic erlaubt, Semantic bleibt verdichtet.

### Versionierung: drei Repos, eines bewusst ohne Remote

| Repo | Inhalt | Remote |
|---|---|---|
| `CLAUDE_HOME/memory/` | Cross-Workspace-Memories, Audits, `trigger_map.md` | empfohlen (privat) |
| `CLAUDE_HOME/episodes/` | Episodic Layer + `_promoted.txt` | empfohlen (privat) |
| `CLAUDE_HOME/projects/` | **nur** `*/memory/**` per Whitelist | **keins, bewusst** |

`install.sh` legt die drei Repos an. Remotes richtet der User selbst ein (`git remote add origin ...`, Erst-Push von Hand).

**Warum kein Remote fuer `projects/`:** Projekt-Memories tragen Betriebsinterna (Server-Adressen, Projekt-IDs, Preise, Kunden). Die Cross-Schicht darf in ein privates Remote, diese nicht. `hooks/memory-auto-commit.sh` committet alle drei Repos, pusht aber `projects/` nie — auch dann nicht, wenn jemand dort ein origin eintraegt; der Healthcheck meldet ein solches origin als Befund.

**Falle bei der Whitelist:** Die `.gitignore` in `projects/` muss `/*` → `!/*/` → `/*/*` → `!/*/memory/**` in dieser Reihenfolge fahren. Wer nur `/*` und `!/*/` schreibt, holt mit den Verzeichnissen auch deren gesamten Inhalt zurueck und zieht die Session-Transkripte mit ein. Nach Aenderungen an dieser `.gitignore` gegenpruefen: `git diff --cached --name-only | grep -c '\.jsonl$'` muss 0 sein.

**Commit-Disziplin bei parallelen Sessions:** An den Memory-Repos arbeiten oft mehrere Claude-Sessions gleichzeitig. Darum committet `memory-auto-commit.sh` NUR explizit genannte Pfade, nie `git add -A`. Ein Aufruf mit Pfaden fuer ein Repo laesst den Index der anderen Repos unberuehrt; ein gescheiterter Commit (z.B. Index-Deckel) endet mit Exit != 0 statt stummem Erfolg. Gegenprobe: `tests/memory-auto-commit.test.sh`.

## Betriebssicherheit (Robustheits-Schicht)

Die Betriebsschicht (Hooks) ist gegen drei Ausfall-Klassen gehaertet. Prinzip durchgehend: **Wurzel-Fix statt Pflaster, eine Quelle statt Zwillinge, normalisieren statt raten.**

### Single Source of Truth fuer geteilte Logik

- `hooks/lib/trigger-map.sh` — `tm_parse` (trigger_map-Mappings), `tm_eval_pairs` (eval-Soll-Prompts), `tm_stamp_last_used` / `tm_unstamp_last_used` (Frontmatter-Stempel). Router, Healthcheck und Read-Stamp sourcen dieselbe Lib — kein Parser-Zwilling.
- `hooks/lib/episodes.sh` — `ep_canon`/`ep_exists`. Existenz-Checks **normalisieren auf kanonisch und pruefen EINEN cwd-unabhaengigen Pfad**, statt drei Formate per OR-Kette zu raten (Wurzel eines Beinahe-Unfalls, bei dem alle Promoted-Eintraege "tot" aussahen, weil der Lauf aus einem anderen Verzeichnis startete).

### Stille Ausfaelle laut machen

- `hooks/memory-system-healthcheck.sh` (SessionStart) prueft bei jedem Start: Bestand angelegt, Interpreter da, trigger_map konsistent, `_promoted.txt` ohne tote Eintraege, Commit-Drift je Repo, kein origin an `projects/`, Index-Deckel am Commit erreichbar. Silent, wenn alles stimmt.
- Jeder Hook ist advisory (exit 0) ausser den Gates; die Gates sind fail-open, aber LAUT (stderr nennt den Ausfall).

### Verlaessliche Kalte-Kandidaten-Messung

- `hooks/memory-read-stamp.sh` (PostToolUse/Read) — stempelt `last_used` bei JEDEM Memory-Read, nicht nur bei Trigger-Treffern. Throttle: max 1 Rewrite pro Datei/Tag. **Burst-Filter**: ab 10 verschiedenen Memories in 15 Minuten gilt der Lauf als Sweep (Audit, Budget-Check) und stempelt nicht — Massenlesen ist kein Gebrauch, und ein Pruefer darf das Signal nicht zustempeln, das er auswerten soll.

## Was NICHT in Memory gehoert

- Code-Patterns, Architektur, Pfade — aus Code lesbar
- Git-History — `git log` ist authoritativ
- Debugging-Loesungen — Fix steht im Code, Why im Commit
- Was schon in CLAUDE.md steht
- Ephemere Task-Details
