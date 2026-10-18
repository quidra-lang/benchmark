import os
import re

import emitter
from emitter import MASK, shown, string_notation, value_notation
from ini_parser import parse_document
from interpolate import Expander
from schema import load_schema


INPUT_DIR = "input"
OUTPUT_DIR = "output"
NUMERIC_TYPES = ("int", "size", "duration")
TRUE_WORDS = ("true", "yes", "on", "1")
FALSE_WORDS = ("false", "no", "off", "0")
SIZE_FACTORS = {"": 1, "b": 1, "kb": 1024, "mb": 1048576, "gb": 1073741824}
DEFAULT_PORTS = {"http": 80, "https": 443}
DAYS_IN_MONTH = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
IPV4_CHARACTERS = "0123456789."
PATH_FORBIDDEN = " \n\t"
INT_PATTERN = re.compile(r"([+-]?)(?:0[xX]([0-9a-fA-F]{1,10})|([0-9](?:_?[0-9])*))")
SIZE_PATTERN = re.compile(r"([0-9]{1,6})(?:\.([0-9]{1,3}))?([A-Za-z]*)")
SECONDS_PATTERN = re.compile(r"[0-9]{1,6}")
DURATION_PATTERN = re.compile(r"(?:([0-9]{1,6})h)?(?:([0-9]{1,6})m)?(?:([0-9]{1,6})s)?")
LABEL_PATTERN = re.compile(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?")
SCHEME_PATTERN = re.compile(r"[A-Za-z][A-Za-z0-9+.-]*")
PORT_PATTERN = re.compile(r"[1-9][0-9]{0,4}")
DATE_PATTERN = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}")


def read_lines(path):
    with open(path) as handle:
        return handle.read().split("\n")[:-1]


def key_order(key):
    section, _, name = key.rpartition(".")
    return section, name


def section_of(key):
    return key.rpartition(".")[0]


def parse_int(text):
    match = INT_PATTERN.fullmatch(text)
    if match is None:
        return None
    sign, hex_digits, decimal = match.groups()
    if hex_digits is not None:
        number = int(hex_digits, 16)
    else:
        digits = decimal.replace("_", "")
        if len(digits) > 12:
            return None
        number = int(digits)
    return -number if sign == "-" else number


def parse_bool(text):
    lowered = text.lower()
    if lowered in TRUE_WORDS:
        return True
    if lowered in FALSE_WORDS:
        return False
    return None


def parse_enum(text, values):
    lowered = text.lower()
    return lowered if lowered in values else None


def parse_size(text):
    match = SIZE_PATTERN.fullmatch(text)
    if match is None:
        return None
    whole, fraction, unit = match.groups()
    factor = SIZE_FACTORS.get(unit.lower())
    if factor is None:
        return None
    if fraction is None:
        return int(whole) * factor
    scaled = int(fraction) * factor
    divisor = 10 ** len(fraction)
    if scaled % divisor != 0:
        return None
    return int(whole) * factor + scaled // divisor


def parse_duration(text):
    if SECONDS_PATTERN.fullmatch(text) is not None:
        return int(text)
    match = DURATION_PATTERN.fullmatch(text)
    if text == "" or match is None:
        return None
    hours, minutes, seconds = (0 if part is None else int(part) for part in match.groups())
    return hours * 3600 + minutes * 60 + seconds


def is_ipv4(text):
    parts = text.split(".")
    if len(parts) != 4:
        return False
    for part in parts:
        if not 1 <= len(part) <= 3:
            return False
        if part != "0" and part.startswith("0"):
            return False
        if int(part) > 255:
            return False
    return True


def parse_host(text):
    if all(char in IPV4_CHARACTERS for char in text):
        return text if is_ipv4(text) else None
    if len(text) > 253:
        return None
    for label in text.split("."):
        if LABEL_PATTERN.fullmatch(label) is None:
            return None
    return text.lower()


def parse_path(text):
    if text == "" or any(char in PATH_FORBIDDEN for char in text):
        return None
    absolute = text.startswith("/")
    parts = []
    for part in text.split("/"):
        if part in ("", "."):
            continue
        if part != "..":
            parts.append(part)
        elif parts and parts[-1] != "..":
            parts.pop()
        elif absolute:
            return None
        else:
            parts.append(part)
    if absolute:
        return "/" + "/".join(parts)
    return "/".join(parts) if parts else "."


def parse_url(text):
    scheme, separator, rest = text.partition("://")
    if separator == "" or SCHEME_PATTERN.fullmatch(scheme) is None:
        return None
    if "?" in rest or "#" in rest:
        return None
    authority, _, path = rest.partition("/")
    host, colon, port = authority.partition(":")
    host_value = parse_host(host)
    path_value = parse_path("/" + path)
    if host_value is None or path_value is None:
        return None
    scheme = scheme.lower()
    result = scheme + "://" + host_value
    if colon:
        if PORT_PATTERN.fullmatch(port) is None or int(port) > 65535:
            return None
        if DEFAULT_PORTS.get(scheme) != int(port):
            result += ":" + port
    return result + path_value


