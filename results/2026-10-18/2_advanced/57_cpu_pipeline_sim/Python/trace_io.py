"""Read trace/configuration files and parse hexadecimal and register fields."""

import re
from pathlib import Path


HEX = re.compile(r"[0-9a-f]{8}\Z")
REGISTER = re.compile(r"r(?:[0-9]|[12][0-9]|3[01])\Z")


def parse_hex(text):
    return int(text, 16) if HEX.fullmatch(text) else None


def parse_register(text):
    return int(text[1:]) if REGISTER.fullmatch(text) else None


def read_inputs():
    trace = Path("input/trace.txt").read_text(encoding="ascii").splitlines()
    config = {"predictors": [], "variants": []}
    for line in Path("input/config.txt").read_text(encoding="ascii").splitlines():
        key, *values = line.split(" ")
        if key in ("BTB", "RAS", "TOP", "INTERVAL"):
            config[key.lower()] = int(values[0])
        elif key == "PREDICTOR":
            config["predictors"].append({"name": values[0], "scheme": values[1],
                                         "parameters": list(map(int, values[2:]))})
        elif key == "VARIANT":
            config["variants"].append({"name": values[0], "forwarding": values[1] == "ON",
                                       "stage": values[2], "latency": int(values[3])})
        elif key == "PRIMARY":
            config["primary"] = tuple(values)
        elif key == "WINDOW":
            config["window"] = tuple(map(int, values))
    return trace, config
