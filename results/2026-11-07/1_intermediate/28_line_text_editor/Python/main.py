import string
import sys


MAX_LINES = 200
MAX_LINE_LENGTH = 80
WRAP_WIDTH = 40
DEFAULT_DISPLAY_COUNT = 5
DEFAULT_SHIFT = 4
BASE_KINDS = ("number", ".", "$", "mark", "forward", "backward")
FORMS = ("p", "n", "l")
TEXT_COMMANDS = ("a", "i", "c")
PLAIN_COMMANDS = ("", "a", "i", "c", "p", "n", "l", "=", "#", "y", "K", "h", "f", "w")
SUFFIX_COMMANDS = ("d", "x", "j", "J")
COUNT_COMMANDS = ("z", ">", "<", "u", "redo")
FILE_COMMANDS = ("read", "write", "W", "e")
NO_ADDRESS_COMMANDS = ("u", "redo", "h", "K", "f", "e")
ONE_ADDRESS_COMMANDS = ("a", "i", "x", "=", "read", "k", "z")
WHOLE_BUFFER_COMMANDS = ("w", "write", "W", "#")
MODIFYING_COMMANDS = (
    "a", "i", "c", "d", "x", "j", "J", "m", "t", "s", ">", "<", "~", "sort", "read", "e",
)
GLOBAL_SUBCOMMANDS = (
    "p", "n", "l", "d", "m", "t", "j", "J", "s", ">", "<", "~", "a", "i", "c", "x",
)
SORT_OPTIONS = "ruin"
FLAG_CHARACTERS = "gpnl" + string.digits
FILE_NAME_CHARACTERS = string.ascii_lowercase + string.digits


class EditorError(Exception):
    pass


class Element:
    def __init__(self, kind, value=0, text=""):
        self.kind = kind
        self.value = value
        self.text = text


class Addresses:
    def __init__(self, count, left=(), separator="", right=()):
        self.count = count
        self.left = left
        self.separator = separator
        self.right = right


class Command:
    def __init__(self, name):
        self.name = name
        self.suffix = ""
        self.number = None
        self.options = ""
        self.file_name = ""
        self.mark = ""
        self.destination = []
        self.search = ""
        self.replacement = None
        self.every = False
        self.count = 1
        self.subcommand = None

    def is_modifying(self):
        if self.name in ("g", "v"):
            return self.subcommand.name not in FORMS
        return self.name in MODIFYING_COMMANDS


class Line:
    def __init__(self, identity, text):
        self.identity = identity
        self.text = text


class Record:
    def __init__(self, command, lines, current):
        self.command = command
        self.lines = lines
        self.current = current


def read_delimited(text, start, delimiter):
    pieces = [""]
    position = start
    while position < len(text) and text[position] != delimiter:
        char = text[position]
        if char == "\\":
            if position + 1 == len(text):
                raise EditorError("missing delimiter")
            pieces[-1] += text[position + 1]
            position += 2
        elif char == "&":
            pieces.append("")
            position += 1
        else:
            pieces[-1] += char
            position += 1
    if position == len(text):
        raise EditorError("missing delimiter")
    return pieces, position + 1


def digits_end(text, start):
    end = start
    while end < len(text) and text[end].isdigit():
        end += 1
    return end


def scan_elements(text):
    elements = []
    position = 0
    while position < len(text):
        char = text[position]
        if char.isdigit():
            end = digits_end(text, position)
            elements.append(Element("number", int(text[position:end])))
        elif char in "+-":
            end = digits_end(text, position + 1)
            amount = int(text[position + 1:end]) if end > position + 1 else 1
            elements.append(Element("offset", amount if char == "+" else -amount))
        elif char in ".$%":
            end = position + 1
            elements.append(Element(char))
        elif char in ",;":
            end = position + 1
            elements.append(Element("separator", text=char))
        elif char == "'":
            end = min(position + 2, len(text))
            elements.append(Element("mark", text=text[position + 1:end]))
        elif char in "/?":
            pieces, end = read_delimited(text, position + 1, char)
            kind = "forward" if char == "/" else "backward"
            elements.append(Element(kind, text="&".join(pieces)))
        else:
            break
        position = end
    return elements, position


def is_single_address(elements):
    if not elements:
        return False
    offsets = elements[1:] if elements[0].kind in BASE_KINDS else elements
    return all(element.kind == "offset" for element in offsets)


