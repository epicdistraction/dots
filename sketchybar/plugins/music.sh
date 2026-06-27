#!/usr/bin/env bash

export PATH="/opt/homebrew/bin:/usr/local/bin:/bin:/usr/bin:/usr/sbin:/sbin"

TEXT=0xffd6f3f0
MUTED=0xff82a9ad
CYAN=0xff7bdff2
PANEL_STRONG=0xcc00283a
MUSIC_BUTTON_BG=0x33000000
TRANSPARENT=0x00ffffff

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
CACHE_DIR="$CONFIG_DIR/cache"
PAGE_STATE="$CACHE_DIR/music_title_page_state"
ARTIST_PAGE_STATE="$CACHE_DIR/music_artist_page_state"
ARTWORK_SIZE=64
PAGE_CHARS=60
PAGE_OVERLAP=8

NP="$(command -v nowplaying-cli || true)"
JQ="$(command -v jq || true)"

reset_page_state() {
  rm -f "$PAGE_STATE" "$ARTIST_PAGE_STATE"
}

is_absent() {
  case "$1" in
    ""|"null"|"(null)"|"<null>") return 0 ;;
  esac

  return 1
}

set_play_icon() {
  local icon="$1"
  local color="$2"

  sketchybar --set music.play \
    icon="$icon" \
    icon.color="$color" \
    background.color=$MUSIC_BUTTON_BG \
    background.image.drawing=off
}

artwork_path_for_data() {
  local data="$1"
  local sig path raw_tmp jpg_tmp

  mkdir -p "$CACHE_DIR"

  sig="$(printf '%s' "$data" | cksum | awk '{print $1 "_" $2}')"
  path="$CACHE_DIR/music_artwork_${sig}.jpg"

  if [ ! -s "$path" ]; then
    raw_tmp="$CACHE_DIR/music_artwork_${sig}.raw"
    jpg_tmp="$CACHE_DIR/music_artwork_${sig}.tmp.jpg"

    if ! printf '%s' "$data" | base64 -D > "$raw_tmp" 2>/dev/null; then
      rm -f "$raw_tmp" "$jpg_tmp"
      return 1
    fi

    if ! sips -s format jpeg -z "$ARTWORK_SIZE" "$ARTWORK_SIZE" "$raw_tmp" --out "$jpg_tmp" >/dev/null 2>&1; then
      rm -f "$raw_tmp" "$jpg_tmp"
      return 1
    fi

    rm -f "$raw_tmp"
    mv "$jpg_tmp" "$path"
  fi

  printf '%s' "$path"
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
  set_play_icon "♪" "$MUTED"
  sketchybar \
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

if [ -z "$JQ" ]; then
  TITLE="$("$NP" get title 2>/dev/null | head -n1)"
  ARTIST="$("$NP" get artist 2>/dev/null | head -n1)"
  RATE="$("$NP" get playbackRate 2>/dev/null | head -n1)"
  ARTWORK_DATA=""
else
  NOWPLAYING_JSON="$("$NP" get --json title artist playbackRate artworkData 2>/dev/null)"

  if ! printf '%s' "$NOWPLAYING_JSON" | "$JQ" -e . >/dev/null 2>&1; then
    NOWPLAYING_JSON="{}"
  fi

  TITLE="$(printf '%s' "$NOWPLAYING_JSON" | "$JQ" -r '.title // ""')"
  ARTIST="$(printf '%s' "$NOWPLAYING_JSON" | "$JQ" -r '.artist // ""')"
  RATE="$(printf '%s' "$NOWPLAYING_JSON" | "$JQ" -r '.playbackRate // ""')"
  ARTWORK_DATA="$(printf '%s' "$NOWPLAYING_JSON" | "$JQ" -r '.artworkData // ""')"
fi

if is_absent "$TITLE"; then
  reset_page_state
  set_play_icon "♪" "$MUTED"
  sketchybar \
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

if ! is_absent "$ARTIST"; then
  DISPLAY_ARTIST="$(page_label "$ARTIST_PAGE_STATE" "$ARTIST")"
else
  DISPLAY_ARTIST="Unknown Artist"
fi

DISPLAY_TITLE="$(page_label "$PAGE_STATE" "$TITLE")"

if ! is_absent "$ARTWORK_DATA" && ARTWORK_PATH="$(artwork_path_for_data "$ARTWORK_DATA")"; then
  sketchybar --set music.play \
    icon="$ICON" \
    icon.color=$TRANSPARENT \
    background.color=0x00000000 \
    background.image="$ARTWORK_PATH" \
    background.image.drawing=on
else
  set_play_icon "$ICON" "$CYAN"
fi

sketchybar --set music.artist \
  label="$DISPLAY_ARTIST" \
  label.color=$TEXT \
  --set music \
  label="$DISPLAY_TITLE" \
  label.color=$TEXT \
  --set music.tile \
  background.color=$BG
