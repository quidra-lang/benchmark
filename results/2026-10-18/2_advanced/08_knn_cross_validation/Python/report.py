from math import gcd


def fixed(value, places=4):
    text = f"{value:.{places}f}"
    if text.startswith("-") and float(text) == 0:
        return text[1:]
    return text


def four_decimal(value):
    return round(value, 4)


def ratio(numerator, denominator):
    return f"{numerator}/{denominator} {fixed(numerator / denominator)}"


def fraction(numerator, denominator):
    if denominator == 0:
        return "- -"
    divisor = gcd(numerator, denominator)
    reduced = f"{numerator // divisor}/{denominator // divisor}"
    return f"{reduced} {fixed(numerator / denominator)}"


def write_lines(path, lines):
    with open(path, "w", newline="\n") as file:
        file.write("\n".join(lines) + "\n")