def address_form(elements):
    if not elements:
        return Addresses(0)
    if len(elements) == 1 and elements[0].kind == "%":
        return Addresses(2, [Element("number", 1)], ",", [Element("$")])
    separators = [index for index, element in enumerate(elements) if element.kind == "separator"]
    if len(separators) > 1:
        raise EditorError("bad address")
    if not separators:
        if not is_single_address(elements):
            raise EditorError("bad address")
        return Addresses(1, elements)
    index = separators[0]
    left, right = elements[:index], elements[index + 1:]
    if (left and not is_single_address(left)) or (right and not is_single_address(right)):
        raise EditorError("bad address")
    return Addresses(2, left, elements[index].text, right)


def is_sort_form(text):
    return text == "sort" or text.startswith("sort ")


def print_suffix(argument):
    if argument not in ("", "p", "n", "l"):
        raise EditorError("invalid suffix")
    return argument


def count_argument(argument):
    if argument == "":
        return None
    if not argument.isdigit() or int(argument) == 0:
        raise EditorError("invalid suffix")
    return int(argument)


def file_name(argument):
    name = argument[1:]
    if (not argument.startswith(" ") or not 1 <= len(name) <= 8
            or any(char not in FILE_NAME_CHARACTERS for char in name)):
        raise EditorError("invalid file name")
    return name


def parse_sort(text):
    command = Command("sort")
    if text.startswith("sort "):
        options = text[5:]
        if (not options or any(option not in SORT_OPTIONS for option in options)
                or len(set(options)) != len(options) or ("i" in options and "n" in options)):
            raise EditorError("invalid suffix")
        command.options = options
    return command


def parse_transfer(command, argument):
    elements, position = scan_elements(argument)
    if not is_single_address(elements):
        raise EditorError("invalid destination")
    command.destination = elements
    command.suffix = print_suffix(argument[position:])


def parse_flags(command, flags):
    has_count = False
    position = 0
    while position < len(flags):
        char = flags[position]
        if char == "g" and not command.every:
            command.every = True
            position += 1
        elif char in FORMS and not command.suffix:
            command.suffix = char
            position += 1
        elif char.isdigit() and not has_count:
            end = digits_end(flags, position)
            command.count = int(flags[position:end])
            if command.count == 0:
                raise EditorError("invalid suffix")
            has_count = True
            position = end
        else:
            raise EditorError("invalid suffix")


def parse_substitute(command, argument):
    if all(char in FLAG_CHARACTERS for char in argument):
        flags = argument
    else:
        delimiter = argument[0]
        if delimiter in (" ", "\\"):
            raise EditorError("missing delimiter")
        pieces, middle = read_delimited(argument, 1, delimiter)
        replacement, end = read_delimited(argument, middle, delimiter)
        command.search = "&".join(pieces)
        if argument[middle:end - 1] != "%":
            command.replacement = replacement
        flags = argument[end:]
    parse_flags(command, flags)


def parse_global(command, argument):
    if argument == "" or argument[0] in (" ", "\\"):
        raise EditorError("missing delimiter")
    pieces, end = read_delimited(argument, 1, argument[0])
    command.search = "&".join(pieces)
    text = argument[end:] or "p"
    if text[0] not in GLOBAL_SUBCOMMANDS or is_sort_form(text):
        raise EditorError("invalid global command")
    command.subcommand = parse_command(text)


def parse_command(text):
    if is_sort_form(text):
        return parse_sort(text)
    name, argument = text[:1], text[1:]
    if name == "r":
        name = "redo" if argument == "" or argument.isdigit() else "read"
    elif name == "w" and argument:
        name = "write"
    command = Command(name)
    if name in PLAIN_COMMANDS:
        if argument:
            raise EditorError("invalid suffix")
    elif name in SUFFIX_COMMANDS:
        command.suffix = print_suffix(argument)
    elif name in COUNT_COMMANDS:
        command.number = count_argument(argument)
    elif name == "~":
        if argument not in ("", "u", "l"):
            raise EditorError("invalid suffix")
        command.options = argument
    elif name in FILE_COMMANDS:
        command.file_name = file_name(argument)
    elif name == "k":
        if len(argument) != 1 or argument not in string.ascii_lowercase:
            raise EditorError("invalid mark")
        command.mark = argument
    elif name in ("m", "t"):
        parse_transfer(command, argument)
    elif name == "s":
        parse_substitute(command, argument)
    elif name in ("g", "v"):
        parse_global(command, argument)
    else:
        raise EditorError("unknown command")
    return command


