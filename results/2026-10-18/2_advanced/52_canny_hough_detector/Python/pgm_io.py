"""Read and write P2 images, the integer trigonometry table and parameters."""

from pathlib import Path


PARAMETER_ORDER = (
    "gauss_size", "gauss_kernel", "gauss_divisor",
    "canny_low", "canny_high",
    "circle_min_radius", "circle_max_radius", "circle_min_percent",
    "circle_max_count", "hough_rho_step", "hough_threshold",
    "hough_max_lines", "segment_tolerance", "segment_max_gap",
    "segment_min_length", "junction_distance", "junction_min_angle",
    "angle_tolerance", "square_tolerance", "contrast_margin",
    "harris_window", "harris_threshold", "harris_max_count",
    "corner_match_distance", "overlay_divisor",
)


def read_pgm(filename="input/image.pgm"):
    lines = Path(filename).read_text(encoding="ascii").splitlines()
    if lines[0] != "P2" or lines[2] != "255":
        raise ValueError("unsupported PGM format")
    width, height = map(int, lines[1].split(" "))
    pixels = [list(map(int, line.split(" "))) for line in lines[3:]]
    if len(pixels) != height or any(len(row) != width for row in pixels):
        raise ValueError("invalid image dimensions")
    return pixels


def read_trig(filename="input/trig.txt"):
    lines = Path(filename).read_text(encoding="ascii").splitlines()
    values = [tuple(map(int, line.split(" "))) for line in lines]
    if len(values) != 180 or any(index != row[0] for index, row in enumerate(values)):
        raise ValueError("invalid trigonometry table")
    return [(row[1], row[2]) for row in values]


def read_params(filename="input/params.txt"):
    rows = [
        line.split(" ") for line in
        Path(filename).read_text(encoding="ascii").splitlines()
    ]
    if len(rows) != len(PARAMETER_ORDER):
        raise ValueError("invalid parameter count")
    result = {}
    for expected, row in zip(PARAMETER_ORDER, rows):
        if row[0] != expected:
            raise ValueError("invalid parameter order")
        values = [int(item) for item in row[1:]]
        result[expected] = values if expected == "gauss_kernel" else values[0]
    return result


def write_pgm(filename, pixels):
    height = len(pixels)
    width = len(pixels[0])
    lines = ["P2", f"{width} {height}", "255"]
    lines.extend(" ".join(map(str, row)) for row in pixels)
    write_lines(filename, lines)


def write_lines(filename, lines):
    target = Path("output") / filename
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("\n".join(lines) + "\n", encoding="ascii")
