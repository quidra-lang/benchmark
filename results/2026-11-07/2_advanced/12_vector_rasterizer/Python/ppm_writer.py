RAMP = "@%#*+=-:,."
CELL_WIDTH = 2
CELL_HEIGHT = 4


def write_text(path, lines):
    with open(path, "w") as handle:
        handle.write("\n".join(lines) + "\n")


def write_ppm(path, image):
    lines = ["P3", f"{len(image[0])} {len(image)}", "255"]
    for row in image:
        lines.append(" ".join(f"{red} {green} {blue}" for red, green, blue in row))
    write_text(path, lines)


def cell_character(image, left, top):
    total = 0
    for y in range(top, top + CELL_HEIGHT):
        for x in range(left, left + CELL_WIDTH):
            red, green, blue = image[y][x]
            total += 299 * red + 587 * green + 114 * blue
    lum = total // 8000
    return RAMP[lum * len(RAMP) // 256]


def write_preview(path, image):
    lines = []
    for top in range(0, len(image), CELL_HEIGHT):
        lines.append("".join(
            cell_character(image, left, top)
            for left in range(0, len(image[0]), CELL_WIDTH)
        ))
    write_text(path, lines)
