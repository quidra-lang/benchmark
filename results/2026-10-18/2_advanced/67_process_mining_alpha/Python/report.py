from fractions import Fraction
from pathlib import Path


def fraction(value):
    value = Fraction(value)
    numerator = abs(value.numerator)
    denominator = value.denominator
    scaled = 10000 * numerator // denominator
    sign = "-" if value < 0 else ""
    decimal_sign = sign if scaled else ""
    return (f"{sign}{numerator}/{denominator}="
            f"{decimal_sign}{scaled // 10000}.{scaled % 10000:04d}")


def percentage(count, total):
    scaled = 10000 * count // total
    return f"{scaled // 100}.{scaled % 100:02d}%"


def names(values):
    return ",".join(values) or "-"


def write_outputs(outputs):
    directory = Path("output")
    directory.mkdir(parents=True, exist_ok=True)
    for name, lines in outputs.items():
        (directory / name).write_text("\n".join(lines) + "\n", encoding="ascii", newline="\n")
