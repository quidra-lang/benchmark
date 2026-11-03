"""Read MLP images, network architectures, initial parameters and runs."""

import csv
from pathlib import Path


class MINSTD:
    def __init__(self, seed):
        self.state = seed

    def draw(self):
        self.state = (48271 * self.state) % 2147483647
        return self.state

    def shuffle(self, values):
        for i in range(len(values), 1, -1):
            j = self.draw() % i
            values[i - 1], values[j] = values[j], values[i - 1]


def read_images(path):
    with open(path, encoding="ascii", newline="") as handle:
        rows = list(csv.reader(handle))[1:]
    return [
        {
            "id": identifier, "label": int(label),
            "pixels": pixels,
            "vector": [float(digit) for digit in pixels],
        }
        for identifier, label, pixels in rows
    ]


def read_architectures(path="input/network.txt"):
    text = Path(path).read_text(encoding="ascii").strip()
    dimensions, *blocks = text.split("\n\n")
    _, width, height = dimensions.split()
    width, height = int(width), int(height)
    networks = []
    for block in blocks:
        lines = block.splitlines()
        name = lines[0].split()[1]
        layers = []
        for line in lines[1:]:
            kind, units, activation = line.split()
            layers.append({
                "units": int(units),
                "activation": activation,
                "kind": kind,
            })
        networks.append({
            "name": name, "layers": layers,
            "width": width, "height": height,
            "classes": layers[-1]["units"],
        })
    return networks


def read_weights(networks, path="input/weights.txt"):
    blocks = Path(path).read_text(encoding="ascii").strip().split("\n\n")
    results = {}
    for network, block in zip(networks, blocks):
        lines = block.splitlines()
        cursor = 1
        theta = []
        for _ in network["layers"]:
            _, layer_number, rows, columns = lines[cursor].split()
            cursor += 1
            for _ in range(int(rows)):
                weights = lines[cursor].split()
                theta.extend(float(value) for value in weights[1:])
                cursor += 1
            biases = lines[cursor].split()
            theta.extend(float(value) for value in biases[1:])
            cursor += 1
        results[network["name"]] = theta
    return results


def read_settings(path="input/params.txt"):
    settings = {"runs": []}
    for line in Path(path).read_text(encoding="ascii").splitlines():
        kind, *items = line.split()
        if kind == "RUN":
            name, network, optimizer, rate, decay, *extra = items
            settings["runs"].append({
                "name": name, "network": network, "optimizer": optimizer,
                "rate": float(rate), "decay": float(decay),
                "extra": list(map(float, extra)),
            })
        elif kind == "LR_STEP":
            settings["lr_step"] = int(items[0])
            settings["lr_gamma"] = float(items[1])
        elif kind in ("PRUNE", "NOISE"):
            settings[kind.lower()] = list(map(int, items))
        else:
            key = {
                "SEED": "seed", "BATCH_SIZE": "batch_size",
                "MAX_EPOCHS": "max_epochs", "PATIENCE": "patience",
                "GRADIENT_CHECK_STRIDE": "gradient_stride",
                "CALIBRATION_BINS": "calibration_bins",
            }[kind]
            settings[key] = int(items[0])
    return settings


def load_inputs():
    networks = read_architectures()
    return {
        "train": read_images("input/train.csv"),
        "test": read_images("input/test.csv"),
        "networks": networks,
        "weights": read_weights(networks),
        "settings": read_settings(),
    }
