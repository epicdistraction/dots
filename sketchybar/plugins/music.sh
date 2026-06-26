#!/usr/bin/env bash

export PATH="/opt/homebrew/bin:/usr/local/bin:/bin:/usr/bin:/usr/sbin:/sbin"

TEXT=0xffd6f3f0
MUTED=0xff82a9ad
CYAN=0xff7bdff2
PANEL_STRONG=0xcc00283a

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
CACHE_DIR="$CONFIG_DIR/cache"
PAGE_STATE="$CACHE_DIR/music_title_page_state"
ARTIST_PAGE_STATE="$CACHE_DIR/music_artist_page_state"
PAGE_CHARS=60
PAGE_OVERLAP=8

NP="$(command -v nowplaying-cli || true)"

reset_page_state() {
  rm -f "$PAGE_STATE" "$ARTIST_PAGE_STATE"
}

page_label() {
  local state_file="$1"
  local text="$2"
  local len=${#text}

  if [ "$len" -le "$PAGE_CHARS" ]; then
    rm -f "$state_file"
    printf '%s' "$text"
    return
  fi

  mkdir -p "$CACHE_DIR"

  local step=$((PAGE_CHARS - PAGE_OVERLAP))
  local page_count=$(( (len - PAGE_CHARS + step - 1) / step + 1 ))
  local sig
  local last_sig=""
  local last_page="-1"
  local page=0

  sig="$(printf '%s' "$text" | cksum | awk '{print $1 ":" $2}')"
  if [ -f "$state_file" ]; then
    IFS='|' read -r last_sig last_page < "$state_file"
  fi

  if [ "$sig" = "$last_sig" ]; then
    page=$(( (last_page + 1) % page_count ))
  fi

  printf '%s|%s\n' "$sig" "$page" > "$state_file"

  local start=$((page * step))
  if [ $((start + PAGE_CHARS)) -gt "$len" ]; then
    start=$((len - PAGE_CHARS))
  fi

  printf '%s' "$text" | cut -c $((start + 1))-$((start + PAGE_CHARS))
}

if [ -z "$NP" ]; then
  reset_page_state
  sketchybar --set music.play \
    icon="♪" \
    icon.color=$MUTED \
    --set music.artist \
    label="Now Playing" \
    label.color=$TEXT \
    --set music \
    label="install: brew install nowplaying-cli" \
    label.color=$TEXT \
    --set music.tile \
    background.color=$PANEL_STRONG
  exit 0
fi

TITLE="$("$NP" get title 2>/dev/null | head -n1)"
ARTIST="$("$NP" get artist 2>/dev/null | head -n1)"
RATE="$("$NP" get playbackRate 2>/dev/null | head -n1)"

if [ -z "$TITLE" ] || [ "$TITLE" = "(null)" ]; then
  reset_page_state
  sketchybar --set music.play \
    icon="♪" \
    icon.color=$MUTED \
    --set music.artist \
    label="Now Playing" \
    label.color=$TEXT \
    --set music \
    label="Nothing playing" \
    label.color=$TEXT \
    --set music.tile \
    background.color=$PANEL_STRONG
  exit 0
fi

ICON="⏸"
BG="$PANEL_STRONG"
if [ "$RATE" = "0" ] || [ "$RATE" = "0.0" ]; then
  ICON="▶"
fi

if [ -n "$ARTIST" ] && [ "$ARTIST" != "(null)" ]; then
  DISPLAY_ARTIST="$(page_label "$ARTIST_PAGE_STATE" "$ARTIST")"
else
  DISPLAY_ARTIST="Unknown Artist"
fi

DISPLAY_TITLE="$(page_label "$PAGE_STATE" "$TITLE")"

sketchybar --set music.play \
  icon="$ICON" \
  icon.color=$CYAN \
  --set music.artist \
  label="$DISPLAY_ARTIST" \
  label.color=$TEXT \
  --set music \
  label="$DISPLAY_TITLE" \
  label.color=$TEXT \
  --set music.tile \
  background.color=$BG
