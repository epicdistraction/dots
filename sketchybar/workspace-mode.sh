#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-}"

SKETCHYBAR_DIR="$HOME/.config/sketchybar"
ACTIVE_RC="$SKETCHYBAR_DIR/sketchybarrc"
STATE_FILE="$SKETCHYBAR_DIR/.workspace-mode"

RECTANGLE_DOMAIN="com.knollsoft.Rectangle"

# Tune these as needed.
DESKTOP_BOTTOM_GAP=140
DESKTOP_WINDOW_GAP=20

MOBILE_BOTTOM_GAP=70
MOBILE_WINDOW_GAP=0

NODOCK_BOTTOM_GAP=0
NODOCK_WINDOW_GAP=0

usage() {
  cat <<EOF
Usage:
  ~/.config/sketchybar/workspace-mode.sh desktop
  ~/.config/sketchybar/workspace-mode.sh mobile
  ~/.config/sketchybar/workspace-mode.sh nodock
  ~/.config/sketchybar/workspace-mode.sh current

Modes:
  desktop  Full desktop/bottom-gutter config
  mobile   Laptop/docked compact config
  nodock   Remove SketchyBar UI entirely, keep service alive
EOF
}

notify() {
  local body="$1"
  /usr/bin/osascript \
    -e "display notification \"$body\" with title \"Workspace Mode\"" \
    >/dev/null 2>&1 || true
}

reload_sketchybar() {
  if command -v sketchybar >/dev/null 2>&1; then
    sketchybar --reload
  else
    echo "sketchybar command not found; config copied but bar was not reloaded." >&2
  fi
}

restart_rectangle() {
  /usr/bin/osascript -e 'quit app "Rectangle"' >/dev/null 2>&1 || true
  sleep 0.35
  /usr/bin/open -a Rectangle >/dev/null 2>&1 || true
}

apply_rectangle_values() {
  local bottom_gap="$1"
  local window_gap="$2"

  defaults write "$RECTANGLE_DOMAIN" screenEdgeGapBottom -int "$bottom_gap"
  defaults write "$RECTANGLE_DOMAIN" gapSize -float "$window_gap"
}

apply_sketchybar_mode() {
  local mode="$1"
  local source_rc="$SKETCHYBAR_DIR/sketchybarrc.$mode"

  if [[ ! -f "$source_rc" ]]; then
    echo "Missing SketchyBar config: $source_rc" >&2
    exit 1
  fi

  cp "$source_rc" "$ACTIVE_RC"
  echo "$mode" > "$STATE_FILE"
  reload_sketchybar

  # Important after nodock:
  # desktop/mobile configs may not explicitly undo hidden=on.
  if [[ "$mode" != "nodock" ]]; then
    sketchybar --bar hidden=off >/dev/null 2>&1 || true
  fi
}

apply_desktop() {
  apply_sketchybar_mode desktop
  apply_rectangle_values "$DESKTOP_BOTTOM_GAP" "$DESKTOP_WINDOW_GAP"
  restart_rectangle
  notify "Desktop mode applied"
}

apply_mobile() {
  apply_sketchybar_mode mobile
  apply_rectangle_values "$MOBILE_BOTTOM_GAP" "$MOBILE_WINDOW_GAP"
  restart_rectangle
  notify "Mobile mode applied"
}

apply_nodock() {
  apply_sketchybar_mode nodock
  apply_rectangle_values "$NODOCK_BOTTOM_GAP" "$NODOCK_WINDOW_GAP"
  restart_rectangle
  notify "No-dock mode applied"
}

case "$MODE" in
  desktop)
    apply_desktop
    ;;

  mobile)
    apply_mobile
    ;;

  nodock|no-dock|no_dock)
    apply_nodock
    ;;

  current)
    if [[ -f "$STATE_FILE" ]]; then
      cat "$STATE_FILE"
    else
      echo "unknown"
    fi
    ;;

  -h|--help|help|"")
    usage
    ;;

  *)
    echo "Unknown mode: $MODE" >&2
    usage
    exit 1
    ;;
esac
