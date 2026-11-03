"""Plain symbol rows and scaled, quiet-zone PBM images."""


def symbol_lines(symbol):
    return ["".join("#" if value else "." for value in row) for row in symbol]


def pbm_text(symbol, quiet_zone, scale):
    size = len(symbol)
    width = (size + 2 * quiet_zone) * scale
    margin = "0" * (quiet_zone * scale)
    empty_row = "0" * width
    lines = ["P1", f"{width} {width}"]
    lines.extend([empty_row] * (quiet_zone * scale))
    for row in symbol:
        pixels = margin + "".join(str(value) * scale for value in row) + margin
        lines.extend([pixels] * scale)
    lines.extend([empty_row] * (quiet_zone * scale))
    return "\n".join(lines) + "\n"
