import re
import sys
from collections import Counter, defaultdict
from itertools import groupby


TYPE_ORDER = ("A", "NS", "CNAME", "SOA", "PTR", "MX", "TXT", "AAAA")
NAME_TYPES = ("NS", "CNAME", "PTR")
FIELD_COUNTS = {"A": 1, "AAAA": 1, "NS": 1, "CNAME": 1, "PTR": 1, "MX": 2, "SOA": 7}
RESPONSE_KINDS = ("ANSWER", "CNAME", "REFERRAL", "NODATA", "NXDOMAIN", "LAME", "TIMEOUT")
FAILURES = ("LAME", "TIMEOUT")
STATUSES = ("NOERROR", "NODATA", "NXDOMAIN", "SERVFAIL")
DEFAULT_SETTINGS = {"MINTTL": 1, "MAXTTL": 86400, "NEGTTL": 3600}
ROOT = ()
WILDCARD = "*"
MAX_TTL = 604800
MAX_MINIMUM = 86400
MAX_PREFERENCE = 65535
MAX_TIME_STEP = 1000000
MAX_CHAIN = 9

LABEL_PATTERN = re.compile(r"[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?")
INTEGER_PATTERN = re.compile(r"0|[1-9][0-9]{0,8}")
OCTET_PATTERN = re.compile(r"0|[1-9][0-9]{0,2}")
GROUP_PATTERN = re.compile(r"[0-9a-fA-F]{1,4}")
TTL_NUMBER = "(0|[1-9][0-9]{0,2})"
TTL_PATTERN = re.compile(
    "".join(f"(?:{TTL_NUMBER}[{unit}])?" for unit in ("wW", "dD", "hH", "mM", "sS"))
)
TTL_UNIT_SECONDS = (604800, 86400, 3600, 60, 1)


class InputError(Exception):
    pass


def parse_integer(word):
    return int(word) if INTEGER_PATTERN.fullmatch(word) else None


def parse_ipv4(word):
    fields = word.split(".")
    if len(fields) != 4 or not all(OCTET_PATTERN.fullmatch(field) for field in fields):
        return None
    value = 0
    for field in fields:
        if int(field) > 255:
            return None
        value = value * 256 + int(field)
    return value


def require_ipv4(word):
    address = parse_ipv4(word)
    if address is None:
        raise InputError(f"bad address {word}")
    return address


def ipv4_text(value):
    return ".".join(str(value >> shift & 255) for shift in (24, 16, 8, 0))


def parse_groups(text):
    if not text:
        return []
    groups = text.split(":")
    if not all(GROUP_PATTERN.fullmatch(group) for group in groups):
        return None
    return [int(group, 16) for group in groups]


def parse_ipv6(word):
    if "::" not in word:
        groups = parse_groups(word)
        return tuple(groups) if groups is not None and len(groups) == 8 else None
    head, tail = word.split("::", 1)
    front, back = parse_groups(head), parse_groups(tail)
    if front is None or back is None or len(front) + len(back) > 7:
        return None
    return tuple(front + [0] * (8 - len(front) - len(back)) + back)


def require_ipv6(word):
    address = parse_ipv6(word)
    if address is None:
        raise InputError(f"bad address {word}")
    return address


def ipv6_text(groups):
    best_start, best_length = -1, 1
    index = 0
    while index < 8:
        end = index
        while end < 8 and groups[end] == 0:
            end += 1
        if end - index > best_length:
            best_start, best_length = index, end - index
        index = max(end, index + 1)
    parts = [f"{group:x}" for group in groups]
    if best_start < 0:
        return ":".join(parts)
    head = ":".join(parts[:best_start])
    tail = ":".join(parts[best_start + best_length:])
    return f"{head}::{tail}"


def parse_name(word, wildcard=False, origin=None):
    if origin is not None and word == "@":
        return origin
    if word == ".":
        return ROOT
    absolute = word.endswith(".")
    parts = (word[:-1] if absolute else word).split(".")
    for index, part in enumerate(parts):
        allowed_wildcard = wildcard and index == 0 and part == WILDCARD
        if not allowed_wildcard and not LABEL_PATTERN.fullmatch(part):
            raise InputError(f"bad name {word}")
    labels = tuple(part.lower() for part in parts)
    if origin is not None and not absolute:
        labels += origin
    return labels


def name_text(name):
    return ".".join(name) + "." if name else "."


