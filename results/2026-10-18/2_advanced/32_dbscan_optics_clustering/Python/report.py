import math
import os


OUTPUT_DIR = "output"


def fraction_text(numerator, denominator):
    divisor = math.gcd(abs(numerator), denominator)
    return f"{numerator // divisor}/{denominator // divisor}"


def root_text(value):
    return f"{math.sqrt(value):.3f}"


def ari_text(numerator, denominator):
    value = f"{numerator / denominator:.4f}"
    if value == "-0.0000":
        value = "0.0000"
    return f"{fraction_text(numerator, denominator)} {value}"


def framed(rows, width):
    border = "+" + "-" * width + "+"
    return [border] + ["|" + row + "|" for row in rows] + [border]


def write_lines(name, lines):
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    with open(os.path.join(OUTPUT_DIR, name), "w") as file:
        file.write("".join(line + "\n" for line in lines))
