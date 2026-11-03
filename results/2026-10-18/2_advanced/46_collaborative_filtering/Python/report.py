"""ASCII report formatting, missing values, and LF-terminated output."""

from pathlib import Path


def real(value):
    if value is None:
        return "-"
    text = f"{value:.4f}"
    return "0.0000" if text == "-0.0000" else text


def optional(value):
    return "-" if value is None else str(value)


def write_lines(path, lines):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii", newline="\n") as stream:
        for line in lines:
            stream.write(line + "\n")
