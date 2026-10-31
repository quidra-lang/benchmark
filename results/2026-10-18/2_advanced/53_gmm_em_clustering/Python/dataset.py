"""Read planar observations, initial Gaussian mixtures, and analysis parameters."""

import csv
from pathlib import Path


def read_points(path="input/points.csv"):
    with open(path, encoding="ascii", newline="") as handle:
        records = list(csv.reader(handle))
    return [
        {"id": row[0], "x": float(row[1]), "y": float(row[2])}
        for row in records[1:]
    ]


def read_initial(path="input/init.txt"):
    text = Path(path).read_text(encoding="ascii")
    result = {}
    for block in text.strip().split("\n\n"):
        rows = block.splitlines()
        k = int(rows[0].split(" ")[1])
        weights = [float(x) for x in rows[1].split(" ")[1:]]
        means = []
        covariances = []
        for row in rows[2:]:
            _, index, x, y, a, b, c = row.split(" ")
            means.append((float(x), float(y)))
            covariances.append((float(a), float(b), float(c)))
        result[k] = {
            "weights": weights, "means": means,
            "covariances": covariances,
        }
    return result


def read_parameters(path="input/params.txt"):
    lines = [
        line.split(" ") for line in
        Path(path).read_text(encoding="ascii").splitlines()
    ]
    raw = {line[0]: line[1:] for line in lines}
    return {
        "ks": list(map(int, raw["K"])),
        "iterations": int(raw["ITERATIONS"][0]),
        "types": raw["TYPES"],
        "epsilon": float(raw["REGULARIZATION"][0]),
        "settle": float(raw["SETTLE_TOLERANCE"][0]),
        "kmeans_iterations": int(raw["KMEANS_MAX_ITERATIONS"][0]),
        "cv_folds": int(raw["CV_FOLDS"][0]),
        "uncertain": float(raw["UNCERTAIN_THRESHOLD"][0]),
        "low_density": float(raw["LOW_DENSITY_THRESHOLD"][0]),
        "gof_edges": list(map(float, raw["GOF_EDGES"])),
        "map_x": tuple(map(float, raw["MAP_X"])),
        "map_y": tuple(map(float, raw["MAP_Y"])),
        "map_size": tuple(map(int, raw["MAP_SIZE"])),
    }


def read_all():
    return read_points(), read_initial(), read_parameters()
