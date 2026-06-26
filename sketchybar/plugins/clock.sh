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

fmt_day() {
  TZ="$1" date '+%a' | tr '[:lower:]' '[:upper:]'
}

fmt_month_day() {
  TZ="$1" date '+%b %-d' | tr '[:lower:]' '[:upper:]'
}

LEFT_SPEC="$(cat "$LEFT_FILE")"
IFS='|' read -r LEFT_TZ LEFT_LABEL LEFT_COLOR <<< "$LEFT_SPEC"

PRIMARY_DAY="$(fmt_day "$PRIMARY_TZ")"
PRIMARY_DATE="$(fmt_month_day "$PRIMARY_TZ")"
PRIMARY_TIME="$(fmt_time "$PRIMARY_TZ")"

sketchybar --set clock \
  label="$PRIMARY_TIME" \
  label.color=$TEXT

sketchybar --set clock.day \
  label="$PRIMARY_DAY" \
  label.color=$CYAN \
  --set clock.month \
  label="$PRIMARY_DATE" \
  label.color=$CYAN

if [ "$LEFT_TZ" = "STOPWATCH" ]; then
  "$CONFIG_DIR/plugins/stopwatch.sh" refresh
else
  LEFT_TIME="$(fmt_time "$LEFT_TZ")"

  sketchybar --set clock.left \
    label="$LEFT_TIME" \
    label.color=$TEXT

  sketchybar --set clock.left.tz \
    label="$LEFT_LABEL ▾" \
    label.color="$LEFT_COLOR"

  "$CONFIG_DIR/plugins/stopwatch.sh" refresh
fi
