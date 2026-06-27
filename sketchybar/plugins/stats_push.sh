#!/usr/bin/env bash

export PATH="/opt/homebrew/bin:/usr/local/bin:/bin:/usr/bin:/usr/sbin:/sbin"
export LC_ALL=C

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
CACHE_DIR="$CONFIG_DIR/cache"
STATE_FILE="${STATS_SWAP_STATE_FILE:-$CACHE_DIR/stats_swapouts.state}"
SKETCHYBAR="${SKETCHYBAR:-$(command -v sketchybar 2>/dev/null)}"

[ -n "$SKETCHYBAR" ] || SKETCHYBAR="/opt/homebrew/bin/sketchybar"
mkdir -p "$CACHE_DIR" 2>/dev/null

CYAN="0xff7bdff2"
CYAN_FILL="0x337bdff2"
BLUE="0xff89b4fa"
BLUE_FILL="0x3389b4fa"
ORANGE="0xffc77d47"
ORANGE_FILL="0x33c77d47"
YELLOW="0xfff9e2af"
YELLOW_FILL="0x33f9e2af"
RED="0xfff38ba8"
RED_FILL="0x33f38ba8"

print_mode="${1:-}"

clamp01() {
  awk -v value="$1" 'BEGIN {
    value += 0
    if (value < 0) value = 0
    if (value > 1) value = 1
    printf "%.3f", value
  }'
}

hot_colors() {
  awk -v value="$1" \
      -v base="$2" -v base_fill="$3" \
      -v yellow="$YELLOW" -v yellow_fill="$YELLOW_FILL" \
      -v red="$RED" -v red_fill="$RED_FILL" 'BEGIN {
    value += 0
    if (value >= 0.85) {
      print red, red_fill
    } else if (value >= 0.65) {
      print yellow, yellow_fill
    } else {
      print base, base_fill
    }
  }'
}

push_graph() {
  "$SKETCHYBAR" --push "$1" "$(clamp01 "$2")" >/dev/null 2>&1
}

vm_stat_output="$(vm_stat 2>/dev/null)"

# ----- CPU -----
cpu_label="$(
  sysctl -n vm.loadavg 2>/dev/null | awk '
    {
      for (i = 1; i <= NF; i++) {
        token = $i
        gsub(/[{}]/, "", token)
        if (token ~ /^[0-9]+([.][0-9]+)?$/) nums[++count] = token
      }
    }
    END {
      if (count >= 3) {
        printf "CPU %.2f %.2f %.2f", nums[1], nums[2], nums[3]
      } else {
        printf "CPU 0.00 0.00 0.00"
      }
    }'
)"

logical_cpus="$(sysctl -n hw.logicalcpu 2>/dev/null | awk '$1 ~ /^[0-9]+$/ && $1 > 0 { print $1; exit }')"
[ -n "$logical_cpus" ] || logical_cpus=1

cpu_pct="$(ps -A -o %cpu= 2>/dev/null | awk '{ sum += $1 } END { printf "%.3f", sum + 0 }')"
cpu_value="$(awk -v pct="$cpu_pct" -v cpus="$logical_cpus" 'BEGIN {
  max_pct = cpus * 100
  if (max_pct <= 0) max_pct = 100
  printf "%.6f", pct / max_pct
}')"

read cpu_color cpu_fill <<<"$(hot_colors "$cpu_value" "$CYAN" "$CYAN_FILL")"

# ----- Memory -----
mem_total_bytes="$(sysctl -n hw.memsize 2>/dev/null | awk '$1 ~ /^[0-9]+$/ { print $1; exit }')"
[ -n "$mem_total_bytes" ] || mem_total_bytes=0

mem_fields="$(
  printf '%s\n' "$vm_stat_output" | awk -v total="$mem_total_bytes" '
    function clean_number(value) {
      gsub(/[^0-9]/, "", value)
      return value + 0
    }
    NR == 1 {
      page_line = $0
      sub(/^.*page size of /, "", page_line)
      sub(/ bytes.*$/, "", page_line)
      if (page_line ~ /^[0-9]+$/) page_size = page_line + 0
    }
    {
      label = $0
      sub(/:.*/, "", label)
      value = $0
      sub(/^[^:]*:/, "", value)
      pages = clean_number(value)

      if (label == "Pages active") active = pages
      else if (label == "Pages wired down") wired = pages
      else if (label == "Anonymous pages") {
        anonymous = pages
        anonymous_found = 1
      }
      else if (label == "Pages occupied by compressor") {
        compressor = pages
        compressor_found = 1
      }
      else if (label == "Pages stored in compressor") compressor_fallback = pages
    }
    END {
      if (page_size <= 0 || total <= 0) {
        printf "0 0 0 0.0"
        exit
      }

      if (!compressor_found) compressor = compressor_fallback

      if (anonymous_found) used_pages = anonymous + wired + compressor
      else used_pages = active + wired + compressor

      used = used_pages * page_size
      if (used < 0) used = 0
      if (used > total) used = total

      gib = 1024 * 1024 * 1024
      printf "%.6f %.0f %.0f %.1f", used / total, used / gib, total / gib, (compressor * page_size) / gib
    }'
)"
read mem_value mem_used_g mem_total_g mem_compressed_g <<<"$mem_fields"

