#!/usr/bin/env bash

export PATH="/opt/homebrew/bin:/usr/local/bin:/bin:/usr/bin:/usr/sbin:/sbin"
export LC_ALL=C

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
CACHE_DIR="$CONFIG_DIR/cache"
SWAP_STATE_FILE="${STATS_SWAP_STATE_FILE:-$CACHE_DIR/stats_swap_used_5m.state}"
GPU_STATE_FILE="${STATS_GPU_STATE_FILE:-$CACHE_DIR/stats_gpu_load_5m.state}"
SKETCHYBAR="${SKETCHYBAR:-$(command -v sketchybar 2>/dev/null)}"

[ -n "$SKETCHYBAR" ] || SKETCHYBAR="/opt/homebrew/bin/sketchybar"
mkdir -p "$CACHE_DIR" 2>/dev/null

CYAN="0xff7bdff2"
CYAN_FILL="0x337bdff2"
GREEN="0xffa6e3a1"
GREEN_FILL="0x33a6e3a1"
BLUE="0xff89b4fa"
BLUE_FILL="0x3389b4fa"
ORANGE="0xffc77d47"
ORANGE_FILL="0x33c77d47"
YELLOW="0xfff9e2af"
YELLOW_FILL="0x33f9e2af"
RED="0xfff38ba8"
RED_FILL="0x33f38ba8"

STAT_LABEL_CHAR_WIDTH=9
STAT_PILL_X_PADDING=2
STAT_CPU_LABEL_WIDTH_TRIM=8
STAT_ITEM_GAP=20
STAT_STATS_SPAN_WIDTH=930
STAT_GRAPH_COUNT=4
STAT_GAP_COUNT=$((STAT_GRAPH_COUNT - 1))
STAT_GRAPH_WIDTH=$(((STAT_STATS_SPAN_WIDTH - STAT_GAP_COUNT * STAT_ITEM_GAP) / STAT_GRAPH_COUNT))
GPU_AVG_1M_WINDOW_SECONDS=60
GPU_AVG_5M_WINDOW_SECONDS=300
GPU_AVG_15M_WINDOW_SECONDS=900
GPU_STATE_RETENTION_SECONDS=$GPU_AVG_15M_WINDOW_SECONDS
SWAP_DELTA_WINDOW_SECONDS=300
SWAP_STATE_RETENTION_SECONDS=900

print_mode="${1:-}"

is_print_mode=0
case "$print_mode" in
  --print-cpu-label|--print-gpu-label|--print-mem-label|--print-swap-label|--print-labels)
    is_print_mode=1
    ;;
esac

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

stat_label_width() {
  local label="$1"
  local graph_width="$2"
  local trim="${3:-0}"
  local label_width

  label_width=$((${#label} * STAT_LABEL_CHAR_WIDTH + 2 * STAT_PILL_X_PADDING - trim))
  if [ "$label_width" -gt "$graph_width" ]; then
    label_width=$graph_width
  fi

  printf '%s' "$label_width"
}

stat_label_offset() {
  local label_width="$1"
  local graph_width="$2"

  printf '%s' "$((-(graph_width + label_width) / 2))"
}

vm_stat_output="$(vm_stat 2>/dev/null)"
now="$(date +%s 2>/dev/null)"

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

# ----- GPU -----
gpu_value=0
gpu_avg_1m_value=0
gpu_avg_5m_value=0
gpu_avg_15m_value=0
gpu_label="GPU --"
gpu_sample_ok=0

need_gpu=1
case "$print_mode" in
  --print-cpu-label|--print-mem-label|--print-swap-label)
    need_gpu=0
    ;;
esac

if [ "$need_gpu" -eq 1 ] && command -v macmon >/dev/null 2>&1; then
  gpu_fields="$(
    macmon pipe -s 1 -i 100 2>/dev/null | awk '
      NR == 1 {
        usage = $0

        if (usage ~ /"gpu_usage":[[][^],]+,[^]]+[]]/) {
          sub(/^.*"gpu_usage":[[][^],]+,/, "", usage)
          sub(/[]].*$/, "", usage)
        } else {
          usage = ""
        }

        if (usage != "") printf "%.6f", usage + 0
        exit
      }'
  )"
  read gpu_value <<<"$gpu_fields"

  if [ -n "$gpu_value" ]; then
    gpu_sample_ok=1
  else
    gpu_value=0
  fi
