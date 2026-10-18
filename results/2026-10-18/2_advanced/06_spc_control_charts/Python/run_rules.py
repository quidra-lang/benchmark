class Zones:
    def __init__(self, limits):
        upper_step = (limits.ucl - limits.cl) / 3
        lower_step = (limits.cl - limits.lcl) / 3
        self.lcl = limits.lcl
        self.cl = limits.cl
        self.ucl = limits.ucl
        self.u1 = limits.cl + upper_step
        self.u2 = limits.cl + 2 * upper_step
        self.l1 = limits.cl - lower_step
        self.l2 = limits.cl - 2 * lower_step


class Signal:
    def __init__(self, chart, rule, start, end, value, direction):
        self.chart = chart
        self.rule = rule
        self.start = start
        self.end = end
        self.value = value
        self.direction = direction


def beyond_limits(window, zones):
    value = window[-1]
    if value > zones.ucl or value < zones.lcl:
        return "UP" if value > zones.cl else "DOWN"
    return None


def beyond_boundary(window, upper, lower, needed):
    value = window[-1]
    if value > upper and sum(item > upper for item in window) >= needed:
        return "UP"
    if value < lower and sum(item < lower for item in window) >= needed:
        return "DOWN"
    return None


def two_of_three(window, zones):
    return beyond_boundary(window, zones.u2, zones.l2, 2)


def four_of_five(window, zones):
    return beyond_boundary(window, zones.u1, zones.l1, 4)


def same_side(window, zones):
    if all(value > zones.cl for value in window):
        return "UP"
    if all(value < zones.cl for value in window):
        return "DOWN"
    return None


def trend(window, zones):
    pairs = list(zip(window, window[1:]))
    if all(later > earlier for earlier, later in pairs):
        return "UP"
    if all(later < earlier for earlier, later in pairs):
        return "DOWN"
    return None


def alternation(window, zones):
    differences = [later - earlier for earlier, later in zip(window, window[1:])]
    if any(difference == 0 for difference in differences):
        return None
    for previous, current in zip(differences, differences[1:]):
        if (previous > 0) == (current > 0):
            return None
    return "NONE"


def stratification(window, zones):
    if all(zones.l1 < value < zones.u1 for value in window):
        return "NONE"
    return None


def mixture(window, zones):
    if not all(value > zones.u1 or value < zones.l1 for value in window):
        return None
    if any(value > zones.u1 for value in window) and any(value < zones.l1 for value in window):
        return "NONE"
    return None


RULES = {
    1: (1, beyond_limits),
    2: (3, two_of_three),
    3: (5, four_of_five),
    4: (8, same_side),
    5: (6, trend),
    6: (14, alternation),
    7: (15, stratification),
    8: (8, mixture),
}


def check_rules(chart, numbers, values, limits, rules):
    zones = Zones(limits)
    signals = []
    for k in range(1, len(values) + 1):
        for rule in rules:
            length, test = RULES[rule]
            if k < length:
                continue
            direction = test(values[k - length:k], zones)
            if direction is not None:
                signals.append(Signal(
                    chart, str(rule), numbers[k - length], numbers[k - 1], values[k - 1], direction
                ))
    return signals
