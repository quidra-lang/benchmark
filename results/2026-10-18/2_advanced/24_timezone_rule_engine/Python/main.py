import os

import tz_parser
from day_rules import (
    NEG_INFINITY, POS_INFINITY, SECONDS_PER_DAY, day_number, days_in_month, split_time, time_value,
)
from report import (
    change_text, clock_text, duration_text, local_text, offset_text, state_text, ut_text,
    write_blocks, write_lines,
)
from resolver import Period, Timeline
from transitions import Rule, abbreviation, adjustment, instance_sequence, run_instances
from tz_parser import MAX_YEAR, MIN_YEAR, FieldError


INPUT_DIR = "input"
OUTPUT_DIR = "output"
LINE_KINDS = ("Rule", "Zone", "Link")
FIELD_COUNTS = {
    "Rule": (10, 10),
    "Zone": (5, 9),
    "continuation": (3, 7),
    "Link": (3, 3),
}
OPTIONS = ("EARLIER", "LATER")
ARGUMENT_KINDS = {
    "TOUTC": ("zone", "local"),
    "TOLOCAL": ("zone", "ut"),
    "CONVERT": ("zone", "zone", "local"),
    "OFFSET": ("zone", "ut"),
    "TRANSITIONS": ("zone", "year", "year"),
    "DURATION": ("zone", "local", "local"),
}


def read_lines(path):
    with open(path) as handle:
        return handle.read().split("\n")[:-1]


def year_start(year):
    return day_number(year, 1, 1) * SECONDS_PER_DAY


def clock_seconds(text):
    return int(text[0:2]) * 3600 + int(text[3:5]) * 60


def names_or_none(names, separator):
    if not names:
        return "none"
    return separator.join(names)


def indented(lines):
    return [lines[0]] + ["  " + line for line in lines[1:]]


def merge_intervals(intervals):
    merged = []
    for low, high in sorted(intervals):
        if merged and low <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], high))
        else:
            merged.append((low, high))
    return merged


def intersect_intervals(first, second):
    pieces = []
    for first_low, first_high in first:
        for second_low, second_high in second:
            low = max(first_low, second_low)
            high = min(first_high, second_high)
            if low < high:
                pieces.append((low, high))
    return merge_intervals(pieces)


class QueryError(Exception):
    pass


class SourceLine:
    def __init__(self, number, content):
        self.number = number
        self.fields = tz_parser.split_fields(content)
        if tz_parser.is_continuation(content):
            self.kind = "continuation"
        elif self.fields[0] in LINE_KINDS:
            self.kind = self.fields[0]
        else:
            self.kind = "unknown"
        self.block = None
        self.position = 0
        self.zone_line = None
        self.field_error = False
        self.error = None

    def accepts_continuation(self):
        if self.kind == "Zone":
            return len(self.fields) >= 6
        return self.kind == "continuation" and len(self.fields) >= 4


class Block:
    def __init__(self, first):
        self.name = first.fields[1]
        self.number = first.number
        self.lines = []
        self.defined = False
        self.add(first)

    def add(self, line):
        line.block = self
        line.position = len(self.lines)
        self.lines.append(line)


class ZoneLine:
    def __init__(self, fields):
        self.stdoff = tz_parser.parse_stdoff(fields[0])
        self.rules_text = fields[1]
        self.rule_set = None
        self.save = 0
        if self.rules_text[0].isdigit():
            self.save = tz_parser.parse_save(self.rules_text)
        elif self.rules_text != "-":
            self.rule_set = self.rules_text
        self.format_text = fields[2]
        tz_parser.check_format(self.format_text, self.rule_set is not None)
        self.until = None
        if len(fields) > 3:
            self.until = tz_parser.parse_until(fields[3:])
        self.start = NEG_INFINITY
        self.end = POS_INFINITY

    def rules_notation(self):
        if self.rule_set is not None:
            return self.rule_set
        if self.rules_text == "-":
            return "-"
        return clock_text(self.save)

    def until_notation(self):
        until = self.until
        time = clock_text(until.time) + until.time_type
        return f"{until.year_text} {until.month_text} {until.day_text} {time}"