fi

write_gpu_state() {
  {
    if [ -r "$GPU_STATE_FILE" ]; then
      awk -v now="$now" -v retention="$GPU_STATE_RETENTION_SECONDS" '
        NF >= 2 &&
        $1 ~ /^[0-9]+$/ &&
        $2 ~ /^[0-9]+([.][0-9]+)?$/ &&
        now >= $1 &&
        now - $1 <= retention {
          print $1, $2
        }' "$GPU_STATE_FILE"
    fi
    printf '%s %.6f\n' "$now" "$gpu_value"
  } >"$GPU_STATE_FILE.tmp" 2>/dev/null && mv "$GPU_STATE_FILE.tmp" "$GPU_STATE_FILE" 2>/dev/null
}

if [ "$gpu_sample_ok" -eq 1 ] && [ -n "$now" ]; then
  read gpu_avg_1m_value gpu_avg_5m_value gpu_avg_15m_value <<<"$(
    {
      if [ -r "$GPU_STATE_FILE" ]; then
        awk -v now="$now" -v retention="$GPU_STATE_RETENTION_SECONDS" '
          NF >= 2 &&
          $1 ~ /^[0-9]+$/ &&
          $2 ~ /^[0-9]+([.][0-9]+)?$/ &&
          now >= $1 &&
          now - $1 <= retention {
            print $1, $2
          }' "$GPU_STATE_FILE"
      fi
      printf '%s %.6f\n' "$now" "$gpu_value"
    } | awk -v now="$now" \
        -v window_1m="$GPU_AVG_1M_WINDOW_SECONDS" \
        -v window_5m="$GPU_AVG_5M_WINDOW_SECONDS" \
        -v window_15m="$GPU_AVG_15M_WINDOW_SECONDS" '
      {
        age = now - $1
        value = $2 + 0
        if (age <= window_1m) {
          sum_1m += value
          count_1m++
        }
        if (age <= window_5m) {
          sum_5m += value
          count_5m++
        }
        if (age <= window_15m) {
          sum_15m += value
          count_15m++
        }
      }
      END {
        avg_1m = count_1m > 0 ? sum_1m / count_1m : 0
        avg_5m = count_5m > 0 ? sum_5m / count_5m : 0
        avg_15m = count_15m > 0 ? sum_15m / count_15m : 0
        printf "%.6f %.6f %.6f", avg_1m, avg_5m, avg_15m
      }'
  )"

  gpu_label="$(awk -v avg_1m="$gpu_avg_1m_value" \
                   -v avg_5m="$gpu_avg_5m_value" \
                   -v avg_15m="$gpu_avg_15m_value" 'BEGIN {
    printf "GPU %.2f %.2f %.2f", avg_1m + 0, avg_5m + 0, avg_15m + 0
  }')"

  if [ "$is_print_mode" -eq 0 ]; then
    write_gpu_state
  fi
fi

read gpu_color gpu_fill <<<"$(hot_colors "$gpu_value" "$GREEN" "$GREEN_FILL")"

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

swap_used_mib="$(awk -v used="$swap_used_g" 'BEGIN {
  printf "%.0f", (used + 0) * 1024
}')"

swap_delta_mib=0

write_swap_state() {
  {
    if [ -r "$SWAP_STATE_FILE" ]; then
      awk -v now="$now" -v retention="$SWAP_STATE_RETENTION_SECONDS" '
        NF >= 2 &&
        $1 ~ /^[0-9]+$/ &&
        $2 ~ /^-?[0-9]+$/ &&
        now >= $1 &&
        now - $1 <= retention {
          print $1, $2
        }' "$SWAP_STATE_FILE"
    fi
    printf '%s %s\n' "$now" "$swap_used_mib"
  } >"$SWAP_STATE_FILE.tmp" 2>/dev/null && mv "$SWAP_STATE_FILE.tmp" "$SWAP_STATE_FILE" 2>/dev/null
}

