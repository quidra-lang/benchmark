import sys


OBJECT = "object"
ARRAY = "array"
STRING = "string"
NUMBER = "number"
BOOLEAN = "boolean"
NULL = "null"
KEY = "key"
INDEX = "index"
ALL = "all"
SLICE = "slice"
JSON_ESCAPES = {
    '"': '"', "\\": "\\", "/": "/", "b": "\b", "f": "\f", "n": "\n", "r": "\r", "t": "\t",
}
KEY_ESCAPES = {
    "'": "'", "\\": "\\", "/": "/", "b": "\b", "f": "\f", "n": "\n", "r": "\r", "t": "\t",
}
QUOTE_ESCAPES = {
    "\\": "\\\\", "\b": "\\b", "\f": "\\f", "\n": "\\n", "\r": "\\r", "\t": "\\t",
}
OPERATORS = ("==", "!=", "<", "<=", ">", ">=", "EXISTS")
SORT_RANKS = {NULL: 0, NUMBER: 1, STRING: 2}


class CommandError(Exception):
    pass


class JsonError(Exception):
    def __init__(self, reason, position):
        super().__init__(reason)
        self.reason = reason
        self.position = position


def is_letter(char):
    return "a" <= char <= "z" or "A" <= char <= "Z"


def is_digit(char):
    return "0" <= char <= "9"


def is_hex_digit(char):
    return is_digit(char) or "a" <= char <= "f" or "A" <= char <= "F"


def is_identifier_start(char):
    return is_letter(char) or char == "_"


def is_identifier_char(char):
    return is_identifier_start(char) or is_digit(char)


def is_identifier(text):
    return text != "" and is_identifier_start(text[0]) and all(
        is_identifier_char(char) for char in text
    )


def is_integer_notation(text):
    if text == "0":
        return True
    digits = text[1:] if text.startswith("-") else text
    return 1 <= len(digits) <= 9 and digits[0] != "0" and all(is_digit(char) for char in digits)


def hex_value(digits):
    if len(digits) != 4 or not all(is_hex_digit(char) for char in digits):
        return -1
    return int(digits, 16)


def quote(text, mark):
    parts = [mark]
    for char in text:
        code = ord(char)
        if char == mark:
            parts.append("\\" + char)
        elif char in QUOTE_ESCAPES:
            parts.append(QUOTE_ESCAPES[char])
        elif code < 32 or code == 127:
            parts.append(f"\\u{code:04x}")
        else:
            parts.append(char)
    parts.append(mark)
    return "".join(parts)


class JsonValue:
    def __init__(self, kind, scalar=None):
        self.kind = kind
        self.scalar = scalar
        self.keys = []
        self.items = []

    def find(self, key):
        return self.keys.index(key) if key in self.keys else -1

    def copy(self):
        duplicate = JsonValue(self.kind, self.scalar)
        duplicate.keys = self.keys[:]
        duplicate.items = [item.copy() for item in self.items]
        return duplicate

    def value_count(self):
        return 1 + sum(item.value_count() for item in self.items)

    def depth(self):
        return 1 + max((item.depth() for item in self.items), default=0)


def compact(value):
    if value.kind == NULL:
        return "null"
    if value.kind == BOOLEAN:
        return "true" if value.scalar else "false"
    if value.kind == NUMBER:
        return str(value.scalar)
    if value.kind == STRING:
        return quote(value.scalar, '"')
    if value.kind == ARRAY:
        return "[" + ",".join(compact(item) for item in value.items) + "]"
    members = [quote(key, '"') + ":" + compact(item) for key, item in zip(value.keys, value.items)]
    return "{" + ",".join(members) + "}"


