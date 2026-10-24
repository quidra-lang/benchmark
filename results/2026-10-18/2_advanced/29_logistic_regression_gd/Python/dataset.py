from itertools import combinations_with_replacement
import math
import os


class Example:
    def __init__(self, ident, values, label):
        self.ident = ident
        self.values = values
        self.label = label


class Settings:
    def __init__(self, entries):
        self.positive = int(entries["POSITIVE"][0])
        self.degree = int(entries["DEGREE"][0])
        self.threshold = float(entries["THRESHOLD"][0])
        self.lambdas = [float(value) for value in entries["LAMBDAS"]]
        self.gd_rate = float(entries["GD"][0])
        self.gd_iterations = int(entries["GD"][1])
        self.sgd_rate = float(entries["SGD"][0])
        self.batch_size = int(entries["SGD"][1])
        self.epochs = int(entries["SGD"][2])
        self.sgd_seed = int(entries["SGD"][3])
        self.softmax_rate = float(entries["SOFTMAX"][0])
        self.softmax_iterations = int(entries["SOFTMAX"][1])
        self.softmax_lambda = float(entries["SOFTMAX"][2])
        self.bootstrap_count = int(entries["BOOTSTRAP"][0])
        self.bootstrap_seed = int(entries["BOOTSTRAP"][1])
        self.permutation_count = int(entries["PERMUTATION"][0])
        self.permutation_seed = int(entries["PERMUTATION"][1])
        self.map_width = int(entries["MAP"][0])
        self.map_height = int(entries["MAP"][1])
        self.cost_fp = int(entries["COST"][0])
        self.cost_fn = int(entries["COST"][1])


class Statistics:
    def __init__(self, means, deviations):
        self.means = means
        self.deviations = deviations


def read_lines(path):
    with open(path) as file:
        return file.read().splitlines()


def read_examples(path):
    lines = read_lines(path)
    names = lines[0].split(",")[1:-1]
    examples = []
    for line in lines[1:]:
        fields = line.split(",")
        values = [float(field) for field in fields[1:-1]]
        examples.append(Example(fields[0], values, int(fields[-1])))
    return names, examples


def read_settings(path):
    entries = {}
    for line in read_lines(path):
        keyword, *values = line.split(" ")
        entries[keyword] = values
    return Settings(entries)


def read_inputs(directory):
    names, train = read_examples(os.path.join(directory, "train.csv"))
    _, test = read_examples(os.path.join(directory, "test.csv"))
    settings = read_settings(os.path.join(directory, "params.txt"))
    return names, train, test, settings


def expansion_tuples(base_count, degree):
    tuples = []
    for length in range(1, degree + 1):
        tuples.extend(combinations_with_replacement(range(base_count), length))
    return tuples


def expanded_names(names, tuples):
    return ["*".join(names[index] for index in indices) for indices in tuples]


def expanded_values(tuples, values):
    expanded = []
    for indices in tuples:
        product = values[indices[0]]
        for index in indices[1:]:
            product *= values[index]
        expanded.append(product)
    return expanded


def compute_statistics(rows, count):
    size = len(rows)
    means = []
    deviations = []
    for j in range(count):
        total = 0.0
        for row in rows:
            total += row[j]
        mean = total / size
        squares = 0.0
        for row in rows:
            squares += (row[j] - mean) * (row[j] - mean)
        means.append(mean)
        deviations.append(math.sqrt(squares / (size - 1)))
    return Statistics(means, deviations)


def standardize(values, statistics, count):
    vector = [1.0]
    for j in range(count):
        vector.append((values[j] - statistics.means[j]) / statistics.deviations[j])
    return vector
