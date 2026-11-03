from dates_calendar import civil_date, day_number, is_leap, month_length


DAY_COUNTS = ("30/360", "30E/360", "ACT/360", "ACT/365F", "ACT/ACT")
ACT_ACT_DENOMINATOR = 365 * 366


def is_end_of_february(year, month, day):
    return month == 2 and day == month_length(year, month)


def thirty_days(start_year, start_month, start_day, end_year, end_month, end_day):
    return 360 * (end_year - start_year) + 30 * (end_month - start_month) + (end_day - start_day)


def thirty_360(start, end):
    start_year, start_month, start_day = civil_date(start)
    end_year, end_month, end_day = civil_date(end)
    start_february = is_end_of_february(start_year, start_month, start_day)
    if start_february and is_end_of_february(end_year, end_month, end_day):
        end_day = 30
    if start_february:
        start_day = 30
    if end_day == 31 and start_day >= 30:
        end_day = 30
    if start_day == 31:
        start_day = 30
    return thirty_days(start_year, start_month, start_day, end_year, end_month, end_day)


def thirty_e_360(start, end):
    start_year, start_month, start_day = civil_date(start)
    end_year, end_month, end_day = civil_date(end)
    return thirty_days(
        start_year, start_month, min(start_day, 30), end_year, end_month, min(end_day, 30)
    )


def actual_actual(start, end):
    leap_days = 0
    other_days = 0
    year = civil_date(start)[0]
    while start < end:
        boundary = min(day_number(year + 1, 1, 1), end)
        if is_leap(year):
            leap_days += boundary - start
        else:
            other_days += boundary - start
        start = boundary
        year += 1
    return 365 * leap_days + 366 * other_days


def year_fraction(convention, start, end):
    if convention == "30/360":
        return thirty_360(start, end), 360
    if convention == "30E/360":
        return thirty_e_360(start, end), 360
    if convention == "ACT/360":
        return end - start, 360
    if convention == "ACT/365F":
        return end - start, 365
    return actual_actual(start, end), ACT_ACT_DENOMINATOR
