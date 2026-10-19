"""Read the valid ASCII trial records and ordered settings."""

import csv


def read_dataset(directory):
    subjects = []
    with (directory / "subjects.csv").open(encoding="ascii", newline="") as source:
        for row in csv.DictReader(source):
            subjects.append({
                "id": int(row["id"]),
                "group": row["group"],
                "time": int(row["time_days"]),
                "event": int(row["event"]),
                "age": int(row["age"]),
                "sex": row["sex"],
                "stage": int(row["stage"]),
            })
    subjects.sort(key=lambda subject: subject["id"])
    settings = {}
    for line in (directory / "params.txt").read_text(encoding="ascii").splitlines():
        name, *values = line.split()
        settings[name] = values
    params = {
        "groups": settings["GROUPS"],
        "report_times": [int(value) for value in settings["REPORT_TIMES"]],
        "tau": int(settings["TAU"][0]),
        "life_table": tuple(int(value) for value in settings["LIFE_TABLE"]),
        "strata": settings["STRATA"][0],
        "subgroups": settings["SUBGROUPS"],
        "landmark": int(settings["LANDMARK"][0]),
        "covariates": settings["COX"],
        "residuals": int(settings["RESIDUALS"][0]),
        "plot": tuple(int(value) for value in settings["PLOT"]),
    }
    return subjects, params
