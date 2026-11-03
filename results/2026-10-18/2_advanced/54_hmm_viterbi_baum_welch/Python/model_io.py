"""Model storage, ordered normalization, and the benchmark's file formats."""

from pathlib import Path


def normalize(values):
    total = 0.0
    for value in values:
        total += value
    return [value / total for value in values]


class Model:
    def __init__(self, name, states, symbols, missing, initial, transition, emission):
        self.name = name
        self.states = tuple(states)
        self.symbols = tuple(symbols)
        self.missing = missing
        self.initial = normalize(initial)
        self.transition = [normalize(row) for row in transition]
        self.emission = [normalize(row) for row in emission]


def read_tokens(filename):
    path = Path("input") / filename
    with path.open(encoding="ascii") as source:
        return [line.rstrip("\n").split(" ") for line in source]


def read_model(rows):
    states = rows[0][1:]
    symbols = rows[1][1:]
    missing = rows[2][1]
    count = len(states)
    initial = [float(value) for value in rows[3][1:]]
    transition = [
        [float(value) for value in row[2:]]
        for row in rows[4:4 + count]
    ]
    emission = [
        [float(value) for value in row[2:]]
        for row in rows[4 + count:4 + 2 * count]
    ]
    return Model("INITIAL", states, symbols, missing, initial, transition, emission)


def read_inputs():
    model = read_model(read_tokens("model.txt"))
    sequences = read_tokens("sequences.txt")
    labeled = read_tokens("labeled.txt")
    parameters = read_tokens("params.txt")
    return model, sequences, labeled, parameters


def real(value, places=4):
    if value is None:
        return "-"
    rendered = f"{value:.{places}f}"
    if rendered == "-0." + "0" * places:
        return rendered[1:]
    return rendered


def model_lines(model):
    lines = [
        f"MODEL {model.name}",
        "STATES " + " ".join(model.states),
        "SYMBOLS " + " ".join(model.symbols),
        f"MISSING {model.missing}",
        "INITIAL " + " ".join(real(value) for value in model.initial),
    ]
    for state, row in zip(model.states, model.transition):
        lines.append(f"TRANSITION {state} " + " ".join(real(value) for value in row))
    for state, row in zip(model.states, model.emission):
        lines.append(f"EMISSION {state} " + " ".join(real(value) for value in row))
    return lines


def write_lines(filename, lines):
    directory = Path("output")
    directory.mkdir(exist_ok=True)
    with (directory / filename).open("w", encoding="ascii", newline="\n") as target:
        target.write("\n".join(lines) + "\n")
