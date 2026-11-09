import base64
import string
import sys


WIRE_TYPES = {
    "uint32": 0, "uint64": 0, "sint32": 0, "sint64": 0, "bool": 0,
    "fixed32": 5, "sfixed32": 5, "fixed64": 1, "string": 2, "bytes": 2,
}
INTEGER_RANGES = {
    "uint32": (0, 4294967295), "uint64": (0, 9007199254740991),
    "sint32": (-2147483648, 2147483647), "sint64": (-4503599627370496, 4503599627370495),
    "fixed32": (0, 4294967295), "sfixed32": (-2147483648, 2147483647),
    "fixed64": (0, 9007199254740991),
}
ZIGZAG_TYPES = ("sint32", "sint64")
QUOTED_JSON_TYPES = ("uint64", "sint64", "fixed64")
WIRE_NAMES = {0: "varint", 1: "i64", 2: "len", 5: "i32"}
FIXED_SIZES = {1: 8, 5: 4}
VARINT_LIMIT = 9007199254740992
REQUIRED_SHAPES = {
    "integer": "integer", "bool": "boolean", "enum": "name",
    "string": "string", "bytes": "bytes", "message": "message",
}
SYMBOL_SHAPES = {"{": "message", "[": "list"}
SYMBOLS = "{}[]:,"
HEX_DIGITS = "0123456789abcdef"
NAME_START = string.ascii_letters + "_"
NAME_CHARACTERS = string.ascii_letters + string.digits + "_"
LITERAL_ESCAPES = {'"': 0x22, "\\": 0x5C, "n": 0x0A, "t": 0x09}
QUOTE_ESCAPES = {0x22: '\\"', 0x5C: "\\\\", 0x0A: "\\n", 0x09: "\\t"}
WORD_COUNTS = {
    "VARINT": 2, "ZIGZAG": 2, "SCHEMA": 2, "ENCODE": 3, "SIZE": 3,
    "DECODE": 3, "LITERAL": 3, "JSON": 3, "CANON": 3, "EXPLAIN": 3,
    "GET": 4, "PATCH": 5, "CLEAR": 4, "MERGE": 4, "DIFF": 4,
}
TEXT_POSITIONS = {"ENCODE": 2, "SIZE": 2, "PATCH": 4}
NUMBER_RANGES = {"VARINT": (0, 9007199254740991), "ZIGZAG": INTEGER_RANGES["sint64"]}
HEX_ARGUMENTS = {
    "DECODE": 1, "LITERAL": 1, "JSON": 1, "CANON": 1, "EXPLAIN": 1,
    "GET": 1, "PATCH": 1, "CLEAR": 1, "MERGE": 2, "DIFF": 2,
}
PATH_COMMANDS = ("GET", "PATCH", "CLEAR")


class CommandError(Exception):
    pass


def byte_error(reason, offset):
    return CommandError(f"{reason} at byte {offset}")


def column_error(reason, column):
    return CommandError(f"{reason} at column {column}")


def is_hex(text):
    return all(char in HEX_DIGITS for char in text)


def zigzag(value):
    return 2 * value if value >= 0 else -2 * value - 1


def unzigzag(value):
    return value // 2 if value % 2 == 0 else -((value + 1) // 2)


def varint_bytes(value):
    result = bytearray()
    while value >= 128:
        result.append(value % 128 + 128)
        value //= 128
    result.append(value)
    return bytes(result)


def hex_text(data):
    return data.hex() if data else "-"


def quote(data, escape_prefix):
    parts = []
    for byte in data:
        if byte in QUOTE_ESCAPES:
            parts.append(QUOTE_ESCAPES[byte])
        elif 0x20 <= byte <= 0x7E:
            parts.append(chr(byte))
        else:
            parts.append(f"{escape_prefix}{byte:02x}")
    return '"' + "".join(parts) + '"'


def json_key(name):
    parts = name.split("_")
    return parts[0] + "".join(part[0].upper() + part[1:] for part in parts[1:])


def parse_number(text, low, high):
    digits = text[1:] if text.startswith("-") else text
    if len(digits) > 18 or not digits.isdigit() or not low <= int(text) <= high:
        raise CommandError("invalid number")
    return int(text)


def parse_hex(text):
    if text == "-":
        return b""
    if text == "" or len(text) % 2 == 1 or not is_hex(text):
        raise CommandError("invalid hex")
    return bytes.fromhex(text)


