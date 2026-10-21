# Trigger Map — Memory-Auto-Routing

Single Source of Truth fuer Trigger→Memory-Mapping. Wird vom Hook `memory-trigger-router.sh` bei jedem `UserPromptSubmit` gelesen.

**Format pro Zeile**: `<regex_pattern> ||| <memory_pfad> ||| <kurzer_anlass>`

- **Spaltentrenner**: ` ||| ` (drei Pipes mit Space-Padding) — eindeutig, weil das in Regex-Alternationen nie vorkommt
- `regex_pattern` — Perl-Regex via `grep -Pqi` (Word-Boundaries `\b` als Idiom). Erwartet `grep` mit `-P`-Support (Standard auf Linux/macOS/Git-Bash; auf minimalen Containern wie Alpine fehlt PCRE). Umlaute doppelt abdecken: `(ae|ä)` statt `[aä]`
- `memory_pfad` — relativ zu `CLAUDE_HOME` (z.B. `memory/feedback_x.md` oder `projects/<slug>/memory/feedback_y.md`)
- `kurzer_anlass` — eine Zeile, was die Memory bei dem Trigger sagt
- Optional direkt unter einer Mapping-Zeile: `# eval: <Soll-Prompt>` — der Healthcheck prueft beim Session-Start, dass das Pattern diesen Prompt trifft (faengt False Negatives wie "committe" vs `\bcommit\b`)

**Verhalten** (siehe Hook):

- Max 3 Treffer pro Prompt (Anti-Spam)
- Eine Memory triggert max 1× pro 30-Min-Fenster (State in `CLAUDE_HOME/.cache/trigger_history.json`)
- Bei Match: `last_used: <today>` wird automatisch in der Memory-Frontmatter gestempelt

**Wartung**: Bei jedem `/merkwerk:memory-audit` pruefen, ob neue Solo-Memories hier fehlen oder ob bestehende Patterns False-Positives produzieren.

---

## Mappings

```
(\bcommit|\bpush|\bstaged\b) ||| memory/feedback_beispiel_git.md ||| Beispiel-Eintrag: Zeile loeschen oder auf eine eigene Memory zeigen lassen
# eval: bitte committe die datei
```
