import string

from day_rules import COMMON_MONTH_DAYS, MONTH_NAMES, SECONDS_PER_DAY, WEEKDAY_NAMES, DaySpec


MIN_YEAR = 1800
MAX_YEAR = 2099
MAX_TIME = 86400
MAX_SAVE = 7200
STDOFF_LIMIT = 57600
MAX_LETTERS = 5
TIME_TYPES = "wsu"
WEEKDAY_OPERATORS = ((">=", "after"), ("<=", "before"))
FORMAT_CHARACTERS = string.ascii_letters + string.digits + "+-/%"


class FieldError(Exception):
    pass


class Until:
    def __init__(self, year_text, month_text, day_text, time, time_type, value):
        self.year_text = year_text
        self.month_text = month_text
        self.day_text = day_text
        self.time = time
        self.time_type = time_type
        self.value = value


def line_content(raw):
    return raw.partition("#")[0].rstrip(" ")


def is_continuation(content):
    return content.startswith(" ")


def split_fields(content):
    return content.split()


def is_number(text, min_digits, max_digits):
    return min_digits <= len(text) <= max_digits and text.isdigit()


def hms_value(text, max_parts=3):
    parts = text.split(":")
    if len(parts) > max_parts or not is_number(parts[0], 1, 2):
        return None
    value = int(parts[0]) * 3600
    for part, unit in zip(parts[1:], (60, 1)):
        if not is_number(part, 2, 2) or int(part) > 59:
            return None
        value += int(part) * unit
    return value


def parse_year(text):
    if not is_number(text, 4, 4) or not MIN_YEAR <= int(text) <= MAX_YEAR:
        raise FieldError("bad year")
    return int(text)


def parse_to(text, from_year):
    if text == "only":
        return from_year
    if text == "max":
        return MAX_YEAR
    if not is_number(text, 4, 4) or not from_year <= int(text) <= MAX_YEAR:
        raise FieldError("bad year")
    return int(text)


def parse_month(text):
    if text not in MONTH_NAMES:
        raise FieldError("bad month")
    return MONTH_NAMES.index(text) + 1


def parse_weekday(text):
    if text not in WEEKDAY_NAMES:
        raise FieldError("bad day spec")
    return WEEKDAY_NAMES.index(text)


def parse_day_of_month(text, month):
    if not is_number(text, 1, 2) or text[0] == "0" or int(text) > COMMON_MONTH_DAYS[month - 1]:
        raise FieldError("bad day spec")
    return int(text)


def parse_day_spec(text, month):
    if text.startswith("last"):
        return DaySpec("last", parse_weekday(text[4:]), 0)
    for operator, kind in WEEKDAY_OPERATORS:
        if operator in text:
            weekday_text, _, day_text = text.partition(operator)
            return DaySpec(kind, parse_weekday(weekday_text), parse_day_of_month(day_text, month))
    return DaySpec("day", 0, parse_day_of_month(text, month))


def parse_time(text):
    time_type = "w"
    if text[-1] in TIME_TYPES:
        time_type = text[-1]
        text = text[:-1]
    value = hms_value(text)
    if value is None or value > MAX_TIME:
        raise FieldError("bad time")
    return value, time_type


def parse_save(text):
    value = hms_value(text, 2)
    if value is None or value > MAX_SAVE:
        raise FieldError("bad save")
    return value


def parse_letter(text):
    if text == "-":
        return ""
    if len(text) > MAX_LETTERS or not all(char in string.ascii_uppercase for char in text):
        raise FieldError("bad letter")
    return text


def parse_stdoff(text):
    sign = 1
    if text.startswith("-"):
        sign = -1
        text = text[1:]
    value = hms_value(text)
    if value is None or value >= STDOFF_LIMIT:
        raise FieldError("bad offset")
    return sign * value


def check_format(text, uses_rule_set):
    placeholders = text.count("%s")
    slashes = text.count("/")
    valid = (
        all(char in FORMAT_CHARACTERS for char in text)
        and text.count("%") == placeholders
        and placeholders <= 1
        and slashes <= 1
        and not (placeholders and slashes)
        and (uses_rule_set or not placeholders)
    )
    if valid and slashes == 1:
        standard, _, daylight = text.partition("/")
        valid = standard != "" and daylight != ""
    if not valid:
        raise FieldError("bad format")


def parse_until(fields):
    year = parse_year(fields[0])
    month_text = fields[1] if len(fields) > 1 else "Jan"
    month = parse_month(month_text)
    day_text = fields[2] if len(fields) > 2 else "1"
    day = parse_day_spec(day_text, month)
    time, time_type = parse_time(fields[3]) if len(fields) > 3 else (0, "w")
    value = day.value(year, month) * SECONDS_PER_DAY + time
    return Until(fields[0], month_text, day_text, time, time_type, value)
