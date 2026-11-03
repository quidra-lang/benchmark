"""Fixed-point output, millisecond times, temperature grids and isotherms."""

from pathlib import Path


def real(value, places):
    rendered = f"{value:.{places}f}"
    if rendered == "-0." + "0" * places:
        return rendered[1:]
    return rendered


def time(milliseconds):
    return f"{milliseconds // 1000}.{milliseconds % 1000:03d}"


def temperature_lines(plate, field):
    return [
        " ".join(real(field[plate.cell(row, column)], 2) for column in range(plate.width))
        for row in range(plate.height)
    ]


def isotherm_lines(plate, field, bands):
    hottest = max(range(plate.count), key=field.__getitem__)
    counts = [0] * (len(bands) + 1)
    characters = []
    for point, temperature in enumerate(field):
        digit = sum(boundary <= temperature for boundary in bands)
        counts[digit] += 1
        characters.append("*" if point == hottest else str(digit))
    lines = [
        "".join(characters[row * plate.width:(row + 1) * plate.width])
        for row in range(plate.height)
    ]
    return counts, lines


def write_lines(filename, lines):
    directory = Path("output")
    directory.mkdir(exist_ok=True)
    with (directory / filename).open("w", encoding="ascii", newline="\n") as destination:
        destination.write("\n".join(lines) + "\n")
