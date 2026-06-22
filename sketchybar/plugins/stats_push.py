#!/usr/bin/env python3

import shutil
import subprocess
import psutil

SKETCHYBAR = shutil.which("sketchybar") or "/opt/homebrew/bin/sketchybar"

# ----- Palette -----
CYAN = "0xff7bdff2"
CYAN_FILL = "0x337bdff2"

BLUE = "0xff89b4fa"
BLUE_FILL = "0x3389b4fa"

ORANGE = "0xffc77d47"
ORANGE_FILL = "0x33c77d47"

YELLOW = "0xfff9e2af"
YELLOW_FILL = "0x33f9e2af"

RED = "0xfff38ba8"
RED_FILL = "0x33f38ba8"

MUTED = "0xff82a9ad"
TEXT = "0xffd6f3f0"


def run(args):
    subprocess.run(
        [SKETCHYBAR] + args,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def push_graph(name, value):
    """
    SketchyBar graphs expect a normalized value from 0.0 to 1.0.
    """
    value = max(0.0, min(1.0, float(value)))
    run(["--push", name, f"{value:.3f}"])


def set_item(name, props):
    """
    Props may contain SketchyBar keys like graph.color or label.color,
    so pass them as strings instead of Python kwargs.
    """
    args = ["--set", name]
    for key, value in props.items():
        args.append(f"{key}={value}")
    run(args)


def hot_color(value, base_color, base_fill):
    """
    value is normalized from 0.0 to 1.0.
    """
    if value >= 0.85:
        return RED, RED_FILL
    if value >= 0.65:
        return YELLOW, YELLOW_FILL
    return base_color, base_fill


# ----- CPU -----
# psutil gives one percent per logical CPU.
# Example: 8 logical CPUs at 50% each = 400% cumulative.
# The graph is normalized against total available CPU capacity,
# so that 400% on an 8-thread machine draws as 50%.
cores = psutil.cpu_percent(interval=0.20, percpu=True)

total_cpu_pct = sum(cores)
max_cpu_pct = max(1, len(cores) * 100)
cpu_value = total_cpu_pct / max_cpu_pct

cpu_color, cpu_fill = hot_color(cpu_value, CYAN, CYAN_FILL)

push_graph("cpu.total", cpu_value)

set_item(
    "cpu.total",
    {
        "graph.color": cpu_color,
        "graph.fill_color": cpu_fill,
    },
)

set_item(
    "cpu.value",
    {
        "label": f"{total_cpu_pct:4.0f}%",
        "label.color": TEXT if cpu_value >= 0.65 else MUTED,
    },
)


# ----- Memory -----
mem = psutil.virtual_memory()
mem_value = mem.percent / 100.0

mem_color, mem_fill = hot_color(mem_value, BLUE, BLUE_FILL)

push_graph("mem.graph", mem_value)

set_item(
    "mem.graph",
    {
        "graph.color": mem_color,
        "graph.fill_color": mem_fill,
    },
)

set_item(
    "mem.value",
    {
        "label": f"{mem.percent:3.0f}%",
        "label.color": TEXT if mem_value >= 0.65 else MUTED,
    },
)


# ----- Swap -----
try:
    swap = psutil.swap_memory()
    swap_percent = swap.percent
except OSError:
    swap_percent = 0.0

swap_value = swap_percent / 100.0

swap_color, swap_fill = hot_color(swap_value, ORANGE, ORANGE_FILL)

push_graph("swap.graph", swap_value)

set_item(
    "swap.graph",
    {
        "graph.color": swap_color,
        "graph.fill_color": swap_fill,
    },
)

set_item(
    "swap.value",
    {
        "label": f"{swap_percent:3.0f}%",
        "label.color": TEXT if swap_value >= 0.65 else MUTED,
    },
)
