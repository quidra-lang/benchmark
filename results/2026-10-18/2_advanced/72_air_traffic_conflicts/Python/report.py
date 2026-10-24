"""Formatting and ASCII file emission for all air-traffic reports."""

from pathlib import Path


def decimal(value, digits=3):
    result = f"{value:.{digits}f}"
    return result[1:] if result.startswith("-") and float(result) == 0.0 else result


def named(**values):
    return " ".join(f"{key}={value}" for key, value in values.items())


def chart(lines):
    width = len(lines[0])
    border = "+" + "-" * width + "+"
    return [border] + ["|" + row + "|" for row in lines] + [border]


def signed(number):
    return f"+{number}" if number > 0 else str(number)


def write_lines(filename, lines):
    target = Path("output") / filename
    target.parent.mkdir(parents=True, exist_ok=True)
    contents = "\n".join(lines)
    target.write_text(contents + "\n" if lines else "", encoding="ascii")
