import os


def fixed_width_line(label, cells, label_width, cell_width):
    return label.ljust(label_width) + "".join(cell.rjust(cell_width) for cell in cells)


def rounded_percent(part, whole):
    return (200 * part + whole) // (2 * whole)


def write_lines(path, lines):
    with open(path, "w", newline="\n") as file:
        file.write("\n".join(lines) + "\n")


def write_files(directory, files):
    os.makedirs(directory, exist_ok=True)
    for name, lines in files:
        write_lines(os.path.join(directory, name), lines)
