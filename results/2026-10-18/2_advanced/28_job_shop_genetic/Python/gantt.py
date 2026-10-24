SCALE_STEPS = (1, 2, 5)
LABEL_WIDTH = 4
TIME_OFFSET = 6
LABEL_EVERY = 10


def ceil_div(numerator, denominator):
    return (numerator + denominator - 1) // denominator


def chart_scale(makespan, width):
    magnitude = 1
    while True:
        for step in SCALE_STEPS:
            scale = step * magnitude
            columns = ceil_div(makespan, scale)
            if columns <= width:
                return scale, columns
        magnitude *= 10


def time_row(scale, columns):
    row = "time"
    for column in range(0, columns, LABEL_EVERY):
        row = row.ljust(TIME_OFFSET + column) + str(column * scale)
    return row


def rule_row(columns):
    ticks = "".join("+" if column % LABEL_EVERY == 0 else "-" for column in range(columns))
    return " " * TIME_OFFSET + ticks


def framed(label, marks):
    return label.ljust(LABEL_WIDTH) + " |" + marks + "|"


def column_mark(intervals, column, scale):
    low = column * scale
    high = low + scale
    mark = "."
    widest = 0
    for start, end, symbol in intervals:
        overlap = min(end, high) - max(start, low)
        if overlap > widest:
            widest = overlap
            mark = symbol
    return mark


def chart_row(label, intervals, scale, columns):
    ordered = sorted(intervals)
    return framed(label, "".join(column_mark(ordered, column, scale) for column in range(columns)))


def busy_row(machine_intervals, scale, columns):
    marks = []
    for column in range(columns):
        time = column * scale
        busy = sum(
            any(start <= time < end for start, end, _ in intervals)
            for intervals in machine_intervals
        )
        marks.append("X" if busy == 10 else str(busy))
    return framed("busy", "".join(marks))