class Zone:
    def __init__(self, name, lines):
        self.name = name
        self.lines = lines
        self.aliases = []
        self.applied = {}
        self.timeline = None

    def rule_sets(self):
        names = []
        for zone_line in self.lines:
            if zone_line.rule_set is not None and zone_line.rule_set not in names:
                names.append(zone_line.rule_set)
        return names

    def line_number_at(self, time):
        for number, zone_line in enumerate(self.lines, 1):
            if zone_line.start <= time < zone_line.end:
                return number
        return None


def parse_rule(line):
    fields = line.fields
    from_year = tz_parser.parse_year(fields[2])
    to_year = tz_parser.parse_to(fields[3], from_year)
    if fields[4] != "-":
        raise FieldError("syntax error")
    month = tz_parser.parse_month(fields[5])
    day = tz_parser.parse_day_spec(fields[6], month)
    at, at_type = tz_parser.parse_time(fields[7])
    save = tz_parser.parse_save(fields[8])
    letter = tz_parser.parse_letter(fields[9])
    return Rule(line.number, fields, from_year, to_year, month, day, at, at_type, save, letter)


def standard_letter(instances):
    for instance in instances:
        if instance.rule.save == 0:
            return instance.rule.letter
    return ""


class Database:
    def __init__(self, raw_lines):
        self.lines = []
        for number, raw in enumerate(raw_lines, 1):
            content = tz_parser.line_content(raw)
            if content:
                self.lines.append(SourceLine(number, content))
        self.blocks = []
        self.rules = {}
        self.sequences = {}
        self.zones = {}
        self.aliases = {}
        self.assemble_blocks()
        for line in self.lines:
            self.check_fields(line)
        zone_names = set()
        for line in self.lines:
            if line.zone_line is not None:
                line.error = self.structural_error(line, zone_names)
        for name, rules in self.rules.items():
            self.sequences[name] = instance_sequence(rules)
        for block in self.blocks:
            block.defined = all(line.error is None for line in block.lines)
            if block.defined:
                self.define_zone(block)
        for line in self.lines:
            if line.kind == "Link" and line.error is None:
                self.register_link(line)

    def assemble_blocks(self):
        previous = None
        for line in self.lines:
            if line.kind == "Zone":
                self.blocks.append(Block(line))
            elif line.kind == "continuation" and previous is not None:
                if previous.block is not None and previous.accepts_continuation():
                    previous.block.add(line)
            previous = line

    def check_fields(self, line):
        try:
            self.parse_fields(line)
        except FieldError as error:
            line.field_error = True
            line.error = str(error)

    def parse_fields(self, line):
        if line.kind == "unknown" or line.kind == "continuation" and line.block is None:
            raise FieldError("syntax error")
        low, high = FIELD_COUNTS[line.kind]
        if not low <= len(line.fields) <= high:
            raise FieldError("syntax error")
        if line.kind == "Rule":
            rule = parse_rule(line)
            self.rules.setdefault(rule.name, []).append(rule)
        elif line.kind == "Zone":
            line.zone_line = ZoneLine(line.fields[2:])
        elif line.kind == "continuation":
            line.zone_line = ZoneLine(line.fields)

    def structural_error(self, line, zone_names):
        zone_line = line.zone_line
        if line.kind == "Zone":
            name = line.fields[1]
            if name in zone_names:
                return "duplicate zone " + name
            zone_names.add(name)
        if zone_line.rule_set is not None and zone_line.rule_set not in self.rules:
            return "unknown rule " + zone_line.rule_set
        if zone_line.until is None:
            return None
        block_lines = line.block.lines
        if line.kind == "continuation":
            previous = block_lines[line.position - 1]
            if not previous.field_error and zone_line.until.value <= previous.zone_line.until.value:
                return "until not increasing"
        if line.position == len(block_lines) - 1:
            return "missing continuation"
        return None

    def define_zone(self, block):
        zone = Zone(block.name, [line.zone_line for line in block.lines])
        switches = []
        start = NEG_INFINITY
        for zone_line in zone.lines:
            zone_line.start = start
            for time, save, letter in self.line_switches(zone, zone_line):
                name = abbreviation(zone_line.format_text, save, letter)
                switches.append(Period(time, zone_line.stdoff + save, save != 0, name))
            start = zone_line.end
        periods = []
        for period in switches:
            if not periods or periods[-1].state() != period.state():
                periods.append(period)
        zone.timeline = Timeline(periods)
        self.zones[zone.name] = zone

    def line_switches(self, zone, zone_line):
        until = zone_line.until
        if zone_line.rule_set is None:
            if until is not None:
                correction = adjustment(until.time_type, zone_line.stdoff, zone_line.save)
                zone_line.end = until.value - correction
            return [(zone_line.start, zone_line.save, "")]
        instances = self.sequences[zone_line.rule_set]
        run = run_instances(instances, zone_line.stdoff, zone_line.start, until)
        zone_line.end = run.end
        if run.pre_start:
            last = run.pre_start[-1]
            switches = [(zone_line.start, last.save, last.letter)]
        else:
            switches = [(zone_line.start, 0, standard_letter(instances))]
        for time, rule in run.applied:
            switches.append((time, rule.save, rule.letter))
            zone.applied[rule.number] = zone.applied.get(rule.number, 0) + 1
        return switches

    def register_link(self, line):
        target, alias = line.fields[1], line.fields[2]
        if target not in self.zones:
            line.error = "unknown link target " + target
        elif alias in self.zones or alias in self.aliases:
            line.error = "duplicate link " + alias
        else:
            self.aliases[alias] = self.zones[target]
            self.zones[target].aliases.append(alias)

    def find_zone(self, word):
        if word in self.zones:
            return self.zones[word]
        return self.aliases.get(word)

    def error_lines(self):
        return [f"line {line.number}: {line.error}" for line in self.lines if line.error is not None]


