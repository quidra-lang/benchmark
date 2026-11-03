MONTH_NAMES = ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
WEEKDAY_NAMES = ("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")
COMMON_MONTH_DAYS = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
SECONDS_PER_DAY = 86400
NEG_INFINITY = -(2 ** 62)
POS_INFINITY = 2 ** 62


def is_leap_year(year):
    return year % 4 == 0 and year % 100 != 0 or year % 400 == 0


def days_in_month(year, month):
    if month == 2 and is_leap_year(year):
        return 29
    return COMMON_MONTH_DAYS[month - 1]


def days_before_year(year):
    previous = year - 1
    return previous * 365 + previous // 4 - previous // 100 + previous // 400


def day_number(year, month, day):
    days = days_before_year(year) - days_before_year(1970) + day - 1
    for earlier in range(1, month):
        days += days_in_month(year, earlier)
    return days


def weekday_of(number):
    return (number + 4) % 7


def date_of_day(number):
    year = 1970 + number // 366
    while day_number(year, 1, 1) > number:
        year -= 1
    while day_number(year + 1, 1, 1) <= number:
        year += 1
    month = 1
    day = number - day_number(year, 1, 1) + 1
    while day > days_in_month(year, month):
        day -= days_in_month(year, month)
        month += 1
    return year, month, day


def time_value(year, month, day, hour, minute, second):
    return day_number(year, month, day) * SECONDS_PER_DAY + hour * 3600 + minute * 60 + second


def split_time(time):
    year, month, day = date_of_day(time // SECONDS_PER_DAY)
    seconds = time % SECONDS_PER_DAY
    return year, month, day, seconds // 3600, seconds // 60 % 60, seconds % 60


class DaySpec:
    def __init__(self, kind, weekday, day):
        self.kind = kind
        self.weekday = weekday
        self.day = day

    def value(self, year, month):
        if self.kind == "last":
            last = day_number(year, month, days_in_month(year, month))
            return last - (weekday_of(last) - self.weekday) % 7
        base = day_number(year, month, self.day)
        if self.kind == "after":
            return base + (self.weekday - weekday_of(base)) % 7
        if self.kind == "before":
            return base - (weekday_of(base) - self.weekday) % 7
        return base
