import os


class Group:
    def __init__(self, number, name):
        self.number = number
        self.name = name
        self.values = []


class PairedSample:
    def __init__(self, before, after):
        self.before = before
        self.after = after
        self.differences = [second - first for first, second in zip(before, after)]


class Settings:
    def __init__(self, entries, comparisons):
        self.seed = entries["seed"][0]
        self.bootstrap = entries["bootstrap"][0]
        self.permutations = entries["permutations"][0]
        self.confidence = entries["confidence"][0]
        self.pilot = entries["pilot"][0]
        self.power_sims, self.power_perms = entries["power"]
        self.bins = entries["bins"][0]
        self.comparisons = comparisons


class Dataset:
    def __init__(self, groups, paired, settings):
        self.groups = groups
        self.paired = paired
        self.settings = settings
        by_name = {group.name: group for group in groups}
        self.pairs = [(by_name[first], by_name[second]) for first, second in settings.comparisons]


def hundredths(text):
    whole, _, fraction = text.partition(".")
    return int(whole) * 100 + int(fraction.ljust(2, "0"))


def read_lines(path):
    with open(path) as file:
        return file.read().splitlines()


def read_groups(path):
    groups = []
    by_name = {}
    for line in read_lines(path)[1:]:
        name, value = line.split(",")
        if name not in by_name:
            by_name[name] = Group(len(groups) + 1, name)
            groups.append(by_name[name])
        by_name[name].values.append(hundredths(value))
    return groups


def read_paired(path):
    before = []
    after = []
    for line in read_lines(path)[1:]:
        _, first, second = line.split(",")
        before.append(hundredths(first))
        after.append(hundredths(second))
    return PairedSample(before, after)


def read_settings(path):
    entries = {}
    comparisons = []
    for line in read_lines(path):
        name, *values = line.split(" ")
        if name == "compare":
            comparisons.append((values[0], values[1]))
        else:
            entries[name] = [int(value) for value in values]
    return Settings(entries, comparisons)


def load_dataset(folder):
    groups = read_groups(os.path.join(folder, "samples.csv"))
    paired = read_paired(os.path.join(folder, "paired.csv"))
    settings = read_settings(os.path.join(folder, "params.txt"))
    return Dataset(groups, paired, settings)