def offset_shift(timeline, index):
    return timeline.periods[index].offset - timeline.periods[index - 1].offset


def transitions_between(timeline, low, high):
    return [
        index for index in range(1, len(timeline.periods))
        if low <= timeline.starts[index] < high
    ]


def change_at(timeline, index):
    return change_text(timeline.starts[index], timeline.periods[index - 1], timeline.periods[index])


def transition_line(timeline, index):
    time = timeline.starts[index]
    shift = offset_shift(timeline, index)
    if shift > 0:
        kind = "gap " + duration_text(shift)
    elif shift < 0:
        kind = "overlap " + duration_text(-shift)
    else:
        kind = "no shift"
    local_before = local_text(time + timeline.periods[index - 1].offset)
    local_after = local_text(time + timeline.periods[index].offset)
    return f"{change_at(timeline, index)} (local {local_before} -> {local_after}, {kind})"


def shifts_text(timeline, indices):
    gaps = 0
    overlaps = 0
    unchanged = 0
    for index in indices:
        shift = offset_shift(timeline, index)
        if shift > 0:
            gaps += 1
        elif shift < 0:
            overlaps += 1
        else:
            unchanged += 1
    return f"gaps {gaps}, overlaps {overlaps}, no shift {unchanged}"


def candidate_text(timeline, local, index):
    period = timeline.periods[index]
    return f"{ut_text(local - period.offset)} ({state_text(period)})"


def chosen_candidate(candidates, option):
    if len(candidates) == 1:
        return candidates[0]
    if len(candidates) == 2 and option == "EARLIER":
        return candidates[0]
    if len(candidates) == 2 and option == "LATER":
        return candidates[1]
    return None


def unresolved_text(timeline, local, candidates):
    if candidates:
        texts = [candidate_text(timeline, local, index) for index in candidates]
        return "AMBIGUOUS " + " or ".join(texts)
    index = timeline.skipping_transition(local)
    time = timeline.starts[index]
    local_before = local_text(time + timeline.periods[index - 1].offset)
    local_after = local_text(time + timeline.periods[index].offset)
    return f"NONEXISTENT gap {local_before} to {local_after} at {ut_text(time)}"