def pretty(value, indent=""):
    if value.kind not in (OBJECT, ARRAY) or not value.items:
        return compact(value)
    inner = indent + "  "
    lines = []
    for position, item in enumerate(value.items):
        label = quote(value.keys[position], '"') + ": " if value.kind == OBJECT else ""
        lines.append(inner + label + pretty(item, inner))
    opening, closing = ("{", "}") if value.kind == OBJECT else ("[", "]")
    return opening + "\n" + ",\n".join(lines) + "\n" + indent + closing


def equal(first, second):
    if first.kind != second.kind:
        return False
    if first.kind == ARRAY:
        return len(first.items) == len(second.items) and all(
            equal(a, b) for a, b in zip(first.items, second.items)
        )
    if first.kind == OBJECT:
        if len(first.keys) != len(second.keys):
            return False
        for key, item in zip(first.keys, first.items):
            position = second.find(key)
            if position < 0 or not equal(item, second.items[position]):
                return False
        return True
    return first.scalar == second.scalar


class JsonReader:
    def __init__(self, text):
        self.text = text
        self.pos = 0

    def peek(self):
        return self.text[self.pos] if self.pos < len(self.text) else ""

    def fail(self, reason, position=None):
        raise JsonError(reason, self.pos if position is None else position)

    def skip_whitespace(self):
        while self.peek() in (" ", "\n"):
            self.pos += 1

    def require(self, char, reason):
        if self.pos == len(self.text):
            self.fail("unexpected end of input")
        if self.text[self.pos] != char:
            self.fail(reason)

    def parse(self):
        value = self.value()
        self.skip_whitespace()
        if self.pos < len(self.text):
            self.fail("trailing characters")
        return value

    def value(self):
        self.skip_whitespace()
        char = self.peek()
        if char == "":
            self.fail("unexpected end of input")
        if char == "{":
            return self.object()
        if char == "[":
            return self.array()
        if char == '"':
            return JsonValue(STRING, self.string())
        if char == "-" or is_digit(char):
            return self.number()
        if is_letter(char):
            return self.literal()
        self.fail(f"unexpected character '{char}'")

    def container_end(self, closing, reason):
        self.skip_whitespace()
        if self.peek() == closing:
            self.pos += 1
            return True
        self.require(",", reason)
        self.pos += 1
        self.skip_whitespace()
        if self.peek() == closing:
            self.fail("trailing comma")
        return False

    def object(self):
        node = JsonValue(OBJECT)
        self.pos += 1
        self.skip_whitespace()
        if self.peek() == "}":
            self.pos += 1
            return node
        while True:
            self.skip_whitespace()
            self.require('"', "expected key")
            start = self.pos
            key = self.string()
            if key in node.keys:
                self.fail("duplicate key " + quote(key, '"'), start)
            self.skip_whitespace()
            self.require(":", "expected ':'")
            self.pos += 1
            node.keys.append(key)
            node.items.append(self.value())
            if self.container_end("}", "expected ',' or '}'"):
                return node

    def array(self):
        node = JsonValue(ARRAY)
        self.pos += 1
        self.skip_whitespace()
        if self.peek() == "]":
            self.pos += 1
            return node
        while True:
            node.items.append(self.value())
            if self.container_end("]", "expected ',' or ']'"):
                return node

    def string(self):
        self.pos += 1
        chars = []
        while True:
            char = self.peek()
            if char == "" or char == "\n":
                self.fail("unterminated string")
            if char == '"':
                self.pos += 1
                return "".join(chars)
            if char == "\\":
                chars.append(self.escape())
            else:
                chars.append(char)
                self.pos += 1

    def escape(self):
        start = self.pos
        self.pos += 1
        escape = self.peek()
        if escape == "" or escape == "\n":
            self.fail("unterminated string")
        if escape == "u":
            code = hex_value(self.text[start + 2:start + 6])
            if code < 0:
                self.fail("bad unicode escape", start)
            if code > 127:
                self.fail("non-ascii escape", start)
            self.pos = start + 6
            return chr(code)
        if escape not in JSON_ESCAPES:
            self.fail(f"invalid escape '\\{escape}'", start)
        self.pos += 1
        return JSON_ESCAPES[escape]

    def number(self):
        start = self.pos
        negative = self.peek() == "-"
        if negative:
            self.pos += 1
        digits_start = self.pos
        while is_digit(self.peek()):
            self.pos += 1
        digits = self.text[digits_start:self.pos]
        if digits == "":
            self.fail("invalid number", start)
        if len(digits) >= 2 and digits[0] == "0":
            self.fail("leading zero", digits_start)
        if self.peek() == ".":
            self.fail("fraction not allowed")
        if self.peek() in ("e", "E"):
            self.fail("exponent not allowed")
        if len(digits) >= 10:
            self.fail("number out of range", start)
        value = int(digits)
        return JsonValue(NUMBER, -value if negative else value)

    def literal(self):
        start = self.pos
        while is_letter(self.peek()):
            self.pos += 1
        word = self.text[start:self.pos]
        if word == "true":
            return JsonValue(BOOLEAN, True)
        if word == "false":
            return JsonValue(BOOLEAN, False)
        if word == "null":
            return JsonValue(NULL)
        self.fail(f"invalid literal '{word}'", start)


