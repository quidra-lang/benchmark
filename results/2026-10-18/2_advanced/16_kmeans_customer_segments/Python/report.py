def real(value):
    text = f"{value:.4f}"
    return "0.0000" if text == "-0.0000" else text


def reals(values):
    return " ".join(real(value) for value in values)


def four_decimal(value):
    return round(value, 4)


def amount(cents):
    sign = "-" if cents < 0 else ""
    return f"{sign}{abs(cents) // 100}.{abs(cents) % 100:02d}"


def write_lines(path, lines):
    with open(path, "w", newline="\n") as handle:
        handle.write("".join(line + "\n" for line in lines))
