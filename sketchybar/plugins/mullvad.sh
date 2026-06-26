#!/usr/bin/env bash

export PATH="/opt/homebrew/bin:/usr/local/bin:/bin:/usr/bin:/usr/sbin:/sbin"

TEXT=0xffd6f3f0
GREEN=0xffa6e3a1
RED=0xfff38ba8

PRIMARY_MULLVAD="/Applications/Mullvad VPN.app/Contents/MacOS/mullvad"
FALLBACK_MULLVAD="/Applications/Mullvad VPN.app/Contents/Resources/mullvad"

MULLVAD="$PRIMARY_MULLVAD"
if [ ! -x "$MULLVAD" ]; then
  MULLVAD="$FALLBACK_MULLVAD"
fi

set_vpn() {
  sketchybar --set clock.vpn \
    label="$1" \
    label.color="$2"
}

get_status() {
  "$MULLVAD" status 2>/dev/null
}

status_head() {
  printf '%s\n' "$1" | head -n1
}

refresh_status() {
  if [ ! -x "$MULLVAD" ]; then
    set_vpn "Mullvad unavailable" "$RED"
    return
  fi

  local status status_head relay
  status="$(get_status)"
  status_head="$(status_head "$status")"

  case "$status_head" in
    Connected*)
      relay="$(printf '%s\n' "$status" | awk -F': *' '/Relay:/ {print $2; exit}')"
      if [ -n "$relay" ]; then
        relay="${relay%% (*}"
        relay="${relay// via / -> }"
        set_vpn "Mullvad $relay" "$GREEN"
      else
        set_vpn "Mullvad connected" "$GREEN"
      fi
      ;;
    Disconnected*)
      set_vpn "Mullvad disconnected" "$RED"
      ;;
    *)
      if [ -n "$status_head" ]; then
        set_vpn "Mullvad $status_head" "$TEXT"
      else
        set_vpn "Mullvad unknown" "$RED"
      fi
      ;;
  esac
}

toggle_connection() {
  if [ ! -x "$MULLVAD" ]; then
    set_vpn "Mullvad unavailable" "$RED"
    return
  fi

  local status status_head
  status="$(get_status)"
  status_head="$(status_head "$status")"

  if [[ "$status_head" == Connected* ]]; then
    set_vpn "Mullvad reconnecting..." "$GREEN"
    "$MULLVAD" reconnect >/dev/null 2>&1
  else
    set_vpn "Mullvad connecting..." "$GREEN"
    "$MULLVAD" connect >/dev/null 2>&1
  fi

  sleep 1
  refresh_status
}

case "$1" in
  click)
    toggle_connection
    ;;
  *)
    refresh_status
    ;;
esac
