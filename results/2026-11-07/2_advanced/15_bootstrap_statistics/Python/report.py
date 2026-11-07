from math import floor

from tests import reduced_fraction


BAR_LENGTH = 40


def real(value):
    text = f"{value:.4f}"
    return "0.0000" if text == "-0.0000" else text


def p_value(numerator, denominator):
    numerator, denominator = reduced_fraction(numerator, denominator)
    return f"{numerator}/{denominator} {real(numerator / denominator)}"


def number_list(numbers):
    if not numbers:
        return "none"
    return " ".join(str(number) for number in sorted(numbers))


def bin_number(value, low, high, bins):
    return min(floor(bins * (value - low) / (high - low)), bins - 1) + 1


def bar(count, top):
    return "#" * ((BAR_LENGTH * count + top - 1) // top)


def write_lines(path, lines):
    with open(path, "w") as file:
        file.write("\n".join(lines) + "\n")