def is_leap_year(year):
    return (year % 4 == 0 and year % 100 != 0) or year % 400 == 0


def parse_date(text):
    if DATE_PATTERN.fullmatch(text) is None:
        return None
    year, month, day = int(text[:4]), int(text[5:7]), int(text[8:])
    if year < 1 or not 1 <= month <= 12:
        return None
    days = DAYS_IN_MONTH[month - 1]
    if month == 2 and is_leap_year(year):
        days = 29
    return text if 1 <= day <= days else None


SCALAR_PARSERS = {
    "int": parse_int,
    "bool": parse_bool,
    "size": parse_size,
    "duration": parse_duration,
    "host": parse_host,
    "path": parse_path,
    "url": parse_url,
    "date": parse_date,
}


def parse_scalar(kind, text, values):
    if kind == "string":
        return text
    if kind == "enum":
        return parse_enum(text, values)
    return SCALAR_PARSERS[kind](text)


def checked_text(text, secret):
    return MASK if secret else string_notation(text)


class CheckError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code
        self.message = message


def invalid_value(key, kind, values, display):
    if kind == "enum":
        return CheckError("E_ENUM", f"{key}: {display} is not one of {','.join(values)}")
    return CheckError("E_TYPE", f"{key}: {display} is not a valid {kind}")


def bound_value(kind, text):
    if text == "":
        return None
    if kind in ("string", "list"):
        return int(text)
    return parse_scalar(kind, text, [])


def bound_text(bound):
    return "" if bound is None else str(bound)


def check_range(key, spec, value):
    lower_text, upper_text = spec.range
    lower = bound_value(spec.kind, lower_text)
    upper = bound_value(spec.kind, upper_text)
    if spec.kind == "string":
        measure = len(value)
        display = f"length {measure}"
    elif spec.kind == "list":
        measure = len(value)
        display = f"count {measure}"
    else:
        measure = value
        display = MASK if spec.secret else str(value)
    if (lower is not None and measure < lower) or (upper is not None and measure > upper):
        bounds = bound_text(lower) + ".." + bound_text(upper)
        raise CheckError("E_RANGE", f"{key}: {display} is out of range {bounds}")


class Definition:
    def __init__(self, value, origin, number, history):
        self.value = value
        self.origin = origin
        self.number = number
        self.history = history


class OutputKey:
    def __init__(self, definition, spec, value):
        self.definition = definition
        self.spec = spec
        self.value = value
        if spec is None:
            self.kind = "string"
            self.secret = False
            self.notation = string_notation(value)
        else:
            self.kind = spec.kind
            self.secret = spec.secret
            self.notation = value_notation(spec.kind, spec.item, value)


class Library:
    def __init__(self, directory):
        self.directory = directory
        self.documents = {}

    def find(self, name):
        if name not in self.documents:
            path = os.path.join(self.directory, name + ".ini")
            if os.path.isfile(path):
                self.documents[name] = parse_document(name, read_lines(path))
            else:
                self.documents[name] = None
        return self.documents[name]


