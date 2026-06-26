#!/usr/bin/env bash

export PATH="/opt/homebrew/bin:/usr/local/bin:/bin:/usr/bin:/usr/sbin:/sbin"

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
LEFT_FILE="$CONFIG_DIR/clock_left_tz"
LABEL_BAND_Y="${CLOCK_LABEL_BAND_Y:-70}"

mouse_y() {
  CLANG_MODULE_CACHE_PATH="${TMPDIR:-/private/tmp}/sketchybar-clang-cache" \
    swift -e 'import AppKit; let p=NSEvent.mouseLocation; let s=NSScreen.screens.first { $0.frame.contains(p) }; print(Int(p.y - (s?.frame.minY ?? 0)))' 2>/dev/null
}

clicked_label_band() {
  local y

  y="$(mouse_y)"
  case "$y" in
    ''|0|*[!0-9]*) return 1 ;;
  esac

  # The timezone/WATCH label is the lower text in this bottom bar cell.
  # Keep that region menu-only so it never starts, stops, or resets the timer.
  [ "$y" -le "$LABEL_BAND_Y" ]
}

if [ -f "$LEFT_FILE" ]; then
  IFS='|' read -r LEFT_MODE _ < "$LEFT_FILE"
fi

if [ "$LEFT_MODE" = "STOPWATCH" ]; then
  if clicked_label_band; then
    sketchybar --set clock.left popup.drawing=toggle
  else
    "$CONFIG_DIR/plugins/stopwatch.sh" click
  fi
else
  sketchybar --set clock.left popup.drawing=toggle
fi
