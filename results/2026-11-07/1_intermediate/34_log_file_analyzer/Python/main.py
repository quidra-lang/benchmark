from collections import Counter
from fractions import Fraction
import sys


METHODS = ("GET", "HEAD", "POST", "PUT", "DELETE", "PATCH", "OPTIONS")
REASONS = ("fields", "date", "time", "ip", "method", "path", "status", "bytes", "latency")
MONTH_DAYS = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
HEX_DIGITS = "0123456789abcdef"
STATUS_CLASSES = ("1xx", "2xx", "3xx", "4xx", "5xx")
FILTER_KEYS = ("METHOD", "STATUS", "IP", "PATH")
TOP_KINDS = ("PATHS", "IPS")
NUMBER_RANGES = {
    "limit": (1, 100),
    "minutes": (1, 1440),
    "width": (1, 100000),
    "threshold": (1, 100000),
    "length": (1, 86400),
    "times": (1, 1000),
}
ARGUMENT_ERRORS = {
    "limit": "invalid number",
    "minutes": "invalid number",
    "width": "invalid number",
    "threshold": "invalid number",
    "length": "invalid number",
    "times": "invalid number",
    "kind": "invalid kind",
    "path": "invalid path",
    "ip": "invalid ip",
    "date": "invalid timestamp",
    "time": "invalid timestamp",
    "key": "invalid key",
    "subject": "invalid key",
    "value": "invalid value",
}
QUERY_FORMS = {
    "SUMMARY": (),
    "MALFORMED": (),
    "STATUS": (),
    "METHODS": (),
    "TOP": ("kind", "limit"),
    "HOURLY": (),
    "TIMELINE": ("minutes",),
    "BANDWIDTH": (),
    "VISITORS": (),
    "LATENCY": ("path",),
    "HISTOGRAM": ("width",),
    "APDEX": ("threshold",),
    "ERRORS": (),
    "SLOWEST": ("limit",),
    "SESSIONS": ("ip", "minutes"),
    "BURST": ("length", "times"),
    "PEAK": ("length",),
    "GAPS": ("length",),
    "IP": ("ip",),
    "RANGE": ("date", "time", "date", "time"),
    "FILTER": ("key", "value"),
    "UNFILTER": ("subject",),
    "RESET": (),
    "STATE": (),
}
OPTIONAL_LAST = ("LATENCY", "SESSIONS")
NEEDS_TARGETS = (
    "STATUS", "METHODS", "TOP", "HOURLY", "TIMELINE", "BANDWIDTH", "VISITORS",
    "HISTOGRAM", "APDEX", "ERRORS", "SLOWEST", "BURST", "PEAK", "GAPS",
)
RATINGS = (
    (Fraction(94, 100), "excellent"),
    (Fraction(85, 100), "good"),
    (Fraction(70, 100), "fair"),
    (Fraction(50, 100), "poor"),
)
BYTE_UNITS = ((1073741824, "GB"), (1048576, "MB"), (1024, "KB"))
DEFAULT_TIMEOUT = 30
BAR_WIDTH = 30
MAX_BUCKETS = 60
PATH_LINES = 3


class QueryError(Exception):
    pass


def is_digits(text):
    return text != "" and all("0" <= character <= "9" for character in text)


def is_canonical(text, max_length):
    if not is_digits(text) or len(text) > max_length:
        return False
    return len(text) == 1 or text[0] != "0"


def is_leap(year):
    return year % 4 == 0 and year % 100 != 0 or year % 400 == 0


def year_days(year):
    return 366 if is_leap(year) else 365


def month_days(year, month):
    if month == 2 and is_leap(year):
        return 29
    return MONTH_DAYS[month - 1]


def is_valid_date(text):
    if len(text) != 10 or text[4] != "-" or text[7] != "-":
        return False
    parts = (text[:4], text[5:7], text[8:])
    if not all(is_digits(part) for part in parts):
        return False
    year, month, day = (int(part) for part in parts)
    if not 2000 <= year <= 2059 or not 1 <= month <= 12:
        return False
    return 1 <= day <= month_days(year, month)


def is_valid_time(text):
    if len(text) != 8 or text[2] != ":" or text[5] != ":":
        return False
    parts = (text[:2], text[3:5], text[6:])
    if not all(is_digits(part) for part in parts):
        return False
    hour, minute, second = (int(part) for part in parts)
    return hour <= 23 and minute <= 59 and second <= 59