class EnumType:
    def __init__(self, name):
        self.name = name
        self.numbers = {}
        self.names = {}

    def add(self, name, number):
        self.numbers[name] = number
        self.names[number] = name


class Field:
    def __init__(self, number, type_name, name, options):
        self.number = number
        self.type_name = type_name
        self.name = name
        self.required = options == ["REQUIRED"]
        self.repeated = options[:1] == ["REPEATED"]
        self.packed = options == ["REPEATED", "PACKED"]
        self.group = options[1] if options[:1] == ["ONEOF"] else None
        self.kind = None
        self.wire_type = None
        self.enum_type = None
        self.message_type = None

    def resolve(self, schema):
        if self.type_name in WIRE_TYPES:
            self.wire_type = WIRE_TYPES[self.type_name]
            self.kind = "integer" if self.type_name in INTEGER_RANGES else self.type_name
        elif self.type_name in schema.enums:
            self.wire_type = 0
            self.kind = "enum"
            self.enum_type = schema.enums[self.type_name]
        else:
            self.wire_type = 2
            self.kind = "message"
            self.message_type = schema.messages[self.type_name]

    def kind_word(self):
        if self.required:
            return "required "
        if self.packed:
            return "repeated packed "
        if self.repeated:
            return "repeated "
        if self.group is not None:
            return f"oneof {self.group} "
        return ""


class MessageType:
    def __init__(self, name):
        self.name = name
        self.fields = []
        self.by_number = {}
        self.by_name = {}

    def add(self, field):
        self.fields.append(field)
        self.by_number[field.number] = field
        self.by_name[field.name] = field


class Schema:
    def __init__(self):
        self.enums = {}
        self.messages = {}


def read_schema(stream):
    schema = Schema()
    current = None
    while True:
        words = stream.readline().rstrip("\n").split(" ")
        if words == ["END", "SCHEMA"]:
            break
        if words[0] == "ENUM":
            current = EnumType(words[1])
            schema.enums[current.name] = current
        elif words[0] == "MESSAGE":
            current = MessageType(words[1])
            schema.messages[current.name] = current
        elif words[0] == "VALUE":
            current.add(words[1], int(words[2]))
        elif words[0] == "FIELD":
            current.add(Field(int(words[1]), words[2], words[3], words[4:]))
    for message_type in schema.messages.values():
        message_type.fields.sort(key=lambda field: field.number)
        for field in message_type.fields:
            field.resolve(schema)
    return schema


class UnknownField:
    def __init__(self, number, wire, raw):
        self.number = number
        self.wire = wire
        self.raw = raw

    def notation(self):
        return str(self.raw) if self.wire == 0 else "<" + self.raw.hex() + ">"

    def encode(self):
        tag = varint_bytes(self.number * 8 + self.wire)
        if self.wire == 0:
            return tag + varint_bytes(self.raw)
        if self.wire == 2:
            return tag + varint_bytes(len(self.raw)) + self.raw
        return tag + self.raw


class Message:
    def __init__(self, message_type):
        self.type = message_type
        self.values = {}
        self.unknown = []

    def has(self, field):
        return field.number in self.values

    def get(self, field):
        return self.values[field.number]

    def items(self, field):
        if field.number not in self.values:
            return []
        if field.repeated:
            return self.values[field.number]
        return [self.values[field.number]]

    def set(self, field, value):
        self.values[field.number] = value

    def set_items(self, field, values):
        if values:
            self.values[field.number] = list(values)
        else:
            self.remove(field)

    def remove(self, field):
        self.values.pop(field.number, None)

    def remove_group(self, field):
        if field.group is None:
            return
        for other in self.type.fields:
            if other.group == field.group and other is not field:
                self.remove(other)

    def present_fields(self):
        return [field for field in self.type.fields if self.has(field)]


def apply_values(message, field, values):
    message.remove_group(field)
    if field.repeated:
        message.set_items(field, message.items(field) + values)
    elif field.kind == "message" and message.has(field):
        merge_message(message.get(field), values[0])
    else:
        message.set(field, values[0])


def merge_message(target, source):
    for field in source.present_fields():
        apply_values(target, field, source.items(field))
    target.unknown.extend(source.unknown)