class Segment:
    def __init__(self, kind, key="", index=0, start=None, end=None):
        self.kind = kind
        self.key = key
        self.index = index
        self.start = start
        self.end = end
        self.descendant = False


class PathReader:
    def __init__(self, text, error):
        self.text = text
        self.pos = 0
        self.error = error

    def fail(self):
        raise CommandError(self.error)

    def at_end(self):
        return self.pos == len(self.text)

    def peek(self):
        return "" if self.at_end() else self.text[self.pos]

    def accept(self, char):
        if self.peek() != char:
            return False
        self.pos += 1
        return True

    def expect(self, char):
        if not self.accept(char):
            self.fail()

    def identifier(self):
        start = self.pos
        if not is_identifier_start(self.peek()):
            self.fail()
        while is_identifier_char(self.peek()):
            self.pos += 1
        return self.text[start:self.pos]

    def quoted_key(self):
        self.expect("'")
        chars = []
        while True:
            char = self.peek()
            if char == "":
                self.fail()
            self.pos += 1
            if char == "'":
                return "".join(chars)
            chars.append(self.escape() if char == "\\" else char)

    def escape(self):
        escape = self.peek()
        self.pos += 1
        if escape == "u":
            code = hex_value(self.text[self.pos:self.pos + 4])
            if code < 0 or code > 127:
                self.fail()
            self.pos += 4
            return chr(code)
        if escape not in KEY_ESCAPES:
            self.fail()
        return KEY_ESCAPES[escape]

    def selection(self):
        if self.peek() == "'":
            key = self.quoted_key()
            self.expect("]")
            return Segment(KEY, key=key)
        end = self.text.find("]", self.pos)
        if end < 0:
            self.fail()
        content = self.text[self.pos:end]
        self.pos = end + 1
        if content == "*":
            return Segment(ALL)
        if is_integer_notation(content):
            return Segment(INDEX, index=int(content))
        start, colon, stop = content.partition(":")
        for bound in (start, stop):
            if bound != "" and not is_integer_notation(bound):
                self.fail()
        if colon == "":
            self.fail()
        return Segment(
            SLICE,
            start=int(start) if start else None,
            end=int(stop) if stop else None,
        )


def parse_path(text):
    reader = PathReader(text, "bad path")
    reader.expect("$")
    segments = []
    while not reader.at_end():
        if reader.accept("["):
            segments.append(reader.selection())
            continue
        reader.expect(".")
        descendant = reader.accept(".")
        if reader.accept("*"):
            segment = Segment(ALL)
        elif descendant and reader.accept("["):
            segment = reader.selection()
        else:
            segment = Segment(KEY, key=reader.identifier())
        segment.descendant = descendant
        segments.append(segment)
    return segments


