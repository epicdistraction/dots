#!/usr/bin/env bash

export PATH="/opt/homebrew/bin:/usr/local/bin:/bin:/usr/bin:/usr/sbin:/sbin"

VENV="$HOME/.config/sketchybar/.venv"

if [ ! -x "$VENV/bin/python" ]; then
  python3 -m venv "$VENV"
fi

if ! "$VENV/bin/python" -c 'import psutil' >/dev/null 2>&1; then
  "$VENV/bin/pip" install psutil >/dev/null 2>&1
fi

exec "$VENV/bin/python" "$HOME/.config/sketchybar/plugins/stats_push.py"