def check_required(message, prefix):
    for field in message.type.fields:
        if field.required and not message.has(field):
            raise CommandError(f"missing required field {prefix}{field.name}")
        if field.kind == "message":
            for index, value in enumerate(message.items(field)):
                suffix = f"[{index}]" if field.repeated else ""
                check_required(value, f"{prefix}{field.name}{suffix}.")


def element_bytes(field, value):
    if field.wire_type == 2:
        payload = encode_message(value) if field.kind == "message" else value
        return varint_bytes(len(payload)) + payload
    if field.wire_type == 5:
        unsigned = value + 4294967296 if value < 0 else value
        return unsigned.to_bytes(4, "little")
    if field.wire_type == 1:
        return value.to_bytes(8, "little")
    if field.kind == "bool":
        return varint_bytes(1 if value else 0)
    if field.type_name in ZIGZAG_TYPES:
        return varint_bytes(zigzag(value))
    return varint_bytes(value)


def field_records(field, values):
    if field.packed:
        payload = b"".join(element_bytes(field, value) for value in values)
        return varint_bytes(field.number * 8 + 2) + varint_bytes(len(payload)) + payload
    tag = varint_bytes(field.number * 8 + field.wire_type)
    return b"".join(tag + element_bytes(field, value) for value in values)


def encode_message(message):
    parts = [field_records(field, message.items(field)) for field in message.present_fields()]
    for unknown in message.unknown:
        parts.append(unknown.encode())
    return b"".join(parts)


def scalar_value(field, number, position):
    if field.kind == "bool":
        if number > 1:
            raise byte_error("value out of range", position)
        return number == 1
    if field.kind == "enum":
        if number not in field.enum_type.names:
            raise byte_error("unknown enum number", position)
        return number
    value = number
    if field.type_name in ZIGZAG_TYPES:
        value = unzigzag(number)
    elif field.type_name == "sfixed32" and number >= 2147483648:
        value = number - 4294967296
    low, high = INTEGER_RANGES[field.type_name]
    if not low <= value <= high:
        raise byte_error("value out of range", position)
    return value


class Reader:
    def __init__(self, data, explaining):
        self.data = data
        self.explaining = explaining
        self.lines = []

    def note(self, line):
        if self.explaining:
            self.lines.append(line)

    def varint(self, start, end):
        value = 0
        shift = 0
        position = start
        while True:
            if position >= end:
                raise byte_error("truncated varint", start)
            byte = self.data[position]
            value |= (byte & 127) << shift
            shift += 7
            position += 1
            if byte < 128:
                break
            if position - start == 8:
                raise byte_error("varint too long", start)
        if value >= VARINT_LIMIT:
            raise byte_error("varint too large", start)
        return value, position

    def fixed(self, start, end, wire):
        size = FIXED_SIZES[wire]
        if end - start < size:
            raise byte_error(f"truncated {WIRE_NAMES[wire]}", start)
        return self.data[start:start + size], start + size

    def read_message(self, message_type, start, end, depth):
        message = Message(message_type)
        position = start
        while position < end:
            position = self.read_record(message, position, end, depth)
        return message

    def read_record(self, message, start, end, depth):
        tag, position = self.varint(start, end)
        number = tag // 8
        wire = tag % 8
        if number == 0:
            raise byte_error("invalid field number", start)
        if wire not in WIRE_NAMES:
            raise byte_error("invalid wire type", start)
        field = message.type.by_number.get(number)
        packed = field is not None and field.repeated and field.wire_type != 2 and wire == 2
        if field is not None and wire != field.wire_type and not packed:
            raise byte_error("wire type mismatch", start)
        value_start = position
        if wire == 0:
            raw, position = self.varint(position, end)
        elif wire == 2:
            length, value_start = self.varint(position, end)
            if value_start + length > end:
                raise byte_error("length past end", position)
            raw = self.data[value_start:value_start + length]
            position = value_start + length
        else:
            raw, position = self.fixed(position, end, wire)
        name = "?" if field is None else field.name
        header = "  " * depth + f"{start} {number} {name} {WIRE_NAMES[wire]}"
        if wire == 2:
            header += f" {len(raw)}"
        if field is None:
            unknown = UnknownField(number, wire, raw)
            message.unknown.append(unknown)
            self.note(f"{header} {unknown.notation()}")
            return position
        if field.kind == "message":
            self.note(header)
            values = [self.read_message(field.message_type, value_start, position, depth + 1)]
        elif packed:
            values = self.packed_values(field, value_start, position)
            notations = "".join(" " + value_notation(field, value) for value in values)
            self.note(f"{header} packed{notations}")
        else:
            values = [self.convert(field, raw, value_start)]
            self.note(f"{header} {value_notation(field, values[0])}")
        if not self.explaining:
            apply_values(message, field, values)
        return position

    def packed_values(self, field, start, end):
        values = []
        position = start
        while position < end:
            element_start = position
            if field.wire_type == 0:
                number, position = self.varint(position, end)
            else:
                raw, position = self.fixed(position, end, field.wire_type)
                number = int.from_bytes(raw, "little")
            values.append(scalar_value(field, number, element_start))
        return values

    def convert(self, field, raw, position):
        if field.kind == "string":
            for index, byte in enumerate(raw):
                if byte >= 0x80:
                    raise byte_error("invalid string", position + index)
            return raw
        if field.kind == "bytes":
            return raw
        if field.wire_type == 0:
            return scalar_value(field, raw, position)
        return scalar_value(field, int.from_bytes(raw, "little"), position)


