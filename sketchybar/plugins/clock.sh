#!/usr/bin/env bash

export PATH="/opt/homebrew/bin:/usr/local/bin:/bin:/usr/bin:/usr/sbin:/sbin"

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"

TEXT=0xffd6f3f0
MUTED=0xff82a9ad
CYAN=0xff7bdff2
BLUE=0xff89b4fa

PRIMARY_TZ="America/Phoenix"
LEFT_FILE="$CONFIG_DIR/clock_left_tz"

[ -f "$LEFT_FILE" ] || echo "America/New_York|ET|$BLUE" > "$LEFT_FILE"

fmt_time() {
  TZ="$1" date '+%-I:%M %p'
}

fmt_date() {
  TZ="$1" date '+%a  %b %-d' | tr '[:lower:]' '[:upper:]'
}

LEFT_SPEC="$(cat "$LEFT_FILE")"
IFS='|' read -r LEFT_TZ LEFT_LABEL LEFT_COLOR <<< "$LEFT_SPEC"

PRIMARY_DATE="$(fmt_date "$PRIMARY_TZ")"
PRIMARY_TIME="$(fmt_time "$PRIMARY_TZ")"
LEFT_TIME="$(fmt_time "$LEFT_TZ")"

sketchybar --set clock \
  icon="$PRIMARY_DATE" \
  label="$PRIMARY_TIME" \
  icon.color=$CYAN \
  label.color=$TEXT

sketchybar --set clock.left \
  icon="$LEFT_LABEL ▾" \
  label="$LEFT_TIME" \
  icon.color="$LEFT_COLOR" \
  label.color=$TEXT
