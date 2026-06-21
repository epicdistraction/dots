#!/usr/bin/env bash

export PATH="/opt/homebrew/bin:/usr/local/bin:/bin:/usr/bin:/usr/sbin:/sbin"

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"

TZ_NAME="$1"
TZ_LABEL="$2"
TZ_COLOR="$3"

if [ -z "$TZ_NAME" ] || [ -z "$TZ_LABEL" ] || [ -z "$TZ_COLOR" ]; then
  exit 1
fi

echo "$TZ_NAME|$TZ_LABEL|$TZ_COLOR" > "$CONFIG_DIR/clock_left_tz"

"$CONFIG_DIR/plugins/clock.sh"

sketchybar --set clock.left popup.drawing=off
sketchybar --trigger clock_update
