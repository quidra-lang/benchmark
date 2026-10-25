import operator
import re
import sys


IDENTIFIER = r"[A-Za-z_][A-Za-z0-9_]*"
SUBSCRIPT = r"0|[1-9][0-9]*"
SEGMENT = rf"{IDENTIFIER}|{SUBSCRIPT}"
IDENTIFIER_PATTERN = re.compile(IDENTIFIER)
KEY_PATTERN = re.compile(rf"{IDENTIFIER}(?:\.{IDENTIFIER}|\[(?:{SUBSCRIPT})\])*")
KEY_PART_PATTERN = re.compile(rf"({IDENTIFIER})|\[({SUBSCRIPT})\]")
NAME_PATTERN = re.compile(rf"\.|@(?:index|number|first|last)|(?:{SEGMENT})(?:\.(?:{SEGMENT}))*")
INTEGER_PATTERN = re.compile(r"0|-?[1-9][0-9]*")
NUMBER_TEXT_PATTERN = re.compile(r"-?[0-9]{1,9}")
STRING_ARGUMENT_PATTERN = re.compile(r"'[^']*'")

STRING_ESCAPES = {'"': '"', "\\": "\\", "n": "\n"}
HTML_ESCAPES = str.maketrans(
    {"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"}
)
SIGILS = {
    "#": "section",
    "^": "inverted",
    "/": "close",
    "!": "comment",
    ">": "partial",
    "&": "raw",
    "=": "delimiter",
}
STANDALONE_KINDS = {"section", "inverted", "close", "comment", "partial", "delimiter"}
FILTERS = {
    "upper", "lower", "title", "trim", "length", "first", "last", "reverse", "items",
    "comma", "sum", "min", "max", "default", "eq", "pad", "lpad", "truncate", "replace",
    "join", "sort", "pluck", "add", "sub", "mul", "div", "mod", "gt", "lt",
}
ARITHMETIC = {
    "add": operator.add,
    "sub": operator.sub,
    "mul": operator.mul,
    "div": operator.floordiv,
    "mod": operator.mod,
    "gt": operator.gt,
    "lt": operator.lt,
}
MAX_PARTIAL_DEPTH = 8


class DataError(Exception):
    pass


class RenderError(Exception):
    pass


class TemplateError(Exception):
    def __init__(self, number, reason):
        super().__init__(reason)
        self.number = number
        self.reason = reason


class Expression:
    def __init__(self, name, filters):
        self.name = name
        self.filters = filters


class Tag:
    def __init__(self, kind, number, argument):
        self.kind = kind
        self.number = number
        self.argument = argument
        self.expression = None
        self.children = []
        self.indentation = ""


def has_part(value, part):
    if isinstance(part, str):
        return isinstance(value, dict) and part in value
    return isinstance(value, list) and part < len(value)


def put(container, part, value):
    if isinstance(container, list) and part == len(container):
        container.append(value)
    else:
        container[part] = value


def parse_key(key):
    if not KEY_PATTERN.fullmatch(key):
        raise DataError(f"bad key '{key}'")
    parts = []
    for match in KEY_PART_PATTERN.finditer(key):
        identifier, subscript = match.groups()
        parts.append((identifier if identifier else int(subscript), key[: match.end()]))
    return parts


def read_string(text, start):
    characters = []
    position = start
    while position < len(text):
        char = text[position]
        if char == '"':
            return "".join(characters), position + 1
        if char == "\\":
            escaped = STRING_ESCAPES.get(text[position + 1 : position + 2])
            if escaped is None:
                raise ValueError
            characters.append(escaped)
            position += 2
        else:
            characters.append(char)
            position += 1
    raise ValueError


def read_scalar(text, start):
    if text.startswith('"', start):
        return read_string(text, start + 1)
    end = start
    while end < len(text) and text[end] not in ",]":
        end += 1
    word = text[start:end]
    if word in ("true", "false"):
        return word == "true", end
    if INTEGER_PATTERN.fullmatch(word):
        return int(word), end
    raise ValueError