def has_text(line):
    try:
        _, position = scan_elements(line)
        command = line[position:]
        if command in TEXT_COMMANDS:
            return True
        if len(command) < 2 or command[0] not in ("g", "v") or command[1] in (" ", "\\"):
            return False
        _, end = read_delimited(command, 2, command[1])
    except EditorError:
        return False
    return command[end:] in TEXT_COMMANDS


def read_commands(lines):
    commands = []
    index = 0
    while index < len(lines) and lines[index] != "Q":
        line = lines[index]
        index += 1
        text = []
        if has_text(line):
            while index < len(lines) and lines[index] != ".":
                text.append(lines[index])
                index += 1
            index += 1
        commands.append((line, text))
    return commands


def byte_count(texts):
    return sum(len(text) + 1 for text in texts)


def leading_integer(text):
    sign = 1
    start = 0
    if text.startswith("-"):
        sign = -1
        start = 1
    end = digits_end(text, start)
    if end == start:
        return 0
    return sign * int(text[start:end])


def sort_key(text, options):
    if "n" in options:
        return leading_integer(text)
    if "i" in options:
        return text.lower()
    return text


def substitute_text(text, pattern, replacement, count, every):
    result = ""
    position = 0
    found = 0
    index = text.find(pattern)
    while index >= 0:
        found += 1
        if found >= count:
            result += text[position:index] + replacement
        else:
            result += text[position:index + len(pattern)]
        position = index + len(pattern)
        if found >= count and not every:
            break
        index = text.find(pattern, position)
    if found < count:
        return None
    return result + text[position:]


