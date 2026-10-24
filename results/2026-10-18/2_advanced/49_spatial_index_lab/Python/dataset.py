"""Read the four ASCII input files, preserving their insertion order."""

from pathlib import Path


def read_csv(path):
    with path.open(encoding="ascii", newline="") as source:
        next(source)
        return [tuple(map(int, line.rstrip("\n").split(","))) for line in source]


def read_dataset(directory="input"):
    directory = Path(directory)
    points = read_csv(directory / "points.csv")
    rectangles = read_csv(directory / "rects.csv")
    with (directory / "params.txt").open(encoding="ascii") as source:
        rows = [line.split() for line in source]
    parameters = {
        "world": int(rows[0][1]),
        "bucket": int(rows[1][1]),
        "maximum": int(rows[2][1]),
        "minimum": int(rows[2][2]),
        "cell_size": int(rows[3][1]),
    }
    with (directory / "queries.txt").open(encoding="ascii") as source:
        commands = []
        for line in source:
            name, *values = line.split()
            commands.append((name, tuple(map(int, values))))
    return points, rectangles, parameters, commands
