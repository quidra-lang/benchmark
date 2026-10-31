BISECTION_STEPS = 80
BASIS_POINT = 0.0001
LOWEST_YIELD = 0.0
HIGHEST_YIELD = 1.0


def bisection(function, low, high, target):
    for _ in range(BISECTION_STEPS):
        middle = (low + high) / 2
        if function(middle) > target:
            low = middle
        else:
            high = middle
    return (low + high) / 2


class RiskMeasures:
    def __init__(self, macaulay, modified, convexity, dv01):
        self.macaulay = macaulay
        self.modified = modified
        self.convexity = convexity
        self.dv01 = dv01


class YieldPricer:
    def __init__(self, flows, fraction, frequency, outstanding):
        self.flows = flows
        self.fraction = fraction
        self.frequency = frequency
        self.outstanding = outstanding

    def present_values(self, rate):
        first = 1 + self.fraction * rate / self.frequency
        growth = 1 + rate / self.frequency
        factor = 1.0
        values = []
        for cash_flow in self.flows:
            values.append(cash_flow / (first * factor))
            factor *= growth
        return values

    def dirty(self, rate):
        total = 0.0
        for value in self.present_values(rate):
            total += value
        return total * 100 / self.outstanding

    def solve(self, target):
        return bisection(self.dirty, LOWEST_YIELD, HIGHEST_YIELD, target)

    def in_range(self, target):
        return self.dirty(LOWEST_YIELD) > target > self.dirty(HIGHEST_YIELD)

    def risk(self, rate):
        growth = 1 + rate / self.frequency
        total = 0.0
        weighted = 0.0
        curvature = 0.0
        for index, value in enumerate(self.present_values(rate)):
            years = (index + self.fraction) / self.frequency
            total += value
            weighted += years * value
            curvature += years * (years + 1 / self.frequency) * value
        macaulay = weighted / total
        convexity = curvature / (total * growth * growth)
        dv01 = (self.dirty(rate - BASIS_POINT) - self.dirty(rate + BASIS_POINT)) / 2
        return RiskMeasures(macaulay, macaulay / growth, convexity, dv01)