def decode(message_type, data):
    reader = Reader(data, False)
    message = reader.read_message(message_type, 0, len(data), 0)
    check_required(message, "")
    return message


def value_notation(field, value):
    if field.kind == "message":
        return message_notation(value)
    if field.kind == "enum":
        return field.enum_type.names[value]
    if field.kind == "bool":
        return "true" if value else "false"
    if field.kind == "string":
        return quote(value, "\\x")
    if field.kind == "bytes":
        return "<" + value.hex() + ">"
    return str(value)


def list_notation(field, values):
    return "[" + ", ".join(value_notation(field, value) for value in values) + "]"


def message_notation(message):
    items = []
    for field in message.present_fields():
        values = message.items(field)
        text = list_notation(field, values) if field.repeated else value_notation(field, values[0])
        items.append(f"{field.name}: {text}")
    return "{" + ", ".join(items) + "}"


def json_value(field, value):
    if field.kind == "message":
        return json_message(value)
    if field.kind == "enum":
        return '"' + field.enum_type.names[value] + '"'
    if field.kind == "bool":
        return "true" if value else "false"
    if field.kind == "string":
        return quote(value, "\\u00")
    if field.kind == "bytes":
        return '"' + base64.b64encode(value).decode("ascii") + '"'
    if field.type_name in QUOTED_JSON_TYPES:
        return f'"{value}"'
    return str(value)


def json_message(message):
    items = []
    for field in message.present_fields():
        values = [json_value(field, value) for value in message.items(field)]
        text = "[" + ",".join(values) + "]" if field.repeated else values[0]
        items.append(f'"{json_key(field.name)}":{text}')
    return "{" + ",".join(items) + "}"


class Token:
    def __init__(self, kind, column, text="", value=None):
        self.kind = kind
        self.column = column
        self.text = text
        self.value = value

    def shape(self):
        if self.kind == "symbol":
            return SYMBOL_SHAPES.get(self.text)
        if self.kind == "name":
            return "boolean" if self.text in ("true", "false") else "name"
        return None if self.kind == "end" else self.kind


def string_token(text, start):
    value = bytearray()
    position = start + 1
    while position < len(text) and text[position] != '"':
        char = text[position]
        escape = text[position + 1:position + 2]
        code = text[position + 2:position + 4]
        if char != "\\":
            value.append(ord(char))
            position += 1
        elif escape in LITERAL_ESCAPES:
            value.append(LITERAL_ESCAPES[escape])
            position += 2
        elif escape == "x" and len(code) == 2 and is_hex(code) and int(code, 16) < 128:
            value.append(int(code, 16))
            position += 4
        else:
            raise column_error("syntax error", start + 1)
    if position >= len(text):
        raise column_error("syntax error", start + 1)
    return Token("string", start + 1, value=bytes(value)), position + 1


def bytes_token(text, start):
    close = text.find(">", start + 1)
    if close < 0:
        raise column_error("syntax error", start + 1)
    digits = text[start + 1:close]
    if len(digits) % 2 == 1 or not is_hex(digits):
        raise column_error("syntax error", start + 1)
    return Token("bytes", start + 1, value=bytes.fromhex(digits)), close + 1


