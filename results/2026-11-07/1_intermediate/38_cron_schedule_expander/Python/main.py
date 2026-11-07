from collections import Counter
import sys


MINUTES_PER_DAY = 1440
LOOKAHEAD = 527040
WINDOW_LIMIT = 44640
DISPLAY_LIMIT = 100
MONTH_LENGTHS = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
WEEKDAY_ABBREVIATIONS = ("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")
WEEKDAY_NAMES = (
    "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
)
MONTH_NAMES = (
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
)
MONTH_CODES = (
    "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC",
)
WEEKDAY_CODES = ("SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT")
ORDINALS = ("1st", "2nd", "3rd", "4th", "5th")
MACROS = {
    "@yearly": "0 0 1 1 *",
    "@annually": "0 0 1 1 *",
    "@monthly": "0 0 1 * *",
    "@weekly": "0 0 * * 0",
    "@daily": "0 0 * * *",
    "@midnight": "0 0 * * *",
    "@hourly": "0 * * * *",
}
POLICIES = ("ALLOW", "FORBID", "REPLACE")
ID_CHARACTERS = "abcdefghijklmnopqrstuvwxyz0123456789_"


class CommandError(Exception):
    pass


def is_leap(year):
    return year % 4 == 0 and year % 100 != 0 or year % 400 == 0


def month_length(year, month):
    if month == 2 and is_leap(year):
        return 29
    return MONTH_LENGTHS[month - 1]


def leap_years_through(year):
    return year // 4 - year // 100 + year // 400


def year_start(year):
    return 365 * (year - 2000) + leap_years_through(year - 1) - leap_years_through(1999)


def day_number(year, month, day):
    number = year_start(year) + day - 1
    for earlier in range(1, month):
        number += month_length(year, earlier)
    return number


def civil_date(number):
    year = 2000 + number // 366
    while year_start(year + 1) <= number:
        year += 1
    day = number - year_start(year) + 1
    month = 1
    while day > month_length(year, month):
        day -= month_length(year, month)
        month += 1
    return year, month, day


def weekday_of(number):
    return (number + 6) % 7


def clock_text(offset):
    return f"{offset // 60:02d}:{offset % 60:02d}"


def date_text(number):
    year, month, day = civil_date(number)
    return f"{year:04d}-{month:02d}-{day:02d}"


def date_notation(number):
    return date_text(number) + " " + WEEKDAY_ABBREVIATIONS[weekday_of(number)]


def datetime_notation(minute):
    number, offset = divmod(minute, MINUTES_PER_DAY)
    weekday = WEEKDAY_ABBREVIATIONS[weekday_of(number)]
    return f"{date_text(number)} {clock_text(offset)} {weekday}"


def span_notation(minutes):
    days, rest = divmod(minutes, MINUTES_PER_DAY)
    return f"{days}d{rest // 60:02d}h{rest % 60:02d}m"


class CalendarDate:
    def __init__(self, number):
        self.number = number
        self.year, self.month, self.day = civil_date(number)
        self.length = month_length(self.year, self.month)
        self.weekday = weekday_of(number)

    def nearest_weekday(self, target):
        weekday = weekday_of(self.number - self.day + target)
        if weekday == 6:
            return 3 if target == 1 else target - 1
        if weekday == 0:
            return target - 2 if target == self.length else target + 1
        return target


class FieldSpec:
    def __init__(self, name, low, high, codes=(), labels=()):
        self.name = name
        self.low = low
        self.high = high
        self.codes = codes
        self.labels = labels

    def error(self, reason):
        return CommandError(f"{self.name} {reason}")

    def number(self, text, low, high, width=2):
        if not (1 <= len(text) <= width and text.isdigit()):
            raise self.error("invalid value")
        value = int(text)
        if not low <= value <= high:
            raise self.error("out of range")
        return value

    def value(self, text):
        if text in self.codes:
            return self.low + self.codes.index(text)
        return self.number(text, self.low, self.high)

    def label(self, value):
        if self.labels:
            return self.labels[value - self.low]
        return str(value)


FIELD_SPECS = (
    FieldSpec("minute", 0, 59),
    FieldSpec("hour", 0, 23),
    FieldSpec("day-of-month", 1, 31),
    FieldSpec("month", 1, 12, MONTH_CODES, MONTH_NAMES),
    FieldSpec("day-of-week", 0, 7, WEEKDAY_CODES, WEEKDAY_NAMES),
)


