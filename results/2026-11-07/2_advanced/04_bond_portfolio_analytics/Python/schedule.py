from dates_calendar import civil_date, day_number, month_length


def months_before(year, month, day, months, end_of_month):
    index = year * 12 + month - 1 - months
    year = index // 12
    month = index % 12 + 1
    if end_of_month:
        return day_number(year, month, month_length(year, month))
    return day_number(year, month, min(day, month_length(year, month)))


def coupon_schedule(issue, maturity, frequency, end_of_month, long_stub):
    year, month, day = civil_date(maturity)
    end_of_month_rule = end_of_month and day == month_length(year, month)
    step = 12 // frequency
    dates = []
    boundary = maturity
    while boundary > issue:
        dates.append(boundary)
        boundary = months_before(year, month, day, step * len(dates), end_of_month_rule)
    if long_stub and boundary != issue and len(dates) >= 2:
        dates.pop()
    dates.append(issue)
    dates.reverse()
    return dates