def name_key(name):
    return name[::-1]


def is_at_or_below(name, ancestor):
    return len(name) >= len(ancestor) and name[len(name) - len(ancestor):] == ancestor


def ancestors(name):
    return [name[index:] for index in range(len(name) + 1)]


def is_wildcard(name):
    return name[:1] == (WILDCARD,)


def parse_ttl(word):
    seconds = parse_integer(word)
    if seconds is None and (match := TTL_PATTERN.fullmatch(word)):
        seconds = sum(
            int(number) * unit
            for number, unit in zip(match.groups(), TTL_UNIT_SECONDS)
            if number is not None
        )
    if seconds is None or not 1 <= seconds <= MAX_TTL:
        raise InputError(f"bad ttl {word}")
    return seconds


def require_type(word):
    if word not in TYPE_ORDER:
        raise InputError(f"bad type {word}")


def parse_data(rtype, fields, origin):
    if rtype == "A":
        return require_ipv4(fields[0])
    if rtype == "AAAA":
        return require_ipv6(fields[0])
    if rtype in NAME_TYPES:
        return parse_name(fields[0], origin=origin)
    if rtype == "MX":
        preference = parse_integer(fields[0])
        if preference is None or preference > MAX_PREFERENCE:
            raise InputError(f"bad preference {fields[0]}")
        return preference, parse_name(fields[1], origin=origin)
    if rtype == "TXT":
        text = " ".join(fields)
        if len(text) < 2 or text[0] != '"' or text[-1] != '"' or '"' in text[1:-1]:
            raise InputError(f"bad text {text}")
        return text
    mname = parse_name(fields[0], origin=origin)
    rname = parse_name(fields[1], origin=origin)
    numbers = []
    for word in fields[2:6]:
        number = parse_integer(word)
        if number is None:
            raise InputError(f"bad number {word}")
        numbers.append(number)
    minimum = parse_integer(fields[6])
    if minimum is None or not 1 <= minimum <= MAX_MINIMUM:
        raise InputError(f"bad minimum {fields[6]}")
    return (mname, rname, *numbers, minimum)


class Record:
    def __init__(self, owner, ttl, rtype, data):
        self.owner = owner
        self.ttl = ttl
        self.rtype = rtype
        self.data = data

    def with_ttl(self, ttl):
        return Record(self.owner, ttl, self.rtype, self.data)

    def with_owner(self, owner):
        return Record(owner, self.ttl, self.rtype, self.data)

    def same_as(self, other):
        return (self.owner, self.rtype, self.data) == (other.owner, other.rtype, other.data)

    def data_key(self):
        if self.rtype in NAME_TYPES:
            return name_key(self.data)
        if self.rtype == "MX":
            preference, host = self.data
            return preference, name_key(host)
        return self.data

    def order_key(self):
        return name_key(self.owner), TYPE_ORDER.index(self.rtype), self.data_key()

    def data_text(self):
        if self.rtype == "A":
            return ipv4_text(self.data)
        if self.rtype == "AAAA":
            return ipv6_text(self.data)
        if self.rtype in NAME_TYPES:
            return name_text(self.data)
        if self.rtype == "MX":
            preference, host = self.data
            return f"{preference} {name_text(host)}"
        if self.rtype == "SOA":
            mname, rname, *numbers = self.data
            return " ".join([name_text(mname), name_text(rname), *map(str, numbers)])
        return self.data

    def text(self):
        return f"{name_text(self.owner)} {self.ttl} {self.rtype} {self.data_text()}"


def in_data_order(records):
    return sorted(records, key=Record.data_key)


class Zone:
    def __init__(self, origin, server, line_number):
        self.origin = origin
        self.server = server
        self.line_number = line_number
        self.records = []
        self.by_owner = {}
        self.existing = set()
        self.soa = None

    def add(self, record):
        self.records.append(record)
        self.by_owner.setdefault(record.owner, []).append(record)
        self.existing.update(ancestors(record.owner))
        if record.rtype == "SOA":
            self.soa = record

    def records_at(self, owner):
        return self.by_owner.get(owner, [])

    def find(self, owner, rtype):
        return in_data_order(record for record in self.records_at(owner) if record.rtype == rtype)

    def exists(self, name):
        return name in self.existing


def outcome_text(kind, answer):
    if kind == "CNAME":
        return f"CNAME {name_text(answer[0].data)}"
    return kind