class Special:
    def __init__(self, kind, number=0, weekday=0):
        self.kind = kind
        self.number = number
        self.weekday = weekday

    def canonical(self):
        if self.kind == "L-n":
            return f"L-{self.number}"
        if self.kind == "nW":
            return f"{self.number}W"
        if self.kind == "v#n":
            return f"{self.weekday}#{self.number}"
        if self.kind == "vL":
            return f"{self.weekday}L"
        return self.kind

    def matches(self, date):
        if self.kind == "L":
            return date.day == date.length
        if self.kind == "LW":
            return date.day == date.nearest_weekday(date.length)
        if self.kind == "L-n":
            return date.day == date.length - self.number
        if self.kind == "nW":
            return self.number <= date.length and date.day == date.nearest_weekday(self.number)
        if self.kind == "v#n":
            return date.weekday == self.weekday and (date.day - 1) // 7 + 1 == self.number
        return date.weekday == self.weekday and date.day + 7 > date.length

    def phrase(self):
        if self.kind == "L":
            return "the last day"
        if self.kind == "LW":
            return "the last weekday"
        if self.kind == "L-n":
            if self.number == 1:
                return "1 day before the last day"
            return f"{self.number} days before the last day"
        if self.kind == "nW":
            return f"the weekday nearest day {self.number}"
        if self.kind == "v#n":
            return f"the {ORDINALS[self.number - 1]} {WEEKDAY_NAMES[self.weekday]}"
        return f"the last {WEEKDAY_NAMES[self.weekday]}"


class Field:
    def __init__(self, spec, text):
        self.spec = spec
        self.values = set()
        self.specials = []
        self.restricted = text[0] != "*"
        for item in text.split(","):
            self.add_item(item)

    def add_item(self, item):
        spec = self.spec
        if item == "":
            raise spec.error("empty item")
        if spec.name == "day-of-month" and (item[0] == "L" or item[-1] == "W"):
            self.add_special(self.day_special(item))
        elif spec.name == "day-of-week" and "#" in item:
            weekday_text, _, number_text = item.partition("#")
            weekday = spec.value(weekday_text) % 7
            self.add_special(Special("v#n", spec.number(number_text, 1, 5, 1), weekday))
        elif spec.name == "day-of-week" and len(item) >= 2 and item[-1] == "L":
            self.add_special(Special("vL", 0, spec.value(item[:-1]) % 7))
        else:
            self.add_range(item)

    def day_special(self, item):
        if item in ("L", "LW"):
            return Special(item)
        if item.startswith("L-"):
            return Special("L-n", self.spec.number(item[2:], 1, 30))
        if item[-1] == "W":
            return Special("nW", self.spec.number(item[:-1], 1, 31))
        raise self.spec.error("invalid value")

    def add_range(self, item):
        spec = self.spec
        base, slash, step_text = item.partition("/")
        if base == "*":
            first, last = spec.low, spec.high
        elif "-" in base:
            first_text, _, last_text = base.partition("-")
            first = spec.value(first_text)
            last = spec.value(last_text)
            if first > last:
                raise spec.error("invalid range")
        else:
            first = spec.value(base)
            last = spec.high if slash else first
        step = 1
        if slash:
            if not (1 <= len(step_text) <= 2 and step_text.isdigit() and int(step_text) >= 1):
                raise spec.error("invalid step")
            step = int(step_text)
        for value in range(first, last + 1, step):
            self.values.add(value % 7 if spec.name == "day-of-week" else value)

    def add_special(self, special):
        if all(other.canonical() != special.canonical() for other in self.specials):
            self.specials.append(special)

    def matches(self, value, date):
        return value in self.values or any(special.matches(date) for special in self.specials)


