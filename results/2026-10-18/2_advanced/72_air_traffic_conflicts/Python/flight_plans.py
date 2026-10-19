"""Input readers and plan representations for the air-traffic benchmark."""

import csv
from pathlib import Path


def load_aircraft(path="input/aircraft.txt"):
    result = {}
    for line in Path(path).read_text(encoding="ascii").splitlines():
        name, climb, descent, minimum = line.split(" ")
        result[name] = {
            "climb": int(climb),
            "descent": int(descent),
            "minimum": int(minimum),
        }
    return result


def load_sectors(path="input/sectors.txt"):
    result = []
    for line in Path(path).read_text(encoding="ascii").splitlines():
        name, *raw = line.split(" ")
        x1, y1, x2, y2, lower, upper, capacity = map(int, raw)
        result.append({
            "name": name,
            "x1": x1, "y1": y1, "x2": x2, "y2": y2,
            "lower": lower, "upper": upper, "capacity": capacity,
            "index": len(result),
        })
    return result


def load_params(path="input/params.txt"):
    fields = [
        line.split(" ")
        for line in Path(path).read_text(encoding="ascii").splitlines()
    ]
    keys = ("separation", "lookahead", "max_delay", "levels",
            "sampling", "radar", "snapshots", "leader", "alert")
    if tuple(row[0] for row in fields) != keys:
        raise ValueError("unexpected parameter keys")
    values = [list(map(int, row[1:])) for row in fields]
    return {
        "dh": values[0][0],
        "dv": values[0][1],
        "lookahead": values[1][0],
        "max_delay": values[2][0],
        "level_min": values[3][0],
        "level_max": values[3][1],
        "sample_start": values[4][0],
        "sample_end": values[4][1],
        "radar": values[5],
        "snapshots": values[6],
        "leader": values[7][0],
        "alert": values[8][0],
    }


def parse_waypoints(text):
    waypoints = []
    for part in text.split(" "):
        words = part.split(":")
        waypoints.append({
            "x": int(words[0]),
            "y": int(words[1]),
            "level": int(words[2]) if len(words) == 3 else None,
        })
    return waypoints


def load_flights(path="input/flights.csv"):
    flights = {}
    with open(path, newline="", encoding="ascii") as handle:
        records = csv.DictReader(handle)
        for record in records:
            callsign = record["callsign"]
            flights[callsign] = {
                "callsign": callsign,
                "type": record["type"],
                "departure": int(record["departure_s"]),
                "level": int(record["level"]),
                "speed_initial": int(record["speed_kt"]),
                "speed": int(record["speed_kt"]),
                "waypoints": parse_waypoints(record["waypoints"]),
                "delay": 0,
                "offset": 0,
                "history": [],
            }
    return dict(sorted(flights.items()))


def clone_plan(plan):
    return {
        **plan,
        "history": list(plan["history"]),
    }


def level_list(plan):
    levels = [plan["level"] + plan["offset"]]
    for waypoint in plan["waypoints"][1:]:
        if waypoint["level"] is not None:
            levels.append(waypoint["level"] + plan["offset"])
    return levels


def load_all():
    return load_flights(), load_aircraft(), load_sectors(), load_params()