def parse_field(text):
    reader = PathReader(text, "bad field")
    reader.expect("@")
    segments = []
    while not reader.at_end():
        if reader.accept("["):
            segment = reader.selection()
            if segment.kind not in (KEY, INDEX):
                reader.fail()
        else:
            reader.expect(".")
            segment = Segment(KEY, key=reader.identifier())
        segments.append(segment)
    return segments


def parse_key(text):
    reader = PathReader(text, "bad key")
    if reader.peek() == "'":
        key = reader.quoted_key()
    else:
        key = reader.identifier()
    if not reader.at_end():
        reader.fail()
    return key


class Step:
    def __init__(self, key, position):
        self.key = key
        self.position = position

    def text(self):
        if self.key is None:
            return f"[{self.position}]"
        if is_identifier(self.key):
            return "." + self.key
        return "[" + quote(self.key, "'") + "]"


class Match:
    def __init__(self, node, steps):
        self.node = node
        self.steps = steps

    def child(self, position):
        key = self.node.keys[position] if self.node.kind == OBJECT else None
        return Match(self.node.items[position], self.steps + [Step(key, position)])

    def location(self):
        return "$" + "".join(step.text() for step in self.steps)

    def positions(self):
        return [step.position for step in self.steps]


def child_position(value, segment):
    if segment.kind == KEY:
        return value.find(segment.key) if value.kind == OBJECT else -1
    if value.kind != ARRAY:
        return -1
    size = len(value.items)
    index = segment.index if segment.index >= 0 else size + segment.index
    return index if 0 <= index < size else -1


def clamp_bound(bound, size):
    if bound < 0:
        bound += size
    return min(max(bound, 0), size)


def slice_positions(value, segment):
    if value.kind != ARRAY:
        return range(0)
    size = len(value.items)
    start = 0 if segment.start is None else clamp_bound(segment.start, size)
    end = size if segment.end is None else clamp_bound(segment.end, size)
    return range(start, end)


def select(segment, match, results):
    if segment.kind == ALL:
        positions = range(len(match.node.items))
    elif segment.kind == SLICE:
        positions = slice_positions(match.node, segment)
    else:
        position = child_position(match.node, segment)
        positions = [position] if position >= 0 else []
    for position in positions:
        results.append(match.child(position))


def preorder(match, results):
    results.append(match)
    for position in range(len(match.node.items)):
        preorder(match.child(position), results)
    return results


def apply_segment(segment, matches):
    results = []
    for match in matches:
        sources = preorder(match, []) if segment.descendant else [match]
        for source in sources:
            select(segment, source, results)
    return results


def evaluate(root, segments):
    matches = [Match(root, [])]
    for segment in segments:
        matches = apply_segment(segment, matches)
    return matches


def field_value(value, segments):
    for segment in segments:
        position = child_position(value, segment)
        if position < 0:
            return None
        value = value.items[position]
    return value


def filter_holds(operator, value, reference):
    if operator == "EXISTS":
        return value is not None
    if operator in ("==", "!="):
        same = value is not None and equal(value, reference)
        return same if operator == "==" else not same
    if value is None or value.kind != reference.kind or value.kind not in (NUMBER, STRING):
        return False
    if operator == "<":
        return value.scalar < reference.scalar
    if operator == "<=":
        return value.scalar <= reference.scalar
    if operator == ">":
        return value.scalar > reference.scalar
    return value.scalar >= reference.scalar


def sort_key(value):
    if value is None or value.kind not in SORT_RANKS:
        return 3, 0
    if value.kind == NULL:
        return 0, 0
    return SORT_RANKS[value.kind], value.scalar


def average_text(numbers):
    total = sum(numbers)
    count = len(numbers)
    rounded = (abs(total) * 200 + count) // (2 * count)
    sign = "-" if total < 0 and rounded >= 1 else ""
    return f"{sign}{rounded // 100}.{rounded % 100:02d}"