def is_valid_ip(text):
    parts = text.split(".")
    if len(parts) != 4:
        return False
    return all(is_canonical(part, 3) and int(part) <= 255 for part in parts)


def is_valid_status(text):
    return len(text) == 3 and is_digits(text) and 100 <= int(text) <= 599


def is_valid_value(key, text):
    if key == "METHOD":
        return text in METHODS
    if key == "STATUS":
        return text in STATUS_CLASSES or is_valid_status(text)
    if key == "IP":
        return is_valid_ip(text)
    return text.startswith("/")


def is_valid_argument(kind, text, arguments):
    if kind in NUMBER_RANGES:
        low, high = NUMBER_RANGES[kind]
        return is_canonical(text, 6) and low <= int(text) <= high
    if kind == "kind":
        return text in TOP_KINDS
    if kind == "path":
        return text.startswith("/")
    if kind == "ip":
        return is_valid_ip(text)
    if kind == "date":
        return is_valid_date(text)
    if kind == "time":
        return is_valid_time(text)
    if kind == "key":
        return text in FILTER_KEYS
    if kind == "subject":
        return text in FILTER_KEYS or text == "RANGE"
    return is_valid_value(arguments[0], text)


def malformed_reason(fields):
    if len(fields) != 8:
        return "fields"
    date, clock, ip, method, path, status, size, latency = fields
    if not is_valid_date(date):
        return "date"
    if not is_valid_time(clock):
        return "time"
    if not is_valid_ip(ip):
        return "ip"
    if method not in METHODS:
        return "method"
    if not path.startswith("/"):
        return "path"
    if not is_valid_status(status):
        return "status"
    if not is_canonical(size, 8):
        return "bytes"
    if not is_canonical(latency, 6):
        return "latency"
    return None


def day_number(year, month, day):
    days = day - 1
    for earlier_year in range(2000, year):
        days += year_days(earlier_year)
    for earlier_month in range(1, month):
        days += month_days(year, earlier_month)
    return days


def seconds_of(date, clock):
    year, month, day = int(date[:4]), int(date[5:7]), int(date[8:])
    hour, minute, second = int(clock[:2]), int(clock[3:5]), int(clock[6:])
    return day_number(year, month, day) * 86400 + hour * 3600 + minute * 60 + second


def interval_label(seconds):
    days, rest = divmod(seconds, 86400)
    year = 2000
    while days >= year_days(year):
        days -= year_days(year)
        year += 1
    month = 1
    while days >= month_days(year, month):
        days -= month_days(year, month)
        month += 1
    return f"{year}-{month:02d}-{days + 1:02d} {rest // 3600:02d}:{rest % 3600 // 60:02d}"


def path_part(part):
    if is_digits(part):
        return "{id}"
    is_hex = all(character in HEX_DIGITS for character in part)
    has_digit = any("0" <= character <= "9" for character in part)
    if len(part) >= 8 and is_hex and has_digit:
        return "{hex}"
    return part


def normalize_path(text):
    kept = []
    for part in text.split("?", 1)[0].split("/"):
        if part == "..":
            if kept:
                kept.pop()
        elif part not in ("", "."):
            kept.append(part)
    return "/" + "/".join(path_part(part) for part in kept)


def ip_order(ip):
    return tuple(int(part) for part in ip.split("."))


def status_matches(value, status):
    if value in STATUS_CLASSES:
        return status // 100 == int(value[0])
    return status == int(value)