def read_list(text):
    elements = []
    position = 1
    while True:
        element, position = read_scalar(text, position)
        elements.append(element)
        if text.startswith(", ", position):
            position += 2
        elif text[position:] == "]":
            return elements
        else:
            raise ValueError


def parse_value(notation):
    try:
        if notation == "[]":
            return []
        if notation == "{}":
            return {}
        if notation.startswith("["):
            return read_list(notation)
        value, end = read_scalar(notation, 0)
        if end != len(notation):
            raise ValueError
        return value
    except ValueError:
        raise DataError(f"bad value '{notation}'") from None


def notation_of(value):
    if isinstance(value, str):
        escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
        return f'"{escaped}"'
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    return "[]" if isinstance(value, list) else "{}"


def collect_leaves(value, path, leaves):
    if isinstance(value, dict) and value:
        for key in sorted(value):
            collect_leaves(value[key], f"{path}.{key}", leaves)
    elif isinstance(value, list) and value:
        for index, element in enumerate(value):
            collect_leaves(element, f"{path}[{index}]", leaves)
    else:
        leaves.append(f"{path} = {notation_of(value)}")


def split_unquoted(text, separator):
    pieces = []
    start = 0
    quoted = False
    for position, char in enumerate(text):
        if char == "'":
            quoted = not quoted
        elif char == separator and not quoted:
            pieces.append(text[start:position])
            start = position + 1
    pieces.append(text[start:])
    return pieces


def parse_argument(text):
    if STRING_ARGUMENT_PATTERN.fullmatch(text):
        return text[1:-1]
    if NUMBER_TEXT_PATTERN.fullmatch(text):
        return int(text)
    return None


def valid_arguments(name, arguments):
    kinds = tuple(type(argument) for argument in arguments)
    match name:
        case "default" | "eq":
            return len(arguments) == 1
        case "pad" | "lpad":
            if kinds not in ((int,), (int, str)) or arguments[0] < 0:
                return False
            return len(arguments) == 1 or len(arguments[1]) == 1
        case "truncate":
            return kinds == (int,) and arguments[0] >= 0
        case "replace":
            return kinds == (str, str) and arguments[0] != ""
        case "join" | "pluck":
            return kinds == (str,)
        case "sort":
            return kinds in ((), (str,))
        case "div" | "mod":
            return kinds == (int,) and arguments[0] != 0
        case "add" | "sub" | "mul" | "gt" | "lt":
            return kinds == (int,)
        case _:
            return not arguments


def parse_expression(text, number):
    pieces = split_unquoted(text, "|")
    name = pieces[0].strip()
    if not NAME_PATTERN.fullmatch(name):
        raise TemplateError(number, f"invalid name '{name}'")
    filters = []
    for piece in pieces[1:]:
        filter_name, *texts = split_unquoted(piece.strip(), ":")
        if filter_name not in FILTERS:
            raise TemplateError(number, f"unknown filter '{filter_name}'")
        arguments = [parse_argument(argument) for argument in texts]
        if None in arguments or not valid_arguments(filter_name, arguments):
            raise TemplateError(number, f"bad arguments for '{filter_name}'")
        filters.append((filter_name, arguments))
    return Expression(name, filters)


def read_tag(line, start, opening, closing, number):
    after = start + len(opening)
    if line.startswith("{", after):
        end = line.find("}" + closing, after + 1)
        if end < 0:
            raise TemplateError(number, "unclosed tag")
        return Tag("raw", number, line[after + 1 : end].strip()), end + 1 + len(closing)
    end = line.find(closing, after)
    if end < 0:
        raise TemplateError(number, "unclosed tag")
    content = line[after:end].strip()
    kind = SIGILS.get(content[:1], "variable")
    if kind in ("variable", "delimiter"):
        return Tag(kind, number, content), end + len(closing)
    return Tag(kind, number, content[1:].strip()), end + len(closing)


def parse_delimiters(content, number):
    items = content[1:-1].split()
    if (
        len(content) < 2
        or not content.endswith("=")
        or len(items) != 2
        or any("=" in item for item in items)
    ):
        raise TemplateError(number, "invalid delimiters")
    return items


