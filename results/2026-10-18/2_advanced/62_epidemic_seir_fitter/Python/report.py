from math import floor


def fmt(value, places=4):
    text = f"{value:.{places}f}"
    if text.startswith("-") and all(character in "0." for character in text[1:]):
        return text[1:]
    return text


def curve_plot(observed, fitted):
    days = len(observed)
    maximum = max(observed)
    width = len(str(maximum))
    grid = [["."] * 70 for _ in range(20)]
    for column in range(70):
        day = column * (days - 1) // 69
        observed_row = min(19, 20 * observed[day] // maximum)
        fitted_row = min(19, floor(20.0 * fitted[day] / maximum))
        grid[observed_row][column] = "o"
        grid[fitted_row][column] = "#" if observed_row == fitted_row else "*"
    lines = [f"plot observed o fitted * both # days 1 {days} max {maximum}"]
    for row in range(19, -1, -1):
        lines.append(f"{maximum * row // 20:>{width}} |" + "".join(grid[row]))
    ticks = "".join("+" if column % 10 == 0 else "-" for column in range(70))
    lines.append(" " * (width + 1) + "+" + ticks)
    labels = [" "] * 70
    for column in range(0, 70, 10):
        label = str(1 + column * (days - 1) // 69)
        labels[column:column + len(label)] = label
    lines.append((" " * (width + 2) + "".join(labels)).rstrip())
    return lines