def integer_token(text, start):
    digits_start = start + 1 if text[start] == "-" else start
    end = digits_start
    while end < len(text) and text[end] in string.digits:
        end += 1
    if end == digits_start:
        raise column_error("syntax error", start + 1)
    return Token("integer", start + 1, value=int(text[start:end])), end


def name_token(text, start):
    end = start + 1
    while end < len(text) and text[end] in NAME_CHARACTERS:
        end += 1
    return Token("name", start + 1, text[start:end]), end


def read_token(text, start):
    char = text[start]
    if char in SYMBOLS:
        return Token("symbol", start + 1, char), start + 1
    if char == '"':
        return string_token(text, start)
    if char == "<":
        return bytes_token(text, start)
    if char == "-" or char in string.digits:
        return integer_token(text, start)
    if char in NAME_START:
        return name_token(text, start)
    raise column_error("syntax error", start + 1)


def tokenize(text):
    tokens = []
    position = 0
    while position < len(text):
        if text[position] == " ":
            position += 1
        else:
            token, position = read_token(text, position)
            tokens.append(token)
    tokens.append(Token("end", len(text) + 1))
    return tokens


class LiteralParser:
    def __init__(self, text):
        self.tokens = tokenize(text)
        self.index = 0

    def peek(self):
        return self.tokens[self.index]

    def take(self):
        token = self.tokens[self.index]
        self.index += 1
        return token

    def at_symbol(self, symbol):
        token = self.peek()
        return token.kind == "symbol" and token.text == symbol

    def fail(self, reason):
        return column_error(reason, self.peek().column)

    def expect(self, symbol):
        if not self.at_symbol(symbol):
            raise self.fail("syntax error")
        return self.take()

    def finish(self):
        if self.peek().kind != "end":
            raise self.fail("syntax error")

    def message(self, message_type):
        self.expect("{")
        message = Message(message_type)
        seen = []
        if not self.at_symbol("}"):
            self.field(message, seen)
            while self.at_symbol(","):
                self.take()
                self.field(message, seen)
        closing = self.expect("}")
        for field in message_type.fields:
            if field.required and field not in seen:
                raise column_error(f"missing required field {field.name}", closing.column)
        return message

    def field(self, message, seen):
        token = self.peek()
        if token.kind != "name":
            raise self.fail("syntax error")
        field = message.type.by_name.get(token.text)
        if field is None:
            raise self.fail("unknown field")
        if field in seen:
            raise self.fail("duplicate field")
        if field.group is not None and any(other.group == field.group for other in seen):
            raise self.fail("oneof conflict")
        self.take()
        seen.append(field)
        self.expect(":")
        if field.repeated:
            message.set_items(field, self.list_value(field))
        else:
            message.set(field, self.element(field))

    def list_value(self, field):
        shape = self.peek().shape()
        if shape is None:
            raise self.fail("syntax error")
        if shape != "list":
            raise self.fail("type mismatch")
        self.take()
        values = []
        if not self.at_symbol("]"):
            values.append(self.element(field))
            while self.at_symbol(","):
                self.take()
                values.append(self.element(field))
        self.expect("]")
        return values

    def element(self, field):
        token = self.peek()
        shape = token.shape()
        if shape is None:
            raise self.fail("syntax error")
        if shape != REQUIRED_SHAPES[field.kind]:
            raise self.fail("type mismatch")
        if shape == "message":
            return self.message(field.message_type)
        self.take()
        if shape == "integer":
            low, high = INTEGER_RANGES[field.type_name]
            if not low <= token.value <= high:
                raise column_error("out of range", token.column)
            return token.value
        if shape == "boolean":
            return token.text == "true"
        if shape == "name":
            if token.text not in field.enum_type.numbers:
                raise column_error("unknown enum value", token.column)
            return field.enum_type.numbers[token.text]
        return token.value


class PathSegment:
    def __init__(self, field, index):
        self.field = field
        self.index = index

    def position(self):
        return 0 if self.index is None else self.index

    def whole(self):
        return self.field.repeated and self.index is None


