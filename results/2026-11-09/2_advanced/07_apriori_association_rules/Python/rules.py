from fractions import Fraction


class Rule:
    def __init__(self, itemset, antecedent, consequent, count, total, antecedent_count,
                 consequent_count):
        self.itemset = itemset
        self.antecedent = antecedent
        self.consequent = consequent
        self.count = count
        self.support = Fraction(count, total)
        self.confidence = Fraction(count, antecedent_count)
        self.lift = lift_of(total, count, antecedent_count, consequent_count)
        self.leverage = Fraction(
            total * count - antecedent_count * consequent_count, total * total
        )
        self.conviction = None
        if antecedent_count != count:
            self.conviction = Fraction(
                (total - consequent_count) * antecedent_count,
                total * (antecedent_count - count),
            )
        self.improvement = Fraction(0)
        self.rank = 0


class RuleSet:
    def __init__(self, generated, rules):
        self.generated = generated
        self.rules = rules
        self.productive = sum(1 for rule in rules if rule.improvement > 0)


def lift_of(total, together, first_count, second_count):
    return Fraction(total * together, first_count * second_count)


def meets_thresholds(confidence, lift, params):
    return confidence >= params.min_confidence and lift >= params.min_lift


def rule_order(rule):
    return -rule.confidence, -rule.lift, -rule.count, rule.antecedent, rule.consequent
