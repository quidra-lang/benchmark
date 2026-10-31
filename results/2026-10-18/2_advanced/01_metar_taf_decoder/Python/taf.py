from groups import State, is_digits
from units import day_of


TAF_SLOTS = (
    ("wind", False),
    ("visibility", False),
    ("weather", True),
    ("cloud", True),
)
CHANGE_INDICATORS = ("BECMG", "TEMPO", "PROB30", "PROB40")
PROBABILITIES = ("PROB30", "PROB40")
TEMPORARY_KINDS = ("TEMPO", "PROB30", "PROB40", "PROB30 TEMPO", "PROB40 TEMPO")


class Change:
    def __init__(self, kind, start, end, groups):
        self.kind = kind
        self.start = start
        self.end = end
        self.groups = groups
        self.state = None


class Taf:
    def __init__(self, number, station, issue, modifier, start, end):
        self.number = number
        self.station = station
        self.issue = issue
        self.modifier = modifier
        self.start = start
        self.end = end
        self.base = None
        self.changes = []


def is_fm_indicator(text):
    return len(text) == 8 and text.startswith("FM") and is_digits(text[2:], 6, 6)


def is_change_indicator(text):
    return text in CHANGE_INDICATORS or is_fm_indicator(text)


def is_period(text):
    return len(text) == 9 and text[4] == "/" and is_digits(text[:4], 4, 4) and is_digits(text[5:], 4, 4)


def parse_period(text, issue_day, calendar):
    if not is_period(text):
        return None
    start_hour, end_hour = int(text[2:4]), int(text[7:9])
    if start_hour > 23 or not 1 <= end_hour <= 24:
        return None
    start = calendar.forecast_time(int(text[:2]), start_hour, 0, issue_day)
    end = calendar.forecast_time(int(text[5:7]), end_hour, 0, issue_day)
    if start is None or end is None or start >= end:
        return None
    return start, end


def fm_time(text, issue_day, calendar):
    hour, minute = int(text[4:6]), int(text[6:8])
    if hour > 23 or minute > 59:
        return None
    return calendar.forecast_time(int(text[2:4]), hour, minute, issue_day)


def change_period(forecast, groups, index, calendar, errors):
    position, kind = groups[index]
    index += 1
    if kind in PROBABILITIES and index < len(groups) and groups[index][1] == "TEMPO":
        kind += " TEMPO"
        index += 1
    issue_day = day_of(forecast.issue)
    if is_fm_indicator(kind):
        time = fm_time(kind, issue_day, calendar)
        if time is None or not forecast.start <= time < forecast.end:
            errors.append((position, f'invalid period "{kind}"'))
            return None, index
        return Change("FM", time, None, []), index
    if index == len(groups) or not is_period(groups[index][1]):
        errors.append((position, f'missing period "{kind}"'))
        return None, index
    period_position, period_text = groups[index]
    period = parse_period(period_text, issue_day, calendar)
    if period is None or period[0] < forecast.start or period[1] > forecast.end:
        errors.append((period_position, f'invalid period "{period_text}"'))
        return None, index + 1
    return Change(kind, period[0], period[1], []), index + 1


def split_changes(forecast, groups, calendar, errors):
    index = 0
    while index < len(groups) and not is_change_indicator(groups[index][1]):
        index += 1
    base = groups[:index]
    changes = []
    while index < len(groups):
        change, index = change_period(forecast, groups, index, calendar, errors)
        end = index
        while end < len(groups) and not is_change_indicator(groups[end][1]):
            end += 1
        if change is not None:
            change.groups = groups[index:end]
            changes.append(change)
        index = end
    return base, changes


def overlay(state, change):
    return State(
        state.wind if change.wind is None else change.wind,
        state.visibility if change.visibility is None else change.visibility,
        state.weather if change.weather is None else change.weather,
        state.cloud if change.cloud is None else change.cloud,
    )


def prevailing_state(forecast, hour):
    state = forecast.base
    for change in forecast.changes:
        if change.kind == "FM" and change.start <= hour:
            state = change.state
        elif change.kind == "BECMG" and change.end <= hour:
            state = overlay(state, change.state)
    return state


def temporary_states(forecast, hour):
    prevailing = prevailing_state(forecast, hour)
    states = []
    for change in forecast.changes:
        if change.kind in TEMPORARY_KINDS and change.start <= hour < change.end:
            states.append((change.kind, overlay(prevailing, change.state)))
    return states
