"""Parse seismic-station geometry, recorded samples, and all 24 settings."""

import csv
from pathlib import Path


PARAMETERS = (
    "sta_window", "lta_window", "trigger_on", "trigger_off",
    "min_duration", "noise_level", "amplitude_window", "clip_level",
    "association_window", "min_stations", "velocity",
    "grid_x", "grid_y", "grid_z", "residual_limit",
    "quality_a", "quality_b", "cluster", "local_magnitude",
    "duration_magnitude", "map_area", "map_size", "section", "timeline",
)


def read_stations(filename="input/stations.csv"):
    with open(filename, encoding="ascii", newline="") as handle:
        rows = list(csv.reader(handle))[1:]
    return [
        {"code":row[0],"x":int(row[1]),"y":int(row[2]),
         "elevation":int(row[3]),"order":index}
        for index,row in enumerate(rows)
    ]


def read_waveforms(filename="input/waveforms.txt"):
    lines = Path(filename).read_text(encoding="ascii").splitlines()
    result = {}
    cursor = 0
    while cursor < len(lines):
        tokens = lines[cursor].split(" ")
        _, code, start, count = tokens
        start, count = int(start), int(count)
        cursor += 1
        samples = []
        while len(samples) < count:
            samples.extend(map(int, lines[cursor].split(" ")))
            cursor += 1
        result[code] = {"start":start,"samples":samples}
    return result


def read_params(filename="input/params.txt"):
    lines = Path(filename).read_text(encoding="ascii").splitlines()
    params = {}
    if len(lines) != len(PARAMETERS):
        raise ValueError("unexpected settings count")
    for name, line in zip(PARAMETERS, lines):
        tokens = line.split(" ")
        if tokens[0] != name:
            raise ValueError("unexpected settings order")
        if name in (
            "velocity", "residual_limit", "quality_a", "quality_b",
            "cluster", "local_magnitude", "duration_magnitude",
        ):
            values = [float(word) for word in tokens[1:]]
        else:
            values = list(map(int, tokens[1:]))
        params[name] = values if len(values) > 1 else values[0]
    return params


def load_inputs():
    stations = read_stations()
    waveforms = read_waveforms()
    params = read_params()
    for station in stations:
        station.update(waveforms[station["code"]])
    return stations, params
