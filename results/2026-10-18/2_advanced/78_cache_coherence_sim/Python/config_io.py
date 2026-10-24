"""Parse hierarchy geometry, named scenarios, regions, watch lines and trace."""

from pathlib import Path
import re


INTEGER = re.compile(r"(?:0|[1-9][0-9]*)\Z")
ADDRESS = re.compile(r"[0-9a-f]{8}\Z")


def decimal_integer(text, maximum=None):
    return (INTEGER.fullmatch(text) is not None
            and (maximum is None or len(text) <= maximum))


def valid_hex_address(text):
    return ADDRESS.fullmatch(text) is not None


def hex_address(value):
    return f"{value:08x}"


def read_config(path="input/config.txt"):
    data = {"scenarios": [], "regions": [], "watch": []}
    for line in Path(path).read_text(encoding="ascii").splitlines():
        fields = line.split(" ")
        kind, values = fields[0], fields[1:]
        if kind == "CORES":
            data["cores"] = int(values[0])
        elif kind == "LINE":
            data["line"] = int(values[0])
        elif kind == "L1":
            data["l1_size"], data["l1_ways"] = map(int, values)
        elif kind == "L2":
            data["l2_size"], data["l2_ways"] = map(int, values)
        elif kind == "LATENCY":
            data["t1"], data["t2"], data["tm"], data["tb"] = map(int, values)
        elif kind == "SCENARIO":
            data["scenarios"].append({
                "name": values[0], "protocol": values[1],
                "l1": values[2], "l2": values[3],
                "order": len(data["scenarios"]),
            })
        elif kind == "PRIMARY":
            data["primary"] = values[0]
        elif kind == "INTERVAL":
            data["interval"] = int(values[0])
        elif kind == "TOP":
            data["top"] = int(values[0])
        elif kind == "REGION":
            data["regions"].append({
                "name": values[0],
                "start": int(values[1], 16),
                "end": int(values[2], 16),
            })
        elif kind == "WATCH":
            data["watch"].append(int(values[0], 16) // data["line"])
    data["l1_sets"] = data["l1_size"] // (data["line"] * data["l1_ways"])
    data["l2_sets"] = data["l2_size"] // (data["line"] * data["l2_ways"])
    data["cap"] = data["l1_sets"] * data["l1_ways"]
    return data


def read_trace(path="input/trace.txt"):
    return Path(path).read_text(encoding="ascii").splitlines()


def write_lines(filename, lines):
    path = Path("output") / filename
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n" if lines else "", encoding="ascii")
