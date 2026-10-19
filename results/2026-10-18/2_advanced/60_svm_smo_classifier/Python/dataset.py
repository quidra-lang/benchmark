"""Read the four input files, preserving every specified example order."""

import csv
from collections import namedtuple
from types import SimpleNamespace

from kernels import Kernel


Example = namedtuple("Example", "id point label")
MulticlassExample = namedtuple("MulticlassExample", "id point class_number role")


def read_binary(path):
    examples = []
    with open(path, encoding="ascii", newline="") as source:
        rows = csv.reader(source)
        next(rows)
        for identifier, x1, x2, label in rows:
            examples.append(Example(identifier, (float(x1), float(x2)), int(label)))
    return examples


def read_multiclass(path):
    training = []
    testing = []
    with open(path, encoding="ascii", newline="") as source:
        rows = csv.reader(source)
        next(rows)
        for identifier, x1, x2, class_number, role in rows:
            example = MulticlassExample(
                identifier, (float(x1), float(x2)), int(class_number), role
            )
            (training if role == "train" else testing).append(example)
    return training, testing


def read_settings(path):
    settings = SimpleNamespace(kernels=[])
    with open(path, encoding="ascii") as source:
        for line in source:
            keyword, *values = line.split()
            match keyword:
                case "C_GRID":
                    settings.c_grid = [float(value) for value in values]
                case "KERNEL":
                    settings.kernels.append(Kernel(*values))
                case "TOLERANCE":
                    settings.tolerance = float(values[0])
                case "EPS":
                    settings.eps = float(values[0])
                case "MAX_PASSES":
                    settings.max_passes = int(values[0])
                case "FOLDS":
                    settings.folds = int(values[0])
                case "LEARNING_CURVE":
                    settings.learning_curve = [int(value) for value in values]
                case "NEWTON_ITERATIONS":
                    settings.newton_iterations = int(values[0])
                case "MULTICLASS":
                    settings.multiclass = (values[0], float(values[1]))
                case "PEGASOS":
                    settings.pegasos = (float(values[0]), int(values[1]), int(values[2]))
                case "PLOT_X":
                    settings.plot_x = tuple(float(value) for value in values)
                case "PLOT_Y":
                    settings.plot_y = tuple(float(value) for value in values)
                case "PLOT_SIZE":
                    settings.plot_size = tuple(int(value) for value in values)
    return settings


def read_inputs():
    training = read_binary("input/train.csv")
    testing = read_binary("input/test.csv")
    multi_training, multi_testing = read_multiclass("input/multiclass.csv")
    settings = read_settings("input/params.txt")
    return training, testing, multi_training, multi_testing, settings