class Cron:
    def __init__(self, tokens):
        if len(tokens) == 1 and tokens[0][0] == "@":
            if tokens[0] not in MACROS:
                raise CommandError("unknown macro")
            tokens = MACROS[tokens[0]].split()
        if len(tokens) != 5:
            raise CommandError("field count")
        self.expanded = " ".join(tokens)
        self.fields = [Field(spec, text) for spec, text in zip(FIELD_SPECS, tokens)]
        self.minute, self.hour, self.day, self.month, self.weekday = self.fields
        self.times = [
            hour * 60 + minute
            for hour in sorted(self.hour.values)
            for minute in sorted(self.minute.values)
        ]

    def field(self, name):
        for field in self.fields:
            if field.spec.name == name:
                return field
        return None

    def both_restricted(self):
        return self.day.restricted and self.weekday.restricted

    def day_condition(self, date):
        day_matches = self.day.matches(date.day, date)
        weekday_matches = self.weekday.matches(date.weekday, date)
        if self.both_restricted():
            return day_matches or weekday_matches
        return day_matches and weekday_matches

    def scheduled(self, date):
        return date.month in self.month.values and self.day_condition(date)


def join_list(items, word="and"):
    if len(items) == 1:
        return items[0]
    return ", ".join(items[:-1]) + f" {word} " + items[-1]


def value_list(field, word="and"):
    values = sorted(field.values)
    label = field.spec.label
    items = []
    start = 0
    while start < len(values):
        end = start
        while end + 1 < len(values) and values[end + 1] == values[end] + 1:
            end += 1
        if end - start >= 2:
            items.append(f"{label(values[start])} through {label(values[end])}")
        else:
            items.extend(label(value) for value in values[start:end + 1])
        start = end + 1
    return join_list(items, word)


def step_of(field):
    values = sorted(field.values)
    if len(values) < 2 or values[0] != 0 or values[1] < 2:
        return None
    if values != list(range(0, field.spec.high + 1, values[1])):
        return None
    return values[1]


def time_phrase(cron):
    minutes = sorted(cron.minute.values)
    hours = sorted(cron.hour.values)
    if len(cron.times) <= 4:
        return "At " + join_list([clock_text(offset) for offset in cron.times])
    minute_step = step_of(cron.minute)
    if len(minutes) == 60:
        phrase = "Every minute"
    elif minute_step is not None:
        phrase = f"Every {minute_step} minutes"
    elif len(minutes) == 1:
        phrase = f"At minute {minutes[0]}"
    else:
        phrase = "At minutes " + value_list(cron.minute)
    if phrase.startswith("At minute") and len(hours) == 24:
        return phrase + " of every hour"
    hour_step = step_of(cron.hour)
    if len(hours) == 24:
        return phrase
    if hour_step is not None:
        return phrase + f", every {hour_step} hours"
    if hours[-1] - hours[0] == len(hours) - 1:
        return phrase + f", between {hours[0]:02d}:00 and {hours[-1]:02d}:59"
    return phrase + ", during hours " + value_list(cron.hour)


def day_of_month_clause(field):
    parts = []
    days = sorted(field.values)
    if len(days) == 1:
        parts.append(f"day {days[0]}")
    elif days:
        parts.append("days " + value_list(field))
    parts.extend(special.phrase() for special in field.specials)
    return join_list(parts) + " of the month"


def day_of_week_clause(field, word):
    parts = []
    if field.values:
        parts.append(value_list(field, word))
    parts.extend(special.phrase() for special in field.specials)
    clause = join_list(parts, word)
    if field.specials:
        clause += " of the month"
    return clause


def day_phrase(cron):
    day_full = len(cron.day.values) == 31
    weekday_full = len(cron.weekday.values) == 7
    if cron.both_restricted():
        if day_full or weekday_full:
            return ""
        day_clause = day_of_month_clause(cron.day)
        return f", on {day_clause} or on {day_of_week_clause(cron.weekday, 'and')}"
    if not day_full and not weekday_full:
        day_clause = day_of_month_clause(cron.day)
        return f", on {day_clause} if it is {day_of_week_clause(cron.weekday, 'or')}"
    if not day_full:
        return ", on " + day_of_month_clause(cron.day)
    if not weekday_full:
        return ", on " + day_of_week_clause(cron.weekday, "and")
    return ""


def month_phrase(cron):
    if len(cron.month.values) == 12:
        return ""
    return ", in " + value_list(cron.month)


def description(cron):
    return time_phrase(cron) + day_phrase(cron) + month_phrase(cron)


def is_job_id(text):
    if not 1 <= len(text) <= 16 or not "a" <= text[0] <= "z":
        return False
    return all(character in ID_CHARACTERS for character in text)


