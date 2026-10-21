#!/usr/bin/env node
/**
 * Index-Deckel am Commit.
 *
 * Liest `git diff --cached -U0` von stdin und blockt, wenn eine NEUE oder
 * GEAENDERTE Eintragszeile in einer Memory-Index-Datei (`MEMORY.md`) mehr als
 * 150 Zeichen hat. Altbestand blockt nicht: geprueft wird nur, was dieser
 * Commit hinzufuegt.
 *
 * Warum am Commit und nicht nur am Werkzeug: `hooks/memory-index-gate.js`
 * prueft Write/Edit/MultiEdit. Gemessen kamen ALLE Ueberlaenge-Zeilen eines
 * Monats ueber Bash (python, Heredoc, sed). Der Commit ist der Punkt, an dem
 * jeder Schreibweg vorbeikommt, egal mit welchem Werkzeug geschrieben wurde.
 *
 * Zeichen, nicht Bytes: Umlaute und Gedankenstriche zaehlen einmal.
 * Exit 0 = ok, Exit 1 = blockiert (Begruendung auf stdout).
 */
const LIMIT = 150;
const EINTRAG = /^\s*[-*]\s*\[/;

let d = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { d += c; });
process.stdin.on('end', () => {
  const zuLang = [];
  let datei = '';
  for (const roh of d.split('\n')) {
    const z = roh.replace(/\r$/, '');
    if (z.startsWith('+++ ')) { datei = z.replace(/^\+\+\+ (b\/)?/, ''); continue; }
    if (!z.startsWith('+') || z.startsWith('+++')) continue;
    const inhalt = z.slice(1);
    if (!EINTRAG.test(inhalt)) continue;
    const n = [...inhalt].length;
    if (n > LIMIT) zuLang.push({ datei, n, inhalt });
  }
  if (!zuLang.length) process.exit(0);
  console.log('');
  console.log(`BLOCKED: ${zuLang.length} neue Index-Zeile(n) ueber dem Deckel von ${LIMIT} Zeichen:`);
  console.log('');
  for (const t of zuLang.slice(0, 5)) {
    console.log(`  - ${t.datei} (${t.n} Zeichen): ${t.inhalt.slice(0, 90)}...`);
  }
  if (zuLang.length > 5) console.log(`  (und ${zuLang.length - 5} weitere)`);
  console.log('');
  console.log('Der Index wird jede Sitzung geladen: eine Zeile ist ein Haken, kein Inhalt.');
  console.log('Details gehoeren in die Notiz selbst (siehe docs/memory-protocol.md).');
  console.log('');
  console.log('Aktionen:');
  console.log('  - Zeile kuerzen, Detail in die Notiz-Datei verschieben, erneut stagen');
  console.log('  - Notfall-Bypass:  git commit --no-verify');
  console.log('');
  process.exit(1);
});