class Profile:
    def __init__(self, number, line):
        name, root, *overrides = line.split(" ")
        self.name = name
        self.root = root
        self.number = number
        self.overrides = overrides
        self.configuration = {}
        self.definition_count = 0
        self.parents = {}
        self.tree = []
        self.reported = set()
        self.outputs = {}
        self.diagnostics = []
        self.errors = 0
        self.warnings = 0
        self.overridden = []
        self.document_keys = 0
        self.manifest_keys = 0
        self.default_keys = 0
        self.dropped = 0

    def report(self, origin, code, message):
        document, line = origin
        self.reported.add((document, line, code, message))

    def define(self, key, value, origin):
        self.definition_count += 1
        history = []
        if key in self.configuration:
            history = list(self.configuration[key].history)
        if not history or history[-1] != origin:
            history.append(origin)
        self.configuration[key] = Definition(value, origin, self.definition_count, history)

    def process(self, schema, library, earlier):
        self.apply(library, self.root, [self.root])
        self.apply_overrides()
        self.inherit_sections()
        self.resolve_aliases(schema)
        sections = self.fill_defaults(schema)
        configured = set(self.configuration)
        self.check_types(schema, self.expand_values())
        self.check_order()
        self.check_required(schema, sections, configured)
        self.check_fixed(earlier)
        self.summarize(len(configured))

    def apply(self, library, name, chain):
        document = library.find(name)
        self.tree.append((len(chain) - 1, name))
        self.reported.update(document.diagnostics)
        for statement in document.statements:
            origin = (name, statement.line)
            if statement.kind == "assign":
                self.define(statement.target, statement.value, origin)
            elif statement.kind == "append":
                self.append(statement.target, statement.value, origin)
            elif statement.kind == "unset":
                self.unset(statement.target, origin)
            elif statement.kind == "inherit":
                self.parents[statement.target] = (statement.value, origin)
            else:
                self.include(library, statement.target, chain, origin)

    def append(self, key, value, origin):
        current = self.configuration.get(key)
        if current is not None and current.value != "":
            value = current.value + "," + value
        self.define(key, value, origin)

    def unset(self, key, origin):
        if key in self.configuration:
            del self.configuration[key]
        else:
            self.report(origin, "W_UNSET", f"{key} is not set")

    def include(self, library, name, chain, origin):
        depth = len(chain)
        if name in chain:
            path = chain[chain.index(name):] + [name]
            self.report(origin, "E_INCLUDE_CYCLE", "include cycle " + " -> ".join(path))
            self.tree.append((depth, name + " (cycle)"))
        elif library.find(name) is None:
            self.report(origin, "E_INCLUDE_MISSING", "missing document " + name)
            self.tree.append((depth, name + " (missing)"))
        else:
            self.apply(library, name, chain + [name])

    def apply_overrides(self):
        for override in self.overrides:
            key, _, value = override.partition("=")
            self.define(key, value, ("manifest", self.number))

    def inherit_sections(self):
        own_keys = {}
        for key, definition in self.configuration.items():
            section, _, name = key.rpartition(".")
            own_keys.setdefault(section, []).append((name, definition))
        for section, (parent, origin) in self.parents.items():
            chain = [section]
            while chain[-1] in self.parents and self.parents[chain[-1]][0] not in chain:
                chain.append(self.parents[chain[-1]][0])
            last = chain[-1]
            if last in self.parents:
                path = chain + [self.parents[last][0]]
                self.report(origin, "E_INHERIT_CYCLE", "inheritance cycle " + " -> ".join(path))
                continue
            if parent not in self.parents and parent not in own_keys:
                self.report(
                    origin, "W_PARENT_EMPTY",
                    f"section {section} inherits from empty section {parent}",
                )
            for ancestor in chain[1:]:
                for name, definition in own_keys.get(ancestor, []):
                    key = section + "." + name
                    if key not in self.configuration:
                        self.configuration[key] = definition

    def resolve_aliases(self, schema):
        for spec in schema.specs:
            aliases = [alias for alias in spec.aliases if alias in self.configuration]
            if not aliases:
                continue
            candidates = aliases
            if spec.pattern in self.configuration:
                candidates = [spec.pattern] + aliases
            winner = candidates[0]
            for candidate in candidates[1:]:
                if self.configuration[candidate].number > self.configuration[winner].number:
                    winner = candidate
            chosen = self.configuration[winner]
            for candidate in candidates:
                origin = self.configuration[candidate].origin
                if candidate != spec.pattern:
                    self.report(
                        origin, "W_DEPRECATED",
                        f"{candidate} is deprecated, use {spec.pattern}",
                    )
                if candidate != winner:
                    self.report(
                        origin, "W_SHADOWED",
                        f"{candidate} is superseded by {winner} at {emitter.origin_text(chosen.origin)}",
                    )
            self.configuration[spec.pattern] = chosen
            for alias in aliases:
                del self.configuration[alias]

    def fill_defaults(self, schema):
        sections = {section_of(key) for key in self.configuration}
        for spec in schema.specs:
            if spec.default is None:
                continue
            for key in schema.target_keys(spec, sections):
                if key not in self.configuration:
                    self.define(key, spec.default, ("schema", spec.line))
        return sections

    def expand_values(self):
        values = {key: definition.value for key, definition in self.configuration.items()}
        origins = {key: definition.origin for key, definition in self.configuration.items()}
        expander = Expander(values, origins)
        for key in sorted(self.configuration, key=key_order):
            expander.expand(key)
        self.reported.update(expander.diagnostics)
        return expander.results

    def check_types(self, schema, results):
        for key in sorted(results, key=key_order):
            text = results[key]
            if text is None:
                continue
            definition = self.configuration[key]
            spec = schema.spec_for(key)
            if spec is None:
                self.report(definition.origin, "W_UNKNOWN", f"{key} is not in the schema")
                self.outputs[key] = OutputKey(definition, None, text)
                continue
            try:
                value = self.normalize(key, spec, text, definition.origin)
            except CheckError as error:
                self.report(definition.origin, error.code, error.message)
                continue
            self.outputs[key] = OutputKey(definition, spec, value)

    def normalize(self, key, spec, text, origin):
        if spec.kind == "list":
            value = self.normalize_list(key, spec, text, origin)
        else:
            value = parse_scalar(spec.kind, text, spec.values)
            if value is None:
                raise invalid_value(key, spec.kind, spec.values, checked_text(text, spec.secret))
        if spec.range is not None:
            check_range(key, spec, value)
        return value

    def normalize_list(self, key, spec, text, origin):
        if text.strip(" ") == "":
            return []
        items = [item.strip(" ") for item in text.split(",")]
        if "" in items:
            self.report(origin, "W_EMPTY_ITEM", f"{key}: empty list item ignored")
            items = [item for item in items if item != ""]
        values = []
        for item in items:
            value = parse_scalar(spec.item, item, spec.values)
            if value is None:
                display = "item " + checked_text(item, spec.secret)
                raise invalid_value(key, spec.item, spec.values, display)
            values.append(value)
        if not spec.unique:
            return values
        unique_values = []
        notations = set()
        for value in values:
            notation = value_notation(spec.item, None, value)
            if notation not in notations:
                notations.add(notation)
                unique_values.append(value)
        if len(unique_values) < len(values):
            self.report(origin, "W_DUPLICATE_ITEM", f"{key}: duplicate items removed")
        return unique_values

    def check_order(self):
        reported = []
        for key in sorted(self.outputs, key=key_order):
            output = self.outputs[key]
            if output.spec is None or output.spec.le is None:
                continue
            limit_key = section_of(key) + "." + output.spec.le
            limit = self.outputs.get(limit_key)
            if limit is None or limit.kind not in NUMERIC_TYPES:
                continue
            if output.value > limit.value:
                self.report(
                    output.definition.origin, "E_ORDER",
                    f"{key}: {shown(output)} is greater than {limit_key} ({shown(limit)})",
                )
                reported.append(key)
        for key in reported:
            del self.outputs[key]

    def check_required(self, schema, sections, configured):
        origin = (self.root, 0)
        for spec in schema.specs:
            if not spec.required:
                continue
            for key in schema.target_keys(spec, sections):
                if key in configured:
                    continue
                if spec.when is None:
                    self.report(origin, "E_REQUIRED", f"{key} is required")
                    continue
                condition_key = section_of(key) + "." + spec.when
                condition = self.outputs.get(condition_key)
                if condition is not None and condition.kind == "bool" and condition.value:
                    self.report(
                        origin, "E_REQUIRED",
                        f"{key} is required when {condition_key} is true",
                    )

    def check_fixed(self, earlier):
        for key in sorted(self.outputs, key=key_order):
            output = self.outputs[key]
            if output.spec is None or not output.spec.fixed:
                continue
            reference = next((profile for profile in earlier if key in profile.outputs), None)
            if reference is None or reference.outputs[key].notation == output.notation:
                continue
            self.report(
                output.definition.origin, "E_FIXED",
                f"{key}: value differs from profile {reference.name}",
            )
            del self.outputs[key]

    def summarize(self, configured_count):
        self.diagnostics = sorted(self.reported)
        self.errors = sum(1 for diagnostic in self.diagnostics if diagnostic[2].startswith("E_"))
        self.warnings = len(self.diagnostics) - self.errors
        for key in sorted(self.outputs, key=key_order):
            history = self.outputs[key].definition.history
            if len(history) >= 2:
                self.overridden.append((key, history))
        for output in self.outputs.values():
            document = output.definition.origin[0]
            if document == "manifest":
                self.manifest_keys += 1
            elif document == "schema":
                self.default_keys += 1
            else:
                self.document_keys += 1
        self.dropped = configured_count - len(self.outputs)


class ProfileDiff:
    def __init__(self, first, second):
        self.first = first.name
        self.second = second.name
        self.entries = []
        self.added = 0
        self.removed = 0
        self.changed = 0
        keys = set(first.outputs) | set(second.outputs)
        for key in sorted(keys, key=key_order):
            before = first.outputs.get(key)
            after = second.outputs.get(key)
            if before is None:
                self.added += 1
                self.entries.append(("+", key, before, after))
            elif after is None:
                self.removed += 1
                self.entries.append(("-", key, before, after))
            elif before.notation != after.notation:
                self.changed += 1
                self.entries.append(("~", key, before, after))


def main():
    schema = load_schema(os.path.join(INPUT_DIR, "schema.txt"))
    library = Library(os.path.join(INPUT_DIR, "conf"))
    profiles = []
    for number, line in enumerate(read_lines(os.path.join(INPUT_DIR, "manifest.txt")), 1):
        profile = Profile(number, line)
        profile.process(schema, library, profiles)
        profiles.append(profile)
    diffs = [ProfileDiff(first, second) for first, second in zip(profiles, profiles[1:])]
    emitter.write_outputs(OUTPUT_DIR, profiles, diffs)


if __name__ == "__main__":
    main()
