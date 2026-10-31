CONTROL_CONSTANTS = {
    2: (1.880, 2.659, 0.0, 3.267, 0.0, 3.267, 1.128, 0.7979),
    3: (1.023, 1.954, 0.0, 2.568, 0.0, 2.574, 1.693, 0.8862),
    4: (0.729, 1.628, 0.0, 2.266, 0.0, 2.282, 2.059, 0.9213),
    5: (0.577, 1.427, 0.0, 2.089, 0.0, 2.114, 2.326, 0.9400),
    6: (0.483, 1.287, 0.030, 1.970, 0.0, 2.004, 2.534, 0.9515),
    7: (0.419, 1.182, 0.118, 1.882, 0.076, 1.924, 2.704, 0.9594),
    8: (0.373, 1.099, 0.185, 1.815, 0.136, 1.864, 2.847, 0.9650),
    9: (0.337, 1.032, 0.239, 1.761, 0.184, 1.816, 2.970, 0.9693),
    10: (0.308, 0.975, 0.284, 1.716, 0.223, 1.777, 3.078, 0.9727),
}


class ControlConstants:
    def __init__(self, a2, a3, b3, b4, d3, d4, d2, c4):
        self.a2 = a2
        self.a3 = a3
        self.b3 = b3
        self.b4 = b4
        self.d3 = d3
        self.d4 = d4
        self.d2 = d2
        self.c4 = c4


class Settings:
    def __init__(self, fields, rules):
        self.characteristic = fields["characteristic"]
        self.lsl = int(fields["lsl"])
        self.usl = int(fields["usl"])
        self.target = int(fields["target"])
        self.subgroup_size = int(fields["subgroup_size"])
        self.phase1_subgroups = int(fields["phase1_subgroups"])
        self.max_passes = int(fields["max_passes"])
        self.rules = rules
        self.cusum_k = float(fields["cusum_k"])
        self.cusum_h = float(fields["cusum_h"])
        self.ewma_lambda = float(fields["ewma_lambda"])
        self.ewma_l = float(fields["ewma_l"])
        self.ma_span = int(fields["ma_span"])
        self.event_gap = int(fields["event_gap"])
        self.ci_z = float(fields["ci_z"])
        self.histogram_bin = int(fields["histogram_bin"])
        self.rolling_window = int(fields["rolling_window"])
        self.rolling_step = int(fields["rolling_step"])


class Lot:
    def __init__(self, number, inspected, defectives, defects):
        self.number = number
        self.inspected = inspected
        self.defectives = defectives
        self.defects = defects


def control_constants(size):
    return ControlConstants(*CONTROL_CONSTANTS[size])


def read_rows(path):
    with open(path) as handle:
        lines = handle.read().splitlines()
    return [[int(field) for field in line.split(",")] for line in lines[1:]]


def read_measurements(path):
    return [value for _, _, value in read_rows(path)]


def read_attributes(path):
    return [Lot(*row) for row in read_rows(path)]


def read_settings(path):
    fields = {}
    rules = {}
    with open(path) as handle:
        for line in handle:
            name, *values = line.split()
            if name == "rules":
                rules[values[0]] = [int(value) for value in values[1:]]
            else:
                fields[name] = values[0]
    return Settings(fields, rules)
