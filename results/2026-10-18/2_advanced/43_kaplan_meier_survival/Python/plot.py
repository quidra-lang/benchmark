"""Draw the specified stepped Kaplan-Meier curves on a character grid."""

from math import floor

from estimators import row_at


def curve_lines(groups, collections, estimates, width, height, time_limit):
    cells = [[set() for _ in range(width)] for _ in range(height)]
    step = time_limit // width
    for index, group in enumerate(groups):
        letter = chr(ord("A") + index)
        maximum = max(subject["time"] for subject in collections[group])
        previous = None
        for column in range(width):
            time = column * step
            if time > maximum:
                break
            survival = row_at(estimates[group], time)["survival"]
            band = min(height - 1, floor(survival * height))
            cells[band][column].add(letter)
            if previous is not None and previous - 1 > band:
                for vertical in range(band + 1, previous):
                    cells[vertical][column].add(letter)
            previous = band
    border = "   +" + "-" * width + "+"
    lines = [border]
    for band in range(height - 1, -1, -1):
        characters = [" " if not cell else next(iter(cell)) if len(cell) == 1 else "*"
                      for cell in cells[band]]
        lines.append(f"{100 * band // height:3d}|{''.join(characters)}|")
    lines.append(border)
    return lines
