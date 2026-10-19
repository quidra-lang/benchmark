"""Monospaced display strings and the exact page-file framing."""


def display_line(pieces, slack, alignment, last):
    pieces = [piece.replace("~", " ") for piece in pieces]
    text = " ".join(pieces)
    if slack <= 0:
        return text
    gaps = len(pieces) - 1
    if alignment == "justify" and not last and gaps:
        quotient, remainder = divmod(slack, gaps)
        parts = [pieces[0]]
        for index, piece in enumerate(pieces[1:]):
            spaces = quotient + 1 + (1 if index < remainder else 0)
            parts.extend((" " * spaces, piece))
        return "".join(parts)
    if alignment == "right":
        return " " * slack + text
    if alignment == "center":
        return " " * (slack // 2) + text
    return text


def format_table(rows, columns, caption, number):
    widths = [max(len(row[index]) for row in rows)
              for index in range(len(columns))]
    lines = []
    if caption:
        lines.append(f"Table {number}. {caption}")
    for row_index, row in enumerate(rows):
        cells = []
        for text, alignment, width in zip(row, columns, widths):
            missing = width - len(text)
            if alignment == "l":
                cell = text + " " * missing
            elif alignment == "r":
                cell = " " * missing + text
            else:
                before = missing // 2
                cell = " " * before + text + " " * (missing - before)
            cells.append(cell)
        lines.append(" | ".join(cells).rstrip(" "))
        if row_index == 0:
            lines.append("-+-".join("-" * width for width in widths))
    return lines


def running_head(fields, values, width, serial_number):
    expanded = []
    for field in fields:
        for name, value in values.items():
            field = field.replace("{" + name + "}", value)
        expanded.append(field)
    left, center, right = expanded
    if serial_number % 2 == 0:
        left, right = right, left
    line = [" "] * width
    placements = ((0, left), ((width - len(center)) // 2, center),
                  (width - len(right), right))
    for start, text in placements:
        line[start:start + len(text)] = text
    return "".join(line).rstrip(" ")


def pages_text(pages):
    lines = []
    for page in pages:
        lines.extend((f"--- page {page['serial']} ---", page["header"], ""))
        lines.extend(page["body"])
        lines.extend(("", page["footer"]))
    return "".join(line + "\n" for line in lines)
