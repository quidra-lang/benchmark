"""Fixed decimal formatting and framed ASCII visualizations."""

from pathlib import Path


LEVELS = " .:-=+*#%@"


def dec(value, places=4):
    result = f"{value:.{places}f}"
    return result[1:] if result.startswith("-") and float(result) == 0 else result


def optional(value):
    return "-" if value is None else dec(value)


def values(items):
    return " ".join(str(v) if isinstance(v, int) else dec(v) for v in items)


def framed(grid):
    if not grid:
        return []
    border = "+" + "-" * len(grid[0]) + "+"
    return [border] + ["|" + "".join(line) + "|" for line in grid] + [border]


def write_lines(name, lines):
    target = Path("output") / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("\n".join(lines) + "\n", encoding="ascii")


def write_blocks(name, blocks):
    rows = []
    for index, block in enumerate(blocks):
        if index:
            rows.append("")
        rows.extend(block)
    write_lines(name, rows)
