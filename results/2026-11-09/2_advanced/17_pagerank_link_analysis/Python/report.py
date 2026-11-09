from math import gcd


def fixed(value, places=6):
    text = f"{value:.{places}f}"
    if text.startswith("-") and float(text) == 0:
        return text[1:]
    return text


def scaled(value, places=6):
    return round(value * 10 ** places)


def fraction(numerator, denominator):
    divisor = gcd(abs(numerator), denominator)
    numerator //= divisor
    denominator //= divisor
    return f"{numerator}/{denominator} {fixed(numerator / denominator, 4)}"


def write_lines(path, lines):
    with open(path, "w") as file:
        file.write("\n".join(lines) + "\n")
