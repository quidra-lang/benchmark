def fixed(value, places=4):
    text = f"{value:.{places}f}"
    if text.startswith("-") and float(text) == 0:
        return text[1:]
    return text


def fraction_text(value):
    return f"{value.numerator}/{value.denominator}"


def fraction_with_real(value):
    return f"{fraction_text(value)} {fixed(value)}"


def decimal_value(value, places):
    return round(value, places)


def write_lines(path, lines):
    with open(path, "w") as file:
        file.write("\n".join(lines) + "\n")