def require_kind(matches, kind, message):
    for match in matches:
        if match.node.kind != kind:
            raise CommandError(f"{message} at {match.location()}")


def reverse_document_order(matches):
    ordered = sorted(matches, key=lambda match: match.positions(), reverse=True)
    targets = []
    for match in ordered:
        if not targets or targets[-1].positions() != match.positions():
            targets.append(match)
    return targets


def resolve(root, positions):
    value = root
    for position in positions:
        value = value.items[position]
    return value


def locate(root, target):
    positions = target.positions()
    return resolve(root, positions[:-1]), positions[-1]


def merge_into(target, patch):
    for key, item in zip(patch.keys, patch.items):
        position = target.find(key)
        if position < 0:
            target.keys.append(key)
            target.items.append(item.copy())
        elif target.items[position].kind == OBJECT and item.kind == OBJECT:
            merge_into(target.items[position], item)
        else:
            target.items[position] = item.copy()


def split_arguments(argument_part, count):
    parts = [] if argument_part is None else argument_part.split(" ", count - 1)
    if len(parts) < count:
        raise CommandError("bad arguments")
    return parts


def words(argument_part, minimum, maximum):
    result = [] if argument_part is None else argument_part.split(" ")
    if not minimum <= len(result) <= maximum:
        raise CommandError("bad arguments")
    return result


