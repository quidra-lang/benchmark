import os


class Row:
    def __init__(self, ident, values, label, target):
        self.ident = ident
        self.values = values
        self.label = label
        self.target = target


class Settings:
    def __init__(self, entries):
        self.scalings = entries["SCALINGS"]
        self.k_values = [int(value) for value in entries["K_VALUES"]]
        self.metrics = entries["METRICS"]
        self.weightings = entries["WEIGHTINGS"]
        self.folds = int(entries["FOLDS"][0])
        self.edit_k = int(entries["EDIT_K"][0])
        self.curve = [int(value) for value in entries["CURVE"]]
        self.bins = [float(value) for value in entries["BINS"]]
        self.top = int(entries["TOP"][0])


def read_lines(path):
    with open(path) as file:
        return file.read().splitlines()


def read_rows(path):
    lines = read_lines(path)
    header = lines[0].split(",")
    rows = []
    for line in lines[1:]:
        fields = line.split(",")
        values = [float(field) for field in fields[1:-2]]
        label = fields[-2] if fields[-2] else None
        target = float(fields[-1]) if fields[-1] else None
        rows.append(Row(fields[0], values, label, target))
    return header[1:-2], rows


def read_settings(path):
    entries = {}
    for line in read_lines(path):
        keyword, *values = line.split(" ")
        entries[keyword] = values
    return Settings(entries)


def read_dataset(directory):
    feature_names, train = read_rows(os.path.join(directory, "train.csv"))
    _, test = read_rows(os.path.join(directory, "test.csv"))
    settings = read_settings(os.path.join(directory, "params.txt"))
    return feature_names, train, test, settings
