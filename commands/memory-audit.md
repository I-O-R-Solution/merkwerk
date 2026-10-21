---
description: Memory-System auditieren — Konsolidierung, Meta-Patterns, Stale, Anti-Memories, Cross-System-Coverage. Kompakter Befund mit konkreten Aktionen, max 110 Zeilen Output.
argument-hint: "[dry-run|apply]"
---

Du bist der Memory-System-Auditor des Users. Dein Job: Das Memory-System (Cross-Workspace + Auto-Memory) **regelmaessig auditieren** und kompakt zurueckliefern, was konsolidiert, generalisiert, archiviert oder neu formuliert werden sollte.

**Mantras (in dieser Reihenfolge):**

1. *"Mehr Memories sind nicht besseres Lernen — Verdichtung ist."* — Memory-Audit-Grundsatz
2. *"Eine Memory die nicht angewandt wird ist Selbst-Luege im System."* — Anti-Memory-Test
3. *"Why-Felder altern langsam, Status-Felder altern schnell."* — Lifecycle-Heuristik

Antworte auf Deutsch. Technische Begriffe bleiben englisch.

Argument: $ARGUMENTS — optional. `CLAUDE_HOME` = `$CLAUDE_CONFIG_DIR`, sonst `~/.claude`. Default (kein Argument oder `dry-run`): nur Befund liefern, keine Aenderungen. Wenn `apply`: nach Befund nummerierte Aktions-Liste praesentieren und auf "Setze Punkt N um" warten.

## Schritt 0: Audit-History laden (Closed Loop)

Vor jeder Analyse: Lies das Verzeichnis `CLAUDE_HOME/memory/audits/` (falls existiert) und nimm die letzten 3 Audit-Files in den Kontext. Pro Eintrag intern erfassen:

- **Datum** des vorigen Audits
- **Vorgeschlagene Aktionen** (Konsolidierung, Meta-Pattern, Anti-Memory)
- **User-Entscheidungen**: was wurde umgesetzt, was abgelehnt, mit welchem Why
- **Offene Items**: was wurde fuer den naechsten Audit zurueckgestellt

Regeln, die daraus entstehen:

- **Doppelt-Vorschlag-Verbot**: Wenn ein Konsolidierungs-Cluster bereits in einem der letzten 3 Audits vorgeschlagen UND vom User abgelehnt wurde, NICHT erneut vorschlagen — es sei denn, neue Memories sind seit der Ablehnung dazugekommen, die das Cluster-Bild aendern. Dann transparent machen: "Cluster wurde am <Datum> abgelehnt mit Begruendung <X>; neue Lage durch <Y> rechtfertigt erneuten Vorschlag."
- **Anti-Memory-Verfolgung (Drei-Status-System)**: Memories die in einem vorigen Audit als Anti-Memory geflaggt wurden, MIT Aktion (z.B. "geschaerft am 2026-04-04"), in der aktuellen Anti-Achse pruefen. Statt Ja/Nein nutze drei Status:
    - **`geheilt-mit-Beleg`** — Auditor kann eine konkrete Anwendung der geschaerften Regel benennen (Datum/Session/Kontext). Im Output: "Heilung bestaetigt — Beleg: [konkreter Vorfall]".
    - **`keine-evidenz-fuer-Bruch`** — kein Beleg fuer Anwendung, aber auch kein Beleg fuer Bruch. Default bei Unsicherheit. Im Output: "Vorsichtige Annahme: keine Evidenz fuer Bruch seit [Datum]; weiter beobachten."
    - **`gebrochen`** — klarer Verstoss in einer Session zwischen den Audits dokumentiert. Im Output: "Erneut gebrochen [Vorfall] — Eskalation: naechste Stufe (Hook → CLAUDE.md) vorschlagen."
  Ohne konkreten Beleg darf NICHT "Heilung bestaetigt" geschrieben werden — `keine-evidenz-fuer-Bruch` ist die ehrliche Default-Antwort, nicht Selbstlob.
- **Offene Items uebernehmen**: Items aus "Naechstes Audit"-Section vorgaenger automatisch in aktuelles Audit aufgreifen.

Wenn `audits/` leer ist: vermerken "Erster Audit — keine Historie" und normal weitermachen.

## Schritt 0.5: Betriebsschicht-Healthcheck

Einmal ausfuehren: `bash "${CLAUDE_PLUGIN_ROOT}/hooks/memory-system-healthcheck.sh"`

Der Audit ist der natuerliche Moment, die Betriebsschicht mitzupruefen (fehlende
Manifest-Hooks, tote Referenzen). Meldet er Probleme: als ersten Hygiene-Befund
in den Output aufnehmen (inkl. Restore-Kommando das er ausgibt). Silent wenn sauber.

## Schritt 1: Memory-Inventar erstellen

**Workspace-ID dynamisch ableiten (nicht hardcoden):**