def check_tag(tag, open_sections):
    match tag.kind:
        case "variable" | "raw":
            tag.expression = parse_expression(tag.argument, tag.number)
        case "section" | "inverted":
            tag.expression = parse_expression(tag.argument, tag.number)
            open_sections.append(tag)
        case "close":
            name = tag.argument
            if not NAME_PATTERN.fullmatch(name):
                raise TemplateError(tag.number, f"invalid name '{name}'")
            if not open_sections:
                raise TemplateError(tag.number, f"unexpected closing '{name}'")
            expected = open_sections[-1].expression.name
            if name != expected:
                raise TemplateError(
                    tag.number, f"mismatched closing '{name}', expected '{expected}'"
                )
            open_sections.pop()
        case "partial":
            if not IDENTIFIER_PATTERN.fullmatch(tag.argument):
                raise TemplateError(tag.number, f"invalid name '{tag.argument}'")


def place_tokens(tokens, targets):
    texts = tokens[0::2]
    tags = tokens[1::2]
    if len(tags) == 1 and tags[0].kind in STANDALONE_KINDS and not "".join(texts).strip():
        if tags[0].kind == "partial":
            tags[0].indentation = texts[0]
        tokens = tags
    else:
        tokens.append("\n")
    for token in tokens:
        if isinstance(token, str):
            if token:
                targets[-1].append(token)
        elif token.kind in ("section", "inverted"):
            targets[-1].append(token)
            targets.append(token.children)
        elif token.kind == "close":
            targets.pop()
        elif token.kind not in ("comment", "delimiter"):
            targets[-1].append(token)


def parse_source(lines):
    opening, closing = "{{", "}}"
    open_sections = []
    nodes = []
    targets = [nodes]
    for number, line in lines:
        tokens = []
        position = 0
        while True:
            start = line.find(opening, position)
            if start < 0:
                tokens.append(line[position:])
                break
            tokens.append(line[position:start])
            tag, position = read_tag(line, start, opening, closing, number)
            if tag.kind == "delimiter":
                opening, closing = parse_delimiters(tag.argument, number)
            else:
                check_tag(tag, open_sections)
            tokens.append(tag)
        place_tokens(tokens, targets)
    if open_sections:
        innermost = open_sections[-1]
        raise TemplateError(innermost.number, f"unclosed section '{innermost.expression.name}'")
    return nodes


def to_string(value):
    match value:
        case None:
            return ""
        case bool():
            return "true" if value else "false"
        case int():
            return str(value)
        case str():
            return value
        case list():
            return ", ".join(to_string(element) for element in value)
        case _:
            raise RenderError("cannot render map")


def to_number(value, filter_name):
    if value is None:
        return 0
    if type(value) is int:
        return value
    if isinstance(value, str) and NUMBER_TEXT_PATTERN.fullmatch(value):
        return int(value)
    raise RenderError(f"not a number for '{filter_name}'")


def sort_rank(value):
    match value:
        case None:
            return (0, 0)
        case bool():
            return (3, value)
        case int():
            return (1, value)
        case str():
            return (2, value)
        case _:
            return (4, 0)


def field_of(element, key):
    return element.get(key) if isinstance(element, dict) else None


def title_case(text):
    return "".join(
        char.upper() if index == 0 or text[index - 1] == " " else char.lower()
        for index, char in enumerate(text)
    )


def aggregate(name, value):
    if not isinstance(value, list):
        return to_number(value, name)
    numbers = [to_number(element, name) for element in value]
    if name == "sum":
        return sum(numbers)
    if not numbers:
        return None
    return min(numbers) if name == "min" else max(numbers)


