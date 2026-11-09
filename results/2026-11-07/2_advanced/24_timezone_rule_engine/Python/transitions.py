from day_rules import POS_INFINITY, SECONDS_PER_DAY


class Rule:
    def __init__(self, number, fields, from_year, to_year, month, day, at, at_type, save, letter):
        self.number = number
        self.fields = fields
        self.name = fields[1]
        self.from_year = from_year
        self.to_year = to_year
        self.month = month
        self.day = day
        self.at = at
        self.at_type = at_type
        self.save = save
        self.letter = letter


class RuleInstance:
    def __init__(self, rule, nominal):
        self.rule = rule
        self.nominal = nominal


class LineRun:
    def __init__(self):
        self.pre_start = []
        self.applied = []
        self.end = POS_INFINITY


def instance_sequence(rules):
    instances = []
    for rule in rules:
        for year in range(rule.from_year, rule.to_year + 1):
            nominal = rule.day.value(year, rule.month) * SECONDS_PER_DAY + rule.at
            instances.append(RuleInstance(rule, nominal))
    instances.sort(key=lambda instance: (instance.nominal, instance.rule.number))
    return instances


def adjustment(time_type, stdoff, save):
    if time_type == "u":
        return 0
    if time_type == "s":
        return stdoff
    return stdoff + save


def run_instances(instances, stdoff, start, until):
    run = LineRun()
    save = 0
    for instance in instances:
        rule = instance.rule
        time = instance.nominal - adjustment(rule.at_type, stdoff, save)
        if until is not None and time >= until.value - adjustment(until.time_type, stdoff, save):
            break
        if time <= start:
            run.pre_start.append(rule)
        else:
            run.applied.append((time, rule))
        save = rule.save
    if until is not None:
        run.end = until.value - adjustment(until.time_type, stdoff, save)
    return run


def abbreviation(format_text, save, letter):
    if "/" in format_text:
        standard, _, daylight = format_text.partition("/")
        return daylight if save != 0 else standard
    return format_text.replace("%s", letter)
