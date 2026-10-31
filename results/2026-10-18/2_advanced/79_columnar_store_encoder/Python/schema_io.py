from collections import namedtuple
from datetime import date, timedelta
from pathlib import Path


Column = namedtuple("Column", "name kind nullable")
TYPES = ("INT", "STRING", "BOOL", "DATE")
EPOCH = date(1970, 1, 1)


def day_number(value):
    return (date.fromisoformat(value) - EPOCH).days


def parse_value(kind, field):
    if field == "":
        return None
    if kind == "INT":
        return int(field)
    if kind == "DATE":
        return day_number(field)
    if kind == "BOOL":
        return field == "true"
    return field


def value_text(kind, value, null="NULL"):
    if value is None:
        return null
    if kind == "DATE":
        return (EPOCH + timedelta(days=value)).isoformat()
    if kind == "BOOL":
        return "true" if value else "false"
    return str(value)


def read_inputs():
    columns = []
    for line in Path("input/schema.txt").read_text(encoding="ascii").splitlines():
        name, kind, nullability = line.split()
        columns.append(Column(name, kind, nullability == "NULLABLE"))
    lines = Path("input/table.csv").read_text(encoding="ascii").splitlines()
    rows = [[parse_value(column.kind, field) for column, field in zip(columns, line.split(","))]
            for line in lines[1:]]
    options = {"encoding": {}}
    for line in Path("input/options.txt").read_text(encoding="ascii").splitlines():
        key, *values = line.split()
        if key == "encoding":
            options[key][values[0]] = values[1]
        else:
            options[key] = int(values[0])
    queries = Path("input/queries.txt").read_text(encoding="ascii").splitlines()
    damaged = bytes.fromhex(Path("input/damaged.hex").read_text(encoding="ascii"))
    return columns, rows, options, queries, damaged


def write_outputs(outputs):
    directory = Path("output")
    directory.mkdir(exist_ok=True)
    for filename, lines in outputs.items():
        content = "\n".join(lines) + ("\n" if lines else "")
        (directory / filename).write_text(content, encoding="ascii", newline="\n")