class Editor:
    def __init__(self):
        self.lines = []
        self.current = 0
        self.marks = {}
        self.cut = []
        self.pattern = None
        self.replacement = None
        self.display_count = DEFAULT_DISPLAY_COUNT
        self.undo_history = []
        self.redo_history = []
        self.files = {}
        self.next_identity = 1
        self.output = []

    def copy(self):
        other = Editor()
        other.lines = list(self.lines)
        other.current = self.current
        other.marks = dict(self.marks)
        other.cut = list(self.cut)
        other.pattern = self.pattern
        other.replacement = self.replacement
        other.display_count = self.display_count
        other.undo_history = list(self.undo_history)
        other.redo_history = list(self.redo_history)
        other.files = dict(self.files)
        other.next_identity = self.next_identity
        return other

    def emit(self, text):
        self.output.append(text)

    def new_lines(self, texts):
        lines = []
        for text in texts:
            lines.append(Line(self.next_identity, text))
            self.next_identity += 1
        return lines

    def insert(self, after, texts):
        self.lines[after:after] = self.new_lines(texts)

    def texts(self, first, last):
        return [line.text for line in self.lines[first - 1:last]]

    def set_text(self, number, text):
        self.lines[number - 1] = Line(self.lines[number - 1].identity, text)

    def line_number(self, identity):
        for index, line in enumerate(self.lines):
            if line.identity == identity:
                return index + 1
        return 0

    def show(self, number, form):
        text = self.lines[number - 1].text
        if form == "p":
            self.emit(text)
        elif form == "n":
            self.emit(f"{number:3d} {text}")
        else:
            rest = text.replace("\\", "\\\\") + "$"
            while len(rest) > WRAP_WIDTH:
                self.emit(rest[:WRAP_WIDTH - 1] + "\\")
                rest = rest[WRAP_WIDTH - 1:]
            self.emit(rest)

    def show_suffix(self, suffix):
        if suffix and self.current >= 1:
            self.show(self.current, suffix)

    def use_pattern(self, text):
        if text:
            self.pattern = text
        elif self.pattern is None:
            raise EditorError("no previous pattern")
        return self.pattern

    def search(self, text, forward):
        pattern = self.use_pattern(text)
        total = len(self.lines)
        if forward:
            order = list(range(self.current + 1, total + 1)) + list(range(1, self.current + 1))
        else:
            order = list(range(self.current - 1, 0, -1)) + list(range(total, self.current - 1, -1))
        for number in order:
            if number >= 1 and pattern in self.lines[number - 1].text:
                return number
        raise EditorError("no match")

    def mark_line(self, name):
        if len(name) != 1 or name not in string.ascii_lowercase:
            raise EditorError("invalid mark")
        number = self.line_number(self.marks[name]) if name in self.marks else 0
        if number == 0:
            raise EditorError("mark not set")
        return number

    def base_value(self, element):
        if element.kind == "number":
            return element.value
        if element.kind == ".":
            return self.current
        if element.kind == "$":
            return len(self.lines)
        if element.kind == "mark":
            return self.mark_line(element.text)
        return self.search(element.text, element.kind == "forward")

    def address_value(self, elements):
        value = self.current
        offsets = elements
        if elements[0].kind in BASE_KINDS:
            value = self.base_value(elements[0])
            offsets = elements[1:]
        for element in offsets:
            value += element.value
        return value

    def address_values(self, addresses):
        if addresses.count == 0:
            return []
        if addresses.count == 1:
            return [self.address_value(addresses.left)]
        if addresses.left:
            left = self.address_value(addresses.left)
        elif addresses.separator == ",":
            left = 1
        else:
            left = self.current
        if addresses.separator == ";":
            if not 0 <= left <= len(self.lines):
                raise EditorError("address out of range")
            self.current = left
        right = self.address_value(addresses.right) if addresses.right else len(self.lines)
        return [left, right]

    def command_range(self, command, values):
        name = command.name
        total = len(self.lines)
        if name in NO_ADDRESS_COMMANDS:
            return 0, 0
        if name in ONE_ADDRESS_COMMANDS:
            if values:
                value = values[0]
            elif name in ("=", "read"):
                value = total
            elif name == "z":
                value = self.current + 1
            else:
                value = self.current
            lowest = 1 if name in ("k", "z") else 0
            if not lowest <= value <= total:
                raise EditorError("address out of range")
            return value, value
        if values:
            first, last = values[0], values[-1]
        elif name in ("g", "v", "sort"):
            first, last = 1, total
        elif name in WHOLE_BUFFER_COMMANDS:
            return 1, total
        elif name in ("j", "J"):
            first, last = self.current, self.current + 1
        else:
            first, last = self.current, self.current
        if not (1 <= first <= total and 1 <= last <= total):
            raise EditorError("address out of range")
        if first > last or (first == last and name in ("j", "J")):
            raise EditorError("invalid range")
        return first, last

    def process(self, line, text):
        before = Record(line, list(self.lines), self.current)
        elements, position = scan_elements(line)
        addresses = address_form(elements)
        command = parse_command(line[position:])
        if command.name in NO_ADDRESS_COMMANDS and addresses.count > 0:
            raise EditorError("unexpected address")
        if command.name in ONE_ADDRESS_COMMANDS and addresses.count == 2:
            raise EditorError("too many addresses")
        values = self.address_values(addresses)
        first, last = self.command_range(command, values)
        self.run(command, first, last, text)
        if len(self.lines) > MAX_LINES:
            raise EditorError("buffer full")
        if command.is_modifying():
            self.undo_history.append(before)
            self.redo_history = []

    def run(self, command, first, last, text):
        handlers = {
            "": self.show_last,
            "p": self.print_lines,
            "n": self.print_lines,
            "l": self.print_lines,
            "z": self.scroll,
            "=": self.print_address,
            "#": self.count_range,
            "w": self.print_buffer,
            "a": self.append_text,
            "i": self.insert_text,
            "c": self.change_text,
            "d": self.delete_lines,
            "y": self.yank_lines,
            "x": self.put_lines,
            "m": self.move_lines,
            "t": self.copy_lines,
            "j": self.join_lines,
            "J": self.join_lines,
            ">": self.indent_lines,
            "<": self.unindent_lines,
            "~": self.convert_case,
            "sort": self.sort_lines,
            "s": self.substitute,
            "k": self.set_mark,
            "K": self.list_marks,
            "u": self.undo,
            "redo": self.redo,
            "h": self.show_history,
            "g": self.global_command,
            "v": self.global_command,
            "write": self.write_file,
            "W": self.append_file,
            "read": self.read_file,
            "e": self.edit_file,
            "f": self.list_files,
        }
        handlers[command.name](command, first, last, text)

    def show_last(self, command, first, last, text):
        self.show(last, "p")
        self.current = last

    def print_lines(self, command, first, last, text):
        for number in range(first, last + 1):
            self.show(number, command.name)
        self.current = last

    def scroll(self, command, first, last, text):
        if command.number is not None:
            self.display_count = command.number
        end = min(first + self.display_count - 1, len(self.lines))
        for number in range(first, end + 1):
            self.show(number, "p")
        self.current = end

    def print_address(self, command, first, last, text):
        self.emit(str(first))

    def count_range(self, command, first, last, text):
        texts = self.texts(first, last)
        words = sum(len(line.split()) for line in texts)
        chars = sum(len(line) for line in texts)
        self.emit(f"count lines={len(texts)} words={words} chars={chars}")

    def print_buffer(self, command, first, last, text):
        texts = self.texts(first, last)
        for line in texts:
            self.emit(line)
        self.emit(f"lines={len(texts)} bytes={byte_count(texts)}")

    def append_text(self, command, first, last, text):
        self.insert(first, text)
        self.current = first + len(text)

    def insert_text(self, command, first, last, text):
        after = max(first, 1) - 1
        self.insert(after, text)
        self.current = after + len(text)

    def remove_range(self, first, last):
        self.cut = self.texts(first, last)
        del self.lines[first - 1:last]
        self.current = first if first <= len(self.lines) else len(self.lines)

    def change_text(self, command, first, last, text):
        self.remove_range(first, last)
        self.insert(first - 1, text)
        if text:
            self.current = first + len(text) - 1

    def delete_lines(self, command, first, last, text):
        self.remove_range(first, last)
        self.show_suffix(command.suffix)

    def yank_lines(self, command, first, last, text):
        self.cut = self.texts(first, last)

    def put_lines(self, command, first, last, text):
        if not self.cut:
            raise EditorError("nothing to put")
        self.insert(first, self.cut)
        self.current = first + len(self.cut)
        self.show_suffix(command.suffix)

    def destination(self, command):
        target = self.address_value(command.destination)
        if not 0 <= target <= len(self.lines):
            raise EditorError("address out of range")
        return target

    def move_lines(self, command, first, last, text):
        target = self.destination(command)
        if first <= target < last:
            raise EditorError("invalid destination")
        block = self.lines[first - 1:last]
        del self.lines[first - 1:last]
        after = target if target < first else target - len(block)
        self.lines[after:after] = block
        self.current = after + len(block)
        self.show_suffix(command.suffix)

    def copy_lines(self, command, first, last, text):
        target = self.destination(command)
        self.insert(target, self.texts(first, last))
        self.current = target + last - first + 1
        self.show_suffix(command.suffix)

    def join_lines(self, command, first, last, text):
        texts = self.texts(first, last)
        if command.name == "J":
            joined = " ".join([texts[0]] + [line.lstrip(" ") for line in texts[1:]])
        else:
            joined = "".join(texts)
        if len(joined) > MAX_LINE_LENGTH:
            raise EditorError("line too long")
        self.set_text(first, joined)
        del self.lines[first:last]
        self.current = first
        self.show_suffix(command.suffix)

    def shift_width(self, command):
        return DEFAULT_SHIFT if command.number is None else command.number

    def indent_lines(self, command, first, last, text):
        width = self.shift_width(command)
        for number in range(first, last + 1):
            shifted = " " * width + self.lines[number - 1].text
            if len(shifted) > MAX_LINE_LENGTH:
                raise EditorError("line too long")
            self.set_text(number, shifted)
        self.current = last

    def unindent_lines(self, command, first, last, text):
        width = self.shift_width(command)
        for number in range(first, last + 1):
            line = self.lines[number - 1].text
            spaces = len(line) - len(line.lstrip(" "))
            self.set_text(number, line[min(width, spaces):])
        self.current = last

    def convert_case(self, command, first, last, text):
        for number in range(first, last + 1):
            line = self.lines[number - 1].text
            if command.options == "u":
                line = line.upper()
            elif command.options == "l":
                line = line.lower()
            else:
                line = line.swapcase()
            self.set_text(number, line)
        self.current = last

    def sort_lines(self, command, first, last, text):
        options = command.options
        block = self.lines[first - 1:last]
        block.sort(key=lambda line: sort_key(line.text, options), reverse="r" in options)
        if "u" in options:
            kept = []
            for line in block:
                if not kept or sort_key(line.text, options) != sort_key(kept[-1].text, options):
                    kept.append(line)
            block = kept
        self.lines[first - 1:last] = block
        self.current = first + len(block) - 1

    def substitute_lines(self, command, first, last):
        pattern = self.use_pattern(command.search)
        if command.replacement is not None:
            self.replacement = command.replacement
        elif self.replacement is None:
            raise EditorError("no previous substitution")
        replacement = pattern.join(self.replacement)
        substituted = 0
        for number in range(first, last + 1):
            result = substitute_text(
                self.lines[number - 1].text, pattern, replacement, command.count, command.every
            )
            if result is None:
                continue
            if len(result) > MAX_LINE_LENGTH:
                raise EditorError("line too long")
            if result == "" or result.endswith(" "):
                raise EditorError("bad line")
            self.set_text(number, result)
            self.current = number
            substituted += 1
        if substituted:
            self.show_suffix(command.suffix)
        return substituted

    def substitute(self, command, first, last, text):
        if self.substitute_lines(command, first, last) == 0:
            raise EditorError("no match")

    def set_mark(self, command, first, last, text):
        self.marks[command.mark] = self.lines[first - 1].identity

    def list_marks(self, command, first, last, text):
        entries = []
        for name in string.ascii_lowercase:
            number = self.line_number(self.marks[name]) if name in self.marks else 0
            if number:
                entries.append(f"{name}={number}")
        self.emit("marks " + (" ".join(entries) if entries else "none"))

    def travel(self, command, source, target, message):
        steps = 1 if command.number is None else command.number
        if len(source) < steps:
            raise EditorError(message)
        for _ in range(steps):
            record = source.pop()
            target.append(Record(record.command, list(self.lines), self.current))
            self.lines = list(record.lines)
            self.current = record.current

    def undo(self, command, first, last, text):
        self.travel(command, self.undo_history, self.redo_history, "nothing to undo")

    def redo(self, command, first, last, text):
        self.travel(command, self.redo_history, self.undo_history, "nothing to redo")

    def show_history(self, command, first, last, text):
        self.emit(f"history undo={len(self.undo_history)} redo={len(self.redo_history)}")
        for kind, history in (("undo", self.undo_history), ("redo", self.redo_history)):
            for number, record in enumerate(reversed(history), 1):
                self.emit(f"{kind} {number}: {record.command}")

    def global_command(self, command, first, last, text):
        pattern = self.use_pattern(command.search)
        wanted = command.name == "g"
        selected = [
            line.identity for line in self.lines[first - 1:last]
            if (pattern in line.text) == wanted
        ]
        if not selected:
            raise EditorError("no match")
        subcommand = command.subcommand
        substituted = 0
        for identity in selected:
            number = self.line_number(identity)
            if number == 0:
                continue
            self.current = number
            sub_first, sub_last = self.command_range(subcommand, [])
            if subcommand.name == "s":
                substituted += self.substitute_lines(subcommand, sub_first, sub_last)
            else:
                self.run(subcommand, sub_first, sub_last, text)
        if subcommand.name == "s" and substituted == 0:
            raise EditorError("no match")

    def file_report(self, name):
        contents = self.files[name]
        self.emit(f"file {name} lines={len(contents)} bytes={byte_count(contents)}")

    def require_file(self, name):
        if name not in self.files:
            raise EditorError("no such file")
        return self.files[name]

    def write_file(self, command, first, last, text):
        self.files[command.file_name] = self.texts(first, last)
        self.file_report(command.file_name)

    def append_file(self, command, first, last, text):
        existing = self.files.get(command.file_name, [])
        self.files[command.file_name] = existing + self.texts(first, last)
        self.file_report(command.file_name)

    def read_file(self, command, first, last, text):
        contents = self.require_file(command.file_name)
        self.insert(first, contents)
        self.current = first + len(contents)
        self.file_report(command.file_name)

    def edit_file(self, command, first, last, text):
        contents = self.require_file(command.file_name)
        self.lines = self.new_lines(contents)
        self.current = len(contents)
        self.file_report(command.file_name)

    def list_files(self, command, first, last, text):
        entries = [f"{name}={len(self.files[name])}" for name in sorted(self.files)]
        self.emit("files " + (" ".join(entries) if entries else "none"))


def main():
    editor = Editor()
    output = []
    for line, text in read_commands(sys.stdin.read().splitlines()):
        trial = editor.copy()
        try:
            trial.process(line, text)
        except EditorError as error:
            output.append(f"? {error}")
            continue
        editor = trial
        output.extend(trial.output)
    sys.stdout.write("".join(line + "\n" for line in output))


if __name__ == "__main__":
    main()
