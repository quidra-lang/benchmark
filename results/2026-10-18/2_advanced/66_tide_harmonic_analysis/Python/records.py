"""Parse the tide-gauge inputs and convert Gregorian times to epoch offsets."""

import csv
from datetime import datetime, timedelta
from pathlib import Path


DATE_FORMAT = "%Y-%m-%d %H:%M"


def parse_datetime(text):
    return datetime.strptime(text, DATE_FORMAT)


def parse_settings(path="input/params.txt"):
    lines = Path(path).read_text(encoding="ascii").splitlines()
    epoch = parse_datetime(lines[0][len("epoch "):])
    stations = []
    cursor = 1
    while lines[cursor].startswith("station "):
        _, code, name = lines[cursor].split(" ", 2)
        stations.append({"code": code, "name": name})
        cursor += 1
    values = {}
    for line in lines[cursor:]:
        keyword, argument = line.split(" ", 1)
        values[keyword] = argument
    spike = values["spike"].split()
    surge = values["surge"].split()
    prediction = values["predict"].split()
    plot = values["plot"].split()
    return {
        "epoch": epoch,
        "stations": stations,
        "reference": values["reference"],
        "flat_run": int(values["flat_run"]),
        "spike_window": int(spike[0]),
        "spike_minimum": int(spike[1]),
        "spike_factor": float(spike[2]),
        "spike_floor": float(spike[3]),
        "rayleigh": float(values["rayleigh"]),
        "snr_min": float(values["snr_min"]),
        "top_residuals": int(values["top_residuals"]),
        "surge_threshold": float(surge[0]),
        "surge_hours": int(surge[1]),
        "prediction_start": parse_datetime(" ".join(prediction[:2])),
        "prediction_hours": int(prediction[2]),
        "grid_minutes": int(values["grid_minutes"]),
        "min_range": float(values["min_range"]),
        "correlation_lag": int(values["correlation_lag"]),
        "plot_code": plot[0],
        "plot_hours": int(plot[1]),
        "plot_top": int(plot[2]),
        "plot_bottom": int(plot[3]),
        "plot_step": int(plot[4]),
    }


def epoch_hours(epoch, instant):
    delta = instant - epoch
    return delta.days * 24 + delta.seconds // 3600


def epoch_minutes(epoch, instant):
    delta = instant - epoch
    return delta.days * 1440 + delta.seconds // 60


def datetime_at_hour(epoch, hour):
    return (epoch + timedelta(hours=hour)).strftime(DATE_FORMAT)


def datetime_at_minute(epoch, minute):
    return (epoch + timedelta(minutes=minute)).strftime(DATE_FORMAT)


def date_at_hour(epoch, hour):
    return (epoch + timedelta(hours=hour)).date()


def date_at_minute(epoch, minute):
    return (epoch + timedelta(minutes=minute)).date()


def noon_hour(epoch, date):
    noon = datetime(date.year, date.month, date.day, 12, 0)
    return epoch_hours(epoch, noon)


def read_constituents(path="input/constituents.txt"):
    lines = Path(path).read_text(encoding="ascii").splitlines()
    count = int(lines[0])
    if count != len(lines) - 1:
        raise ValueError("constituent count mismatch")
    result = []
    for line in lines[1:]:
        name, speed = line.split(" ")
        result.append({"name": name, "speed": float(speed)})
    return result


def read_observations(epoch, stations, path="input/observations.csv"):
    table = {station["code"]: {"values": {}, "rows": 0} for station in stations}
    with open(path, encoding="ascii", newline="") as handle:
        for row in list(csv.reader(handle))[1:]:
            code, time_text, value_text = row
            hour = epoch_hours(epoch, parse_datetime(time_text))
            table[code]["values"][hour] = None if value_text == "NA" else float(value_text)
            table[code]["rows"] += 1
    return table


def read_all_inputs():
    settings = parse_settings()
    constituents = read_constituents()
    observations = read_observations(settings["epoch"], settings["stations"])
    return settings, constituents, observations
