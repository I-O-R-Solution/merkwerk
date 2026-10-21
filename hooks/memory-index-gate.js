#!/usr/bin/env node
/*
 * memory-index-gate.js — PreToolUse (Write|Edit|MultiEdit)
 * Haelt den 150-Zeichen-Deckel je Eintragszeile in einer memory/MEMORY.md.
 * Gegenprobe: tests/memory-index-gate.test.sh
 *
 * ── WARUM DIESER HOOK EXISTIERT ──────────────────────────────────────────────
 *   Die Regel steht in docs/memory-protocol.md ("Index-Eintraege: max 150
 *   Zeichen, eine Zeile"). Als reiner Text hielt sie nicht: in einem System
 *   mit ~25 Index-Dateien lagen nach zwei Monaten 222 Zeilen ueber dem Deckel,
 *   die laengste 1.638 Zeichen, und eine Handkuerzung stand vier Wochen spaeter
 *   ueber ihrem Ausgangswert. Der Ausloeser ist deterministisch erkennbar ->
 *   Gate statt dritter Textstufe (Eskalationsleiter, docs/memory-protocol.md).
 *
 *   DER SCHADEN IST NICHT UNORDNUNG, SONDERN FALSCHE ANTWORTEN. Die MEMORY.md
 *   ist die einzige Sekundaerquelle, die unaufgefordert im Kontext landet.
 *   Solange eine Zeile kurz ist, ist sie ein Wegweiser und man schlaegt die
 *   Notiz auf. Wird sie zum Absatz, liest sie sich wie die Notiz - und niemand
 *   pflegt sie nach. Belegt: zwei Falschaussagen aus Index-Zeilen, die einen
 *   Zustand behaupteten ("offen", "ueberholt"), den die Notiz laengst widerlegte.
 *
 * ── GARANTIE-REGISTER ──────────────────────────────────────────────────────
 * ERKENNEND fuer (per Gegenprobe belegt, memory-index-gate.test.sh):
 *   - Write mit einer NEUEN Eintragszeile ueber dem Deckel
 *   - Edit / MultiEdit, deren new_string eine solche Zeile enthaelt
 *   - beide Pfadtrenner (Windows und POSIX), Cross- und Projekt-Schicht
 *   - Zeichen, nicht Bytes: Umlaute und Emoji zaehlen einmal, nicht zwei- oder
 *     viermal (in Bash haette ${#var} hier falsch gezaehlt)
 *
 * OFFEN gegen (bewusst, wer mehr behauptet, zitiert falsch):
 *   - Schreibwege ausserhalb der Werkzeuge Write/Edit/MultiEdit, also jedes
 *     `cat > MEMORY.md`, `sed -i`, `python`. Absicht: der Bash-Pfad gehoert
 *     dem safety-guard, und ein zweites Gate dort waere ein Dauerfehlalarm.
 *     Am Commit gedeckt: `git-hooks/pre-commit` + `git-hooks/memory-index-check.js`
 *     pruefen jede neue Index-Zeile, egal mit welchem Werkzeug geschrieben.
 *   - Wachstum des Index NACH dem Schreiben (kein Nachtraegliches Schrumpfen)
 *   - Wachstum in der SUMME bei lauter kurzen Zeilen. Der Deckel ist je Zeile,
 *     nicht je Datei. Die Datei-Summe ist Sache von /context-budget.
 *   - Inhaltliche Drift zwischen Index und Notiz. Die Statuswort-Warnung unten
 *     ist ein billiger Stellvertreter, kein Beweis, und deshalb nur Warnung.
 *
 * ── ZWEI DESIGN-ENTSCHEIDUNGEN, DIE FEHLALARME VERHINDERN ──────────────────
 * 1) Geprueft werden NUR NEUE oder GEAENDERTE Zeilen, nie der Bestand. Bei
 *    Write wird gegen die Datei auf der Platte verglichen, bei Edit zaehlt der
 *    new_string. Ohne das blockte der Waechter am ersten Tag jeden Index-Schreib
 *    in jedem Arbeitsordner - und ein Waechter, der dauernd im Weg steht, wird
 *    abgeschaltet.
 * 2) Der Deckel steht an EINER Stelle (LIMIT unten, Marker GATE_LIMIT). Die
 *    Gegenprobe liest ihn aus dieser Datei statt eine eigene Zahl zu verdrahten.
 */

'use strict';

const fs = require('fs');
const path = require('path');

/* GATE_LIMIT — einzige Stelle. Die Gegenprobe greppt diese Zeile. */
const LIMIT = 150;

/* Billiger Stellvertreter gegen Index-Drift: Woerter, die einen LAUFZUSTAND
 * behaupten. Ein Zustand veraltet, sobald jemand die Sache anfasst, und wer
 * mergt hat keinen Grund, die Notiz aufzuschlagen. Eine dauerhafte Falle
 * ("activeElement ist im change-Handler schon BODY") veraltet nicht.
 * Laufzustaende gehoeren in eine Status-Datei des Projekts, die ERSETZT statt
 * anhaengt. Diese Liste ist eine AUFZAEHLUNG und damit per Definition
 * unvollstaendig - deshalb nur Warnung, niemals Block. */
const STATUS_WOERTER = [
  'ueberholt', 'überholt', 'historisch', 'erledigt', 'abgeschlossen',
  'offen', 'steht aus', 'faellig', 'fällig', 'live',
  'gemerged', 'gemergt', 'gepusht', 'committet', 'deployt', 'fertig',
];

const EINTRAG = /^\s*[-*]\s*\[/;

function readStdin() {
  return new Promise((resolve) => {
    let d = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (c) => { d += c; });
    process.stdin.on('end', () => resolve(d));
  });
}

