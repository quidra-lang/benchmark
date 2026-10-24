from song_parser import ROWS_PER_PATTERN


def samples_per_tick(rate, tempo):
    return rate * 5 // (tempo * 2)


def next_row(song, position, row):
    jump = None
    pattern_break = None
    for cell in song.cells(position, row):
        effect = cell.effect
        if effect is None:
            continue
        if effect.name == "F" and effect.value == 0:
            return None
        if effect.name == "B":
            jump = effect.value
        elif effect.name == "D":
            pattern_break = effect.value
    if jump is None and pattern_break is None:
        if row < ROWS_PER_PATTERN - 1:
            return position, row + 1
        return position + 1, 0
    target_position = position + 1 if jump is None else jump
    if pattern_break is None or pattern_break >= ROWS_PER_PATTERN:
        return target_position, 0
    return target_position, pattern_break


def reachable_rows(song):
    reached = set()
    current = (0, 0)
    while current is not None and current not in reached:
        reached.add(current)
        current = next_row(song, *current)
        if current is not None and current[0] >= len(song.order):
            current = None
    return reached
