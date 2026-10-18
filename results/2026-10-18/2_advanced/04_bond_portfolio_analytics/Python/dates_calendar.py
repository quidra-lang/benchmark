EPOCH_YEAR = 2000
EPOCH_WEEKDAY = 5
FIRST_VALID_YEAR = 2001
LAST_VALID_YEAR = 2099
MONTH_LENGTHS = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
BUSINESS_DAY_RULES = ("FOLLOWING", "MODIFIED_FOLLOWING", "PRECEDING", "UNADJUSTED")


def is_leap(year):
    return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)


def year_length(year):
    return 366 if is_leap(year) else 365


def month_length(year, month):
    if month == 2 and is_leap(year):
        return 29
    return MONTH_LENGTHS[month - 1]


def split_date(text):
    return int(text[0:4]), int(text[5:7]), int(text[8:10])


def is_valid_date(text):
    year, month, day = split_date(text)
    if not FIRST_VALID_YEAR <= year <= LAST_VALID_YEAR or not 1 <= month <= 12:
        return False
    return 1 <= day <= month_length(year, month)


def day_number(year, month, day):
    number = day - 1
    for earlier_year in range(EPOCH_YEAR, year):
        number += year_length(earlier_year)
    for earlier_month in range(1, month):
        number += month_length(year, earlier_month)
    return number


def parse_date(text):
    year, month, day = split_date(text)
    return day_number(year, month, day)


def civil_date(number):
    year = EPOCH_YEAR
    while number >= year_length(year):
        number -= year_length(year)
        year += 1
    month = 1
    while number >= month_length(year, month):
        number -= month_length(year, month)
        month += 1
    return year, month, number + 1


def format_date(number):
    year, month, day = civil_date(number)
    return f"{year:04d}-{month:02d}-{day:02d}"


def weekday(number):
    return (number + EPOCH_WEEKDAY) % 7


class Calendar:
    def __init__(self, holidays):
        self.holidays = set(holidays)

    def is_business_day(self, number):
        return weekday(number) < 5 and number not in self.holidays

    def following(self, number):
        while not self.is_business_day(number):
            number += 1
        return number

    def preceding(self, number):
        while not self.is_business_day(number):
            number -= 1
        return number

    def adjust(self, number, rule):
        if rule == "FOLLOWING":
            return self.following(number)
        if rule == "PRECEDING":
            return self.preceding(number)
        if rule == "MODIFIED_FOLLOWING":
            following = self.following(number)
            if civil_date(following)[1] != civil_date(number)[1]:
                return self.preceding(number)
            return following
        return number

    def business_days_after(self, number, count):
        while count > 0:
            number += 1
            if self.is_business_day(number):
                count -= 1
        return number

    def business_days_before(self, number, count):
        while count > 0:
            number -= 1
            if self.is_business_day(number):
                count -= 1
        return number
