import os


OUTPUT_DIR = "output"
LABEL_WIDTH = 10


def money(cents):
    return f"{cents // 100}.{cents % 100:02d}"


def percent(part, whole):
    return (200 * part + whole) // (2 * whole)


def table_row(label, values, width):
    return label.ljust(LABEL_WIDTH) + "".join(str(value).rjust(width) for value in values)


def write_report(name, lines):
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    with open(os.path.join(OUTPUT_DIR, name), "w") as file:
        file.write("".join(line + "\n" for line in lines))