def apply_filter(name, arguments, value):
    match name:
        case "upper":
            return to_string(value).upper()
        case "lower":
            return to_string(value).lower()
        case "title":
            return title_case(to_string(value))
        case "trim":
            return to_string(value).strip(" ")
        case "length":
            if isinstance(value, (list, dict)):
                return len(value)
            return len(to_string(value))
        case "first" | "last":
            if not isinstance(value, list):
                return value
            if not value:
                return None
            return value[0] if name == "first" else value[-1]
        case "reverse":
            return value[::-1] if isinstance(value, (list, str)) else value
        case "items":
            if not isinstance(value, dict):
                return value
            return [{"key": key, "value": value[key]} for key in sorted(value)]
        case "comma":
            return f"{to_number(value, name):,}"
        case "sum" | "min" | "max":
            return aggregate(name, value)
        case "default":
            return value or arguments[0]
        case "eq":
            return to_string(value) == to_string(arguments[0])
        case "pad" | "lpad":
            text = to_string(value)
            fill = arguments[1] if len(arguments) == 2 else " "
            if name == "pad":
                return text.ljust(arguments[0], fill)
            return text.rjust(arguments[0], fill)
        case "truncate":
            text = to_string(value)
            limit = arguments[0]
            return text[:limit] + "..." if len(text) > limit else text
        case "replace":
            return to_string(value).replace(arguments[0], arguments[1])
        case "join":
            if not isinstance(value, list):
                return to_string(value)
            return arguments[0].join(to_string(element) for element in value)
        case "sort":
            if not isinstance(value, list):
                return value
            if not arguments:
                return sorted(value, key=sort_rank)
            return sorted(value, key=lambda element: sort_rank(field_of(element, arguments[0])))
        case "pluck":
            if not isinstance(value, list):
                return value
            return [field_of(element, arguments[0]) for element in value]
        case _:
            return ARITHMETIC[name](to_number(value, name), arguments[0])


class Renderer:
    def __init__(self, root, partials, strict):
        self.partials = partials
        self.strict = strict
        self.contexts = [root]
        self.loops = []
        self.output = []

    def render(self, nodes, depth):
        for node in nodes:
            if isinstance(node, str):
                self.output.append(node)
                continue
            try:
                self.render_tag(node, depth)
            except RenderError as error:
                raise TemplateError(node.number, str(error)) from None

    def render_tag(self, tag, depth):
        match tag.kind:
            case "variable" | "raw":
                text = to_string(self.evaluate(tag.expression, self.strict))
                self.output.append(text if tag.kind == "raw" else text.translate(HTML_ESCAPES))
            case "section":
                self.render_section(tag, depth)
            case "inverted":
                if not self.evaluate(tag.expression, False):
                    self.render(tag.children, depth)
            case "partial":
                self.render_partial(tag, depth)

    def render_section(self, tag, depth):
        value = self.evaluate(tag.expression, False)
        if isinstance(value, list):
            for index, element in enumerate(value):
                self.contexts.append(element)
                self.loops.append((index, len(value)))
                self.render(tag.children, depth)
                self.contexts.pop()
                self.loops.pop()
        elif value:
            self.contexts.append(value)
            self.render(tag.children, depth)
            self.contexts.pop()

    def render_partial(self, tag, depth):
        name = tag.argument
        if name not in self.partials:
            raise RenderError(f"unknown partial '{name}'")
        if depth == MAX_PARTIAL_DEPTH:
            raise RenderError(f"partial depth exceeded at '{name}'")
        source = [
            (number, tag.indentation + text if text else text)
            for number, text in self.partials[name]
        ]
        self.render(parse_source(source), depth + 1)

    def evaluate(self, expression, strict):
        found, value = self.resolve(expression.name)
        if not found and strict:
            raise RenderError(f"missing '{expression.name}'")
        for name, arguments in expression.filters:
            value = apply_filter(name, arguments, value)
        return value

    def resolve(self, name):
        if name == ".":
            return True, self.contexts[-1]
        if name.startswith("@"):
            if not self.loops:
                return False, None
            index, count = self.loops[-1]
            variables = {
                "@index": index,
                "@number": index + 1,
                "@first": index == 0,
                "@last": index == count - 1,
            }
            return True, variables[name]
        parts = [int(part) if part.isdigit() else part for part in name.split(".")]
        for context in reversed(self.contexts):
            if has_part(context, parts[0]):
                value = context
                for part in parts:
                    if not has_part(value, part):
                        return False, None
                    value = value[part]
                return True, value
        return False, None


