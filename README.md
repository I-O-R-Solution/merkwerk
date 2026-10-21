# merkwerk

Memory-Engine fuer [Claude Code](https://code.claude.com): Claude merkt sich ueber Sessions hinweg, was es gelernt hat, und das System prueft sich selbst, ob das Gelernte noch stimmt und noch greift.

*English: a two-tier memory engine for Claude Code (curated memories + per-session episodes), with trigger routing, a self-auditing loop (promotion/demotion), a hard cap on index lines and path-exact auto-commits into three git repos. All prompts and docs are in German.*

## Engine und Bestand

Dieses Repo ist die **Engine**: Hooks, Skill, Commands, Regelwerk, Vorlagen. Was Claude sich merkt, ist der **Bestand** und liegt getrennt davon unter `~/.claude/` in drei eigenen Git-Repos:

| Repo | Inhalt | Remote |
|---|---|---|
| `~/.claude/memory/` | Cross-Workspace-Memories, Index `MEMORY.md`, `trigger_map.md`, Audit-Historie | privat, optional |
| `~/.claude/episodes/` | eine Kurz-Episode pro Session, `_promoted.txt` | privat, optional |
| `~/.claude/projects/` | nur `*/memory/**` der Workspaces (Whitelist) | **nie** — Projekt-Memories tragen Interna |

## Installation (3 Schritte)

Voraussetzungen: Claude Code, `git`, `node`, `bash` (unter Windows: Git Bash), `python` oder `jq`.

```bash
# 1. Plugin aus GitHub installieren
claude plugin marketplace add olisconsulting-cloud/merkwerk
claude plugin install merkwerk@merkwerk

# 2. Bestand anlegen (drei Repos, Vorlagen, Index-Deckel am Commit)
bash ~/.claude/plugins/cache/merkwerk/merkwerk/*/install.sh

# 3. Claude Code neu starten. Der Healthcheck meldet sich nur, wenn etwas fehlt.
```

Fuer Entwickler, die am Plugin arbeiten: Repo klonen, `claude plugin marketplace add /pfad/zum/klon`, dann `claude plugin install merkwerk@merkwerk` — das Plugin laeuft direkt aus dem Klon, ohne Kopie.

Danach in die eigene `~/.claude/CLAUDE.md` eine Zeile: *"Memory-Regeln: `<plugin-pfad>/docs/memory-protocol.md` (bei Bedarf lesen, nicht importieren)."*

## Was die Engine tut

**Beim Session-Start** (`SessionStart`)
- `memory-system-healthcheck.sh` — prueft Bestand, Interpreter, `trigger_map`, tote Promoted-Eintraege, Commit-Drift, Index-Deckel. Silent, wenn alles stimmt.
- `memory-audit-reminder.sh` — meldet, wenn der Audit faellig ist (>35 Tage oder >30 neue Episoden).

**Bei jedem Prompt** (`UserPromptSubmit`)
- `memory-trigger-router.sh` — matcht den Prompt gegen `trigger_map.md` und blendet passende Memories ein. Max 3 pro Prompt, 30-Minuten-Fenster pro Memory.

**Bei jedem Read / Write** (`PostToolUse`, `PreToolUse`)
- `memory-read-stamp.sh` — stempelt `last_used`, wenn eine Memory gelesen wird. Burst-Filter: Massenlesen zaehlt nicht.
- `memory-index-gate.js` — blockt neue Index-Zeilen ueber 150 Zeichen. Der Index ist ein Wegweiser, keine zweite Notiz.

**Am Session-Ende** (`/merkwerk:ende` oder "Feierabend")
- Memory-Check → Episode schreiben → Wurzel-Typ-Fruehwarnung → eigene Schreibpfade committen.

**Alle 4-6 Wochen** (`/merkwerk:memory-audit [dry-run|apply]`)
- Acht Pruef-Achsen: Konsolidierung, Meta-Patterns, Stale, Anti-Memories, Hygiene, Cross-System-Coverage, Promotion (Episoden → Memory), Demotion (Memory → Episode). Befund + nummerierte Aktionen, nichts passiert ohne Bestaetigung.

**Am Commit** (`git-hooks/pre-commit`, je Memory-Repo per `core.hooksPath`)
- Secret-Dateien blocken, Index-Deckel auch fuer Schreibwege ausserhalb von Claude (Bash, Python, Editor).

## Grundsaetze

- **Lazy Load.** Nur die `MEMORY.md`-Indizes liegen immer im Kontext; eine Memory wird erst gelesen, wenn ihr Haken passt.
- **Why-Pflicht.** Jede Regel traegt den Vorfall, aus dem sie stammt. Ohne Why veraltet sie.
- **Volumen nur im Episodic.** Episoden sind billig und verfallen nach 90 Tagen, Memories sind verdichtet und bleiben.
- **Gates statt dritter Textstufe.** Was deterministisch erkennbar ist, prueft ein Hook. Was nicht, bekommt hoechstens zwei Textregeln und dann eine Zweitmessung.
- **Explizite Pfade.** Der Auto-Commit kennt kein `git add -A` — an den Repos arbeiten oft mehrere Sessions gleichzeitig.

Das vollstaendige Regelwerk: [docs/memory-protocol.md](docs/memory-protocol.md).

## Eigene Erweiterungen

- `~/.claude/session-ende.local.md` — eigene Zusatzschritte fuer das Session-Ende (z.B. ein Projekt-Tagebuch). Wird vom Skill gelesen, wenn vorhanden.
- `~/.claude/memory/trigger_map.md` — eigene Trigger. Mit `# eval:`-Zeilen prueft der Healthcheck, dass das Pattern wirklich trifft.

## Tests

```bash
for t in tests/*.test.sh; do bash "$t"; done
```

Jede Suite enthaelt Sabotage-Proben: das geprueften Skript wird absichtlich kaputtgemacht, und die Suite muss rot werden. Eine Suite, die am kaputten Skript gruen bleibt, misst nichts.

## Lizenz

MIT