def working_hours(timeline, start, end):
    pieces = []
    for index in timeline.nearby(start, end):
        offset = timeline.periods[index].offset
        low = max(start - offset, timeline.starts[index])
        high = min(end - offset, timeline.end_of(index))
        if low < high:
            pieces.append((low, high))
    return merge_intervals(pieces)


def parse_value(kind, word):
    year = int(word[0:4])
    if not MIN_YEAR <= year <= MAX_YEAR:
        return None
    if kind == "year":
        return year
    month = int(word[5:7])
    day = int(word[8:10])
    if not 1 <= month <= 12 or not 1 <= day <= days_in_month(year, month):
        return None
    if kind == "date":
        return day_number(year, month, day)
    hour = int(word[11:13])
    minute = int(word[14:16])
    second = int(word[17:19])
    if hour > 23 or minute > 59 or second > 59:
        return None
    return time_value(year, month, day, hour, minute, second)


def argument_kinds(command, count):
    if command == "MEETING":
        return ("date",) + ("zone",) * (count - 1)
    return ARGUMENT_KINDS[command]


class QueryRunner:
    def __init__(self, database, work_start, work_end):
        self.database = database
        self.work_start = work_start
        self.work_end = work_end
        self.answers = []
        self.transition_blocks = []

    def argument(self, kind, word):
        if kind == "zone":
            zone = self.database.find_zone(word)
            if zone is None:
                raise QueryError("unknown zone " + word)
            return zone
        value = parse_value(kind, word)
        if value is None:
            raise QueryError("invalid value " + word)
        return value

    def run(self, line):
        words = line.split(" ")
        command = words[0]
        arguments = words[1:]
        option = None
        if command in ("TOUTC", "CONVERT") and arguments[-1] in OPTIONS:
            option = arguments.pop()
        kinds = argument_kinds(command, len(arguments))
        try:
            values = [self.argument(kind, word) for kind, word in zip(kinds, arguments)]
            result = self.answer(line, command, values, arguments, option)
        except QueryError as error:
            result = f"ERROR {error}"
        self.answers.append(f"{line} => {result}")

    def answer(self, line, command, values, arguments, option):
        if command == "TOUTC":
            return self.to_utc(values[0], values[1], option)
        if command == "TOLOCAL":
            return self.to_local(values[0], values[1])
        if command == "CONVERT":
            return self.convert(values[0], values[1], values[2], option)
        if command == "OFFSET":
            return self.offset(values[0], values[1])
        if command == "TRANSITIONS":
            return self.transitions(line, values[0], values[1], values[2])
        if command == "DURATION":
            return self.duration(values[0], values[1:], arguments[1:])
        return self.meeting(values[0], values[1:], arguments[1:])

    def to_utc(self, zone, local, option):
        timeline = zone.timeline
        candidates = timeline.candidates(local)
        index = chosen_candidate(candidates, option)
        if index is None:
            return unresolved_text(timeline, local, candidates)
        return candidate_text(timeline, local, index)

    def to_local(self, zone, time):
        period = zone.timeline.period_at(time)
        return f"{local_text(time + period.offset)} ({state_text(period)})"

    def convert(self, source, target, local, option):
        candidates = source.timeline.candidates(local)
        index = chosen_candidate(candidates, option)
        if index is None:
            return unresolved_text(source.timeline, local, candidates)
        time = local - source.timeline.periods[index].offset
        period = target.timeline.period_at(time)
        target_local = time + period.offset
        shift = target_local // SECONDS_PER_DAY - local // SECONDS_PER_DAY
        shift_text = f"+{shift}" if shift > 0 else str(shift)
        return (
            f"{local_text(target_local)} ({state_text(period)}) at {ut_text(time)}, "
            f"day shift {shift_text}"
        )

    def offset(self, zone, time):
        timeline = zone.timeline
        index = timeline.index_at(time)
        text = state_text(timeline.periods[index])
        if index >= 1:
            text += " since " + ut_text(timeline.starts[index])
        if index + 1 < len(timeline.periods):
            text += " until " + ut_text(timeline.starts[index + 1])
        return text

    def transitions(self, line, zone, first_year, last_year):
        if first_year > last_year:
            raise QueryError("invalid range")
        timeline = zone.timeline
        selected = transitions_between(timeline, year_start(first_year), year_start(last_year + 1))
        block = [line]
        for index in selected:
            block.append(transition_line(timeline, index))
        block.append(shifts_text(timeline, selected))
        self.transition_blocks.append(block)
        return f"transitions: {len(selected)}"

    def duration(self, zone, locals_, words):
        timeline = zone.timeline
        periods = []
        for local, word in zip(locals_, words):
            candidates = timeline.candidates(local)
            if len(candidates) == 2:
                return "AMBIGUOUS " + word
            if not candidates:
                return "NONEXISTENT " + word
            periods.append(timeline.periods[candidates[0]])
        first, second = locals_
        elapsed = (second - periods[1].offset) - (first - periods[0].offset)
        change = periods[1].offset - periods[0].offset
        return (
            f"{elapsed} s ({duration_text(elapsed)}), wall clock {duration_text(second - first)}, "
            f"offset change {offset_text(change)}"
        )

    def meeting(self, day, zones, words):
        start = day * SECONDS_PER_DAY + self.work_start
        end = day * SECONDS_PER_DAY + self.work_end
        common = working_hours(zones[0].timeline, start, end)
        for zone in zones[1:]:
            common = intersect_intervals(common, working_hours(zone.timeline, start, end))
        if not common:
            return "NONE"
        parts = []
        for low, high in common:
            members = []
            for word, zone in zip(words, zones):
                period = zone.timeline.period_at(low)
                members.append(f"{word} {local_text(low + period.offset)} {period.abbreviation}")
            span = f"{ut_text(low)} to {ut_text(high)} ({duration_text(high - low)})"
            parts.append(f"{span} [{', '.join(members)}]")
        return "; ".join(parts)