if [ -n "$swap_used_mib" ] && [ -n "$now" ]; then
  if [ -r "$SWAP_STATE_FILE" ]; then
    swap_delta_mib="$(
      awk -v now="$now" \
          -v current="$swap_used_mib" \
          -v window="$SWAP_DELTA_WINDOW_SECONDS" '
        NF >= 2 &&
        $1 ~ /^[0-9]+$/ &&
        $2 ~ /^-?[0-9]+$/ {
          age = now - $1
          if (age >= window && (!found || age < best_age)) {
            baseline = $2
            best_age = age
            found = 1
          }
        }
        END {
          if (found) printf "%.0f", current - baseline
          else printf "0"
        }' "$SWAP_STATE_FILE"
    )"
  fi

  if [ "$is_print_mode" -eq 0 ]; then
    write_swap_state
  fi
fi

swap_label="$(awk -v used="$swap_used_g" -v delta="$swap_delta_mib" 'BEGIN {
  printf "SWP %.1fG %+dM/5m", used + 0, delta + 0
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
  --print-gpu-label)
    printf '%s\n' "$gpu_label"
    exit 0
    ;;
  --print-swap-label)
    printf '%s\n' "$swap_label"
    exit 0
    ;;
  --print-labels)
    printf '%s\n%s\n%s\n%s\n' "$swap_label" "$mem_label" "$gpu_label" "$cpu_label"
    exit 0
    ;;
esac

cpu_label_width="$(stat_label_width "$cpu_label" "$STAT_GRAPH_WIDTH" "$STAT_CPU_LABEL_WIDTH_TRIM")"
gpu_label_width="$(stat_label_width "$gpu_label" "$STAT_GRAPH_WIDTH" "$STAT_CPU_LABEL_WIDTH_TRIM")"
mem_label_width="$(stat_label_width "$mem_label" "$STAT_GRAPH_WIDTH")"
swap_label_width="$(stat_label_width "$swap_label" "$STAT_GRAPH_WIDTH")"

cpu_label_offset="$(stat_label_offset "$cpu_label_width" "$STAT_GRAPH_WIDTH")"
gpu_label_offset="$(stat_label_offset "$gpu_label_width" "$STAT_GRAPH_WIDTH")"
mem_label_offset="$(stat_label_offset "$mem_label_width" "$STAT_GRAPH_WIDTH")"
swap_label_offset="$(stat_label_offset "$swap_label_width" "$STAT_GRAPH_WIDTH")"

push_graph "cpu.total" "$cpu_value"
"$SKETCHYBAR" --set cpu.total graph.color="$cpu_color" graph.fill_color="$cpu_fill" >/dev/null 2>&1
"$SKETCHYBAR" --set cpu.stat_label \
  label="$cpu_label" \
  label.color="$cpu_color" \
  label.width="$cpu_label_width" \
  label.align=center \
  label.padding_left=0 \
  label.padding_right=0 \
  padding_right="$cpu_label_offset" >/dev/null 2>&1

push_graph "gpu.graph" "$gpu_value"
"$SKETCHYBAR" --set gpu.graph graph.color="$gpu_color" graph.fill_color="$gpu_fill" >/dev/null 2>&1
"$SKETCHYBAR" --set gpu.stat_label \
  label="$gpu_label" \
  label.color="$gpu_color" \
  label.width="$gpu_label_width" \
  label.align=center \
  label.padding_left=0 \
  label.padding_right=0 \
  padding_right="$gpu_label_offset" >/dev/null 2>&1

push_graph "mem.graph" "$mem_value"
"$SKETCHYBAR" --set mem.graph graph.color="$mem_color" graph.fill_color="$mem_fill" >/dev/null 2>&1
"$SKETCHYBAR" --set mem.stat_label \
  label="$mem_label" \
  label.color="$mem_color" \
  label.width="$mem_label_width" \
  label.align=center \
  label.padding_left=0 \
  label.padding_right=0 \
  padding_right="$mem_label_offset" >/dev/null 2>&1

push_graph "swap.graph" "$swap_value"
"$SKETCHYBAR" --set swap.graph graph.color="$swap_color" graph.fill_color="$swap_fill" >/dev/null 2>&1
"$SKETCHYBAR" --set swap.stat_label \
  label="$swap_label" \
  label.color="$swap_color" \
  label.width="$swap_label_width" \
  label.align=center \
  label.padding_left=0 \
  label.padding_right=0 \
  padding_right="$swap_label_offset" >/dev/null 2>&1
