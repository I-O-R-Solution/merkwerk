# Episodic Memory Layer

Beobachtungs-Sammelbecken zwischen Session-Erfahrung und kuratierter Memory.

## Wer schreibt hier

Der Skill `merkwerk:session-ende` schreibt bei jedem Session-Ende eine Episode nach `YYYY-MM/YYYY-MM-DD_<session-id>.md`. Format: 5 Pflicht-Abschnitte (Was passierte, Was gelernt, Reibung/Wurzel, Offen, Workspace), kein Frontmatter.

## Wer liest hier

`/merkwerk:memory-audit` Achse 7 (Promotion-Kandidaten) prueft beim Audit, ob Episoden-Cluster reif fuer Promotion zu echter Memory sind. Confidence-tiered + Session-Distance-Schutz. Achse 7b zaehlt Wurzel-Typen zu Denkfehler-Clustern.

## Verfall

Episoden ohne Promotion werden nach 90 Tagen hart geloescht (`hooks/episode-cleanup.sh`, laeuft im Audit-`apply`). Promoted Episoden ueberleben — die Liste lebt in `_promoted.txt`.

## Manuell anfassen?

Im Normalfall nicht. Ist Sammelbecken, kein Tagebuch. Wenn du was suchst, geh ueber den Audit oder `grep`.
