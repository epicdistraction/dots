#!/usr/bin/env bash

export PATH="/opt/homebrew/bin:/usr/local/bin:/bin:/usr/bin:/usr/sbin:/sbin"

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
STATE_FILE="$CONFIG_DIR/cache/stopwatch_state"
LEFT_FILE="$CONFIG_DIR/clock_left_tz"
TIME_ITEM="clock.left"
TZ_ITEM="clock.left.tz"
MENU_ITEM="clock.tz.stopwatch"
STOPWATCH_MODE="STOPWATCH"
STOPWATCH_LABEL="WATCH"

TEXT=0xffd6f3f0
MUTED=0xff82a9ad
GREEN=0xffa6e3a1

mkdir -p "$CONFIG_DIR/cache"

now() {
  date +%s
}

write_state() {
  printf '%s|%s|%s\n' "$1" "$2" "$3" > "$STATE_FILE"
}

is_uint() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

read_state() {
  STATUS=stopped
  ELAPSED=0
  STARTED_AT=0

  if [ -f "$STATE_FILE" ]; then
    IFS='|' read -r STATUS ELAPSED STARTED_AT < "$STATE_FILE"
  fi

  case "$STATUS" in
    running|stopped) ;;
    *) STATUS=stopped ;;
  esac

  is_uint "$ELAPSED" || ELAPSED=0
  is_uint "$STARTED_AT" || STARTED_AT=0
}

current_elapsed() {
  local delta

  if [ "$STATUS" = "running" ]; then
    delta=$(($(now) - STARTED_AT))
    [ "$delta" -lt 0 ] && delta=0
    printf '%s\n' $((ELAPSED + delta))
  else
    printf '%s\n' "$ELAPSED"
  fi
}

format_elapsed() {
  local total="$1"
  local hours=$((total / 3600))
  local minutes=$(((total % 3600) / 60))
  local seconds=$((total % 60))

  if [ "$hours" -gt 0 ]; then
    printf '%02d:%02d:%02d' "$hours" "$minutes" "$seconds"
  else
    printf '%02d:%02d' "$minutes" "$seconds"
  fi
}

is_stopwatch_selected() {
  local selected_mode

  if [ -f "$LEFT_FILE" ]; then
    IFS='|' read -r selected_mode _ < "$LEFT_FILE"
  fi

  [ "$selected_mode" = "$STOPWATCH_MODE" ]
}

display_color() {
  local elapsed="$1"

  if [ "$STATUS" = "running" ]; then
    printf '%s\n' "$GREEN"
  elif [ "$elapsed" -gt 0 ]; then
    printf '%s\n' "$TEXT"
  else
    printf '%s\n' "$MUTED"
  fi
}

mouse_geometry() {
  CLANG_MODULE_CACHE_PATH="${TMPDIR:-/private/tmp}/sketchybar-clang-cache" \
    swift -e 'import AppKit; let p=NSEvent.mouseLocation; let s=NSScreen.screens.first { $0.frame.contains(p) }; let minX = s?.frame.minX ?? 0; let width = s?.frame.width ?? 0; print("\(Int(p.x - minX))|\(Int(width))")' 2>/dev/null
}

clicked_menu_time() {
  local geometry x screen_width split_x right_offset

  geometry="$(mouse_geometry)"
  IFS='|' read -r x screen_width <<< "$geometry"

  right_offset="${STOPWATCH_MENU_TIME_RIGHT_OFFSET:-}"
  if is_uint "$right_offset" && is_uint "$screen_width" && [ "$screen_width" -gt "$right_offset" ]; then
    split_x=$((screen_width - right_offset))
  else
    split_x="${STOPWATCH_MENU_TIME_X_MIN:-}"
  fi

  is_uint "$split_x" && [ "$split_x" -gt 0 ] || return 1
  is_uint "$x" && [ "$x" -gt 0 ] || return 1

  # The popup row is one SketchyBar item. Clicks on "WATCH" promote only;
  # clicks on the time span control the stopwatch without changing promotion.
  [ "$x" -ge "$split_x" ]
}

sync_update_freqs() {
  local time_freq=5
  local menu_freq=0

  # The stopwatch keeps logical time from STARTED_AT, so hidden background
  # running does not need polling. When promoted, clock.left ticks once a
  # second; the popup entry ticks only while the dropdown is shown.
  if [ "$STATUS" = "running" ]; then
    menu_freq=1
    is_stopwatch_selected && time_freq=1
  fi

  sketchybar --set "$TIME_ITEM" update_freq="$time_freq" \
             --set "$MENU_ITEM" updates=when_shown update_freq="$menu_freq"
}

render() {
  local elapsed display color
  read_state

  elapsed="$(current_elapsed)"
  display="$(format_elapsed "$elapsed")"
  color="$(display_color "$elapsed")"

  sketchybar --set "$MENU_ITEM" \
    label="$STOPWATCH_LABEL $display" \
    label.color="$color"

  if is_stopwatch_selected; then
    sketchybar --set "$TIME_ITEM" \
      label="$display" \
      label.color="$color" \
      --set "$TZ_ITEM" \
      label="$STOPWATCH_LABEL ▾" \
      label.color="$GREEN"
  fi

  sync_update_freqs
}

promote() {
  printf '%s|%s|%s\n' "$STOPWATCH_MODE" "$STOPWATCH_LABEL" "$GREEN" > "$LEFT_FILE"

  sketchybar --set "$TIME_ITEM" popup.drawing=off
}

menu_click() {
  if clicked_menu_time; then
    case "${BUTTON:-left}" in
      right) reset ;;
      *) toggle ;;
    esac
    render
    return
  fi

  promote
  render
  sketchybar --trigger clock_update
}

toggle() {
  local elapsed
  read_state
  elapsed="$(current_elapsed)"

  if [ "$STATUS" = "running" ]; then
    write_state stopped "$elapsed" 0
  else
    write_state running "$elapsed" "$(now)"
  fi
}

reset() {
  # Reset always stops the stopwatch, whether it was running or already paused.
  write_state stopped 0 0
}

case "$1" in
  select)
    promote
    render
    sketchybar --trigger clock_update
    ;;
  menu_click)
    menu_click
    ;;
  click)
    case "${BUTTON:-left}" in
      right) reset ;;
      *) toggle ;;
    esac
    render
    ;;
  render|refresh|render_menu|sync)
    render
    ;;
  *)
    render
    ;;
esac