def decimal(numerator, denominator, places):
    scale = 10 ** places
    whole, fraction = divmod(numerator * scale // denominator, scale)
    return f"{whole}." + str(fraction).zfill(places)


def percentage(part, whole):
    return decimal(part * 100, whole, 2) + "%"


def bar(count, maximum):
    return "#" * ((count * BAR_WIDTH + maximum - 1) // maximum)


def byte_notation(size):
    for unit, suffix in BYTE_UNITS:
        if size >= unit:
            return decimal(size, unit, 1) + suffix
    return f"{size}B"


def group_by(records, key):
    groups = {}
    for record in records:
        groups.setdefault(key(record), []).append(record)
    return groups


def by_count(counts, order=lambda key: key):
    return sorted(counts, key=lambda key: (-counts[key], order(key)))


def class_counts(records):
    counts = [0] * len(STATUS_CLASSES)
    for record in records:
        counts[record.status // 100 - 1] += 1
    return counts


def bucket_counts(numbers):
    first, last = min(numbers), max(numbers)
    if last - first + 1 > MAX_BUCKETS:
        raise QueryError("too many buckets")
    counts = [0] * (last - first + 1)
    for number in numbers:
        counts[number - first] += 1
    return first, counts


def percentile(values, rank):
    return values[(rank * len(values) + 99) // 100 - 1]


class Record:
    def __init__(self, line_number, fields):
        date, clock, ip, method, path, status, size, latency = fields
        self.line_number = line_number
        self.date = date
        self.hour = int(clock[:2])
        self.timestamp = date + " " + clock
        self.seconds = seconds_of(date, clock)
        self.ip = ip
        self.method = method
        self.path = normalize_path(path)
        self.status = int(status)
        self.size = int(size)
        self.latency = int(latency)

    def order(self):
        return self.seconds, self.line_number

    def is_error(self):
        return self.status >= 400


class TimeRange:
    def __init__(self, start_date, start_time, end_date, end_time):
        self.start = start_date + " " + start_time
        self.end = end_date + " " + end_time
        self.start_seconds = seconds_of(start_date, start_time)
        self.end_seconds = seconds_of(end_date, end_time)

    def contains(self, seconds):
        return self.start_seconds <= seconds <= self.end_seconds


class Filters:
    def __init__(self):
        self.range = None
        self.conditions = dict.fromkeys(FILTER_KEYS)

    def accepts(self, record):
        if self.range is not None and not self.range.contains(record.seconds):
            return False
        method = self.conditions["METHOD"]
        if method is not None and record.method != method:
            return False
        status = self.conditions["STATUS"]
        if status is not None and not status_matches(status, record.status):
            return False
        ip = self.conditions["IP"]
        if ip is not None and record.ip != ip:
            return False
        path = self.conditions["PATH"]
        return path is None or record.path == path


class Window:
    def __init__(self, records, length):
        self.size = 0
        self.start = None
        self.end = None
        first = 0
        for last, record in enumerate(records):
            while record.seconds - records[first].seconds >= length:
                first += 1
            if last - first + 1 > self.size:
                self.size = last - first + 1
                self.start = records[first]
                self.end = record


class ApdexScore:
    def __init__(self, records, threshold):
        self.count = len(records)
        self.satisfied = 0
        self.tolerating = 0
        for record in records:
            if record.status >= 500:
                continue
            if record.latency <= threshold:
                self.satisfied += 1
            elif record.latency <= 4 * threshold:
                self.tolerating += 1
        self.frustrated = self.count - self.satisfied - self.tolerating
        self.points = 2 * self.satisfied + self.tolerating
        self.score = Fraction(self.points, 2 * self.count)

    def notation(self):
        return decimal(self.points, 2 * self.count, 3)

    def rating(self):
        for minimum, name in RATINGS:
            if self.score >= minimum:
                return name
        return "unacceptable"


class PathErrors:
    def __init__(self, path, records):
        self.path = path
        self.count = len(records)
        self.client = sum(record.status // 100 == 4 for record in records)
        self.server = sum(record.status // 100 == 5 for record in records)
        self.failed = self.client + self.server

    def order(self):
        return -Fraction(self.failed, self.count), -self.failed, self.path


class Endpoint:
    def __init__(self, method, path, records):
        self.method = method
        self.path = path
        self.count = len(records)
        self.total = sum(record.latency for record in records)
        self.maximum = max(record.latency for record in records)

    def order(self):
        return -Fraction(self.total, self.count), -self.maximum, self.path, self.method


class LogAnalyzer:
    def __init__(self, log_lines):
        self.line_count = len(log_lines)
        self.records = []
        self.malformed = []
        for line_number, line in enumerate(log_lines, 1):
            fields = line.split()
            reason = malformed_reason(fields)
            if reason is None:
                self.records.append(Record(line_number, fields))
            else:
                self.malformed.append((line_number, reason))
        self.records.sort(key=Record.order)
        self.filters = Filters()
        self.output = []
        self.handlers = {
            "SUMMARY": self.summary,
            "MALFORMED": self.malformed_lines,
            "STATUS": self.status_breakdown,
            "METHODS": self.method_breakdown,
            "TOP": self.top,
            "HOURLY": self.hourly,
            "TIMELINE": self.timeline,
            "BANDWIDTH": self.bandwidth,
            "VISITORS": self.visitors,
            "LATENCY": self.latency,
            "HISTOGRAM": self.histogram,
            "APDEX": self.apdex,
            "ERRORS": self.errors,
            "SLOWEST": self.slowest,
            "SESSIONS": self.sessions,
            "BURST": self.burst,
            "PEAK": self.peak,
            "GAPS": self.gaps,
            "IP": self.ip_details,
            "RANGE": self.set_range,
            "FILTER": self.add_filter,
            "UNFILTER": self.remove_filter,
            "RESET": self.reset,
            "STATE": self.state,
        }

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def bar_line(self, label, count, maximum):
        if count == 0:
            self.emit(label, count)
        else:
            self.emit(label, count, bar(count, maximum))

    def targets(self):
        return [record for record in self.records if self.filters.accepts(record)]

    def summary(self, arguments, records):
        self.emit(
            "SUMMARY", "lines", self.line_count, "valid", len(self.records),
            "malformed", len(self.malformed),
        )
        total = sum(record.size for record in records)
        ips = {record.ip for record in records}
        paths = {record.path for record in records}
        self.emit("requests", len(records), "bytes", total, "ips", len(ips), "paths", len(paths))
        if not records:
            self.emit("span", "none")
            return
        first, last = records[0], records[-1]
        self.emit("span", first.timestamp, last.timestamp, last.seconds - first.seconds)

    def malformed_lines(self, arguments, records):
        self.emit("MALFORMED", len(self.malformed))
        for reason in REASONS:
            line_numbers = [number for number, cause in self.malformed if cause == reason]
            if line_numbers:
                self.emit(reason, len(line_numbers), *line_numbers)

    def status_breakdown(self, arguments, records):
        total = len(records)
        self.emit("STATUS", total)
        for label, count in zip(STATUS_CLASSES, class_counts(records)):
            self.emit(label, count, percentage(count, total))
        counts = Counter(record.status for record in records)
        for status in sorted(counts):
            self.emit(status, counts[status], percentage(counts[status], total))

    def method_breakdown(self, arguments, records):
        total = len(records)
        self.emit("METHODS", total)
        counts = Counter(record.method for record in records)
        for method in by_count(counts):
            self.emit(method, counts[method], percentage(counts[method], total))

    def top(self, arguments, records):
        kind, limit = arguments[0], int(arguments[1])
        if kind == "PATHS":
            counts = Counter(record.path for record in records)
            keys = by_count(counts)
        else:
            counts = Counter(record.ip for record in records)
            keys = by_count(counts, ip_order)
        shown = min(limit, len(keys))
        self.emit("TOP", kind, shown, "of", len(keys))
        rank = 0
        for index, key in enumerate(keys[:shown]):
            if index == 0 or counts[key] != counts[keys[index - 1]]:
                rank = index + 1
            self.emit(rank, key, counts[key], percentage(counts[key], len(records)))

    def hourly(self, arguments, records):
        counts = [0] * 24
        for record in records:
            counts[record.hour] += 1
        maximum = max(counts)
        peak_hour = counts.index(maximum)
        self.emit("HOURLY", len(records), "peak", f"{peak_hour:02d}", maximum)
        for hour, count in enumerate(counts):
            self.bar_line(f"{hour:02d}", count, maximum)

    def timeline(self, arguments, records):
        minutes = int(arguments[0])
        width = minutes * 60
        first, counts = bucket_counts([record.seconds // width for record in records])
        self.emit("TIMELINE", minutes, len(counts))
        maximum = max(counts)
        for offset, count in enumerate(counts):
            self.bar_line(interval_label((first + offset) * width), count, maximum)

    def bandwidth(self, arguments, records):
        days = group_by(records, lambda record: record.date)
        total = sum(record.size for record in records)
        self.emit("BANDWIDTH", len(days), total, byte_notation(total))
        for date in sorted(days):
            size = sum(record.size for record in days[date])
            self.emit(date, len(days[date]), size, byte_notation(size))

    def visitors(self, arguments, records):
        first_days = {}
        for record in records:
            if record.ip not in first_days or record.date < first_days[record.ip]:
                first_days[record.ip] = record.date
        days = group_by(records, lambda record: record.date)
        self.emit("VISITORS", len(days), len(first_days))
        for date in sorted(days):
            ips = {record.ip for record in days[date]}
            new = sum(first_days[ip] == date for ip in ips)
            self.emit(date, "unique", len(ips), "new", new, "returning", len(ips) - new)

    def latency(self, arguments, records):
        if arguments:
            target = normalize_path(arguments[0])
            selected = [record for record in records if record.path == target]
        else:
            target = "all"
            selected = records
        if not selected:
            self.emit("LATENCY", "no records")
            return
        values = sorted(record.latency for record in selected)
        count = len(values)
        trim = count // 10
        trimmed = values[trim:count - trim]
        self.emit(
            "LATENCY", target, "count", count, "min", values[0],
            "p50", percentile(values, 50), "p90", percentile(values, 90),
            "p99", percentile(values, 99), "max", values[-1],
            "mean", decimal(sum(values), count, 2),
            "trimmed", decimal(sum(trimmed), len(trimmed), 2),
        )

    def histogram(self, arguments, records):
        width = int(arguments[0])
        first, counts = bucket_counts([record.latency // width for record in records])
        self.emit("HISTOGRAM", width, len(counts))
        maximum = max(counts)
        for offset, count in enumerate(counts):
            low = (first + offset) * width
            self.bar_line(f"{low}-{low + width - 1}", count, maximum)

    def apdex(self, arguments, records):
        threshold = int(arguments[0])
        overall = ApdexScore(records, threshold)
        self.emit(
            "APDEX", threshold, overall.notation(), overall.rating(),
            "satisfied", overall.satisfied, "tolerating", overall.tolerating,
            "frustrated", overall.frustrated,
        )
        groups = group_by(records, lambda record: record.path)
        scores = [(path, ApdexScore(group, threshold)) for path, group in groups.items()]
        scores.sort(key=lambda item: (item[1].score, -item[1].count, item[0]))
        for path, score in scores:
            self.emit(path, score.notation(), score.rating(), score.count)

    def errors(self, arguments, records):
        failed = sum(record.is_error() for record in records)
        self.emit("ERRORS", failed, "of", len(records), percentage(failed, len(records)))
        groups = group_by(records, lambda record: record.path)
        rows = [PathErrors(path, group) for path, group in groups.items()]
        rows = [row for row in rows if row.failed > 0]
        rows.sort(key=PathErrors.order)
        for row in rows:
            self.emit(
                row.path, row.count, row.client, row.server,
                percentage(row.failed, row.count),
            )

    def slowest(self, arguments, records):
        limit = int(arguments[0])
        groups = group_by(records, lambda record: (record.method, record.path))
        endpoints = [Endpoint(method, path, group) for (method, path), group in groups.items()]
        endpoints.sort(key=Endpoint.order)
        shown = min(limit, len(endpoints))
        self.emit("SLOWEST", shown, "of", len(endpoints))
        for rank, endpoint in enumerate(endpoints[:shown], 1):
            self.emit(
                rank, endpoint.method, endpoint.path, "count", endpoint.count,
                "avg", decimal(endpoint.total, endpoint.count, 2), "max", endpoint.maximum,
            )

    def sessions(self, arguments, records):
        ip = arguments[0]
        minutes = int(arguments[1]) if len(arguments) == 2 else DEFAULT_TIMEOUT
        selected = [record for record in records if record.ip == ip]
        if not selected:
            self.emit("SESSIONS", "no records")
            return
        sessions = [[selected[0]]]
        for previous, record in zip(selected, selected[1:]):
            if record.seconds - previous.seconds <= minutes * 60:
                sessions[-1].append(record)
            else:
                sessions.append([record])
        durations = sum(session[-1].seconds - session[0].seconds for session in sessions)
        self.emit(
            "SESSIONS", ip, "timeout", minutes, "count", len(sessions),
            "requests", len(selected),
            "avg_duration", decimal(durations, len(sessions), 1),
            "avg_requests", decimal(len(selected), len(sessions), 1),
        )
        for number, session in enumerate(sessions, 1):
            first, last = session[0], session[-1]
            paths = {record.path for record in session}
            self.emit(
                number, first.timestamp, last.timestamp,
                last.seconds - first.seconds, len(session), len(paths),
            )

    def burst(self, arguments, records):
        length, times = int(arguments[0]), int(arguments[1])
        failures = [record for record in records if record.is_error()]
        matches = []
        for ip, group in group_by(failures, lambda record: record.ip).items():
            window = Window(group, length)
            if window.size >= times:
                matches.append((ip, window))
        matches.sort(key=lambda item: (-item[1].size, ip_order(item[0])))
        self.emit("BURST", length, times, len(matches))
        for ip, window in matches:
            self.emit(ip, window.size, window.start.timestamp, window.end.timestamp)

    def peak(self, arguments, records):
        length = int(arguments[0])
        window = Window(records, length)
        self.emit("PEAK", length, window.size, window.start.timestamp, window.end.timestamp)

    def gaps(self, arguments, records):
        length = int(arguments[0])
        gaps = [
            (before, after) for before, after in zip(records, records[1:])
            if after.seconds - before.seconds >= length
        ]
        self.emit("GAPS", length, len(gaps))
        for before, after in gaps:
            self.emit(before.timestamp, after.timestamp, after.seconds - before.seconds)

    def ip_details(self, arguments, records):
        ip = arguments[0]
        selected = [record for record in records if record.ip == ip]
        if not selected:
            self.emit("IP", "no records")
            return
        total = sum(record.size for record in selected)
        failed = sum(record.is_error() for record in selected)
        paths = Counter(record.path for record in selected)
        self.emit(
            "IP", ip, "requests", len(selected), "bytes", total,
            "errors", failed, "paths", len(paths),
        )
        self.emit("first", selected[0].timestamp, "last", selected[-1].timestamp)
        methods = Counter(record.method for record in selected)
        parts = ["methods"]
        for method in by_count(methods):
            parts.extend((method, methods[method]))
        self.emit(*parts)
        parts = ["classes"]
        for label, count in zip(STATUS_CLASSES, class_counts(selected)):
            parts.extend((label, count))
        self.emit(*parts)
        for path in by_count(paths)[:PATH_LINES]:
            self.emit("path", path, paths[path])

    def set_range(self, arguments, records):
        time_range = TimeRange(*arguments)
        if time_range.start_seconds > time_range.end_seconds:
            raise QueryError("invalid range")
        self.filters.range = time_range
        self.emit("RANGE", time_range.start, time_range.end, "active", len(self.targets()))

    def add_filter(self, arguments, records):
        key, value = arguments
        if key == "PATH":
            value = normalize_path(value)
        self.filters.conditions[key] = value
        self.emit("FILTER", key, value, "active", len(self.targets()))

    def remove_filter(self, arguments, records):
        key = arguments[0]
        if key == "RANGE":
            if self.filters.range is None:
                raise QueryError("not filtered")
            self.filters.range = None
        else:
            if self.filters.conditions[key] is None:
                raise QueryError("not filtered")
            self.filters.conditions[key] = None
        self.emit("UNFILTER", key, "active", len(self.targets()))

    def reset(self, arguments, records):
        self.filters = Filters()
        self.emit("RESET", "active", len(self.targets()))

    def state(self, arguments, records):
        time_range = self.filters.range
        range_text = "-" if time_range is None else time_range.start + " " + time_range.end
        parts = ["STATE", "active", len(records), "range", range_text]
        for key in FILTER_KEYS:
            value = self.filters.conditions[key]
            parts.extend((key.lower(), "-" if value is None else value))
        self.emit(*parts)

    def execute(self, line):
        name, *arguments = line.split()
        try:
            if name not in QUERY_FORMS:
                raise QueryError("unknown query")
            form = QUERY_FORMS[name]
            omitted = name in OPTIONAL_LAST and len(arguments) == len(form) - 1
            if len(arguments) != len(form) and not omitted:
                raise QueryError("wrong arguments")
            for kind, text in zip(form, arguments):
                if not is_valid_argument(kind, text, arguments):
                    raise QueryError(ARGUMENT_ERRORS[kind])
            records = self.targets()
            if name in NEEDS_TARGETS and not records:
                self.emit(name, "no records")
            else:
                self.handlers[name](arguments, records)
        except QueryError as error:
            self.emit("ERROR", error)


def main():
    lines = sys.stdin.read().splitlines()
    separator = lines.index("---")
    end = lines.index("END", separator + 1)
    analyzer = LogAnalyzer(lines[:separator])
    for line in lines[separator + 1:end]:
        analyzer.execute(line)
    sys.stdout.write("\n".join(analyzer.output) + "\n")


if __name__ == "__main__":
    main()
