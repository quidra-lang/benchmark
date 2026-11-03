"""Benchmark-specified four-decimal formatting and file writers."""

import math
from pathlib import Path


def real(value):
    formatted = f"{value:.4f}"
    return "0.0000" if formatted == "-0.0000" else formatted


def fields(**items):
    return " ".join(f"{key}={real(value) if isinstance(value, float) else value}"
                    for key, value in items.items())


def write_lines(name, lines):
    target = Path("output") / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("\n".join(lines) + "\n", encoding="ascii")


def write_csv(name, header, rows):
    lines = [header]
    for row in rows:
        lines.append(",".join(real(v) if isinstance(v, float) else str(v)
                              for v in row))
    write_lines(name, lines)


def shade_lines(grid, sample_rate, frame_length, band_db):
    """One row per FFT bin, descending frequency with fixed nine-wide labels."""
    count = len(grid)
    maximum = max(value for frame in grid for value in frame)
    shades = " .:-=+*#%@"
    lines = []
    for k in range(frame_length // 2, -1, -1):
        pixels = []
        for t in range(count):
            amplitude_db = 20 * math.log10(grid[t][k] / maximum)
            level = max(0, 9 - math.floor(-amplitude_db / band_db))
            pixels.append(shades[level])
        lines.append(f"{real(k * sample_rate / frame_length):>9} |{''.join(pixels)}|")
    return lines
