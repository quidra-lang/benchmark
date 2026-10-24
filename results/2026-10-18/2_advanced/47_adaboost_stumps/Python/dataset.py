"""Read the binary data, multi-class data, and ordered experiment settings."""

import csv
from collections import namedtuple
from pathlib import Path
from types import SimpleNamespace


Row = namedtuple("Row", "id values label")
Inputs = namedtuple(
    "Inputs", "features train test multi_features multi_train multi_test params"
)


def read_binary(path):
    with path.open(encoding="ascii", newline="") as source:
        records = csv.reader(source)
        features = next(records)[1:-1]
        rows = [
            Row(fields[0], tuple(map(float, fields[1:-1])), int(fields[-1]))
            for fields in records
        ]
    return features, rows


def read_multiclass(path):
    training = []
    testing = []
    with path.open(encoding="ascii", newline="") as source:
        records = csv.reader(source)
        features = next(records)[1:-2]
        for fields in records:
            row = Row(fields[0], tuple(map(float, fields[1:-2])), int(fields[-2]))
            destination = training if fields[-1] == "train" else testing
            destination.append(row)
    return features, training, testing


def read_params(path):
    with path.open(encoding="ascii") as source:
        fields = dict(line.rstrip("\n").split(" ", 1) for line in source)
    noise = list(map(int, fields["NOISE"].split()))
    return SimpleNamespace(
        rounds=int(fields["ROUNDS"]),
        variants=fields["VARIANTS"].split(),
        bins=int(fields["BINS"]),
        smoothing=float(fields["SMOOTHING"]),
        convergence=float(fields["CONVERGENCE"]),
        clip=float(fields["CLIP"]),
        folds=int(fields["FOLDS"]),
        margins=list(map(float, fields["MARGINS"].split())),
        classes=int(fields["CLASSES"]),
        samme_rounds=int(fields["SAMME_ROUNDS"]),
        permutation=tuple(map(int, fields["PERMUTATION"].split())),
        noise_seed=noise[0],
        noise=noise[1:],
        sizes=list(map(int, fields["SIZES"].split())),
        shrinkage=list(map(float, fields["SHRINKAGE"].split())),
        bootstrap=tuple(map(int, fields["BOOTSTRAP"].split())),
    )


def read_inputs(directory="input"):
    directory = Path(directory)
    features, training = read_binary(directory / "train.csv")
    _, testing = read_binary(directory / "test.csv")
    multi_features, multi_training, multi_testing = read_multiclass(
        directory / "multiclass.csv"
    )
    params = read_params(directory / "params.txt")
    return Inputs(
        features, training, testing,
        multi_features, multi_training, multi_testing, params,
    )
