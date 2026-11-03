"""File input, year-month arithmetic and fixed-decimal output."""

import csv
from pathlib import Path


def rows(name):
    with open(Path("input") / name, encoding="ascii", newline="") as handle:
        return list(csv.DictReader(handle))


def read_inputs():
    series = {}
    for row in rows("series.csv"):
        record = series.setdefault(row["series"], {"periods": [], "raw": []})
        record["periods"].append(row["period"])
        record["raw"].append(None if row["value"] == "NA" else int(row["value"]))
    events = {name: {} for name in series}
    for row in rows("events.csv"):
        events[row["series"]][row["period"]] = row["kind"]
    inventory = {}
    for row in rows("inventory.csv"):
        inventory[row["series"]] = {
            "on_hand": int(row["on_hand"]), "lead_time": int(row["lead_time"]),
            "review": int(row["review"]), "service": float(row["service"]),
        }
    settings = {}
    for line in Path("input/params.txt").read_text(encoding="ascii").splitlines():
        key, *values = line.split(" ")
        if key in ("alpha", "beta", "gamma", "phi", "interval"):
            settings[key] = list(map(float, values))
        elif key == "ljung_box":
            settings[key] = list(map(int, values))
        elif key == "outlier":
            settings[key] = float(values[0])
        else:
            settings[key] = int(values[0])
    return series, events, inventory, settings


def next_month(period):
    year, month = map(int, period.split("-"))
    year += month // 12
    month = month % 12 + 1
    return f"{year:04d}-{month:02d}"


def real(value):
    if value is None:
        return "NA"
    result = f"{value:.4f}"
    return "0.0000" if result == "-0.0000" else result


def write_lines(name, lines):
    target = Path("output") / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("\n".join(lines) + "\n", encoding="ascii")
