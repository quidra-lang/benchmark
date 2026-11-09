from daycount import year_fraction
from pricing import bisection
from schedule import coupon_schedule


DAYS_PER_YEAR = 365
PAR_DAY_COUNT = "30/360"
LOWEST_RATE = 0.0
HIGHEST_RATE = 1.0
PAR_PRICE = 1.0
LOWEST_SPREAD = -0.5
HIGHEST_SPREAD = 0.5


class ZeroCurve:
    def __init__(self, days, rates):
        self.days = days
        self.rates = rates

    def zero_rate(self, day):
        if day <= self.days[0]:
            return self.rates[0]
        if day >= self.days[-1]:
            return self.rates[-1]
        index = 1
        while self.days[index] < day:
            index += 1
        if self.days[index] == day:
            return self.rates[index]
        low_day = self.days[index - 1]
        low_rate = self.rates[index - 1]
        weight = (day - low_day) / (self.days[index] - low_day)
        return low_rate + (self.rates[index] - low_rate) * weight

    def discount(self, day, spread):
        rate = self.zero_rate(day) + spread
        years, remainder = divmod(day, DAYS_PER_YEAR)
        growth = 1.0
        for _ in range(years):
            growth *= 1 + rate
        return 1 / (growth * (1 + rate * remainder / DAYS_PER_YEAR))

    def forward(self, start, end):
        ratio = self.discount(start, 0.0) / self.discount(end, 0.0)
        return (ratio - 1) * DAYS_PER_YEAR / (end - start)

    def shifted(self, deltas):
        return ZeroCurve(self.days, [rate + delta for rate, delta in zip(self.rates, deltas)])

    def present_value(self, flows, spread):
        total = 0.0
        for day, cash_flow in flows:
            total += cash_flow * self.discount(day, spread)
        return total


def flat_curve(rate):
    return ZeroCurve([0], [rate])


def par_bond_flows(settlement, maturity, coupon, frequency):
    dates = coupon_schedule(settlement, maturity, frequency, False, False)
    flows = []
    for index in range(1, len(dates)):
        numerator, denominator = year_fraction(PAR_DAY_COUNT, dates[index - 1], dates[index])
        cash_flow = coupon * numerator / (10000 * denominator)
        if index == len(dates) - 1:
            cash_flow += 1
        flows.append((dates[index] - settlement, cash_flow))
    return flows


def bootstrap(settlement, pillars):
    days = []
    rates = []
    for maturity, coupon, frequency in pillars:
        flows = par_bond_flows(settlement, maturity, coupon, frequency)
        days.append(maturity - settlement)
        rate = bisection(
            lambda trial: ZeroCurve(days, rates + [trial]).present_value(flows, 0.0),
            LOWEST_RATE, HIGHEST_RATE, PAR_PRICE,
        )
        rates.append(rate)
    return ZeroCurve(days, rates)


def z_spread(curve, flows, target):
    return bisection(
        lambda spread: curve.present_value(flows, spread), LOWEST_SPREAD, HIGHEST_SPREAD, target
    )
