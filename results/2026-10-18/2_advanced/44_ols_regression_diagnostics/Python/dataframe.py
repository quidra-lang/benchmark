"""Read the four ASCII input files without changing their record order."""

from pathlib import Path


class DataFrame:
    def __init__(self, columns, kinds, rows):
        self.columns = columns
        self.kinds = kinds
        self.rows = rows


def read_csv(path, kinds=None):
    lines = Path(path).read_text(encoding="ascii").splitlines()
    columns = lines[0].split(",")
    records = [line.split(",") for line in lines[1:]]
    if kinds is None:
        kinds = {}
        for j, column in enumerate(columns):
            categorical = any(
                record[j] != "NA" and record[j][0].isupper()
                for record in records
            )
            kinds[column] = "categorical" if categorical else "numeric"
    else:
        kinds = {column: kinds[column] for column in columns}
    rows = []
    for record in records:
        row = {}
        for column, value in zip(columns, record):
            if value == "NA":
                row[column] = None
            elif kinds[column] == "numeric":
                row[column] = float(value)
            else:
                row[column] = value
        rows.append(row)
    return DataFrame(columns, kinds, rows)


def read_models(path):
    return Path(path).read_text(encoding="ascii").splitlines()


def read_params(path):
    params = {}
    for line in Path(path).read_text(encoding="ascii").splitlines():
        keyword, *values = line.split(" ")
        if keyword == "BEST_SUBSETS":
            params[keyword] = int(values[0])
        elif keyword == "PLOT":
            params[keyword] = (int(values[0]), int(values[1]), float(values[2]))
        else:
            params[keyword] = float(values[0])
    return params
