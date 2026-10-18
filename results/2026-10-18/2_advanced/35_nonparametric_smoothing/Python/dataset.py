import os


class Points:
    def __init__(self, xs, ys):
        self.X = xs
        self.Y = ys
        self.x = [value / 100 for value in xs]
        self.y = [value / 100 for value in ys]
        self.n = len(xs)


class Series:
    def __init__(self, name):
        self.name = name
        self.pairs = []
        self.points = None


class TestPoint:
    def __init__(self, series, position):
        self.series = series
        self.position = position


class Candidate:
    def __init__(self, text, value):
        self.text = text
        self.value = value


class Settings:
    def __init__(self, entries):
        self.windows = [Candidate(text, int(text)) for text in entries["WINDOWS"]]
        self.kernels = entries["KERNELS"]
        self.bandwidths = [Candidate(text, hundredths(text)) for text in entries["BANDWIDTHS"]]
        self.degrees = [int(text) for text in entries["LOESS_DEGREES"]]
        self.spans = [Candidate(text, hundredths(text)) for text in entries["SPANS"]]
        self.iterations = int(entries["ROBUST_ITERATIONS"][0])
        self.lambdas = [Candidate(text, float(text)) for text in entries["LAMBDAS"]]
        self.folds = int(entries["CV_FOLDS"][0])
        self.isotonic = entries["ISOTONIC"]
        self.grid_points = int(entries["GRID_POINTS"][0])
        self.band_z = float(entries["BAND_Z"][0])
        self.band_methods = entries["BAND_METHODS"]
        self.threshold = hundredths(entries["OUTLIER_THRESHOLD"][0])
        self.replicates, self.trim, self.seed = (int(text) for text in entries["BOOTSTRAP"])
        self.plot_series = entries["PLOT_SERIES"]
        self.plot_methods = entries["PLOT_METHODS"]
        self.width, self.height = (int(text) for text in entries["PLOT_SIZE"])


class Dataset:
    def __init__(self, series, tests, settings):
        self.series = series
        self.tests = tests
        self.settings = settings


def hundredths(text):
    negative = text.startswith("-")
    whole, fraction = text.lstrip("-").split(".")
    value = int(whole) * 100 + int(fraction)
    return -value if negative else value


def read_lines(path):
    with open(path) as file:
        return file.read().splitlines()


def read_series(path):
    series = []
    by_name = {}
    for line in read_lines(path)[1:]:
        name, x_text, y_text = line.split(",")
        if name not in by_name:
            by_name[name] = Series(name)
            series.append(by_name[name])
        by_name[name].pairs.append((hundredths(x_text), hundredths(y_text)))
    for item in series:
        item.pairs.sort()
        item.points = Points([x for x, _ in item.pairs], [y for _, y in item.pairs])
    return series


def read_tests(path):
    tests = []
    for line in read_lines(path)[1:]:
        name, x_text = line.split(",")
        tests.append(TestPoint(name, hundredths(x_text)))
    return tests


def read_settings(path):
    entries = {}
    for line in read_lines(path):
        keyword, *values = line.split(" ")
        entries[keyword] = values
    return Settings(entries)


def load_dataset(folder):
    series = read_series(os.path.join(folder, "series.csv"))
    tests = read_tests(os.path.join(folder, "test_points.csv"))
    settings = read_settings(os.path.join(folder, "params.txt"))
    return Dataset(series, tests, settings)