def parse_path(message_type, text):
    parts = text.split(".")
    segments = []
    current = message_type
    for position, part in enumerate(parts):
        name = part
        index = None
        bracket = part.find("[")
        if bracket >= 0:
            name = part[:bracket]
            digits = part[bracket + 1:-1]
            if not part.endswith("]") or len(digits) > 6 or not digits.isdigit():
                return None
            index = int(digits)
        field = current.by_name.get(name)
        if field is None or (index is not None and not field.repeated):
            return None
        segments.append(PathSegment(field, index))
        if position < len(parts) - 1:
            if field.kind != "message" or (field.repeated and index is None):
                return None
            current = field.message_type
    return segments


def follow(message, segments):
    for segment in segments:
        values = message.items(segment.field)
        if segment.position() >= len(values):
            return None
        message = values[segment.position()]
    return message


def patch_child(message, segment):
    field = segment.field
    if field.repeated:
        values = message.items(field)
        if segment.index >= len(values):
            raise CommandError("index out of range")
        return values[segment.index]
    if not message.has(field):
        message.remove_group(field)
        message.set(field, Message(field.message_type))
    return message.get(field)


class Request:
    def __init__(self, message_type):
        self.message_type = message_type
        self.data = []
        self.path = None
        self.text = None


class Codec:
    def __init__(self, schema):
        self.schema = schema
        self.output = []
        self.number_handlers = {"VARINT": self.varint, "ZIGZAG": self.zigzag}
        self.handlers = {
            "SCHEMA": self.show_schema, "ENCODE": self.encode, "SIZE": self.size,
            "DECODE": self.decode_text, "LITERAL": self.literal, "JSON": self.json,
            "CANON": self.canon, "EXPLAIN": self.explain, "GET": self.get,
            "PATCH": self.patch, "CLEAR": self.clear, "MERGE": self.merge, "DIFF": self.diff,
        }

    def emit(self, line):
        self.output.append(line)

    def request(self, line, words):
        command = words[0]
        message_type = self.schema.messages.get(words[1])
        if message_type is None:
            raise CommandError("unknown message type")
        request = Request(message_type)
        request.data = [parse_hex(word) for word in words[2:2 + HEX_ARGUMENTS.get(command, 0)]]
        if command in PATH_COMMANDS:
            request.path = parse_path(message_type, words[3])
            if request.path is None:
                raise CommandError("invalid path")
        if command in TEXT_POSITIONS:
            request.text = line.split(" ", TEXT_POSITIONS[command])[-1]
        return request

    def execute(self, line):
        words = line.split(" ")
        command = words[0]
        try:
            if command not in WORD_COUNTS:
                raise CommandError("unknown command")
            expected = WORD_COUNTS[command]
            if len(words) < expected or (len(words) > expected and command not in TEXT_POSITIONS):
                raise CommandError("wrong number of arguments")
            if command in NUMBER_RANGES:
                low, high = NUMBER_RANGES[command]
                self.number_handlers[command](parse_number(words[1], low, high))
            else:
                self.handlers[command](self.request(line, words))
        except CommandError as error:
            self.emit(f"ERROR {error}")

    def varint(self, number):
        self.emit(varint_bytes(number).hex())

    def zigzag(self, number):
        value = zigzag(number)
        self.emit(f"{value} {varint_bytes(value).hex()}")

    def show_schema(self, request):
        message_type = request.message_type
        self.emit(message_type.name)
        self.schema_fields(message_type, [message_type], 1)

    def schema_fields(self, message_type, chain, depth):
        for field in message_type.fields:
            line = "  " * depth + f"{field.number} {field.name}: {field.kind_word()}{field.type_name}"
            if field.enum_type is not None:
                names = field.enum_type.names
                line += " (" + ", ".join(f"{names[number]}={number}" for number in sorted(names)) + ")"
            nested = field.message_type
            if nested is not None and nested in chain:
                self.emit(line + " (recursive)")
                continue
            self.emit(line)
            if nested is not None:
                self.schema_fields(nested, chain + [nested], depth + 1)

    def literal_message(self, request):
        parser = LiteralParser(request.text)
        message = parser.message(request.message_type)
        parser.finish()
        return message

    def encode(self, request):
        self.emit(hex_text(encode_message(self.literal_message(request))))

    def size(self, request):
        message = self.literal_message(request)
        parts = [str(len(encode_message(message)))]
        for field in message.present_fields():
            parts.append(f"{field.name}={len(field_records(field, message.items(field)))}")
        self.emit(" ".join(parts))

    def emit_text(self, message):
        self.emit(message.type.name + " {")
        self.text_contents(message, 1)
        self.emit("}")

    def text_contents(self, message, depth):
        indent = "  " * depth
        for field in message.present_fields():
            for value in message.items(field):
                if field.kind == "message":
                    self.emit(f"{indent}{field.name} {{")
                    self.text_contents(value, depth + 1)
                    self.emit(indent + "}")
                else:
                    self.emit(f"{indent}{field.name}: {value_notation(field, value)}")
        for unknown in message.unknown:
            self.emit(f"{indent}{unknown.number}: {WIRE_NAMES[unknown.wire]} {unknown.notation()}")

    def decode_text(self, request):
        self.emit_text(decode(request.message_type, request.data[0]))

    def literal(self, request):
        self.emit(message_notation(decode(request.message_type, request.data[0])))

    def json(self, request):
        self.emit(json_message(decode(request.message_type, request.data[0])))

    def canon(self, request):
        self.emit(hex_text(encode_message(decode(request.message_type, request.data[0]))))

    def explain(self, request):
        data = request.data[0]
        if not data:
            self.emit("(empty)")
            return
        reader = Reader(data, True)
        reader.read_message(request.message_type, 0, len(data), 0)
        self.output.extend(reader.lines)

    def get(self, request):
        message = decode(request.message_type, request.data[0])
        last = request.path[-1]
        target = follow(message, request.path[:-1])
        values = [] if target is None else target.items(last.field)
        if last.whole():
            self.emit(list_notation(last.field, values))
        elif last.position() < len(values):
            self.emit(value_notation(last.field, values[last.position()]))
        else:
            self.emit("(none)")

    def patch(self, request):
        message = decode(request.message_type, request.data[0])
        last = request.path[-1]
        field = last.field
        parser = LiteralParser(request.text)
        value = parser.list_value(field) if last.whole() else parser.element(field)
        parser.finish()
        target = message
        for segment in request.path[:-1]:
            target = patch_child(target, segment)
        if last.whole():
            target.set_items(field, value)
        elif field.repeated:
            values = target.items(field)
            if last.index >= len(values):
                raise CommandError("index out of range")
            target.set_items(field, values[:last.index] + [value] + values[last.index + 1:])
        else:
            target.remove_group(field)
            target.set(field, value)
        check_required(message, "")
        self.emit(hex_text(encode_message(message)))

    def clear(self, request):
        message = decode(request.message_type, request.data[0])
        last = request.path[-1]
        target = follow(message, request.path[:-1])
        if target is not None and last.index is None:
            target.remove(last.field)
        elif target is not None:
            values = target.items(last.field)
            if last.index < len(values):
                target.set_items(last.field, values[:last.index] + values[last.index + 1:])
        check_required(message, "")
        self.emit(hex_text(encode_message(message)))

    def merge(self, request):
        self.emit_text(decode(request.message_type, request.data[0] + request.data[1]))

    def diff(self, request):
        messages = []
        for data, label in zip(request.data, ("first", "second")):
            try:
                messages.append(decode(request.message_type, data))
            except CommandError as error:
                raise CommandError(f"{error} in {label}")
        lines = []
        self.compare(messages[0], messages[1], "", lines)
        self.output.extend(lines or ["SAME"])

    def compare(self, first, second, prefix, lines):
        for field in first.type.fields:
            left = first.items(field)
            right = second.items(field)
            for index in range(max(len(left), len(right))):
                path = prefix + field.name + (f"[{index}]" if field.repeated else "")
                both = index < len(left) and index < len(right)
                if both and field.kind == "message":
                    self.compare(left[index], right[index], path + ".", lines)
                elif not both or left[index] != right[index]:
                    old = value_notation(field, left[index]) if index < len(left) else "(none)"
                    new = value_notation(field, right[index]) if index < len(right) else "(none)"
                    lines.append(f"{path}: {old} -> {new}")


def main():
    schema = read_schema(sys.stdin)
    codec = Codec(schema)
    count = int(sys.stdin.readline())
    for _ in range(count):
        codec.execute(sys.stdin.readline().rstrip("\n"))
    sys.stdout.write("\n".join(codec.output) + "\n")


if __name__ == "__main__":
    main()
