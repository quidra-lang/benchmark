from features import FEATURE_NAMES, SQRT_FEATURES


class Condition:
    def __init__(self, feature, comparison, threshold):
        self.feature = FEATURE_NAMES.index(feature)
        self.comparison = comparison
        self.threshold = float(threshold)

    def holds(self, center):
        if self.comparison == ">":
            return center[self.feature] > self.threshold
        return center[self.feature] < self.threshold


class Rule:
    def __init__(self, line):
        words = line.split(" ")
        self.name = words[0]
        self.conditions = [
            Condition(words[i], words[i + 1], words[i + 2]) for i in range(1, len(words), 3)
        ]

    def holds(self, center):
        return all(condition.holds(center) for condition in self.conditions)


def read_rules(path):
    with open(path) as handle:
        return [Rule(line) for line in handle.read().splitlines()]


def rule_number(rules, center):
    return next(number for number, rule in enumerate(rules, 1) if rule.holds(center))


def original_scale(center, means, sds):
    values = []
    for feature, component in enumerate(center):
        value = means[feature] + sds[feature] * component
        values.append(value * value if SQRT_FEATURES[feature] else value)
    return values
