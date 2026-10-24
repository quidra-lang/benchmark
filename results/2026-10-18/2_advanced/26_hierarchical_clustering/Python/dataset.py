class Observation:
    def __init__(self, ident, label, values):
        self.ident = ident
        self.label = label
        self.values = values


class Settings:
    def __init__(self, entries):
        self.distance = entries["DISTANCE"][0]
        self.standardize = entries["STANDARDIZE"][0]
        self.linkages = entries["LINKAGES"]
        self.cut_heights = [float(value) for value in entries["CUT_HEIGHTS"]]
        self.cut_counts = [int(value) for value in entries["CUT_K"]]
        self.inconsistency_depth = int(entries["INCONSISTENCY"][0])
        self.inconsistency_count = int(entries["INCONSISTENCY"][1])
        self.gap_max_k = int(entries["GAP_MAX_K"][0])
        self.list_size = int(entries["LIST_SIZE"][0])
        self.width = int(entries["DENDROGRAM_WIDTH"][0])
        self.compare_linkage = entries["COMPARE_LINKAGE"][0]
        self.replicates = int(entries["SUBSAMPLES"][0])
        self.percent = int(entries["SUBSAMPLES"][1])
        self.seed = int(entries["SUBSAMPLES"][2])
        self.refine_iterations = int(entries["REFINE_ITERATIONS"][0])


def read_lines(path):
    with open(path) as file:
        return file.read().splitlines()


def read_observations(path):
    lines = read_lines(path)
    feature_names = lines[0].split(",")[2:]
    observations = []
    for line in lines[1:]:
        ident, label, *values = line.split(",")
        observations.append(Observation(ident, label, [float(value) for value in values]))
    return feature_names, observations


def read_settings(path):
    entries = {}
    for line in read_lines(path):
        keyword, *values = line.split(" ")
        entries[keyword] = values
    return Settings(entries)


def write_lines(path, lines):
    with open(path, "w") as file:
        file.write("".join(line + "\n" for line in lines))