def read_block(lines, start, marker):
    end = lines.index(marker, start)
    return list(enumerate(lines[start:end], start + 1)), end + 1


class TemplateEngine:
    def __init__(self):
        self.strict = False
        self.reset()

    def reset(self):
        self.root = {}
        self.partials = {}
        self.templates = {}

    def run(self, lines):
        position = 0
        while lines[position] != "END":
            line = lines[position]
            number = position + 1
            command, _, name = line.partition(" ")
            position = number
            if line == "DATA":
                body, position = read_block(lines, position, "ENDDATA")
                self.load_data(body)
            elif command == "PARTIAL":
                body, position = read_block(lines, position, "ENDPARTIAL")
                self.define_partial(name, body)
            elif command == "TEMPLATE":
                body, position = read_block(lines, position, "ENDTEMPLATE")
                self.templates[name] = body
                self.render(name)
            elif command == "RENDER":
                if name in self.templates:
                    self.render(name)
                else:
                    print(f"TEMPLATE {name} ERROR line {number}: unknown template '{name}'")
            elif line == "DUMP":
                self.dump()
            elif command == "STRICT":
                self.strict = name == "ON"
                print(line)
            elif line == "RESET":
                self.reset()
                print("RESET")

    def load_data(self, body):
        assigned = 0
        unset = 0
        errors = []
        for number, line in body:
            if not line or line.startswith("#"):
                continue
            try:
                if line.startswith("UNSET "):
                    self.unset(line[6:])
                    unset += 1
                else:
                    self.assign(line)
                    assigned += 1
            except DataError as error:
                errors.append(f"ERROR line {number}: {error}")
        print(f"DATA set={assigned} unset={unset} errors={len(errors)}")
        for error in errors:
            print(error)

    def assign(self, line):
        key, separator, notation = line.partition(" = ")
        if not separator:
            raise DataError("bad line")
        parts = parse_key(key)
        value = parse_value(notation)
        container = self.root
        detached = None
        for position, (part, prefix) in enumerate(parts):
            if isinstance(part, int) and part > len(container):
                raise DataError(f"index gap at '{prefix}'")
            if position == len(parts) - 1:
                put(container, part, value)
                break
            required = dict if isinstance(parts[position + 1][0], str) else list
            if has_part(container, part):
                child = container[part]
                if not isinstance(child, required):
                    raise DataError(f"type conflict at '{prefix}'")
            else:
                child = required()
                if detached is None:
                    detached = (container, part, child)
                else:
                    put(container, part, child)
            container = child
        if detached is not None:
            put(*detached)

    def unset(self, key):
        parts = parse_key(key)
        parent = target = self.root
        for part, _ in parts:
            if not has_part(target, part):
                raise DataError(f"no value at '{key}'")
            parent, target = target, target[part]
        del parent[part]

    def define_partial(self, name, body):
        try:
            parse_source(body)
        except TemplateError as error:
            print(f"PARTIAL {name} ERROR line {error.number}: {error.reason}")
            return
        status = "REPLACED" if name in self.partials else "DEFINED"
        self.partials[name] = body
        print(f"PARTIAL {name} {status} lines={len(body)}")

    def render(self, name):
        renderer = Renderer(self.root, self.partials, self.strict)
        try:
            renderer.render(parse_source(self.templates[name]), 0)
        except TemplateError as error:
            print(f"TEMPLATE {name} ERROR line {error.number}: {error.reason}")
            return
        result = "".join(renderer.output)
        lines = result.split("\n")
        if lines[-1] == "":
            lines.pop()
        print(f"TEMPLATE {name} OK lines={len(lines)} chars={len(result)}")
        for line in lines:
            print(line)

    def dump(self):
        leaves = []
        for key in sorted(self.root):
            collect_leaves(self.root[key], key, leaves)
        print(f"DUMP leaves={len(leaves)}")
        for leaf in leaves:
            print(leaf)


def main():
    TemplateEngine().run(sys.stdin.read().split("\n"))


if __name__ == "__main__":
    main()