def date_value(text):
    if len(text) != 10 or text[4] != "-" or text[7] != "-":
        return None
    if not (text[:4] + text[5:7] + text[8:]).isdigit():
        return None
    year, month, day = int(text[:4]), int(text[5:7]), int(text[8:])
    if not (2001 <= year <= 2098 and 1 <= month <= 12):
        return None
    if not 1 <= day <= month_length(year, month):
        return None
    return day_number(year, month, day)


def time_value(text):
    if len(text) != 5 or text[2] != ":" or not (text[:2] + text[3:]).isdigit():
        return None
    hour, minute = int(text[:2]), int(text[3:])
    if hour > 23 or minute > 59:
        return None
    return hour * 60 + minute


def parse_date(text):
    number = date_value(text)
    if number is None:
        raise CommandError("invalid date")
    return number


def parse_datetime(date, time):
    number = date_value(date)
    offset = time_value(time)
    if number is None or offset is None:
        raise CommandError("invalid datetime")
    return number * MINUTES_PER_DAY + offset


def parse_year_month(text):
    if len(text) != 7 or text[4] != "-" or not (text[:4] + text[5:]).isdigit():
        raise CommandError("invalid month")
    year, month = int(text[:4]), int(text[5:])
    if not (2001 <= year <= 2098 and 1 <= month <= 12):
        raise CommandError("invalid month")
    return year, month


def parse_limited(text, width, maximum, reason):
    if not (1 <= len(text) <= width and text.isdigit() and text[0] != "0"):
        raise CommandError(reason)
    if int(text) > maximum:
        raise CommandError(reason)
    return int(text)


def hour_symbol(count):
    if count == 0:
        return "."
    if count <= 9:
        return str(count)
    return "+"


class Job:
    def __init__(self, job_id, cron, text):
        self.id = job_id
        self.cron = cron
        self.text = text
        self.enabled = True
        self.duration = 1
        self.policy = "ALLOW"


class Execution:
    def __init__(self, start, end):
        self.start = start
        self.end = end


