"""Read the grain data and preserve every input sequence's order."""

import csv
from collections import namedtuple
from pathlib import Path
from types import SimpleNamespace


Row = namedtuple("Row", "id values label class_index")
Dataset = namedtuple("Dataset", "features classes train test costs params")


def read_table(path):
    with path.open(encoding="ascii", newline="") as source:
        records = csv.reader(source)
        features = next(records)[1:-1]
        rows = [
            (int(record[0]), [float(value) for value in record[1:-1]], record[-1])
            for record in records
        ]
    return features, rows


def read_parameters(path, features):
    values = {}
    subsets = []
    pairs = []
    feature_indices = {name: index for index, name in enumerate(features)}
    with path.open(encoding="ascii") as source:
        for line in source:
            keyword, *arguments = line.rstrip("\n").split(" ")
            if keyword == "SUBSET":
                name, *names = arguments
                subsets.append((name, tuple(feature_indices[item] for item in names)))
            elif keyword == "PAIR":
                pairs.append(tuple(feature_indices[item] for item in arguments))
            else:
                values[keyword] = arguments
    return SimpleNamespace(
        prior=values["PRIOR"][0],
        epsilon=float(values["VAR_SMOOTHING"][0]),
        smoothing_grid=[float(item) for item in values["SMOOTHING_GRID"]],
        gamma=float(values["QDA_GAMMA"][0]),
        gamma_grid=[float(item) for item in values["GAMMA_GRID"]],
        folds=int(values["CV_FOLDS"][0]),
        calibration_edges=[float(item) for item in values["CALIBRATION_EDGES"]],
        reject_thresholds=[float(item) for item in values["REJECT_THRESHOLDS"]],
        curve=[int(item) for item in values["CURVE"]],
        outlier_threshold=float(values["OUTLIER_THRESHOLD"][0]),
        bootstrap_count=int(values["BOOTSTRAP"][0]),
        seed=int(values["BOOTSTRAP"][1]),
        map_size=tuple(int(item) for item in values["MAP_SIZE"]),
        plot_size=tuple(int(item) for item in values["PLOT_SIZE"]),
        subsets=subsets,
        pairs=pairs,
    )


def read_costs(path, classes):
    with path.open(encoding="ascii", newline="") as source:
        records = csv.reader(source)
        columns = next(records)[1:]
        by_actual = {record[0]: [float(value) for value in record[1:]] for record in records}
    column_indices = [columns.index(name) for name in classes]
    return [[by_actual[name][column] for column in column_indices] for name in classes]


def read_inputs(directory="input"):
    directory = Path(directory)
    features, training_records = read_table(directory / "train.csv")
    _, test_records = read_table(directory / "test.csv")
    classes = sorted({label for _, _, label in training_records})
    class_indices = {name: index for index, name in enumerate(classes)}
    train = [Row(identifier, values, label, class_indices[label])
             for identifier, values, label in training_records]
    test = [Row(identifier, values, label, class_indices[label])
            for identifier, values, label in test_records]
    costs = read_costs(directory / "costs.csv", classes)
    params = read_parameters(directory / "params.txt", features)
    return Dataset(features, classes, train, test, costs, params)
