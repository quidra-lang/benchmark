"""Read integer ECG samples, reference annotations, and detector settings."""

from pathlib import Path


PARAMETERS = (
    "refractory_ms", "twave_ms", "searchback_percent",
    "premature_percent", "qrs_width_ms", "match_ms",
    "pause_ms", "brady_ms", "tachy_ms", "excerpt_ms",
    "segment_ms", "strip_start_ms", "strip_ms",
    "strip_rows", "chart_rows", "poincare_size",
)


def read_ecg(path="input/ecg.csv"):
    lines = Path(path).read_text(encoding="ascii").splitlines()
    return [int(line.split(",")[1]) for line in lines[1:]]


def read_annotations(path="input/annotations.csv"):
    lines = Path(path).read_text(encoding="ascii").splitlines()
    return [
        {"sample": int(row[0]), "label": row[1], "beat": None}
        for row in (line.split(",") for line in lines[1:])
    ]


def read_params(path="input/params.txt"):
    lines = Path(path).read_text(encoding="ascii").splitlines()
    params = {}
    for name, line in zip(PARAMETERS, lines):
        key, value = line.split(" ")
        if key != name:
            raise ValueError("invalid setting order")
        params[key] = int(value)
    return params


def write_lines(path, lines):
    output = Path("output") / path
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines) + "\n", encoding="ascii")
