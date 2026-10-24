import os


MISSING = "?"


class Attribute:
    def __init__(self, index, name, kind, values):
        self.index = index
        self.name = name
        self.integer = kind == "INT"
        self.values = values
        self.positions = {value: position for position, value in enumerate(values)}

    def parse(self, text):
        if text == MISSING:
            return None
        if self.integer:
            return int(text)
        return self.positions[text]


class Row:
    def __init__(self, ident, values, label):
        self.ident = ident
        self.values = values
        self.label = label

    def value(self, attribute):
        return self.values[attribute.index]

    def missing_count(self):
        return sum(value is None for value in self.values)


class Settings:
    def __init__(self, entries):
        self.max_depth = int(entries["MAX_DEPTH"][0])
        self.min_samples_split = int(entries["MIN_SAMPLES_SPLIT"][0])
        self.min_samples_leaf = int(entries["MIN_SAMPLES_LEAF"][0])
        self.max_surrogates = int(entries["MAX_SURROGATES"][0])
        self.folds = int(entries["FOLDS"][0])
        self.curve = [int(value) for value in entries["CURVE"]]
        self.bag_trees = int(entries["BAG_TREES"][0])
        self.bag_seed = int(entries["BAG_SEED"][0])
        self.permutation_repeats = int(entries["PERMUTATION_REPEATS"][0])
        self.permutation_seed = int(entries["PERMUTATION_SEED"][0])


class Dataset:
    def __init__(self, attributes, target, classes, train, validation, test, settings):
        self.attributes = attributes
        self.target = target
        self.classes = classes
        self.train = train
        self.validation = validation
        self.test = test
        self.settings = settings


def read_lines(path):
    with open(path) as file:
        return file.read().splitlines()


def read_schema(path):
    attributes = []
    target = None
    classes = []
    for line in read_lines(path):
        keyword, name, *rest = line.split(" ")
        if keyword == "ATTRIBUTE":
            attributes.append(Attribute(len(attributes), name, rest[0], rest[1:]))
        else:
            target = name
            classes = rest
    return attributes, target, classes


def read_rows(path, attributes, classes):
    positions = {name: index for index, name in enumerate(classes)}
    rows = []
    for line in read_lines(path)[1:]:
        fields = line.split(",")
        values = [attribute.parse(text) for attribute, text in zip(attributes, fields[1:-1])]
        rows.append(Row(fields[0], values, positions[fields[-1]]))
    return rows


def read_settings(path):
    entries = {}
    for line in read_lines(path):
        keyword, *values = line.split(" ")
        entries[keyword] = values
    return Settings(entries)


def load_dataset(directory):
    attributes, target, classes = read_schema(os.path.join(directory, "schema.txt"))
    train = read_rows(os.path.join(directory, "train.csv"), attributes, classes)
    validation = read_rows(os.path.join(directory, "validation.csv"), attributes, classes)
    test = read_rows(os.path.join(directory, "test.csv"), attributes, classes)
    settings = read_settings(os.path.join(directory, "params.txt"))
    return Dataset(attributes, target, classes, train, validation, test, settings)
