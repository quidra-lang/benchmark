import os


MISSING_VALUE = "NA"


class Table:
    def __init__(self, names, ids, rows):
        self.names = names
        self.ids = ids
        self.rows = rows


class Settings:
    def __init__(self, entries):
        self.missing = entries["MISSING"][0]
        self.scaling = entries["SCALING"][0]
        self.components = entries["COMPONENTS"][0]
        self.cumulative_target = float(entries["CUMULATIVE_TARGET"][0])
        self.parallel_iterations = int(entries["PARALLEL"][0])
        self.seed = int(entries["PARALLEL"][1])
        self.t2_limit = float(entries["T2_LIMIT"][0])
        self.spe_limit = float(entries["SPE_LIMIT"][0])
        self.varimax_cycles = int(entries["VARIMAX_CYCLES"][0])
        self.top_rows = int(entries["TOP_ROWS"][0])
        self.scree_width = int(entries["SCREE_WIDTH"][0])
        self.biplot_width = int(entries["BIPLOT_SIZE"][0])
        self.biplot_height = int(entries["BIPLOT_SIZE"][1])
        self.circle_radius = int(entries["CIRCLE_RADIUS"][0])
        self.diagnostic_width = int(entries["DIAGNOSTIC_SIZE"][0])
        self.diagnostic_height = int(entries["DIAGNOSTIC_SIZE"][1])


class Dataset:
    def __init__(self, data, supplementary, settings):
        self.data = data
        self.supplementary = supplementary
        self.settings = settings


def read_lines(path):
    with open(path) as file:
        return file.read().splitlines()


def parse_value(text):
    if text == MISSING_VALUE:
        return None
    return float(text)


def read_table(path):
    lines = read_lines(path)
    names = lines[0].split(",")[1:]
    ids = []
    rows = []
    for line in lines[1:]:
        row_id, *values = line.split(",")
        ids.append(row_id)
        rows.append([parse_value(text) for text in values])
    return Table(names, ids, rows)


def read_settings(path):
    entries = {}
    for line in read_lines(path):
        keyword, *values = line.split(" ")
        entries[keyword] = values
    return Settings(entries)


def load_dataset(directory):
    data = read_table(os.path.join(directory, "data.csv"))
    supplementary = read_table(os.path.join(directory, "supplementary.csv"))
    settings = read_settings(os.path.join(directory, "params.txt"))
    return Dataset(data, supplementary, settings)
