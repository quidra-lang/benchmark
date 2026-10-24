from groups import is_digits


MAIN_SLOTS = (
    ("modifier", False),
    ("wind", False),
    ("variation", False),
    ("visibility", False),
    ("rvr", True),
    ("weather", True),
    ("cloud", True),
    ("temperature", False),
    ("pressure", False),
    ("no trend", False),
)
TREND_SLOTS = (
    ("wind", False),
    ("visibility", False),
    ("weather", True),
    ("cloud", True),
)
TREND_INDICATORS = ("BECMG", "TEMPO")


class Trend:
    def __init__(self, kind, times, groups):
        self.kind = kind
        self.times = times
        self.groups = groups
        self.section = None


def split_body(groups):
    remarks = []
    for index, (_, text) in enumerate(groups):
        if text == "RMK":
            groups, remarks = groups[:index], groups[index + 1:]
            break
    for index, (_, text) in enumerate(groups):
        if text in TREND_INDICATORS:
            return groups[:index], groups[index:], remarks
    return groups, [], remarks


def trend_sections(trend_part):
    sections = []
    for group in trend_part:
        if group[1] in TREND_INDICATORS:
            sections.append([])
        sections[-1].append(group)
    return sections


def is_time_group(groups, index, prefixes):
    if index >= len(groups):
        return False
    text = groups[index][1]
    return len(text) == 6 and text[:2] in prefixes and is_digits(text[2:], 4, 4)


def time_group_count(groups):
    if is_time_group(groups, 1, ("FM",)):
        return 2 if is_time_group(groups, 2, ("TL",)) else 1
    return 1 if is_time_group(groups, 1, ("TL", "AT")) else 0


def read_trend(groups, errors):
    count = time_group_count(groups)
    times = []
    for position, text in groups[1:1 + count]:
        hour, minute = int(text[2:4]), int(text[4:6])
        if hour > 23 or minute > 59:
            errors.append((position, f'invalid period "{text}"'))
            return None
        times.append((text[:2], hour, minute))
    return Trend(groups[0][1], times, groups[1 + count:])


def is_signed_tenths(text):
    return len(text) == 4 and text[0] in ("0", "1") and is_digits(text[1:], 3, 3)


def signed_tenths(text):
    value = int(text[1:])
    return -value if text[0] == "1" else value


def read_remarks(remarks):
    sea_level_pressures = []
    precise_temperatures = []
    for _, text in remarks:
        if len(text) == 6 and text.startswith("SLP") and is_digits(text[3:], 3, 3):
            value = int(text[3:])
            sea_level_pressures.append(9000 + value if value >= 500 else 10000 + value)
        elif len(text) == 9 and text[0] == "T" and is_signed_tenths(text[1:5]) and is_signed_tenths(text[5:]):
            precise_temperatures.append((signed_tenths(text[1:5]), signed_tenths(text[5:])))
    return sea_level_pressures, precise_temperatures
