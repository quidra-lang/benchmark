"""ASCII PGM images and the stereo benchmark's parameter file."""

from pathlib import Path


def read_pgm(path):
    lines = Path(path).read_text(encoding="ascii").splitlines()
    width, height = map(int, lines[1].split())
    values = [int(value) for line in lines[3:] for value in line.split()]
    return width, height, values


def read_parameters(path="input/params.txt"):
    parameters = {}
    samples = []
    text_keys = {"wta_cost", "sgm_cost"}
    list_keys = {"sad_windows", "ssd_windows", "census_windows"}
    for line in Path(path).read_text(encoding="ascii").splitlines():
        key, *values = line.split()
        if key == "sample":
            samples.append(tuple(map(int, values)))
        elif key in text_keys:
            parameters[key] = values[0]
        elif key in list_keys:
            parameters[key] = list(map(int, values))
        else:
            parameters[key] = int(values[0])
    parameters["sample_pixels"] = samples
    return parameters


def write_pgm(path, width, height, pixels):
    lines = ["P2", f"{width} {height}", "255"]
    for y in range(height):
        lines.append(" ".join(map(str, pixels[y * width:(y + 1) * width])))
    Path(path).write_text("\n".join(lines) + "\n", encoding="ascii")