mem_label="$(awk -v used="$mem_used_g" -v total="$mem_total_g" -v compressed="$mem_compressed_g" 'BEGIN {
  printf "MEM %.0f/%.0fG C%.1fG", used + 0, total + 0, compressed + 0
}')"

read mem_color mem_fill <<<"$(hot_colors "$mem_value" "$BLUE" "$BLUE_FILL")"

# ----- Swap -----
swap_fields="$(
  sysctl vm.swapusage 2>/dev/null | awk '
    function to_gib(raw, value, unit) {
      gsub(/,/, "", raw)
      value = raw
      sub(/[^0-9.].*/, "", value)
      unit = raw
      sub(/^[0-9.]+/, "", unit)
      unit = toupper(substr(unit, 1, 1))

      if (unit == "B") return value / 1073741824
      if (unit == "K") return value / 1048576
      if (unit == "M") return value / 1024
      if (unit == "T") return value * 1024
      return value + 0
    }
    {
      line = $0
      gsub(/=/, " = ", line)
      count = split(line, fields, /[[:space:]]+/)
      for (i = 1; i <= count; i++) {
        if (fields[i] == "total" && fields[i + 1] == "=") total_g = to_gib(fields[i + 2])
        else if (fields[i] == "used" && fields[i + 1] == "=") used_g = to_gib(fields[i + 2])
      }
    }
    END {
      value = 0
      if (total_g > 0) value = used_g / total_g
      printf "%.6f %.1f", value, used_g
    }'
)"
read swap_value swap_used_g <<<"$swap_fields"

swap_counter="$(
  printf '%s\n' "$vm_stat_output" | awk '
    function clean_number(value) {
      gsub(/[^0-9]/, "", value)
      return value
    }
    /^Swapouts:/ {
      swapouts = clean_number($0)
      swapouts_found = 1
    }
    /^Pageouts:/ {
      pageouts = clean_number($0)
      pageouts_found = 1
    }
    END {
      if (swapouts_found) print swapouts
      else if (pageouts_found) print pageouts
    }'
)"

swap_out_rate=0
now="$(date +%s 2>/dev/null)"

is_print_mode=0
case "$print_mode" in
  --print-cpu-label|--print-mem-label|--print-swap-label|--print-labels)
    is_print_mode=1
    ;;
esac

write_swap_state() {
  printf '%s %s\n' "$swap_counter" "$now" >"$STATE_FILE" 2>/dev/null
}

if [ -n "$swap_counter" ] && [ -n "$now" ]; then
  if [ -r "$STATE_FILE" ]; then
    read previous_counter previous_time _ <"$STATE_FILE"
    swap_state_result="$(
      awk -v counter="$swap_counter" -v previous="$previous_counter" \
          -v now="$now" -v previous_time="$previous_time" 'BEGIN {
        if (counter !~ /^[0-9]+$/ || previous !~ /^[0-9]+$/ ||
            now !~ /^[0-9]+$/ || previous_time !~ /^[0-9]+$/) {
          print "invalid 0"
          exit
        }

        delta = counter - previous
        elapsed = now - previous_time
        if (elapsed <= 0) {
          print "elapsed_invalid 0"
        } else if (delta < 0) {
          print "counter_reset 0"
        } else {
          rate = delta / elapsed
          if (rate < 0) rate = 0
          printf "ok %.0f", rate
        }
      }'
    )"
    read swap_state_status swap_out_rate <<<"$swap_state_result"

    case "$swap_state_status" in
      ok)
        if [ "$is_print_mode" -eq 0 ]; then
          write_swap_state
        fi
        ;;
      counter_reset)
        write_swap_state
        ;;
    esac
  else
    write_swap_state
  fi
fi

swap_label="$(awk -v used="$swap_used_g" -v rate="$swap_out_rate" 'BEGIN {
  printf "SWP %.1fG O %.0f/s", used + 0, rate + 0
}')"

read swap_color swap_fill <<<"$(hot_colors "$swap_value" "$ORANGE" "$ORANGE_FILL")"

case "$print_mode" in
  --print-cpu-label)
    printf '%s\n' "$cpu_label"
    exit 0
    ;;
  --print-mem-label)
    printf '%s\n' "$mem_label"
    exit 0
    ;;
  --print-swap-label)
    printf '%s\n' "$swap_label"
    exit 0
    ;;
  --print-labels)
    printf '%s\n%s\n%s\n' "$swap_label" "$mem_label" "$cpu_label"
    exit 0
    ;;
esac

push_graph "cpu.total" "$cpu_value"
"$SKETCHYBAR" --set cpu.total graph.color="$cpu_color" graph.fill_color="$cpu_fill" >/dev/null 2>&1
"$SKETCHYBAR" --set cpu.stat_label label="$cpu_label" label.color="$cpu_color" >/dev/null 2>&1

push_graph "mem.graph" "$mem_value"
"$SKETCHYBAR" --set mem.graph graph.color="$mem_color" graph.fill_color="$mem_fill" >/dev/null 2>&1
"$SKETCHYBAR" --set mem.stat_label label="$mem_label" label.color="$mem_color" >/dev/null 2>&1

push_graph "swap.graph" "$swap_value"
"$SKETCHYBAR" --set swap.graph graph.color="$swap_color" graph.fill_color="$swap_fill" >/dev/null 2>&1
"$SKETCHYBAR" --set swap.stat_label label="$swap_label" label.color="$swap_color" >/dev/null 2>&1
