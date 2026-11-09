from headers import remove_comments, split_words


WEEKDAYS = ("mon", "tue", "wed", "thu", "fri", "sat", "sun")
MONTHS = ("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec")
MONTH_DAYS = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
NAMED_ZONES = {
    "ut": 0, "gmt": 0, "z": 0, "est": -300, "edt": -240, "cst": -360,
    "cdt": -300, "mst": -420, "mdt": -360, "pst": -480, "pdt": -420,
}
SYNTAX_ERROR = "bad Date syntax"
RANGE_ERROR = "Date out of range"
WEEKDAY_ERROR = "Date weekday mismatch"


class DateError(Exception):
    pass


def is_leap(year):
    return year % 4 == 0 and year % 100 != 0 or year % 400 == 0


def days_in_month(year, month):
    if month == 2 and is_leap(year):
        return 29
    return MONTH_DAYS[month - 1]


def days_in_year(year):
    return 366 if is_leap(year) else 365


def days_since_epoch(year, month, day):
    days = sum(days_in_year(current) for current in range(1970, year))
    days += sum(days_in_month(year, current) for current in range(1, month))
    return days + day - 1


def civil_date(days):
    year = 1970
    while days >= days_in_year(year):
        days -= days_in_year(year)
        year += 1
    month = 1
    while days >= days_in_month(year, month):
        days -= days_in_month(year, month)
        month += 1
    return year, month, days + 1


def format_utc(seconds):
    days, rest = divmod(seconds, 86400)
    year, month, day = civil_date(days)
    hour, rest = divmod(rest, 3600)
    minute, second = divmod(rest, 60)
    return f"{year:04d}-{month:02d}-{day:02d} {hour:02d}:{minute:02d}:{second:02d}"


def has_digits(text, *lengths):
    return len(text) in lengths and text.isdigit()


def is_numeric_zone(text):
    return text[0] in "+-" and has_digits(text[1:], 4)


def parse_zone(text):
    if is_numeric_zone(text):
        hours, minutes = int(text[1:3]), int(text[3:5])
        if hours > 23 or minutes > 59:
            raise DateError(RANGE_ERROR)
        offset = hours * 60 + minutes
        return -offset if text[0] == "-" else offset
    return NAMED_ZONES[text.lower()]


def date_tokens(value):
    text = remove_comments(value)
    if text is None:
        raise DateError(SYNTAX_ERROR)
    tokens = split_words(text.replace(",", " , "))
    weekday = None
    if len(tokens) >= 3 and tokens[0].lower() in WEEKDAYS and tokens[1] == ",":
        weekday = WEEKDAYS.index(tokens[0].lower())
        tokens = tokens[2:]
    if len(tokens) != 5:
        raise DateError(SYNTAX_ERROR)
    day, month, year, time, zone = tokens
    pieces = time.split(":")
    valid = (
        has_digits(day, 1, 2)
        and month.lower() in MONTHS
        and has_digits(year, 2, 4)
        and len(pieces) in (2, 3)
        and all(has_digits(piece, 2) for piece in pieces)
        and (is_numeric_zone(zone) or zone.lower() in NAMED_ZONES)
    )
    if not valid:
        raise DateError(SYNTAX_ERROR)
    return weekday, day, month, year, pieces, zone


def parse_date(value):
    weekday, day_text, month_text, year_text, pieces, zone_text = date_tokens(value)
    day = int(day_text)
    month = MONTHS.index(month_text.lower()) + 1
    year = int(year_text)
    if len(year_text) == 2:
        year += 2000 if year < 50 else 1900
    hour, minute = int(pieces[0]), int(pieces[1])
    second = int(pieces[2]) if len(pieces) == 3 else 0
    offset = parse_zone(zone_text)
    if year < 1970 or year > 2099 or day < 1 or day > days_in_month(year, month):
        raise DateError(RANGE_ERROR)
    if hour > 23 or minute > 59 or second > 59:
        raise DateError(RANGE_ERROR)
    days = days_since_epoch(year, month, day)
    seconds = days * 86400 + hour * 3600 + minute * 60 + second - offset * 60
    if seconds < 0:
        raise DateError(RANGE_ERROR)
    if weekday is not None and (days + 3) % 7 != weekday:
        raise DateError(WEEKDAY_ERROR)
    return seconds
