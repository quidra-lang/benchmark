from math import gcd


SINE_TABLE = (0, 174, 342, 500, 643, 766, 866, 940, 985, 1000)
LONG_MONTHS = (1, 3, 5, 7, 8, 10, 12)
MINUTES_PER_DAY = 1440
MILLIMETERS_PER_MILE = 1609344


def sin(angle):
    angle %= 360
    if angle <= 90:
        return SINE_TABLE[angle // 10]
    if angle <= 180:
        return SINE_TABLE[(180 - angle) // 10]
    if angle <= 270:
        return -SINE_TABLE[(angle - 180) // 10]
    return -SINE_TABLE[(360 - angle) // 10]


def cos(angle):
    return sin(angle + 90)


def knots(speed, unit):
    if unit == "MPS":
        return (speed * 1944 + 500) // 1000
    return speed


def inhg_from_hpa(hpa):
    return (hpa * 2953 + 500) // 1000


def hpa_from_inhg(inhg):
    return (inhg * 33864 + 50000) // 100000


def days_in_month(year, month):
    if month == 2:
        leap = year % 4 == 0 and year % 100 != 0 or year % 400 == 0
        return 29 if leap else 28
    return 31 if month in LONG_MONTHS else 30


def following_month(year, month):
    if month == 12:
        return year + 1, 1
    return year, month + 1


def day_minutes(day, hour, minute):
    return ((day - 1) * 24 + hour) * 60 + minute


def day_of(time):
    return time // MINUTES_PER_DAY + 1


def hour_mark(time):
    return time - time % 60


class Calendar:
    def __init__(self, year, month):
        self.year = year
        self.month = month
        self.days = days_in_month(year, month)
        self.next_year, self.next_month = following_month(year, month)
        self.next_days = days_in_month(self.next_year, self.next_month)

    def forecast_time(self, day, hour, minute, issue_day):
        if day >= issue_day:
            if day > self.days:
                return None
            return day_minutes(day, hour, minute)
        if day < 1 or day > self.next_days:
            return None
        return self.days * MINUTES_PER_DAY + day_minutes(day, hour, minute)

    def stamp(self, time):
        year, month = self.year, self.month
        if time >= self.days * MINUTES_PER_DAY:
            year, month = self.next_year, self.next_month
            time -= self.days * MINUTES_PER_DAY
        day, minutes = divmod(time, MINUTES_PER_DAY)
        return f"{year:04d}-{month:02d}-{day + 1:02d}T{minutes // 60:02d}:{minutes % 60:02d}Z"


def miles_from_meters(meters):
    return 1000 * meters, MILLIMETERS_PER_MILE


def mile_fraction(whole, numerator, denominator):
    if denominator == 0:
        return whole, 1
    return whole * denominator + numerator, denominator


def meters_from_miles(numerator, denominator):
    return MILLIMETERS_PER_MILE * numerator // (1000 * denominator)


def fraction_less(first, second):
    return first[0] * second[1] < second[0] * first[1]


def fraction_text(numerator, denominator):
    if denominator == 0:
        return "undefined"
    divisor = gcd(numerator, denominator)
    return f"{numerator // divisor}/{denominator // divisor}"
