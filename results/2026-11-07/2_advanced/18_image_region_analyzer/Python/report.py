import os


def decimal(value, digits):
    scale = 10 ** digits
    numerator = value.numerator
    denominator = value.denominator
    scaled = (2 * scale * abs(numerator) + denominator) // (2 * denominator)
    sign = "-" if numerator < 0 and scaled > 0 else ""
    return f"{sign}{scaled // scale}.{scaled % scale:0{digits}d}"


def hull_area_text(doubled):
    return f"{doubled // 2}.{5 if doubled % 2 else 0}"


def write_files(directory, files):
    os.makedirs(directory, exist_ok=True)
    for name, lines in files:
        with open(os.path.join(directory, name), "w", newline="\n") as file:
            for line in lines:
                file.write(line + "\n")