class Scheduler:
    def __init__(self):
        self.jobs = {}
        self.holidays = set()
        self.output = []
        self.handlers = {
            "JOB": (2, None, self.add_job),
            "VALIDATE": (1, None, self.validate),
            "REMOVE": (1, 1, self.remove),
            "RENAME": (2, 2, self.rename),
            "ENABLE": (1, 1, self.enable),
            "DISABLE": (1, 1, self.disable),
            "RUNTIME": (3, 3, self.runtime),
            "LIST": (0, 0, self.list_jobs),
            "EXPAND": (2, 2, self.expand),
            "DESCRIBE": (1, 1, self.describe),
            "MATCH": (3, 3, self.match),
            "NEXT": (4, 4, self.next_fires),
            "PREV": (4, 4, self.previous_fires),
            "COUNT": (5, 5, self.count),
            "GAP": (3, 3, self.gap),
            "OVERLAP": (6, 6, self.overlap),
            "TIMELINE": (4, 4, self.timeline),
            "CONFLICTS": (4, 4, self.conflicts),
            "WEEK": (1, 1, self.week),
            "CALENDAR": (2, 2, self.calendar),
            "SIMULATE": (4, 4, self.simulate),
            "EXCLUDE": (1, 1, self.exclude),
            "INCLUDE": (1, 1, self.include),
            "HOLIDAYS": (0, 0, self.show_holidays),
        }

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def job(self, job_id):
        if job_id not in self.jobs:
            raise CommandError("unknown job")
        return self.jobs[job_id]

    def new_id(self, job_id):
        if not is_job_id(job_id):
            raise CommandError("invalid id")
        if job_id in self.jobs:
            raise CommandError("duplicate job")
        return job_id

    def window(self, arguments):
        lo = parse_datetime(arguments[0], arguments[1])
        hi = parse_datetime(arguments[2], arguments[3])
        if lo > hi:
            raise CommandError("invalid window")
        if hi - lo > WINDOW_LIMIT:
            raise CommandError("window too long")
        return lo, hi

    def sorted_jobs(self):
        return [self.jobs[job_id] for job_id in sorted(self.jobs)]

    def enabled_jobs(self):
        return [job for job in self.sorted_jobs() if job.enabled]

    def runs_on(self, job, date):
        return job.cron.scheduled(date) and date.number not in self.holidays

    def fire_times(self, job, lo, hi, limit=None):
        times = []
        for number in range(lo // MINUTES_PER_DAY, hi // MINUTES_PER_DAY + 1):
            if not self.runs_on(job, CalendarDate(number)):
                continue
            for offset in job.cron.times:
                minute = number * MINUTES_PER_DAY + offset
                if lo <= minute <= hi:
                    times.append(minute)
                    if len(times) == limit:
                        return times
        return times

    def fire_times_backward(self, job, lo, hi, limit):
        times = []
        for number in range(hi // MINUTES_PER_DAY, lo // MINUTES_PER_DAY - 1, -1):
            if not self.runs_on(job, CalendarDate(number)):
                continue
            for offset in reversed(job.cron.times):
                minute = number * MINUTES_PER_DAY + offset
                if lo <= minute <= hi:
                    times.append(minute)
                    if len(times) == limit:
                        return times
        return times

    def firing_slots(self, lo, hi):
        slots = [[] for _ in range(hi - lo + 1)]
        for job in self.enabled_jobs():
            for minute in self.fire_times(job, lo, hi):
                slots[minute - lo].append(job.id)
        return slots

    def mismatches(self, job, minute):
        cron = job.cron
        date = CalendarDate(minute // MINUTES_PER_DAY)
        offset = minute % MINUTES_PER_DAY
        satisfied = cron.day_condition(date)
        reasons = []
        if offset % 60 not in cron.minute.values:
            reasons.append("minute")
        if offset // 60 not in cron.hour.values:
            reasons.append("hour")
        if not satisfied and not cron.day.matches(date.day, date):
            reasons.append("day-of-month")
        if date.month not in cron.month.values:
            reasons.append("month")
        if not satisfied and not cron.weekday.matches(date.weekday, date):
            reasons.append("day-of-week")
        if date.number in self.holidays:
            reasons.append("excluded")
        return reasons

    def add_job(self, arguments):
        job_id = self.new_id(arguments[0])
        cron = Cron(arguments[1:])
        self.jobs[job_id] = Job(job_id, cron, " ".join(arguments[1:]))
        self.emit("JOB", job_id, "added")

    def validate(self, arguments):
        cron = Cron(arguments)
        rule = "OR" if cron.both_restricted() else "AND"
        self.emit("VALID", cron.expanded, rule, len(cron.times))

    def remove(self, arguments):
        job = self.job(arguments[0])
        del self.jobs[job.id]
        self.emit("REMOVE", job.id)

    def rename(self, arguments):
        job = self.job(arguments[0])
        new_id = self.new_id(arguments[1])
        del self.jobs[job.id]
        job.id = new_id
        self.jobs[new_id] = job
        self.emit("RENAME", arguments[0], new_id)

    def enable(self, arguments):
        job = self.job(arguments[0])
        if job.enabled:
            raise CommandError("already enabled")
        job.enabled = True
        self.emit("ENABLE", job.id)

    def disable(self, arguments):
        job = self.job(arguments[0])
        if not job.enabled:
            raise CommandError("already disabled")
        job.enabled = False
        self.emit("DISABLE", job.id)

    def runtime(self, arguments):
        job = self.job(arguments[0])
        duration = parse_limited(arguments[1], 4, MINUTES_PER_DAY, "invalid duration")
        policy = arguments[2]
        if policy not in POLICIES:
            raise CommandError("invalid policy")
        job.duration = duration
        job.policy = policy
        self.emit("RUNTIME", job.id, duration, policy)

    def list_jobs(self, arguments):
        self.emit("LIST", len(self.jobs))
        for job in self.sorted_jobs():
            status = "on" if job.enabled else "off"
            self.emit(job.id, status, job.duration, job.policy, job.text)

    def expand(self, arguments):
        job = self.job(arguments[0])
        field = job.cron.field(arguments[1])
        if field is None:
            raise CommandError("invalid field")
        values = sorted(field.values)
        specials = [special.canonical() for special in field.specials]
        self.emit("EXPAND", job.id, arguments[1], len(values), *values, *specials)

    def describe(self, arguments):
        job = self.job(arguments[0])
        self.emit("DESCRIBE", job.id, description(job.cron))

    def match(self, arguments):
        job = self.job(arguments[0])
        minute = parse_datetime(arguments[1], arguments[2])
        reasons = self.mismatches(job, minute)
        if reasons:
            self.emit("MATCH", job.id, datetime_notation(minute), "no", *reasons)
        else:
            self.emit("MATCH", job.id, datetime_notation(minute), "yes")

    def next_fires(self, arguments):
        job = self.job(arguments[0])
        base = parse_datetime(arguments[1], arguments[2])
        count = parse_limited(arguments[3], 2, 50, "invalid count")
        times = self.fire_times(job, base + 1, base + LOOKAHEAD, count)
        self.emit("NEXT", job.id, len(times))
        for minute in times:
            self.emit(datetime_notation(minute), "+" + span_notation(minute - base))
        if len(times) < count:
            self.emit("NONE")

    def previous_fires(self, arguments):
        job = self.job(arguments[0])
        base = parse_datetime(arguments[1], arguments[2])
        count = parse_limited(arguments[3], 2, 50, "invalid count")
        times = self.fire_times_backward(job, base - LOOKAHEAD, base - 1, count)
        self.emit("PREV", job.id, len(times))
        for minute in times:
            self.emit(datetime_notation(minute), "-" + span_notation(base - minute))
        if len(times) < count:
            self.emit("NONE")

    def count(self, arguments):
        job = self.job(arguments[0])
        lo, hi = self.window(arguments[1:])
        times = self.fire_times(job, lo, hi)
        days = {minute // MINUTES_PER_DAY for minute in times}
        self.emit("COUNT", job.id, "runs", len(times), "days", len(days))

    def gap(self, arguments):
        job = self.job(arguments[0])
        base = parse_datetime(arguments[1], arguments[2])
        times = self.fire_times(job, base, base + WINDOW_LIMIT)
        if len(times) < 2:
            self.emit("GAP", job.id, "runs", len(times), "none")
            return
        gaps = [later - earlier for earlier, later in zip(times, times[1:])]
        longest = max(gaps)
        index = gaps.index(longest)
        self.emit(
            "GAP", job.id, "runs", len(times),
            "shortest", span_notation(min(gaps)), "longest", span_notation(longest),
            "from", datetime_notation(times[index]),
            "to", datetime_notation(times[index + 1]),
        )
        tally = Counter(gaps)
        for value in sorted(tally):
            self.emit(span_notation(value), tally[value])

    def overlap(self, arguments):
        first = self.job(arguments[0])
        second = self.job(arguments[1])
        lo, hi = self.window(arguments[2:])
        second_times = set(self.fire_times(second, lo, hi))
        common = [minute for minute in self.fire_times(first, lo, hi) if minute in second_times]
        if not common:
            self.emit("OVERLAP", first.id, second.id, 0)
            return
        self.emit(
            "OVERLAP", first.id, second.id, len(common),
            "first", datetime_notation(common[0]), "last", datetime_notation(common[-1]),
        )

    def timeline(self, arguments):
        lo, hi = self.window(arguments)
        pairs = []
        for offset, job_ids in enumerate(self.firing_slots(lo, hi)):
            for job_id in job_ids:
                pairs.append((lo + offset, job_id))
        self.emit("TIMELINE", len(pairs))
        for minute, job_id in pairs[:DISPLAY_LIMIT]:
            self.emit(datetime_notation(minute), job_id)
        if len(pairs) > DISPLAY_LIMIT:
            self.emit("...", len(pairs) - DISPLAY_LIMIT, "more")

    def conflicts(self, arguments):
        lo, hi = self.window(arguments)
        conflicts = [
            (lo + offset, job_ids)
            for offset, job_ids in enumerate(self.firing_slots(lo, hi))
            if len(job_ids) >= 2
        ]
        peak = max((len(job_ids) for _, job_ids in conflicts), default=0)
        self.emit("CONFLICTS", len(conflicts), "peak", peak)
        for minute, job_ids in conflicts[:DISPLAY_LIMIT]:
            self.emit(datetime_notation(minute), len(job_ids), *job_ids)
        if len(conflicts) > DISPLAY_LIMIT:
            self.emit("...", len(conflicts) - DISPLAY_LIMIT, "more")

    def week(self, arguments):
        start = parse_date(arguments[0])
        lo = start * MINUTES_PER_DAY
        hi = lo + 7 * MINUTES_PER_DAY - 1
        counts = [0] * (7 * 24)
        for job in self.enabled_jobs():
            for minute in self.fire_times(job, lo, hi):
                counts[(minute - lo) // 60] += 1
        self.emit("WEEK", arguments[0], sum(counts))
        for index in range(7):
            hours = counts[index * 24:(index + 1) * 24]
            symbols = "".join(hour_symbol(count) for count in hours)
            self.emit(date_notation(start + index), symbols, sum(hours))

    def calendar(self, arguments):
        job = self.job(arguments[0])
        year, month = parse_year_month(arguments[1])
        first = day_number(year, month, 1)
        cells = ["..."] * weekday_of(first)
        days = 0
        for day in range(1, month_length(year, month) + 1):
            date = CalendarDate(first + day - 1)
            if not job.cron.scheduled(date):
                mark = "-"
            elif date.number in self.holidays:
                mark = "x"
            else:
                mark = "*"
                days += 1
            cells.append(f"{day:02d}{mark}")
        while len(cells) % 7 != 0:
            cells.append("...")
        runs = days * len(job.cron.times)
        self.emit("CALENDAR", job.id, arguments[1], "days", days, "runs", runs)
        self.emit(*WEEKDAY_ABBREVIATIONS)
        for start in range(0, len(cells), 7):
            self.emit(*cells[start:start + 7])

    def simulate(self, arguments):
        lo, hi = self.window(arguments)
        jobs = self.enabled_jobs()
        changes = [0] * (hi - lo + MINUTES_PER_DAY + 1)
        summaries = []
        for job in jobs:
            executions = []
            skipped = 0
            replaced = 0
            for minute in self.fire_times(job, lo, hi):
                previous = executions[-1] if executions else None
                running = previous is not None and previous.end > minute
                if running and job.policy == "FORBID":
                    skipped += 1
                    continue
                if running and job.policy == "REPLACE":
                    previous.end = minute
                    replaced += 1
                executions.append(Execution(minute, minute + job.duration))
            for execution in executions:
                changes[execution.start - lo] += 1
                changes[execution.end - lo] -= 1
            busy = sum(execution.end - execution.start for execution in executions)
            summaries.append((job, len(executions), skipped, replaced, busy))
        peak = 0
        peak_minute = lo
        running = 0
        for offset, change in enumerate(changes):
            running += change
            if running > peak:
                peak = running
                peak_minute = lo + offset
        if peak > 0:
            self.emit("SIMULATE", len(jobs), "peak", peak, "at", datetime_notation(peak_minute))
        else:
            self.emit("SIMULATE", len(jobs), "peak", 0)
        for job, started, skipped, replaced, busy in summaries:
            self.emit(
                job.id, job.policy, "started", started, "skipped", skipped,
                "replaced", replaced, "busy", busy,
            )

    def exclude(self, arguments):
        number = parse_date(arguments[0])
        if number in self.holidays:
            raise CommandError("already excluded")
        self.holidays.add(number)
        self.emit("EXCLUDE", date_notation(number), "holidays", len(self.holidays))

    def include(self, arguments):
        number = parse_date(arguments[0])
        if number not in self.holidays:
            raise CommandError("not excluded")
        self.holidays.remove(number)
        self.emit("INCLUDE", date_notation(number), "holidays", len(self.holidays))

    def show_holidays(self, arguments):
        self.emit("HOLIDAYS", len(self.holidays))
        for number in sorted(self.holidays):
            self.emit(date_notation(number))

    def execute(self, tokens):
        name, arguments = tokens[0], tokens[1:]
        try:
            if name not in self.handlers:
                raise CommandError("unknown command")
            minimum, maximum, handler = self.handlers[name]
            if len(arguments) < minimum or (maximum is not None and len(arguments) > maximum):
                raise CommandError("wrong arguments")
            handler(arguments)
        except CommandError as error:
            self.emit("ERROR", error)


def main():
    scheduler = Scheduler()
    count = int(sys.stdin.readline())
    for _ in range(count):
        scheduler.execute(sys.stdin.readline().split())
    sys.stdout.write("\n".join(scheduler.output) + "\n")


if __name__ == "__main__":
    main()