class Response:
    def __init__(self, kind, answer=(), authority=(), additional=(), referral=None):
        self.kind = kind
        self.answer = answer
        self.authority = authority
        self.additional = additional
        self.referral = referral

    def summary(self):
        if self.kind == "REFERRAL":
            return f"REFERRAL {name_text(self.referral)}"
        return outcome_text(self.kind, self.answer)


class Entry:
    def __init__(self, kind, records, expiry):
        self.kind = kind
        self.records = records
        self.expiry = expiry


class Resolver:
    def __init__(self):
        self.output = []
        self.root_hints = []
        self.zones = []
        self.current_zone = None
        self.zones_by_server = {}
        self.down = set()
        self.clock = 0
        self.cache = {}
        self.settings = dict(DEFAULT_SETTINGS)
        self.query_counts = defaultdict(Counter)
        self.hits = 0
        self.resolution_counts = Counter()

    def emit(self, line):
        self.output.append(line)

    def trace(self, depth, line):
        self.emit("  " * (depth + 1) + line)

    def load(self, line_number, line):
        words = line.split(" ")
        try:
            if words[0] == "ROOT":
                self.add_roots(words[1:])
            elif words[0] == "ZONE":
                self.current_zone = None
                self.add_zone(line_number, words[1], words[2])
            else:
                self.add_record(words)
        except InputError as error:
            self.emit(f"error line {line_number}: {error}")

    def add_roots(self, words):
        addresses = []
        for word in words:
            address = require_ipv4(word)
            if address in self.root_hints or address in addresses:
                raise InputError(f"duplicate root {word}")
            addresses.append(address)
        self.root_hints.extend(addresses)

    def add_zone(self, line_number, origin_word, server_word):
        origin = parse_name(origin_word)
        server = require_ipv4(server_word)
        if any(zone.origin == origin and zone.server == server for zone in self.zones):
            raise InputError(f"duplicate zone {name_text(origin)} at {server_word}")
        self.current_zone = Zone(origin, server, line_number)
        self.zones.append(self.current_zone)

    def add_record(self, words):
        zone = self.current_zone
        if zone is None:
            raise InputError("no current zone")
        owner_word, ttl_word, rtype, *fields = words
        owner = parse_name(owner_word, wildcard=True, origin=zone.origin)
        if not is_at_or_below(owner, zone.origin):
            raise InputError(f"out of zone {name_text(owner)}")
        ttl = parse_ttl(ttl_word)
        require_type(rtype)
        if rtype in FIELD_COUNTS and len(fields) != FIELD_COUNTS[rtype]:
            raise InputError("wrong field count")
        record = Record(owner, ttl, rtype, parse_data(rtype, fields, zone.origin))
        if rtype == "NS" and is_wildcard(owner):
            raise InputError("ns at wildcard")
        if rtype == "SOA" and owner != zone.origin:
            raise InputError("soa not at origin")
        if rtype == "SOA" and zone.soa is not None:
            raise InputError("duplicate soa")
        existing = zone.records_at(owner)
        if any(other.same_as(record) for other in existing):
            raise InputError("duplicate record")
        has_cname = any(other.rtype == "CNAME" for other in existing)
        if (rtype == "CNAME" and existing) or (rtype != "CNAME" and has_cname):
            raise InputError(f"cname conflict {name_text(owner)}")
        zone.add(record)

    def finish_zones(self):
        kept = []
        for zone in self.zones:
            label = f"zone {name_text(zone.origin)} at {ipv4_text(zone.server)}"
            if zone.soa is None:
                self.emit(f"error line {zone.line_number}: {label} has no soa")
            else:
                self.emit(f"{label} records={len(zone.records)}")
                kept.append(zone)
        self.zones = kept
        for zone in kept:
            self.zones_by_server.setdefault(zone.server, []).append(zone)
        total = sum(len(zone.records) for zone in kept)
        self.emit(f"loaded roots={len(self.root_hints)} zones={len(kept)} records={total}")

    def reachable(self, server):
        return server not in self.down and server in self.zones_by_server

    def respond(self, server, name, rtype, cut):
        if not self.reachable(server):
            return Response("TIMEOUT")
        candidates = [
            zone for zone in self.zones_by_server[server] if is_at_or_below(name, zone.origin)
        ]
        if not candidates:
            return Response("LAME")
        zone = max(candidates, key=lambda candidate: len(candidate.origin))
        if len(zone.origin) < len(cut):
            return Response("LAME")
        for length in range(len(zone.origin) + 1, len(name) + 1):
            point = name[len(name) - length:]
            nameservers = zone.find(point, "NS")
            if nameservers:
                glue = [record for ns in nameservers for record in zone.find(ns.data, "A")]
                return Response(
                    "REFERRAL", authority=nameservers, additional=glue, referral=point
                )
        records = zone.records_at(name)
        if not records:
            if zone.exists(name):
                return Response("NODATA", authority=[zone.soa])
            closest = next(ancestor for ancestor in ancestors(name)[1:] if zone.exists(ancestor))
            records = zone.records_at((WILDCARD,) + closest)
            if not records:
                return Response("NXDOMAIN", authority=[zone.soa])
        records = [record.with_owner(name) for record in records]
        matching = in_data_order(record for record in records if record.rtype == rtype)
        if matching:
            return Response("ANSWER", answer=matching)
        cnames = [record for record in records if record.rtype == "CNAME"]
        if rtype != "CNAME" and cnames:
            return Response("CNAME", answer=cnames)
        return Response("NODATA", authority=[zone.soa])

    def ask(self, server, name, rtype, cut):
        response = self.respond(server, name, rtype, cut)
        self.query_counts[server][response.kind] += 1
        return response

    def store_positive(self, records):
        lowest = min(record.ttl for record in records)
        cache_ttl = min(max(lowest, self.settings["MINTTL"]), self.settings["MAXTTL"])
        key = (records[0].owner, records[0].rtype)
        self.cache[key] = Entry("POS", in_data_order(records), self.clock + cache_ttl)
        return cache_ttl

    def store_negative(self, name, rtype, response):
        soa = response.authority[0]
        cache_ttl = min(soa.ttl, soa.data[-1], self.settings["NEGTTL"])
        self.cache[(name, rtype)] = Entry(response.kind, [], self.clock + cache_ttl)

    def positive_entry(self, name, rtype):
        entry = self.cache.get((name, rtype))
        return entry if entry is not None and entry.kind == "POS" else None

    def aged(self, entry):
        return [record.with_ttl(entry.expiry - self.clock) for record in entry.records]

    def cached_result(self, name, rtype):
        entry = self.cache.get((name, rtype))
        if entry is not None:
            if entry.kind == "POS":
                return "ANSWER", self.aged(entry)
            return entry.kind, []
        if any(
            entry.kind == "NXDOMAIN" and is_at_or_below(name, cached_name)
            for (cached_name, _), entry in self.cache.items()
        ):
            return "NXDOMAIN", []
        entry = self.positive_entry(name, "CNAME")
        if rtype != "CNAME" and entry is not None:
            return "CNAME", self.aged(entry)
        return None

    def lookup(self, name, rtype, depth, pending):
        query = f"{name_text(name)} {rtype}"
        result = self.cached_result(name, rtype)
        if result is not None:
            self.hits += 1
            self.trace(depth, f"CACHE HIT {query} -> {outcome_text(*result)}")
            return result
        cut, nameservers = ROOT, None
        for ancestor in ancestors(name):
            entry = self.positive_entry(ancestor, "NS")
            if entry is not None:
                self.hits += 1
                self.trace(depth, f"CACHE HIT {query} -> REFERRAL {name_text(ancestor)}")
                cut = ancestor
                nameservers = [record.data for record in entry.records]
                break
        while True:
            response = self.query_servers(name, rtype, cut, nameservers, depth, pending)
            if response is None:
                return f"SERVFAIL no server for {name_text(cut)}", []
            if response.kind == "REFERRAL":
                self.store_positive(response.authority)
                for _, glue in groupby(response.additional, key=lambda record: record.owner):
                    self.store_positive(list(glue))
                cut = response.referral
                nameservers = [record.data for record in response.authority]
            elif response.kind in ("ANSWER", "CNAME"):
                cache_ttl = self.store_positive(response.answer)
                return response.kind, [record.with_ttl(cache_ttl) for record in response.answer]
            else:
                self.store_negative(name, rtype, response)
                return response.kind, []

    def query_servers(self, name, rtype, cut, nameservers, depth, pending):
        for address in self.destinations(nameservers, depth, pending):
            response = self.ask(address, name, rtype, cut)
            self.trace(
                depth,
                f"ASK {ipv4_text(address)} {name_text(name)} {rtype} -> {response.summary()}",
            )
            if response.kind not in FAILURES:
                return response
        return None

    def destinations(self, nameservers, depth, pending):
        if nameservers is None:
            yield from self.root_hints
            return
        for host in sorted(nameservers, key=name_key):
            yield from self.host_addresses(host, depth, pending)

    def host_addresses(self, host, depth, pending):
        entry = self.positive_entry(host, "A")
        if entry is not None:
            return sorted(record.data for record in entry.records)
        if (host, "A") in pending:
            self.trace(depth, f"GLUELESS {name_text(host)} -> LOOP")
            return []
        self.trace(depth, f"GLUELESS {name_text(host)}")
        status, answer = self.resolve(host, "A", depth + 1, pending)
        if status != "NOERROR":
            return []
        return sorted(record.data for record in answer if record.rtype == "A")

    def resolve(self, name, rtype, depth, pending):
        pending.append((name, rtype))
        chain = []
        seen = {name}
        current = name
        while True:
            kind, records = self.lookup(current, rtype, depth, pending)
            if kind != "CNAME":
                break
            chain.extend(records)
            target = records[0].data
            if target in seen:
                kind = "SERVFAIL cname loop"
                break
            if len(chain) == MAX_CHAIN:
                kind = "SERVFAIL cname chain too long"
                break
            seen.add(target)
            current = target
        pending.pop()
        if kind == "ANSWER":
            status, answer = "NOERROR", chain + records
        elif kind.startswith("SERVFAIL"):
            status, answer = kind, []
        else:
            status, answer = kind, chain
        self.resolution_counts[status.split(" ")[0]] += 1
        return status, answer

    def resolve_and_report(self, name, rtype):
        status, answer = self.resolve(name, rtype, 0, [])
        for record in answer:
            self.emit(f"answer {record.text()}")
        self.emit(f"status {status}")
        return status, answer

    def address_resolution(self, host):
        addresses = []
        for rtype in ("A", "AAAA"):
            status, answer = self.resolve(host, rtype, 0, [])
            if status == "NOERROR":
                addresses.extend(record.data_text() for record in answer if record.rtype == rtype)
        return " ".join(addresses) if addresses else "no address"

    def execute(self, line_number, line):
        command, *arguments = line.split(" ")
        handlers = {
            "RESOLVE": self.resolve_command,
            "MX": self.mx_command,
            "REVERSE": self.reverse_command,
            "QUERY": self.query_command,
            "DUMP": self.dump_command,
            "DOWN": self.down_command,
            "UP": self.up_command,
            "SET": self.set_command,
            "TIME": self.time_command,
            "CACHE": self.cache_command,
            "FLUSH": self.flush_command,
            "STATS": self.stats_command,
        }
        try:
            handlers[command](*arguments)
        except InputError as error:
            self.emit(f"error line {line_number}: {error}")

    def resolve_command(self, name_word, rtype):
        name = parse_name(name_word, wildcard=True)
        require_type(rtype)
        self.emit(f"resolve {name_text(name)} {rtype}")
        self.resolve_and_report(name, rtype)

    def reverse_command(self, address_word):
        if ":" in address_word:
            groups = require_ipv6(address_word)
            address = ipv6_text(groups)
            digits = "".join(f"{group:04x}" for group in groups)
            name = tuple(reversed(digits)) + ("ip6", "arpa")
        else:
            address = ipv4_text(require_ipv4(address_word))
            name = tuple(reversed(address.split("."))) + ("in-addr", "arpa")
        self.emit(f"reverse {address} {name_text(name)}")
        self.resolve_and_report(name, "PTR")

    def mx_command(self, name_word):
        name = parse_name(name_word, wildcard=True)
        self.emit(f"mx {name_text(name)}")
        status, answer = self.resolve_and_report(name, "MX")
        if status == "NOERROR":
            for record in answer:
                if record.rtype != "MX":
                    continue
                preference, host = record.data
                if host == ROOT:
                    self.emit(f"exchange {preference} . -> null")
                else:
                    addresses = self.address_resolution(host)
                    self.emit(f"exchange {preference} {name_text(host)} -> {addresses}")
        elif status == "NODATA":
            host = answer[-1].data if answer else name
            addresses = self.address_resolution(host)
            self.emit(f"implicit {name_text(host)} -> {addresses}")

    def query_command(self, server_word, name_word, rtype):
        server = require_ipv4(server_word)
        name = parse_name(name_word, wildcard=True)
        require_type(rtype)
        response = self.ask(server, name, rtype, ROOT)
        self.emit(f"query {server_word} {name_text(name)} {rtype} -> {response.summary()}")
        sections = (
            ("answer", response.answer),
            ("authority", response.authority),
            ("additional", response.additional),
        )
        for section, records in sections:
            for record in records:
                self.emit(f"{section} {record.text()}")

    def dump_command(self, server_word, name_word):
        server = require_ipv4(server_word)
        name = parse_name(name_word)
        prefix = f"dump {server_word} {name_text(name)}"
        if not self.reachable(server):
            self.emit(f"{prefix} -> TIMEOUT")
            return
        zone = next((zone for zone in self.zones_by_server[server] if zone.origin == name), None)
        if zone is None:
            self.emit(f"{prefix} -> REFUSED")
            return
        self.emit(f"{prefix} records={len(zone.records)}")
        for record in sorted(zone.records, key=Record.order_key):
            self.emit(f"  {record.text()}")

    def down_command(self, server_word):
        server = require_ipv4(server_word)
        if server in self.down:
            raise InputError(f"server {server_word} already down")
        self.down.add(server)
        self.emit(f"down {server_word}")

    def up_command(self, server_word):
        server = require_ipv4(server_word)
        if server not in self.down:
            raise InputError(f"server {server_word} not down")
        self.down.remove(server)
        self.emit(f"up {server_word}")

    def set_command(self, key, value_word):
        if key not in self.settings:
            raise InputError(f"bad setting {key}")
        value = parse_integer(value_word)
        if value is None or not 1 <= value <= MAX_TTL:
            raise InputError(f"bad value {value_word}")
        updated = {**self.settings, key: value}
        if updated["MINTTL"] > updated["MAXTTL"]:
            raise InputError("minttl above maxttl")
        self.settings = updated
        self.emit(f"set {key}={value}")

    def time_command(self, seconds_word):
        seconds = parse_integer(seconds_word)
        if seconds is None or not 1 <= seconds <= MAX_TIME_STEP:
            raise InputError(f"bad time {seconds_word}")
        self.clock += seconds
        expired = [key for key, entry in self.cache.items() if entry.expiry <= self.clock]
        for key in expired:
            del self.cache[key]
        self.emit(f"time now={self.clock} expired={len(expired)}")

    def selected_keys(self, name_word):
        if name_word is None:
            return list(self.cache)
        name = parse_name(name_word)
        return [key for key in self.cache if is_at_or_below(key[0], name)]

    def cache_command(self, name_word=None):
        keys = sorted(
            self.selected_keys(name_word),
            key=lambda key: (name_key(key[0]), TYPE_ORDER.index(key[1])),
        )
        self.emit(f"cache entries={len(keys)}")
        for name, rtype in keys:
            entry = self.cache[(name, rtype)]
            if entry.kind == "POS":
                for record in self.aged(entry):
                    self.emit(f"  {record.text()}")
            else:
                remaining = entry.expiry - self.clock
                self.emit(f"  {name_text(name)} {remaining} {rtype} {entry.kind}")

    def flush_command(self, name_word=None):
        keys = self.selected_keys(name_word)
        for key in keys:
            del self.cache[key]
        self.emit(f"flush removed={len(keys)}")

    def stats_command(self):
        total = sum(sum(counts.values()) for counts in self.query_counts.values())
        self.emit(f"stats queries={total} hits={self.hits}")
        for address in sorted(self.query_counts):
            counts = self.query_counts[address]
            details = " ".join(f"{kind.lower()}={counts[kind]}" for kind in RESPONSE_KINDS)
            self.emit(f"  {ipv4_text(address)} sent={sum(counts.values())} {details}")
        details = " ".join(
            f"{status.lower()}={self.resolution_counts[status]}" for status in STATUSES
        )
        self.emit(f"resolutions {details}")


def main():
    resolver = Resolver()
    in_zone_section = True
    for line_number, line in enumerate(sys.stdin.read().splitlines(), 1):
        if in_zone_section:
            if line == "END ZONES":
                resolver.finish_zones()
                in_zone_section = False
            else:
                resolver.load(line_number, line)
        elif line == "END":
            break
        else:
            resolver.execute(line_number, line)
    sys.stdout.write("\n".join(resolver.output) + "\n")


if __name__ == "__main__":
    main()
