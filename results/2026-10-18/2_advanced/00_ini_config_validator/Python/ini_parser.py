import re

from lexer import logical_lines


NAME = r"[a-z][a-z0-9_]*"
NAME_PATTERN = re.compile(NAME)
SECTION_PATTERN = re.compile(rf"{NAME}(?:\.{NAME})*")
DIRECTIVES = ("@include", "@unset")


def is_name(text):
    return NAME_PATTERN.fullmatch(text) is not None


def is_section_name(text):
    return SECTION_PATTERN.fullmatch(text) is not None


def trimmed(segments):
    result = list(segments)
    result[0] = result[0].lstrip(" ")
    result[-1] = result[-1].rstrip(" ")
    return result


def assigned_value(segments):
    if len(segments) == 1:
        return segments[0]
    if len(segments) == 3 and segments[0] == "" and segments[2] == "":
        return segments[1]
    return None


class Statement:
    def __init__(self, kind, line, target, value=""):
        self.kind = kind
        self.line = line
        self.target = target
        self.value = value


class Document:
    def __init__(self, name):
        self.name = name
        self.statements = []
        self.diagnostics = []


class DocumentParser:
    def __init__(self, name):
        self.document = Document(name)
        self.section = None
        self.base = None
        self.assigned = {}

    def report(self, line, code, message):
        self.document.diagnostics.append((self.document.name, line, code, message))

    def add(self, kind, line, target, value=""):
        self.document.statements.append(Statement(kind, line, target, value))

    def interpret(self, line):
        if line.error is not None:
            code, message = line.error
            self.report(line.number, code, message)
            return
        segments = trimmed(line.segments)
        first = segments[0]
        if len(segments) == 1 and first == "":
            return
        if first.startswith("["):
            self.header(line.number, segments)
        elif first.startswith("@"):
            self.directive(line.number, segments)
        else:
            self.assignment(line.number, segments)

    def fail_header(self, number, message):
        self.report(number, "E_SECTION", message)
        self.section = None

    def header(self, number, segments):
        text = segments[0]
        name, colon, parent = text[1:-1].partition(":")
        name = name.strip(" ")
        parent = parent.strip(" ")
        well_formed = len(segments) == 1 and text.endswith("]")
        relative = name.startswith(".") and is_section_name(name[1:])
        if not well_formed or (colon and not is_section_name(parent)):
            self.fail_header(number, "invalid section header")
        elif not relative and not is_section_name(name):
            self.fail_header(number, "invalid section header")
        elif relative and self.base is None:
            self.fail_header(number, "relative section without base")
        else:
            if relative:
                self.section = self.base + name
            else:
                self.section = name
                self.base = name
            if colon:
                self.add("inherit", number, self.section, parent)

    def directive(self, number, segments):
        words = segments[0].split()
        if len(segments) > 1 or len(words) != 2 or words[0] not in DIRECTIVES or not is_name(words[1]):
            self.report(number, "E_SYNTAX", "invalid directive")
        elif words[0] == "@include":
            self.add("include", number, words[1])
        elif self.section is None:
            self.report(number, "E_NO_SECTION", "no current section")
        else:
            self.add("unset", number, self.section + "." + words[1])

    def assignment(self, number, segments):
        if not any("=" in segment for segment in segments[::2]):
            self.report(number, "E_SYNTAX", "invalid line")
            return
        if "=" not in segments[0]:
            self.report(number, "E_SYNTAX", "invalid key")
            return
        key, _, rest = segments[0].partition("=")
        key = key.strip(" ")
        append = key.endswith("+")
        if append:
            key = key[:-1].rstrip(" ")
        if not is_name(key):
            self.report(number, "E_SYNTAX", "invalid key")
            return
        value = assigned_value(trimmed([rest] + segments[1:]))
        if value is None:
            self.report(number, "E_SYNTAX", "invalid value")
            return
        if self.section is None:
            self.report(number, "E_NO_SECTION", "no current section")
            return
        full_key = self.section + "." + key
        if not append:
            if full_key in self.assigned:
                previous = self.assigned[full_key]
                self.report(number, "W_DUPLICATE", f"{full_key} already set at line {previous}")
            self.assigned[full_key] = number
        self.add("append" if append else "assign", number, full_key, value)


def parse_document(name, physical_lines):
    parser = DocumentParser(name)
    for line in logical_lines(physical_lines):
        parser.interpret(line)
    return parser.document
