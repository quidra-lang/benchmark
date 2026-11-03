"""Read smoothing data, retaining exact integer hundredths and input order."""

import csv
from pathlib import Path


def hundredths(text):
    return int(text.replace(".", ""))


def read_dataset():
    series = {}
    with open("input/series.csv", encoding="ascii", newline="") as handle:
        for row in csv.DictReader(handle):
            series.setdefault(row["series"], []).append(
                (hundredths(row["x"]), hundredths(row["y"]))
            )
    for points in series.values():
        points.sort(key=lambda point: point[0])
    with open("input/test_points.csv", encoding="ascii", newline="") as handle:
        tests = [(row["series"], hundredths(row["x"]))
                 for row in csv.DictReader(handle)]
    settings = {}
    for line in Path("input/params.txt").read_text(encoding="ascii").splitlines():
        key, *values = line.split(" ")
        settings[key] = values
    for key in ("ROBUST_ITERATIONS", "CV_FOLDS", "GRID_POINTS"):
        settings[key] = int(settings[key][0])
    for key in ("BAND_Z", "OUTLIER_THRESHOLD"):
        settings[key] = float(settings[key][0])
    for key in ("BOOTSTRAP", "PLOT_SIZE"):
        settings[key] = tuple(map(int, settings[key]))
    return series, tests, settings