Per Bash: `pwd` → Pfad in Claude-Code-Slug konvertieren. Konvention: Doppelpunkt,
Pfadtrenner UND Punkte werden JE zu einem Bindestrich; Gross/Kleinschreibung bleibt.
Beispiel: `c:\Users\jane\.claude` → `c--Users-jane--claude` (das `--claude` entsteht
aus `\` + `.`).

Wenn das resultierende Verzeichnis `CLAUDE_HOME/projects/<slug>/memory/` NICHT
existiert: `ls CLAUDE_HOME/projects/` laufen lassen und pruefen ob ein Slug dem
`pwd` offensichtlich entspricht (Tippfehler-/Konventions-Drift). Nur wenn auch
das nichts ergibt: Fallback auf cross-workspace-only und im Output flaggen:
"Auto-Memory-Schicht fuer aktuellen Workspace nicht gefunden — nur
Cross-Workspace auditiert. Slug-Pfad versucht: <slug>".

**Lese-Disziplin (Pflicht — Anti-Truncation):** Memory-Files NIEMALS per Sammel-`cat`/`for`-Schleife in einem Bash-Aufruf lesen. Solche Bulk-Reads werden bei viel Material (>~40 KB) STILL abgeschnitten — der Auditor merkt es nicht und auditiert auf halben Daten (real passiert: falscher „leerer Block"-Befund aus Truncation). Stattdessen:

- Zuerst nur die Datei-Liste + Zeilenzahl holen: `wc -l CLAUDE_HOME/memory/*.md` (+ Workspace-Pfad). Das ist klein und truncatet nicht.
- Dann **jede** Memory-Datei einzeln mit dem **Read-Tool** lesen (nicht Bash-`cat`). Read paginiert sichtbar statt still abzuschneiden — und erfüllt zugleich den Read-before-Edit-Hook, falls die Memory später im selben Lauf editiert wird (spart die sonst nötigen Nachlese-Calls).
- Datei mit > 2000 Zeilen: in Read-Segmenten bis EOF lesen. Vollständigkeit verifizieren: gelesene Datei-Zahl == `wc -l`-Liste, jede Datei bis zur letzten Zeile. Bei Lücke nachladen, bevor irgendein Befund darauf gestützt wird.

Pro Datei dabei erfassen:

1. **Cross-Workspace** (`CLAUDE_HOME/memory/`): MEMORY.md + alle `*.md`-Files (inkl. `audits/`-Historie aus Schritt 0)
2. **Auto-Memory** (`CLAUDE_HOME/projects/<dynamisch abgeleiteter slug>/memory/`): MEMORY.md + alle `*.md`-Files
3. **Frontmatter-Extrakt** pro File: `name`, `type`, `verified`, `stale_after_days`, ggf. `status`
4. **Body-Quick-Scan**: `Why:` und `How to apply:` extrahieren (erste 200 Zeichen reichen)

Aufgabe: Liste mit (Pfad, Type, Tage-seit-verified, Stale-Status, Themen-Tags die du aus dem Inhalt ableitest). NICHT zeigen — nur intern halten.

## Schritt 2: Die Pruef-Achsen

### Achse 1: Konsolidierungs-Kandidaten (Themen-Cluster)

Welche Memories ueberlappen thematisch und koennten zu einer einzigen Memory verdichtet werden?

Heuristik: Wenn 2+ Feedback-Memories denselben Why-Kern haben (z.B. "weniger ist mehr"), ist Konsolidierung wahrscheinlich elegant. NICHT konsolidieren wenn die How-to-apply-Felder konkret unterschiedlich sind — dann sind es echte Spezialfaelle einer Meta-Regel (das gehoert in Achse 2).

### Achse 2: Meta-Pattern-Kandidaten (uebergeordnete Regel)

Welche 3+ Memories sind Spezialfaelle einer noch nicht ausgesprochenen Meta-Regel?

Heuristik: Wenn du bei der Auflistung der Why-Felder denkst "die zeigen alle dasselbe Prinzip aus verschiedenen Winkeln", ist das ein Meta-Pattern-Kandidat. Vorschlag: neue Memory mit der Meta-Regel + Pointer auf die Spezialfaelle (NICHT die Spezialfaelle loeschen — sie liefern den konkreten Anwendungs-Kontext).

### Achse 3: Stale-Lifecycle

- **Ueberfaellig**: `(today - verified) > stale_after_days` — flaggen + Aktion (verifizieren / archivieren / `stale_after_days` erhoehen wenn Projekt ruht)
- **Status-Marker pruefen**: Frontmatter-Feld `status:` (z.B. "ruht") — wenn vorhanden, in Aktions-Vorschlag einrechnen
- **Fehlende Stale-Frontmatter** bei `type: project` oder zeitkritischem `type: user`/`reference` → Pflicht-Erinnerung
- **Kalte-Kandidaten-Regel**: wenn `last_used` fehlt **ODER** `(today - last_used) > 60` UND `(today - verified) > 60` UND **NICHT** `critical: true` → flaggen als "kalter Kandidat" (Aktion: re-verify / Stale verlaengern / archivieren). Memories die selten ausgeloest werden aber bei Verstoss Schaden anrichten, brauchen `critical: true` als Schutz
  - **`last_used` misst ALLE Zugriffe**: nicht nur Trigger-Router-Treffer, sondern auch Lazy-Load-Reads via `hooks/memory-read-stamp.sh` (PostToolUse). Vorher war das Signal blind fuer lazy geladene Memories — eine genutzte Memory sah trotzdem "kalt" aus. Die Regel misst damit erst seitdem verlaesslich; `last_used`-Werte aus der Zeit davor sind als untere Schranke zu lesen (nicht "nie benutzt", nur "nie getriggert")

### Achse 4: Anti-Memories (Pattern wird nicht angewandt)

Schwierigste Achse — braucht Selbst-Reflexion. Frage pro Feedback-Memory:

- Hast du das Pattern in den letzten Sessions gebrochen? Wenn ja → Anti-Memory.
- Ist das Pattern so vage formuliert, dass es nicht durchsetzbar ist? → Anti-Memory.
- Steht es im Widerspruch zu einer anderen, neueren Memory? → Konflikt flaggen.

**Adversarial Probing**: pro Feedback-Memory **1 Counterexample-Probe** generieren — eine konkrete Sample-Situation, in der du entscheiden musst "wuerde die Memory hier eindeutig handlungsleitend sein?". Drei mogliche Antworten:

- **Memory greift klar** — valider Output, keine Aktion noetig
- **Memory zu vage** — Schaerfungs-Vorschlag im Output
- **Nicht anwendbar** — Probe war ausserhalb des Memory-Scope, kein Befund

**Hard-Constraints** fuer Probes:

- Probe muss aus der realen Domain des Users stammen (ableitbar aus CLAUDE.md, den project-Memories und den Episoden) — keine Phantasie-Probes
- Bei Unsicherheit: keine Probe (valider Output)
- Maximal 1 Probe pro Memory (Audit-Laufzeit beachten)

**Anwendungs-Zaehlung (nur belegte Ereignisse)**: pro geprueftem Anti-Memory-Kandidaten aus genau DREI Quellen zaehlen — (a) `*_blocked_*`-Episoden eines Schutz-Hooks (falls der User einen betreibt) **nach bestandener Herkunfts-Probe** (siehe unten), (b) `**Reibung/Wurzel**`-Zeilen der Episoden SEIT dem letzten Audit (**angewendet** / **gebrochen** / **neutral** je nach Inhalt), (c) `CLAUDE_HOME/.cache/trigger_hits.log` — Feuer-Frequenz des Trigger-Routers pro Memory (Zeilen-Format `timestamp|memory_pfad`).

**Herkunfts-Probe fuer Quelle (a) — Pflicht vor jeder Zaehlung** (eingefuehrt, weil die alte Regel „zaehlen automatisch als gebrochen" in einem Lauf beinahe 25 Scheinbrueche gemeldet haette): Eine Block-Episode belegt, dass der Guard gefeuert hat — nicht, dass eine Regel gebrochen wurde. Drei Herkuenfte sind moeglich, nur die erste zaehlt:

1. **Echter Verstoss** — ein Arbeitsbefehl, der die Regel wirklich verletzt. Zaehlt als **gebrochen**.
2. **Gegenprobe/Testlauf** — der blockierte Befehl stammt aus einer Testsuite oder Hook-Probe. Zaehlt **gar nicht**. Erkennungsmerkmale: identischer Befehlstext dutzendfach ueber Tage, Testfall-Kennungen (`--dry-run`, Marker wie `p1.6-m`, `"echt"`), Haeufung binnen Minuten. **Pruefung:** den auffaelligen Befehlstext im Workspace greppen (`grep -rn "<text>" <workspace> --include='*.sh' --include='*.js'`) — findet sich eine Testdatei, ist die Herkunft geklaert.
3. **Fehlalarm des Guards** — der Befehl verletzt nichts, das Muster traf daneben (Beleg: ein Heredoc-Text wurde als „rm -rf ~" geblockt, weil er als Befehl gelesen wurde). Zaehlt **nicht als Bruch**, aber als **Hygiene-Befund** gegen den Guard.

Im Output die Trennung sichtbar machen: „N Blocks roh, davon T Testlaeufe / F Fehlalarme / **E echte**". Ohne diese Trennung ist die Anti-Achse blind fuer den Unterschied zwischen einem Rueckfall und einem gut getesteten System — und bestraft ausgerechnet die Workspaces, die ihre Guards am gruendlichsten pruefen. Semantik-Leitplanke: der Log belegt "Reminder wurde gezeigt", NICHT "Regel wurde befolgt" — Wirkung bewertet der Auditor ausschliesslich gegen (a)+(b). Keine selbstberichteten "hat gegriffen"-Stempel ausserhalb dieser drei Quellen (Konfabulations-Schutz, siehe feedback_keine_worte_in_mund_legen). Im Output Zahlen nennen: "angewendet 5x, gebrochen 0x, getriggert 12x seit <Datum>". "keine-evidenz-fuer-Bruch" bleibt der ehrliche Fallback bei 0 Treffern — aber erst NACH der Zaehlung, nicht statt ihr.

**confidence-Pflege** (nur bei "Setze Punkt N um", NIE im Dry-Run): bei `geheilt-mit-Beleg` +1 Stufe (0.3→0.6→0.9, Maximum), bei `gebrochen` −1 Stufe (Minimum 0.3); fehlt das Feld, mit 0.6 anlegen. Memories auf 0.9 im Output als Hochzug-Kandidat (CLAUDE.md/Hook) nennen.

**Eskalations-Beschleunigung**: 2x gebrochen in Folge — ueber zwei Audits ODER zwei dokumentierte Vorfaelle zwischen Audits (z.B. zwei `*_blocked_*`-Episoden, die die Herkunfts-Probe bestanden haben) — loest den Eskalations-Vorschlag (Hook/CLAUDE.md) SOFORT im selben Audit aus, nicht "weiter beobachten".

**Wenn die Klasse schon ein Gate hat**: Ein erneuter Bruch ist dann KEIN Argument fuer die naechsthoehere Stufe, sondern zuerst der Verdacht, dass das bestehende Gate ein Loch hat. Pflicht vor jedem Eskalations-Vorschlag: die Fehlerform am Gate NACHFAHREN (Payload bauen, Hook aufrufen, Exit lesen). Blockt es die belegte Form nicht, ist die Reparatur des Gates der Vorschlag — nicht eine neue Stufe (Beleg: ein Gate feuerte live und liess trotzdem 4 realistische Formen durch; die eigene Gegenprobe war dabei 34/34 gruen).

Stufenwahl nach der belegten **Eskalationsleiter** in `docs/memory-protocol.md` §Eskalationsleiter (max 2 Textstufen pro Klasse; deterministischer Ausloeser direkt Gate; Gate-Wirkung nur mit fremder Herkunft; semantische Ausloeser: Zweitmessung statt Hook). Zusaetzlich pro Audit `CLAUDE_HOME/memory/audits/LERNKURVE.md` um eine Fenster-Zeile fortschreiben (Methode steht in der Datei; beim ersten Audit anlegen: Datum, Episoden mit Wurzel-Zeile, Anteil mit benannter Reibung).

Bei Anti-Memories: nicht loeschen. Optionen vorschlagen — (a) schaerfer formulieren, (b) als Hook in `settings.json` migrieren (deterministische Durchsetzung), (c) als CLAUDE.md-Zeile hochziehen wenn Always-On gerechtfertigt, (d) ins `trigger_map.md` aufnehmen falls Solo-Memory.

### Achse 5: Routing- und Hygiene-Verstoesse

- **Routing-Verstoss**: User-Profile in Workspace-Schicht oder Projekt-Fakten in Cross-Workspace
- **Index-Drift**: `MEMORY.md`-Eintrag fehlt fuer ein File ODER Eintrag zeigt auf nicht-existentes File. **Index-frei per Design** (KEIN Drift-Befund): `audits/`-Historie, `trigger_map.md`, `_promoted.txt`
- **Body-Disziplin**: `feedback` oder `project` ohne klare `Why:`-Sektion
- **Doc-Memory-Konfusion**: Memory >80 Zeilen oder mit umfangreichen Tabellen/Mail-Templates → Kandidat fuer Doc-Auslagerung mit Pointer
- **Tote `originSessionId`**: Feld vorhanden ohne Mehrwert — ggf. streichen (Default: behalten, aber nicht aktiv pflegen)
- **Anlass-Vokabular** (Recall-Oberflaeche; bewusst statt Embeddings): 3-5 MEMORY.md-One-Liner stichprobenhaft Fresh-Eyes-testen — "wuerde ein frischer Claude einen realistischen Prompt des Users auf diese Zeile matchen?" Hooks die nur Fachbegriffe tragen (ohne das Alltagsvokabular des Users) → Umformulierungs-Vorschlag

### Achse 6: Cross-System-Coverage (Wo lebt das Pattern wirklich?)

Pro `type: feedback`-Memory pruefen, ob das Pattern auch ausserhalb der Memory-Schicht kodiert ist. Such-Set:

- `CLAUDE_HOME/CLAUDE.md` und alles, was sie per `@`-Import einbindet (Always-On)
- `CLAUDE_HOME/skills/*/SKILL.md` — fokussiere auf vom User selbst gebaute Skills. Skills aus Plugins oder fremden Repos enthalten selten die Patterns des Users
- `CLAUDE_HOME/commands/*.md`
- `CLAUDE_HOME/rules/*.md` (falls dort was liegt)

Pro Memory einer von vier Status:

1. **Always-On-Doppel** — Pattern ist sowohl in CLAUDE.md (oder einem Import) als auch Memory. Memory liefert Vertiefung. Status: gut, kein Handlungsbedarf.
2. **Skill-Durchgesetzt** — Pattern wird durch einen Skill/Command deterministisch ausgefuehrt. Status: Goldstandard, Anti-Memory-Risiko nahezu null.
3. **Solo-Memory** — Pattern lebt NUR in der Memory. **Anti-Memory-Risiko hoch**, weil Lazy-Load die Memory nur bei Hook-Match laedt. Bei hoher Anwendungs-Frequenz: Hochzug-Kandidat (CLAUDE.md). Bei Trigger-spezifischer Anwendung (z.B. nur bei Bootstrap): Solo-OK, aber Hook im Index pruefen.
4. **Tot-Doppelt** — Pattern ist in einem Skill VOLLSTAENDIG kodiert UND zusaetzlich als Memory-Kopie vorhanden ohne Mehrwert. Memory zu Pointer reduzieren ("siehe Skill X").

Heuristik fuer Begriffs-Matching: nicht jedes Wort-Match ist echte Coverage. Nur zaehlen wenn das **Why** des Patterns in der anderen Quelle enthalten oder direkt ableitbar ist. Beispiel: Wort "simplicity" in einem SEO-Skill als Coding-Style-Hinweis ist NICHT dieselbe Idee wie `feedback_simplicity_over_formalism` (Anti-Premature-Structure).

**Trigger-Map-Wartung (Pflicht-Teil dieser Achse** — versprochen in
`docs/memory-protocol.md` §Trigger-Routing, vorher nirgends ausgefuehrt):
`CLAUDE_HOME/memory/trigger_map.md` lesen und pruefen:

- **Fehlender Trigger**: Solo-Memory (Status 3) ohne Eintrag im Trigger-Map → Kandidat fuer neuen Pattern-Eintrag
- **Toter Trigger**: Eintrag zeigt auf Memory-Pfad der nicht mehr existiert → Zeile entfernen (Vorschlag)
- **False-Positive-Verdacht**: Pattern das laut `CLAUDE_HOME/.cache/trigger_hits.log` auffaellig oft feuert (append-only Treffer-Log, Frequenz pro Memory zaehlbar — `trigger_history.json` haelt nur Last-Fire-Timestamps), dessen Memory aber themenfremd zu den Sessions ist → Pattern schaerfen

Befunde zaehlen in den Cross-System-Cap hinein (siehe unten).

Aktions-Vorschlaege **max 2 pro Audit** (Cap):

- **Hochzug** → CLAUDE.md (fuer Solo-Memories die hochfrequent oder vertrauens-kritisch sind)
- **Pointer-Reduktion** → Memory zu thin pointer (fuer Tot-Doppelte)
- **Cross-Reference einfuegen** → in Memory-Index-Hook ergaenzen "(auch in CLAUDE.md / Skill X)"
- **Trigger-Map-Fix** → Eintrag ergaenzen / tote Zeile entfernen / Pattern schaerfen

### Achse 7: Promotion-Kandidaten (Episodic → Semantic)

`CLAUDE_HOME/episodes/YYYY-MM/*.md` ist das Sammelbecken pro Session. Achse 7 prueft ob Episoden-Cluster reif fuer Promotion zu echter Memory sind.

**Kontext-Schutz bei >30 Episoden (Pflicht)**: Episoden NICHT alle in den
Haupt-Kontext lesen. Stattdessen einen Subagent (Explore oder general-purpose)
mit Schritt 1+2 unten beauftragen. Der Subagent-Auftrag enthaelt:
Episoden-Pfad-Liste, das 5-Abschnitts-Format, die Cluster-Definition aus
Schritt 2 UND den Auftrag fuer Unter-Scan 7b (Wurzel-Typ-Zaehlung inkl.
`*_blocked_*`). Rueckgabe kompakt: pro Cluster Name, Episoden-Pfade,
Session-Praefixe, 1-Satz-Pattern, Zitat-Beleg (max 1 Zeile pro Episode) +
die 7b-Zaehltabelle (Wurzel-Typ / Treffer / Sessions / Beleg-Pfade). Der
Auditor prueft danach die Beleg-Episoden der finalen Kandidaten selbst nach
(Read, stichprobenhaft) — Befunde ohne Nachpruefung duerfen nicht in den
Output. Dieselbe Anti-Truncation-Disziplin wie Schritt 1 des Audits gilt
auch fuer den Subagent (Read-Tool, kein Sammel-cat).

**Vorgehen**:

1. Liste alle Episoden der letzten 90 Tage (rekursiv ueber Monats-Subordner)
2. Cluster nach Inhalts-Aehnlichkeit (Auditor-Reasoning, kein Tag-System) — Cluster = mehrere Episoden mit gemeinsamem Pattern in "Was passierte" oder "Was gelernt"
3. Pro Cluster: Confidence-Bewertung **rueckblickend** (kein Frontmatter-Feld noetig):
   - **Hoch** — klares Signal, Beleg vorhanden, Vorfall mit Folgeschaden → Schwelle 2 Episoden
   - **Mittel** — Pattern erkennbar, kein Schaden, Kontext-spezifisch → Schwelle 3 Episoden
   - **Niedrig** — diffuses Signal, Kontext-vag → Schwelle 5 Episoden
4. **Session-Distance-Schutz**: Promotion erst wenn Episoden aus mindestens **2 verschiedenen Sessions** stammen (verschiedene `<session-id-prefix>` im Dateinamen). Verhindert dass eine lange Session 3 Episoden mit 3 Symptomen desselben Vorfalls produziert.
5. Vorschlag: neue Memory `<type>_<slug>.md` mit Why aus Episoden destilliert + Frontmatter-Feld `promoted_from: [<pfad1>, <pfad2>, ...]` als Provenance-Trail.
6. **Cross-Workspace-Check**: stammt der Cluster aus Episoden von ≥2 verschiedenen Workspaces (Workspace-Abschnitt der Episoden), als **Cross-Space-Kandidat** flaggen — die Memory gehoert dann nach `CLAUDE_HOME/memory/` (nicht in eine Workspace-Schicht), betroffene Workspace-MEMORY.md bekommen nur Pointer-Eintraege. Der User entscheidet, ob Cross-Space oder bewusst lokal (verschiedene Whys pro Workspace = lokal lassen).

**Cap**: max 3 Promotion-Kandidaten pro Audit (Aktions-Muedigkeit vermeiden).

**Bei "Setze Punkt N um"**: Memory anlegen, Pfade an `CLAUDE_HOME/episodes/_promoted.txt` anhaengen (eine Zeile pro Episode-Pfad), Index-Eintrag in entsprechendem `MEMORY.md` ergaenzen.

**Niemals autonom** — User bestaetigt explizit.

#### Unter-Scan 7b: Denkfehler-Wurzel-Cluster (Meta-Blindflecken)

Seit dem Korrektur-Reflex (docs/memory-protocol.md §Korrektur-Reflex-Loop) tragen Episoden eine `**Reibung/Wurzel**`-Zeile mit einem **Wurzel-Typ** aus fester Taxonomie. Dieser Unter-Scan aggregiert sie zu Blindflecken — denn ein einzelner Fehler ist Rauschen, derselbe Wurzel-Typ ueber mehrere Sessions ist ein Muster, das eine dauerhafte Regel verdient.

**Vorgehen**:

1. Scanne die `**Reibung/Wurzel**`-Zeilen aller Episoden der letzten 90 Tage + alle `*_blocked_*`-Episoden (falls ein Schutz-Hook solche schreibt) auf den Wurzel-Typ. (Bei >30 Episoden: laeuft im selben Subagent-Auftrag wie Achse 7, siehe Kontext-Schutz dort.)
2. Zaehle pro Wurzel-Typ: Treffer-Anzahl + Anzahl **verschiedener Sessions** (Session-Distance-Schutz wie Achse 7, gegen Dopplung aus einer langen Session).
3. **Schwelle**: ≥3x derselbe Wurzel-Typ ueber **≥2 verschiedene Sessions** → Blindfleck-Kandidat.
4. **Vorschlag** je Kandidat (eine Eskalations-Stufe, nicht alle): geschaerfte/neue `feedback`-Memory (Default) · Hochzug nach `CLAUDE.md` (wenn hochfrequent oder vertrauens-kritisch) · Hook in `settings.json` (NUR wenn der Ausloeser deterministisch erkennbar ist — semantische Korrekturen sind es nicht).
5. Taxonomie-Pflege: taucht ein realer Wurzel-Typ wiederholt auf, der nicht in der Taxonomie steht, als Ergaenzung vorschlagen. Die Taxonomie lebt nur in `docs/memory-protocol.md` §Korrektur-Reflex-Loop und in `hooks/wurzel-fruehwarnung.sh` (Zaehl-Liste); beide zusammen erweitern, bewusst klein halten.

**Cap**: max 2 Kandidaten pro Audit. **Niemals autonom** — User bestaetigt explizit.

### Achse 8: Demotion-Kandidaten (Semantic → Episodic)

Wenn Achse 4 Adversarial Probing eine Memory wiederholt als "vage" entlarvt (zweimal in Folge in zwei verschiedenen Audits), ist die Memory nicht mehr handlungsleitend → Demotion.

**Vorgehen**:

1. Lade letzte 3 Audits aus `CLAUDE_HOME/memory/audits/`
2. Suche nach Memories die in Achse 4 zweimal in Folge "Memory zu vage" Status hatten
3. Vorschlag: Memory zerlegen — original `Why:` als Episode `CLAUDE_HOME/episodes/YYYY-MM/YYYY-MM-DD_demoted_<slug>.md` schreiben, semantische Memory loeschen, Index-Eintrag im entsprechenden `MEMORY.md` entfernen

**Cap**: max 2 Demotion-Kandidaten pro Audit.

**Niemals autonom** — User bestaetigt explizit mit voller Kontext-Sicht.

### Cleanup: Episodic Verfall

Nur im `apply`-Modus vor dem Output ausfuehren: `bash "${CLAUDE_PLUGIN_ROOT}/hooks/episode-cleanup.sh"` — es loescht Episoden hart, wenn `(today - mtime) > 90 Tage` UND nicht in `_promoted.txt`; der Default-Lauf (`dry-run`) verspricht in Schritt 0 "keine Aenderungen" und darf deshalb nichts loeschen. Output silent ausser bei Loeschungen — dann Anzahl im Audit-Output erwaehnen.

Im `dry-run` stattdessen nur zaehlen und als "wuerde loeschen: hoechstens N" melden: `find CLAUDE_HOME/episodes -mindepth 1 -maxdepth 3 -type f -name '????-??-??_*.md' -mtime +90 | wc -l` (ohne Abgleich mit `_promoted.txt`, darum Obergrenze).

## Schritt 3: Output (max 110 Zeilen)

```text
# Memory-Audit — <Datum>

**<Eine-Zeilen-Verdikt>** — N Memories (Cross: X, Workspace: Y), ~Z% gesund, <kritischer Befund oder "keine kritischen Befunde">. Historie: <N voriger Audits, davon <M> mit offenen Items / "Erster Audit">.

## Heilungen aus voriger Audit (nur wenn Historie da)
- **<File>**: <Aktion vom Datum X> — Status jetzt <greift / greift nicht / partiell>
(weglassen wenn keine Heilungen zu pruefen)

## Konsolidierung (max 3)
- **<Cluster-Name>**: <File A> + <File B> [+ <File C>] — <warum konsolidieren> → <konkreter Vorschlag mit neuem Namen>

## Meta-Patterns (max 3)
- **<Meta-Regel-Vorschlag>**: aus <File A>, <File B>, <File C> → neue Memory `feedback_<slug>.md` mit Pointern

## Stale & Lifecycle (max 5)
- **<File>** (X Tage ueberfaellig, status: <status>): <Aktion — verifizieren / Stale erhoehen / archivieren>

## Anti-Memories (max 3)
- **<File>**: <Status — gebrochen / keine-evidenz-fuer-Bruch / geheilt-mit-Beleg> — Aktion oder Bemerkung
  (bei "gebrochen": Vorfall + Eskalations-Stufe; bei "keine-evidenz": "weiter beobachten"; bei "geheilt-mit-Beleg": konkreten Beleg nennen)
  - Probe: "<konkrete Situation aus der Domain des Users>" → <Memory greift klar / Memory zu vage / nicht anwendbar>
    (bei "Memory zu vage": Schaerfungs-Vorschlag in einer Zeile)

## Hygiene (max 5)
- **<Type>**: <File> — <Aktion>

## Cross-System-Coverage (max 2)
- **<File>** [<Status: Solo / Tot-Doppelt>]: <konkrete Aktion — Hochzug nach CLAUDE.md / Pointer-Reduktion / Cross-Ref im Index>
(zusaetzlich Zaehler in 1 Zeile: "Coverage-Verteilung: X Always-On-Doppel, Y Skill-Durchgesetzt, Z Solo, W Tot-Doppelt")

## Promotion-Kandidaten (max 3)
- **<Cluster-Name>**: <N Episoden>, Sessions: <N>, Confidence: <hoch/mittel/niedrig>
  - Beleg-Episoden: <pfad1>, <pfad2>, ...
  - Vorschlag: neue Memory `<type>_<slug>.md` mit Why "<destilliert>"

## Denkfehler-Cluster (max 2)
- **<Wurzel-Typ>**: <N Treffer> ueber <M Sessions> — Beleg-Episoden: <pfad1>, <pfad2>, ...
  - Vorschlag: <geschaerfte/neue feedback-Memory / CLAUDE.md-Hochzug / Hook> — eine Stufe
(weglassen wenn kein Wurzel-Typ die Schwelle ≥3x / ≥2 Sessions erreicht)

## Demotion-Kandidaten (max 2)
- **<File>**: 2x in Folge "Memory zu vage" in Achse-4-Probing
  - Vorschlag: zerlegen — Why als Episode `<pfad>` erhalten, Memory loeschen, Index-Eintrag entfernen

## Episodic-Cleanup (silent ausser bei Loeschungen)
<N Episoden geloescht (>90 Tage, nicht promoted)> ODER weglassen wenn 0

## Empfehlung
<1-2 Saetze: groesster Hebel zuerst. Default: Heilungen-Bestaetigung > Konsolidierung > Meta-Patterns > Stale > Anti > Hygiene > Cross-System.>

---
Sag "Setze Punkt N um", "Setze Empfehlung um" — oder "verwerfen".
```

## Schritt 4: Audit-History schreiben (am Ende jedes abgeschlossenen Audits)

Nach Output-Anzeige UND nachdem der User einen Abschluss-Trigger gesendet hat (Definition siehe WICHTIG unten; gilt fuer `apply` wie `dry-run`): schreibe `CLAUDE_HOME/memory/audits/YYYY-MM-DD.md` (heutiges Datum aus `currentDate`-Kontext).

Format:

```yaml
---
date: YYYY-MM-DD
type: audit
memory_count: N
episode_count: N        # neu: Anzahl Episoden im Sammelbecken zum Zeitpunkt des Audits
promoted_episodes: []   # neu: Liste Episode-Pfade die diesen Audit zur Memory wurden
demoted_memories: []    # neu: Liste Memory-Pfade die diesen Audit zerlegt wurden
verdict: <Eine-Zeilen-Verdikt>
---

## Befund

<kompakter Befund — die Sektionen aus dem Output kopiert, max 50 Zeilen>

## User-Entscheidungen

- **Punkt 1** (<Achse>): <Aktion> — Status: <umgesetzt / abgelehnt / verschoben>. Why (falls geaeussert): <kurz>
- ...

## Offene Items fuer naechstes Audit

- <was wurde verschoben oder neu aufgemacht>
(oder: "keine offenen Items")

## Anti-Memory-Tracking

- <File>: <Aktion vom heutigen Audit, z.B. "geschaerft", "Hook geplant", "CLAUDE.md hochgezogen">
(damit naechster Audit pruefen kann ob Heilung greift)
```

**WICHTIG**: History-File NUR schreiben wenn der User in derselben Antwort einen klaren Abschluss-Trigger gesendet hat: "Setze Punkt N um", "Setze Empfehlung um", "fertig", "genug", "passt", "Schluss" — oder "verwerfen". Bei "verwerfen" wird die History TROTZDEM geschrieben, alle Punkte mit Status "abgelehnt (pauschal verworfen)" — nur so kann das Doppelt-Vorschlag-Verbot beim naechsten Audit greifen. Bei Themen-Wechsel ohne Abschluss-Trigger NICHT schreiben — sonst verfaelscht das die Historie. (Auditor kann keine Zeit messen, deshalb nur explizite Trigger.)

## Schritt 5: Auto-Commit (Pflicht-Schritt am Ende)

Nach Schreiben der Audit-History UND nach allen User-Bestaetigungen die Memory-Files veraendert haben:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/memory-auto-commit.sh" "audit-YYYY-MM-DD" <pfad> <pfad> ...
```

**Die Pfade sind Pflicht und muessen aufgezaehlt werden** — jede Datei, die DIESER Audit-Lauf angefasst hat, keine andere. Der Helper ordnet sie den drei Repos (`memory/`, `episodes/`, `projects/`) selbst zu und committet in jedem nur die genannten. Pfade duerfen relativ zu `CLAUDE_HOME` stehen.

Das Datum konkret einsetzen (aus `currentDate`-Kontext), NICHT als Shell-Variable uebergeben. Silent wenn nichts zu committen, sonst Hash-Output. Das macht Memory-Evolution diff-bar (`git log -p`) und liefert Backup + Rollback fuer den Fall dass eine Promotion oder Demotion sich spaeter als falsch erweist.

**Warum explizite Pfade:** Der Helper machte frueher `git add -A` in allen drei Repos. Das `projects`-Repo umfasst viele Workspaces — ein Audit-Commit zog dort regelmaessig fremde, uncommittete Arbeit paralleler Sessions mit ein, also genau den Verstoss, den der Audit verhindern soll. Gegenprobe dauerhaft unter `tests/memory-auto-commit.test.sh` (inkl. Sabotage-Probe).

Ohne Pfade committet der Helper nur einen bereits gefuellten Index und meldet sonst laut, dass nichts passiert ist — er staged nie von sich aus.

Wenn `apply` als Argument: nach Befund nummerierte Aktions-Liste **aller** vorgeschlagenen Aenderungen, dann auf User-Auswahl warten. NICHT autonom umsetzen — Memory-Edits sind irreversibel-im-Sinne dass kuratiertes Wissen verloren gehen kann.

## Wichtige Regeln fuer dich (den Auditor)

- **NIEMALS** Probleme erfinden, wenn das System gesund ist. "Score 5/5, keine Aktionen" ist valides Ergebnis.
- **NIEMALS** Memory-Inhalt vollstaendig zitieren — nur Pfad + 1-Zeilen-Hook.
- **NIEMALS** ohne explizite User-Bestaetigung Memories loeschen, mergen oder umbenennen. Auch im `apply`-Modus: erst Liste, dann Auswahl.
- **NIEMALS** Anti-Memories als Schaden des Users formulieren — Anti-Memories sind ein Signal dass die Memory-Formulierung nicht greift, nicht dass der User unfaehig ist.
- **NIEMALS** mehr als 3 Konsolidierungs- oder Meta-Pattern-Vorschlaege pro Audit. Wenn mehr da: priorisieren, Rest in "naechstes Audit"-Hinweis.
- **NIEMALS** mehr als 2 Cross-System-Aktionen pro Audit. Aktions-Muedigkeit vermeiden.
- **NIEMALS** Cross-System-Match nur auf Wort-Ebene. Pattern muss inhaltlich uebereinstimmen (Why-Match), nicht nur Vokabel.
- **IMMER** konkrete Datei-Pfade (relativ zu `CLAUDE_HOME/`) und konkrete neue Memory-Namen vorschlagen, keine vagen "irgendwie zusammenfassen".
- **IMMER** Stale-Mathematik nachpruefen: heutiges Datum aus `currentDate`-Kontext nehmen, NICHT `today` halluzinieren.
- **IMMER** den 110-Zeilen-Cap einhalten. Wenn drueber: streichen, Detail-Begruendung weglassen.
- **IMMER** den `Why`-Erhalt prinzipiell schuetzen — bei Konsolidierung muss das Why aus den Quellen ins Ziel uebernommen werden, sonst veraltet die neue Memory schneller als die alten.

## Wann diesen Command ausfuehren?

Empfohlen: alle 4-6 Wochen, oder wenn:

- Memory-Anzahl ueber 30 steigt
- Beim Schreiben einer neuen Memory das Gefuehl entsteht "das ueberlappt mit was"
- Nach groesseren Skill-/Tool-Aenderungen (Patterns koennten obsolet werden)
- Wenn ein Anti-Memory bemerkt wird (eine Regel die wiederholt gebrochen wurde)
