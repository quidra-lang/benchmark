import os


OUTPUT_DIR = "output"
RULES_HEADER = (
    "rank,antecedent,consequent,count,support,confidence,lift,leverage,conviction,improvement"
)


def fraction_text(value):
    numerator = abs(value.numerator)
    denominator = value.denominator
    scaled = 10000 * numerator // denominator
    decimal = f"{scaled // 10000}.{scaled % 10000:04d}"
    if value >= 0:
        return f"{numerator}/{denominator}={decimal}"
    sign = "-" if scaled > 0 else ""
    return f"-{numerator}/{denominator}={sign}{decimal}"


def percent_text(part, whole):
    scaled = 10000 * part // whole
    return f"{scaled // 100}.{scaled % 100:02d}%"


def money_text(cents):
    return f"{cents // 100}.{cents % 100:02d}"


def itemset_text(itemset):
    return "+".join(itemset)


def rule_arrow(rule):
    return f"{itemset_text(rule.antecedent)} -> {itemset_text(rule.consequent)}"


def rule_csv_line(rule):
    conviction = "INF" if rule.conviction is None else fraction_text(rule.conviction)
    fields = [
        str(rule.rank), itemset_text(rule.antecedent), itemset_text(rule.consequent),
        str(rule.count), fraction_text(rule.support), fraction_text(rule.confidence),
        fraction_text(rule.lift), fraction_text(rule.leverage), conviction,
        fraction_text(rule.improvement),
    ]
    return ",".join(fields)


def rules_csv(rules):
    return [RULES_HEADER] + [rule_csv_line(rule) for rule in rules]


def write_report(name, lines):
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    with open(os.path.join(OUTPUT_DIR, name), "w") as handle:
        handle.write("".join(line + "\n" for line in lines))