/* Nur Dateien, die wirklich ein Memory-Index sind. trigger_map.md und
 * memory/audits/* heissen nicht MEMORY.md und sind damit automatisch aussen. */
function istIndexDatei(p) {
  if (typeof p !== 'string' || !p) return false;
  /* Doppelte Trenner zusammenziehen: auf Windows entstehen sie real durch
   * gemischte Schreibweisen und path.join-Reste (`C:\a\\b/c`). Ohne das Falten
   * lief `//memory//MEMORY.md` am Deckel vorbei — gefangen von Fall A5 der
   * Gegenprobe. */
  const norm = p.replace(/\\/g, '/').replace(/\/{2,}/g, '/').toLowerCase();
  return norm.endsWith('/memory/memory.md') || norm === 'memory/memory.md';
}

function zeilen(text) {
  if (typeof text !== 'string') return [];
  return text.split('\n').map((z) => z.replace(/\r$/, ''));
}

/* Kandidaten sind die Zeilen, die dieser Aufruf NEU in die Datei bringt. */
function neueZeilen(tool, input) {
  if (tool === 'Write') {
    const neu = zeilen(input.content);
    let bestand = new Set();
    try {
      if (fs.existsSync(input.file_path)) {
        bestand = new Set(zeilen(fs.readFileSync(input.file_path, 'utf8')));
      }
    } catch (err) {
      /* Platte nicht lesbar: dann ist JEDE Zeile ein Kandidat. Lieber ein
       * Fehlalarm als eine stille Luecke - und die Ursache wird genannt. */
      process.stderr.write(
        `[memory-index-gate] Bestand nicht lesbar (${err.message}) — pruefe alle Zeilen\n`
      );
    }
    return neu.filter((z) => !bestand.has(z));
  }
  if (tool === 'Edit') return zeilen(input.new_string);
  if (tool === 'MultiEdit') {
    const edits = Array.isArray(input.edits) ? input.edits : [];
    return edits.flatMap((e) => zeilen(e && e.new_string));
  }
  return [];
}

function statusTreffer(zeile) {
  const klein = zeile.toLowerCase();
  return STATUS_WOERTER.filter((w) => klein.includes(w));
}

(async () => {
  try {
    if ((process.env.MEMORY_INDEX_GATE || '').toLowerCase() === 'off') {
      process.stderr.write('[memory-index-gate] ABGESCHALTET per MEMORY_INDEX_GATE=off\n');
      process.exit(0);
    }

    const raw = await readStdin();
    if (!raw.trim()) process.exit(0);

    let payload;
    try {
      payload = JSON.parse(raw);
    } catch {
      process.exit(0);
    }

    const tool = payload.tool_name || '';
    const input = payload.tool_input || {};
    if (!['Write', 'Edit', 'MultiEdit'].includes(tool)) process.exit(0);
    if (!istIndexDatei(input.file_path)) process.exit(0);

    const kandidaten = neueZeilen(tool, input).filter((z) => EINTRAG.test(z));

    const zuLang = [];
    const mitStatus = [];
    for (const z of kandidaten) {
      const roh = z.replace(/\s+$/, '');
      if ([...roh].length > LIMIT) zuLang.push(roh);
      else {
        const t = statusTreffer(roh);
        if (t.length) mitStatus.push({ zeile: roh, woerter: t });
      }
    }

    if (zuLang.length) {
      const datei = path.basename(path.dirname(input.file_path)) + '/MEMORY.md';
      let msg = `[memory-index-gate] BLOCKIERT: ${zuLang.length} neue Index-Zeile(n) `
        + `ueber dem Deckel von ${LIMIT} Zeichen (${datei}).\n\n`;
      for (const z of zuLang.slice(0, 3)) {
        msg += `  ${[...z].length} Zeichen: ${z.slice(0, 110)}…\n`;
      }
      if (zuLang.length > 3) msg += `  (und ${zuLang.length - 3} weitere)\n`;
      msg += '\nDer Index ist ein Wegweiser, keine zweite Notiz. Was hier nicht '
        + 'hineinpasst,\ngehoert in die Zieldatei — der Text steht dort in der Regel schon.\n'
        + 'Ein Laufzustand (offen, erledigt, live) gehoert in eine Status-Datei des Projekts,\n'
        + 'die ihn ERSETZT statt ihn anzuhaengen. Im Index bleibt Thema + eine dauerhafte Falle.\n'
        + 'Regel: docs/memory-protocol.md (Index-Schema). Grund: hooks/memory-index-gate.js Kopf.\n';
      process.stderr.write(msg);
      process.exit(2);
    }

    if (mitStatus.length) {
      let msg = '[memory-index-gate] Hinweis (kein Block): neue Index-Zeile(n) nennen einen '
        + 'Laufzustand.\n';
      for (const m of mitStatus.slice(0, 3)) {
        msg += `  ${m.woerter.join(', ')} — ${m.zeile.slice(0, 90)}\n`;
      }
      msg += '  Zustaende veralten unbemerkt. Sie gehoeren in eine Status-Datei des Projekts, '
        + 'der Index traegt dauerhafte Fallen.\n';
      process.stderr.write(msg);
      process.stdout.write(msg);
    }

    process.exit(0);
  } catch (err) {
    /* Fail-open, aber LAUT. Ein stiller Ausfall ist die gefaehrlichste Form. */
    process.stderr.write(`[memory-index-gate] AUSFALL, nicht geprueft: ${err.message}\n`);
    process.exit(0);
  }
})();
