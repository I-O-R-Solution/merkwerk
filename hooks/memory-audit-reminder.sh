#!/bin/bash
# memory-audit-reminder.sh — SessionStart hook
# Erinnert beim Session-Start dass /memory-audit faellig ist.
# Faellig = letzter Audit > 35 Tage ODER Episode-Count > 30.
#
# Verhalten:
# - Cross-Workspace aktiv (kein cwd-Filter)
# - Liest letzten Audit aus ~/.claude/memory/audits/*.md (Datum aus Filename)
# - Zaehlt Episoden-Files in ~/.claude/episodes/ (Format-Filter)
# - Output silent ausser bei Faelligkeit
# - Advisory only - kein Block

set -u

CLAUDE_HOME="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
AUDITS_DIR="${CLAUDE_HOME}/memory/audits"
EPISODES_DIR="${CLAUDE_HOME}/episodes"
DAYS_THRESHOLD=35
EPISODE_COUNT_THRESHOLD=30

days_since_audit=999
episode_count=0
last_audit_file=""

# 1. Letzten Audit ermitteln
if [ -d "$AUDITS_DIR" ]; then
  last_audit_file=$(find "$AUDITS_DIR" -maxdepth 1 -type f -name '????-??-??.md' 2>/dev/null | sort -r | head -1)
  if [ -n "$last_audit_file" ]; then
    audit_date=$(basename "$last_audit_file" .md)
    audit_epoch=$(date -d "$audit_date" +%s 2>/dev/null || echo 0)
    now_epoch=$(date +%s)
    if [ "$audit_epoch" -gt 0 ]; then
      days_since_audit=$(( (now_epoch - audit_epoch) / 86400 ))
    fi
  fi
fi

# 2. Episoden zaehlen — NUR die seit dem letzten Audit (Fix 2026-06-13:
#    Gesamt-Zaehlung machte den Reminder ab 30 Lebenszeit-Episoden dauerfaellig)
if [ -d "$EPISODES_DIR" ]; then
  if [ -n "$last_audit_file" ]; then
    episode_count=$(find "$EPISODES_DIR" -mindepth 1 -maxdepth 3 -type f -name '????-??-??_*.md' -newer "$last_audit_file" 2>/dev/null | wc -l | tr -d ' ')
  else
    episode_count=$(find "$EPISODES_DIR" -mindepth 1 -maxdepth 3 -type f -name '????-??-??_*.md' 2>/dev/null | wc -l | tr -d ' ')
  fi
fi

# 3. Faelligkeit pruefen
fire_audit_age=0
fire_episode_count=0
[ "$days_since_audit" -ge "$DAYS_THRESHOLD" ] && fire_audit_age=1
[ "$episode_count" -ge "$EPISODE_COUNT_THRESHOLD" ] && fire_episode_count=1

[ "$fire_audit_age" -eq 0 ] && [ "$fire_episode_count" -eq 0 ] && exit 0

# 4. Reminder ausgeben
echo ""
echo "Memory-Audit-Reminder:"
if [ "$fire_audit_age" -eq 1 ]; then
  if [ -n "$last_audit_file" ]; then
    echo "  - Letzter Audit war vor ${days_since_audit} Tagen (Schwelle: ${DAYS_THRESHOLD} Tage)"
  else
    echo "  - Noch nie ein Audit durchgefuehrt"
  fi
fi
if [ "$fire_episode_count" -eq 1 ]; then
  echo "  - ${episode_count} neue Episoden seit dem letzten Audit (Schwelle: ${EPISODE_COUNT_THRESHOLD})"
fi
echo "  (verglichen mit Audit: ${audit_date:-keiner})"
echo "  -> /merkwerk:memory-audit waere faellig"
echo ""

exit 0