def rule_text(rule):
    fields = rule.fields
    at = clock_text(rule.at) + rule.at_type
    return (
        f"rule {rule.name} {fields[2]} {fields[3]} {fields[5]} {fields[6]} {at} "
        f"{clock_text(rule.save)} {fields[9]}"
    )


def database_block(database):
    rule_lines = [line for line in database.lines if line.kind == "Rule"]
    link_lines = [line for line in database.lines if line.kind == "Link"]
    valid_rules = sum(1 for line in rule_lines if line.error is None)
    valid_links = sum(1 for line in link_lines if line.error is None)
    zones = list(database.zones.values())
    used = set()
    for zone in zones:
        used.update(zone.rule_sets())
    unused = [name for name in database.rules if name not in used]
    invalid = [f"{block.name} (line {block.number})" for block in database.blocks if not block.defined]
    lines = [
        "DATABASE",
        f"rule lines: {valid_rules} valid, {len(rule_lines) - valid_rules} invalid",
        f"zones: {len(zones)} defined, {len(database.blocks) - len(zones)} invalid",
        f"zone lines: {sum(len(zone.lines) for zone in zones)} in defined zones",
        f"links: {valid_links} defined, {len(link_lines) - valid_links} invalid",
        f"errors: {len(database.error_lines())}",
        "unused rules: " + names_or_none(unused, " "),
        "invalid zones: " + names_or_none(invalid, ", "),
    ]
    for name, rules in database.rules.items():
        first = min(rule.from_year for rule in rules)
        if any(rule.fields[3] == "max" for rule in rules):
            last = "max"
        else:
            last = str(max(rule.to_year for rule in rules))
        count = sum(1 for zone in zones if name in zone.rule_sets())
        lines.append(f"rule set {name}: lines {len(rules)}, years {first}-{last}, zones {count}")
    return lines


