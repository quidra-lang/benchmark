from day_rules import split_time


def local_text(time):
    year, month, day, hour, minute, second = split_time(time)
    return f"{year:04d}-{month:02d}-{day:02d}T{hour:02d}:{minute:02d}:{second:02d}"


def ut_text(time):
    return local_text(time) + "Z"


def offset_text(value):
    sign = "-" if value < 0 else "+"
    hours, rest = divmod(abs(value), 3600)
    minutes, seconds = divmod(rest, 60)
    text = f"{sign}{hours:02d}:{minutes:02d}"
    if seconds != 0:
        text += f":{seconds:02d}"
    return text


def duration_text(value):
    sign = "-" if value < 0 else ""
    hours, rest = divmod(abs(value), 3600)
    minutes, seconds = divmod(rest, 60)
    return f"{sign}{hours}:{minutes:02d}:{seconds:02d}"


def clock_text(value):
    hours, rest = divmod(value, 3600)
    minutes, seconds = divmod(rest, 60)
    text = f"{hours}:{minutes:02d}"
    if seconds != 0:
        text += f":{seconds:02d}"
    return text


def state_text(period):
    kind = "DST" if period.dst else "STD"
    return f"{offset_text(period.offset)} {kind} {period.abbreviation}"


def change_text(time, before, after):
    return f"{ut_text(time)} {state_text(before)} -> {state_text(after)}"


def write_lines(path, lines):
    with open(path, "w") as handle:
        for line in lines:
            handle.write(line + "\n")


def write_blocks(path, blocks):
    lines = []
    for index, block in enumerate(blocks):
        if index > 0:
            lines.append("")
        lines.extend(block)
    write_lines(path, lines)