class JsonQueryTool:
    def __init__(self):
        self.document = JsonValue(NULL)
        self.history = []
        self.output = []
        self.handlers = {
            "GET": self.get,
            "COMPACT": self.show_compact,
            "PRETTY": self.show_pretty,
            "TYPE": self.show_type,
            "LENGTH": self.length,
            "KEYS": self.keys,
            "FLATTEN": self.flatten,
            "COUNT": self.count,
            "SUM": self.total,
            "MIN": self.minimum,
            "MAX": self.maximum,
            "AVG": self.average,
            "FILTER": self.filter_elements,
            "SET": self.set_value,
            "DELETE": self.delete,
            "INSERT": self.insert,
            "MERGE": self.merge,
            "SORT": self.sort,
            "RENAME": self.rename,
            "UNDO": self.undo,
        }

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def commit(self, document):
        self.history.append(self.document)
        self.document = document

    def load(self, lines):
        text = "\n".join(lines)
        try:
            document = JsonReader(text).parse()
        except JsonError as error:
            line = text.count("\n", 0, error.position) + 1
            column = error.position - text.rfind("\n", 0, error.position)
            self.emit(f"PARSE ERROR line {line} col {column}: {error.reason}")
            return
        self.commit(document)
        self.emit(f"LOADED nodes={document.value_count()} depth={document.depth()}")

    def execute(self, line):
        name, space, argument_part = line.partition(" ")
        if name not in self.handlers:
            self.emit(f"ERROR unknown command '{name}'")
            return
        try:
            self.handlers[name](argument_part if space else None)
        except CommandError as error:
            self.emit("ERROR", error)
        except JsonError as error:
            self.emit(f"PARSE ERROR col {error.position + 1}: {error.reason}")

    def path_matches(self, argument_part, optional=False):
        arguments = words(argument_part, 0 if optional else 1, 1)
        path = arguments[0] if arguments else "$"
        return evaluate(self.document, parse_path(path))

    def report(self, matches, describe):
        if not matches:
            self.emit("no match")
        for match in matches:
            self.emit(describe(match))

    def get(self, argument_part):
        matches = self.path_matches(argument_part)
        self.report(matches, lambda match: match.location() + " = " + compact(match.node))

    def show_compact(self, argument_part):
        matches = self.path_matches(argument_part, True)
        self.report(matches, lambda match: compact(match.node))

    def show_pretty(self, argument_part):
        matches = self.path_matches(argument_part, True)
        self.report(matches, lambda match: pretty(match.node))

    def show_type(self, argument_part):
        matches = self.path_matches(argument_part)
        self.report(matches, lambda match: match.location() + " " + match.node.kind)

    def length(self, argument_part):
        matches = self.path_matches(argument_part)
        for match in matches:
            if match.node.kind not in (OBJECT, ARRAY, STRING):
                raise CommandError(f"no length at {match.location()}")
        self.report(matches, lambda match: f"{match.location()} {length_of(match.node)}")

    def keys(self, argument_part):
        matches = self.path_matches(argument_part)
        require_kind(matches, OBJECT, "not an object")
        self.report(matches, lambda match: match.location() + " " + key_array(match.node))

    def flatten(self, argument_part):
        matches = self.path_matches(argument_part, True)
        if not matches:
            self.emit("no match")
        for match in matches:
            for leaf in preorder(match, []):
                if not leaf.node.items:
                    self.emit(leaf.location(), "=", compact(leaf.node))

    def count(self, argument_part):
        self.emit("COUNT", len(self.path_matches(argument_part)))

    def numbers(self, argument_part):
        matches = self.path_matches(argument_part)
        return [match.node.scalar for match in matches if match.node.kind == NUMBER]

    def total(self, argument_part):
        self.emit("SUM", sum(self.numbers(argument_part)))

    def minimum(self, argument_part):
        numbers = self.numbers(argument_part)
        self.emit("MIN", min(numbers) if numbers else "null")

    def maximum(self, argument_part):
        numbers = self.numbers(argument_part)
        self.emit("MAX", max(numbers) if numbers else "null")

    def average(self, argument_part):
        numbers = self.numbers(argument_part)
        self.emit("AVG", average_text(numbers) if numbers else "null")

    def filter_elements(self, argument_part):
        parts = [] if argument_part is None else argument_part.split(" ", 3)
        has_value = len(parts) == 4
        if len(parts) < 3 or has_value == (parts[2] == "EXISTS"):
            raise CommandError("bad arguments")
        segments = parse_path(parts[0])
        field = parse_field(parts[1])
        operator = parts[2]
        if operator not in OPERATORS:
            raise CommandError("bad operator")
        reference = JsonReader(parts[3]).parse() if has_value else None
        matches = evaluate(self.document, segments)
        require_kind(matches, ARRAY, "not an array")
        found = False
        for match in matches:
            for position in range(len(match.node.items)):
                element = match.child(position)
                if filter_holds(operator, field_value(element.node, field), reference):
                    self.emit(element.location(), "=", compact(element.node))
                    found = True
        if not found:
            self.emit("no match")

    def set_value(self, argument_part):
        path, value_text = split_arguments(argument_part, 2)
        segments = parse_path(path)
        value = JsonReader(value_text).parse()
        if not segments:
            self.commit(value)
            self.emit("SET", 1)
            return
        last = segments[-1]
        targets = []
        for parent in evaluate(self.document, segments[:-1]):
            if last.kind == KEY and not last.descendant and parent.node.kind == OBJECT:
                position = parent.node.find(last.key)
                if position < 0:
                    position = len(parent.node.items)
                targets.append(Match(None, parent.steps + [Step(last.key, position)]))
            else:
                targets.extend(apply_segment(last, [parent]))
        targets = reverse_document_order(targets)
        document = self.document.copy()
        for target in targets:
            container, position = locate(document, target)
            if position == len(container.items):
                container.keys.append(target.steps[-1].key)
                container.items.append(value.copy())
            else:
                container.items[position] = value.copy()
        self.commit(document)
        self.emit("SET", len(targets))

    def delete(self, argument_part):
        path, = words(argument_part, 1, 1)
        segments = parse_path(path)
        if not segments:
            raise CommandError("cannot delete root")
        targets = reverse_document_order(evaluate(self.document, segments))
        document = self.document.copy()
        for target in targets:
            container, position = locate(document, target)
            del container.items[position]
            if container.kind == OBJECT:
                del container.keys[position]
        self.commit(document)
        self.emit("DELETE", len(targets))

    def insert(self, argument_part):
        path, index_text, value_text = split_arguments(argument_part, 3)
        segments = parse_path(path)
        if not is_integer_notation(index_text):
            raise CommandError("bad index")
        index = int(index_text)
        value = JsonReader(value_text).parse()
        matches = evaluate(self.document, segments)
        require_kind(matches, ARRAY, "not an array")
        for match in matches:
            size = len(match.node.items)
            if not -size - 1 <= index <= size:
                raise CommandError(f"index out of range at {match.location()}")
        targets = reverse_document_order(matches)
        document = self.document.copy()
        for target in targets:
            array = resolve(document, target.positions())
            position = index if index >= 0 else len(array.items) + 1 + index
            array.items.insert(position, value.copy())
        self.commit(document)
        self.emit("INSERT", len(targets))

    def merge(self, argument_part):
        path, value_text = split_arguments(argument_part, 2)
        segments = parse_path(path)
        patch = JsonReader(value_text).parse()
        if patch.kind != OBJECT:
            raise CommandError("merge value is not an object")
        matches = evaluate(self.document, segments)
        require_kind(matches, OBJECT, "not an object")
        targets = reverse_document_order(matches)
        document = self.document.copy()
        for target in targets:
            merge_into(resolve(document, target.positions()), patch)
        self.commit(document)
        self.emit("MERGE", len(targets))

    def sort(self, argument_part):
        arguments = words(argument_part, 1, 3)
        options = arguments[1:]
        descending = len(options) > 0 and options[-1] == "DESC"
        if descending:
            options.pop()
        if len(options) > 1 or "DESC" in options:
            raise CommandError("bad arguments")
        segments = parse_path(arguments[0])
        field = parse_field(options[0] if options else "@")
        matches = evaluate(self.document, segments)
        require_kind(matches, ARRAY, "not an array")
        targets = reverse_document_order(matches)
        document = self.document.copy()
        for target in targets:
            array = resolve(document, target.positions())
            array.items.sort(
                key=lambda item: sort_key(field_value(item, field)), reverse=descending
            )
        self.commit(document)
        self.emit("SORT", len(targets))

    def rename(self, argument_part):
        path, key_text = words(argument_part, 2, 2)
        segments = parse_path(path)
        new_key = parse_key(key_text)
        matches = evaluate(self.document, segments)
        for match in matches:
            if not match.steps or match.steps[-1].key is None:
                raise CommandError(f"not a member at {match.location()}")
        targets = reverse_document_order(matches)
        document = self.document.copy()
        for target in targets:
            container, position = locate(document, target)
            if container.keys[position] != new_key and new_key in container.keys:
                raise CommandError(f"key exists at {target.location()}")
            container.keys[position] = new_key
        self.commit(document)
        self.emit("RENAME", len(targets))

    def undo(self, argument_part):
        words(argument_part, 0, 0)
        if not self.history:
            raise CommandError("nothing to undo")
        self.document = self.history.pop()
        self.emit("UNDO", len(self.history))


def length_of(value):
    return len(value.scalar) if value.kind == STRING else len(value.items)


def key_array(value):
    return "[" + ",".join(quote(key, '"') for key in value.keys) + "]"


def read_block(lines, start):
    end = start
    while end < len(lines) and lines[end] != "%%":
        end += 1
    return lines[start:end], end + 1


def main():
    lines = sys.stdin.read().split("\n")
    tool = JsonQueryTool()
    block, position = read_block(lines, 0)
    tool.load(block)
    while position < len(lines) and lines[position] != "END":
        line = lines[position]
        position += 1
        if line == "LOAD":
            block, position = read_block(lines, position)
            tool.load(block)
        else:
            tool.execute(line)
    sys.stdout.write("\n".join(tool.output) + "\n")


if __name__ == "__main__":
    main()