def dst_lines(timeline, reference):
    dst_indices = [index for index, period in enumerate(timeline.periods) if period.dst]
    if dst_indices:
        years = [split_time(timeline.starts[index])[0] for index in dst_indices]
        lines = [f"dst years: {min(years)}-{max(years)}"]
    else:
        lines = ["dst years: none"]
    year = split_time(reference)[0]
    low = year_start(year)
    high = year_start(year + 1)
    pieces = []
    for index in dst_indices:
        start = max(low, timeline.starts[index])
        end = min(high, timeline.end_of(index))
        if start < end:
            pieces.append((start, end))
    total = 0
    for start, end in merge_intervals(pieces):
        lines.append(f"dst period: {ut_text(start)} to {ut_text(end)} ({duration_text(end - start)})")
        total += end - start
    lines.append(f"dst total {year}: {duration_text(total)}")
    return lines


def zone_block(database, zone, reference):
    timeline = zone.timeline
    periods = timeline.periods
    lines = ["ZONE " + zone.name, "aliases: " + names_or_none(zone.aliases, " ")]
    for number, zone_line in enumerate(zone.lines, 1):
        text = (
            f"line {number}: {offset_text(zone_line.stdoff)} {zone_line.rules_notation()} "
            f"{zone_line.format_text}"
        )
        if number >= 2:
            text += " from " + ut_text(zone_line.start)
        if zone_line.until is not None:
            text += f" until {zone_line.until_notation()} = {ut_text(zone_line.end)}"
        count = len(transitions_between(timeline, zone_line.start, zone_line.end))
        lines.append(f"{text}, transitions {count}")
    for name in zone.rule_sets():
        for rule in database.rules[name]:
            lines.append(f"{rule_text(rule)}, applied {zone.applied.get(rule.number, 0)}")
    offsets = [period.offset for period in periods]
    lines.append(f"offset range: {offset_text(min(offsets))} to {offset_text(max(offsets))}")
    state_counts = {}
    for period in periods:
        state = state_text(period)
        state_counts[state] = state_counts.get(state, 0) + 1
    for state, count in state_counts.items():
        lines.append(f"state {state}, periods {count}")
    index = timeline.index_at(reference)
    period = periods[index]
    lines.append(
        f"reference: {local_text(reference + period.offset)} ({state_text(period)}), "
        f"line {zone.line_number_at(reference)}"
    )
    previous_change = change_at(timeline, index) if index >= 1 else "none"
    next_change = change_at(timeline, index + 1) if index + 1 < len(periods) else "none"
    lines.append("previous transition: " + previous_change)
    lines.append("next transition: " + next_change)
    every = list(range(1, len(periods)))
    lines.append(f"transitions: {len(every)}, {shifts_text(timeline, every)}")
    lines.extend(dst_lines(timeline, reference))
    return lines


def main():
    database = Database(read_lines(os.path.join(INPUT_DIR, "tzdata.txt")))
    params = read_lines(os.path.join(INPUT_DIR, "params.txt"))
    reference = parse_value("ut", params[0].split(" ")[1])
    workday = params[1].split(" ")
    runner = QueryRunner(database, clock_seconds(workday[1]), clock_seconds(workday[2]))
    for line in read_lines(os.path.join(INPUT_DIR, "queries.txt")):
        runner.run(line)
    blocks = [indented(database_block(database))]
    for name in sorted(database.zones):
        blocks.append(indented(zone_block(database, database.zones[name], reference)))
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    write_lines(os.path.join(OUTPUT_DIR, "answers.txt"), runner.answers)
    write_lines(os.path.join(OUTPUT_DIR, "errors.txt"), database.error_lines())
    write_blocks(os.path.join(OUTPUT_DIR, "transitions.txt"), runner.transition_blocks)
    write_blocks(os.path.join(OUTPUT_DIR, "zone_summary.txt"), blocks)


if __name__ == "__main__":
    main()
