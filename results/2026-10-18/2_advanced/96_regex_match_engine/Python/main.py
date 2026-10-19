"""ASCII regular expression parsing, compilation and comparison of matching VMs."""

from pathlib import Path

from backtrack_vm import BacktrackingVM, TooManySteps
from charset import (
    ASCII, STANDARD, escaped_set, is_letter, switched,
)
from formatter import (
    decode_quoted, instruction_notation, quoted, set_notation,
)
from pike_vm import PikeVM


class PatternError(Exception):
    def __init__(self, message, column):
        super().__init__(message)
        self.message = message
        self.column = column


class PatternParser:
    """Strict recursive-descent parser with the specification's error precedence."""

    def __init__(self, text):
        self.text = text
        self.index = 0
        self.groups = 0
        self.named = {}
        self.backrefs = []

    def peek(self, offset=0):
        position = self.index + offset
        return self.text[position] if position < len(self.text) else None

    def take(self):
        char = self.peek()
        if char is not None:
            self.index += 1
        return char

    def error(self, message, column=None):
        raise PatternError(
            message, self.index + 1 if column is None else column
        )

    def digits(self):
        start = self.index
        while self.peek() is not None and self.peek() in "0123456789":
            self.take()
        return self.text[start:self.index]

    def name(self):
        initial = self.peek()
        if initial is None or not (
                is_letter(initial) or initial == "_"):
            self.error("invalid group name")
        start = self.index
        while self.peek() is not None and (
                is_letter(self.peek()) or self.peek().isdigit()
                or self.peek() == "_"):
            self.take()
        name = self.text[start:self.index]
        if self.peek() != ">":
            self.error("invalid group name")
        self.take()
        return name

    def parse(self):
        root = self.alternation()
        if self.peek() is not None:
            self.error("unmatched )")
        for ref in self.backrefs:
            if ref["name"] is not None:
                if ref["name"] not in self.named:
                    self.error("unknown group name", ref["column"])
                ref["number"] = self.named[ref["name"]]
            elif ref["number"] > self.groups:
                self.error("invalid group reference", ref["column"])
        return root

    def alternation(self):
        children = [self.concatenation()]
        while self.peek() == "|":
            self.take()
            children.append(self.concatenation())
        return children[0] if len(children) == 1 else {
            "kind": "alternation", "elements": children,
        }

    def concatenation(self):
        children = []
        while self.peek() is not None and self.peek() not in "|)":
            children.append(self.quantified())
        return children[0] if len(children) == 1 else {
            "kind": "concat", "elements": children,
        }

    def quantified(self):
        char = self.peek()
        if char in ("*", "+", "?", "{"):
            self.error("nothing to repeat")
        element = self.element()
        if self.peek() not in ("*", "+", "?", "{"):
            return element
        if element["kind"] in ("assert", "look"):
            self.error("nothing to repeat")
        beginning = self.index + 1
        char = self.take()
        if char == "*":
            lower, upper = 0, None
        elif char == "+":
            lower, upper = 1, None
        elif char == "?":
            lower, upper = 0, 1
        else:
            low_digits = self.digits()
            if not low_digits:
                self.error("invalid quantifier", beginning)
            lower = int(low_digits)
            if self.peek() == "}":
                upper = lower
            elif self.peek() == ",":
                self.take()
                if self.peek() == "}":
                    upper = None
                else:
                    high_digits = self.digits()
                    if not high_digits:
                        self.error("invalid quantifier", beginning)
                    upper = int(high_digits)
            else:
                self.error("invalid quantifier", beginning)
            if self.peek() != "}":
                self.error("invalid quantifier", beginning)
            self.take()
            if lower > 100 or (upper is not None and upper > 100):
                self.error("quantifier too large", beginning)
            if upper is not None and lower > upper:
                self.error("quantifier range out of order", beginning)
        repetition_kind = "greedy"
        if self.peek() == "?":
            self.take()
            repetition_kind = "lazy"
        elif self.peek() == "+":
            self.take()
            repetition_kind = "possessive"
        if self.peek() in ("*", "+", "?", "{"):
            self.error("nested quantifier")
        return {
            "kind": "repeat", "child": element,
            "lower": lower, "upper": upper,
            "mode": repetition_kind,
        }

    def element(self):
        char = self.peek()
        if char == "(":
            return self.group()
        if char == "[":
            return self.character_class()
        if char == "\\":
            return self.escape()
        if char == ".":
            self.take()
            return {"kind": "any"}
        if char in ("^", "$"):
            self.take()
            return {"kind": "assert", "value": "BOL" if char == "^" else "EOL"}
        self.take()
        return {"kind": "literal", "value": char}

    def group(self):
        column = self.index + 1
        self.take()
        kind = "capture"
        named = None
        if self.peek() == "?":
            self.take()
            special = self.peek()
            if special not in (":", "=", "!", "<"):
                self.error("invalid group", column)
            self.take()
            kind = {
                ":": "noncapture", "=": "ahead",
                "!": "negative", "<": "capture",
            }[special]
            if special == "<":
                name_column = self.index + 1
                named = self.name()
                if named in self.named:
                    self.error("duplicate group name", name_column)
        number = None
        if kind == "capture":
            self.groups += 1
            number = self.groups
            if named is not None:
                self.named[named] = number
        content = self.alternation()
        if self.peek() != ")":
            self.error("missing )", column)
        self.take()
        if kind == "noncapture":
            return content
        if kind in ("ahead", "negative"):
            return {"kind": "look", "positive": kind == "ahead",
                    "child": content}
        return {"kind": "group", "number": number, "child": content}

    def class_item(self):
        char = self.peek()
        if char != "\\":
            return ord(self.take())
        column = self.index + 1
        self.take()
        special = self.peek()
        if special is None:
            self.error("trailing backslash", column)
        self.take()
        if special in "dDwWsS":
            return set(escaped_set(special))
        if special in ("n", "t"):
            return ord("\n" if special == "n" else "\t")
        if special.isalpha() or special.isdigit():
            self.error("invalid escape", column)
        return ord(special)

    def character_class(self):
        opening = self.index + 1
        self.take()
        negate = self.peek() == "^"
        if negate:
            self.take()
        if self.peek() == "]":
            self.error("empty class")
        values = set()
        while True:
            if self.peek() is None:
                self.error("missing ]", opening)
            if self.peek() == "]":
                self.take()
                break
            first = self.class_item()
            if self.peek() == "-" and self.peek(1) not in (None, "]"):
                column = self.index + 1
                self.take()
                if isinstance(first, set):
                    self.error("invalid range", column)
                last = self.class_item()
                if isinstance(last, set) or first > last:
                    self.error("invalid range", column)
                values.update(range(first, last + 1))
            elif isinstance(first, set):
                values.update(first)
            else:
                values.add(first)
        return {"kind": "class", "set": frozenset(values), "neg": negate}

    def escape(self):
        column = self.index + 1
        self.take()
        char = self.peek()
        if char is None:
            self.error("trailing backslash", column)
        self.take()
        if char in "dDwWsS":
            return {
                "kind": "class", "set": frozenset(STANDARD[char.lower()]),
                "neg": char.isupper(),
            }
        if char in "bB":
            return {
                "kind": "assert", "value": "WORD" if char == "b" else "NOTWORD",
            }
        if char in ("n", "t"):
            return {"kind": "literal",
                    "value": "\n" if char == "n" else "\t"}
        if char in "123456789":
            number = char + self.digits()
            ref = {
                "kind": "backref", "number": int(number),
                "name": None, "column": column,
            }
            self.backrefs.append(ref)
            return ref
        if char == "k":
            if self.peek() != "<":
                self.error("invalid escape", column)
            self.take()
            name = self.name()
            ref = {"kind": "backref", "number": None,
                   "name": name, "column": column}
            self.backrefs.append(ref)
            return ref
        if char.isalpha() or char.isdigit():
            self.error("invalid escape", column)
        return {"kind": "literal", "value": char}


def compile_program(root):
    """Emit numbered opcodes with the exact priorities and patch targets."""
    program = []

    def emit(op, **parts):
        address = len(program)
        program.append({"op": op, **parts})
        return address

    def compile_node(node):
        kind = node["kind"]
        if kind == "literal":
            emit("CHAR", char=node["value"])
        elif kind == "any":
            emit("ANY")
        elif kind == "class":
            emit("CLASS", set=node["set"], neg=node["neg"])
        elif kind == "assert":
            emit("ASSERT", kind=node["value"])
        elif kind == "backref":
            emit("BACKREF", group=node["number"])
        elif kind == "group":
            emit("SAVE", slot=node["number"] * 2)
            compile_node(node["child"])
            emit("SAVE", slot=node["number"] * 2 + 1)
        elif kind == "look":
            pc = emit("LOOK", kind="AHEAD" if node["positive"] else "NOT",
                      x=None)
            compile_node(node["child"])
            emit("MATCH")
            program[pc]["x"] = len(program)
        elif kind == "concat":
            for child in node["elements"]:
                compile_node(child)
        elif kind == "alternation":
            endings = []
            for child in node["elements"][:-1]:
                pc = emit("SPLIT", x=len(program) + 1, y=None)
                compile_node(child)
                jump = emit("JMP", x=None)
                program[pc]["y"] = len(program)
                endings.append(jump)
            compile_node(node["elements"][-1])
            for pc in endings:
                program[pc]["x"] = len(program)
        elif kind == "repeat":
            child, lower, upper = (
                node["child"], node["lower"], node["upper"]
            )
            mode = node["mode"]
            if mode == "possessive":
                pc = emit("LOOK", kind="ATOMIC", x=None)
                clone = {**node, "mode": "greedy"}
                compile_node(clone)
                emit("MATCH")
                program[pc]["x"] = len(program)
                return
            if upper is None and lower == 0:
                split = emit("SPLIT", x=None, y=None)
                continuation = len(program)
                compile_node(child)
                emit("JMP", x=split)
                end = len(program)
                if mode == "lazy":
                    program[split].update(x=end, y=continuation)
                else:
                    program[split].update(x=continuation, y=end)
                return
            if upper is None:
                for _ in range(lower - 1):
                    compile_node(child)
                beginning = len(program)
                compile_node(child)
                split = emit("SPLIT", x=None, y=None)
                end = len(program)
                if mode == "lazy":
                    program[split].update(x=end, y=beginning)
                else:
                    program[split].update(x=beginning, y=end)
                return
            for _ in range(lower):
                compile_node(child)
            optional = []
            for _ in range(upper - lower):
                split = emit("SPLIT", x=None, y=None)
                continuation = len(program)
                compile_node(child)
                optional.append((split, continuation))
            end = len(program)
            for split, continuation in optional:
                if mode == "lazy":
                    program[split].update(x=end, y=continuation)
                else:
                    program[split].update(x=continuation, y=end)
        else:
            raise ValueError("unhandled AST node " + kind)

    emit("SAVE", slot=0)
    compile_node(root)
    emit("SAVE", slot=1)
    emit("MATCH")
    return program


def length_range(node):
    kind = node["kind"]
    if kind in ("literal", "any", "class"):
        return 1, 1
    if kind in ("assert", "look"):
        return 0, 0
    if kind == "backref":
        return 0, None
    if kind == "group":
        return length_range(node["child"])
    if kind in ("concat", "alternation"):
        children = [length_range(child) for child in node["elements"]]
        if kind == "concat":
            minimum = sum(a for a, b in children)
            maximum = None if any(b is None for a, b in children) else sum(
                b for a, b in children
            )
        else:
            minimum = min(a for a, b in children)
            maximum = None if any(b is None for a, b in children) else max(
                b for a, b in children
            )
        return minimum, maximum
    if kind == "repeat":
        lower, upper = node["lower"], node["upper"]
        a, b = length_range(node["child"])
        maximum = (
            0 if b == 0 else
            None if b is None or upper is None else upper * b
        )
        return lower * a, maximum
    raise ValueError(kind)


def first_characters(node, flags):
    kind = node["kind"]
    if kind == "literal":
        char = node["value"]
        value = {ord(char)}
        if "i" in flags and is_letter(char):
            value.add(ord(switched(char)))
        return value, False
    if kind == "any":
        value = set(ASCII)
        if "s" not in flags:
            value.remove(10)
        return value, False
    if kind == "class":
        chars = set(node["set"])
        matched = set()
        for code in ASCII:
            equal = code in chars or (
                "i" in flags and is_letter(chr(code))
                and ord(switched(chr(code))) in chars
            )
            if equal != node["neg"]:
                matched.add(code)
        return matched, False
    if kind in ("assert", "look"):
        return set(), True
    if kind == "backref":
        return set(ASCII), True
    if kind == "group":
        return first_characters(node["child"], flags)
    if kind == "alternation":
        choices = [first_characters(child, flags)
                   for child in node["elements"]]
        return set().union(*(a for a, b in choices)), any(
            b for a, b in choices
        )
    if kind == "concat":
        characters = set()
        nullable = True
        for child in node["elements"]:
            child_chars, is_nullable = first_characters(child, flags)
            characters.update(child_chars)
            if not is_nullable:
                nullable = False
                break
        return characters, nullable
    if kind == "repeat":
        if node["upper"] == 0:
            return set(), True
        chars, nullable = first_characters(node["child"], flags)
        return chars, nullable or node["lower"] == 0
    raise ValueError(kind)


def read_patterns(path="input/patterns.txt"):
    patterns = {}
    for line in Path(path).read_text(encoding="ascii").splitlines():
        name, flags_text, pattern_text = line.split(" ", 2)
        entry = {
            "name": name, "flags_text": flags_text,
            "flags": "" if flags_text == "-" else flags_text,
            "pattern": pattern_text,
        }
        parser = PatternParser(pattern_text)
        try:
            root = parser.parse()
            program = compile_program(root)
            entry.update({
                "root": root, "program": program,
                "groups": parser.groups, "named": parser.named,
                "pike": all(ins["op"] not in ("BACKREF", "LOOK")
                            for ins in program),
                "error": None,
            })
        except PatternError as exc:
            entry["error"] = (exc.message, exc.column)
        patterns[name] = entry
    return patterns


def read_subjects(path="input/subjects.txt"):
    result = {}
    for line in Path(path).read_text(encoding="ascii").splitlines():
        name, quoted_text = line.split(" ", 1)
        result[name] = decode_quoted(quoted_text)
    return result


def read_commands(path="input/commands.txt"):
    commands = []
    for line in Path(path).read_text(encoding="ascii").splitlines():
        if line.startswith("REPLACE "):
            _, mode, name, subject, encoded = line.split(" ", 4)
            record = {
                "name": name, "subject": subject, "kind": "REPLACE",
                "mode": mode, "template": decode_quoted(encoded),
            }
        elif line.startswith("LIST "):
            record = {"kind": "LIST", "name": line.split(" ")[1]}
        else:
            kind, name, subject = line.split(" ")
            record = {"kind": kind, "name": name, "subject": subject}
        commands.append({
            **record, "number": len(commands) + 1,
            "line": line,
        })
    return commands


def parse_template(text, pattern):
    parts = []
    pos = 0
    while pos < len(text):
        if text[pos] != "$":
            parts.append(("literal", text[pos]))
            pos += 1
            continue
        if pos + 1 >= len(text):
            return None
        next_char = text[pos + 1]
        if next_char == "$":
            parts.append(("literal", "$"))
            pos += 2
            continue
        if next_char in "0123456789":
            group = int(next_char)
            pos += 2
        elif next_char == "{":
            end = text.find("}", pos + 2)
            if end < 0:
                return None
            name = text[pos + 2:end]
            if name.isdecimal() and name:
                group = int(name)
            elif name in pattern["named"]:
                group = pattern["named"][name]
            else:
                return None
            pos = end + 1
        else:
            return None
        if group > pattern["groups"]:
            return None
        parts.append(("group", group))
    return parts


def expand_template(parts, captures, text):
    result = []
    for kind, value in parts:
        if kind == "literal":
            result.append(value)
        else:
            a, b = captures[2 * value:2 * value + 2]
            result.append(text[a:b] if a is not None and b is not None else "")
    return "".join(result)


def scans(vm, kind):
    if kind in ("MATCH", "SEARCH", "REPLACE FIRST"):
        result = vm.search(0)
        return [result] if result is not None else []
    found = []
    start = 0
    while start <= len(vm.text):
        result = vm.search(start)
        if result is None:
            break
        found.append(result)
        start = result[1] if result[1] > result[0] else result[1] + 1
    return found


def execute_command(command, pattern, subjects):
    """Run both engines when possible, sharing one step budget per command."""
    if pattern["error"] is not None:
        return {"status": "invalid pattern", "steps": []}
    if command["kind"] == "LIST":
        return {"status": "list", "steps": []}
    template = None
    if command["kind"] == "REPLACE":
        template = parse_template(command["template"], pattern)
        if template is None:
            return {"status": "invalid template", "steps": []}
    text = subjects[command["subject"]]
    full = command["kind"] == "MATCH"
    search_kind = (
        "REPLACE " + command["mode"]
        if command["kind"] == "REPLACE" else command["kind"]
    )
    backtracking = BacktrackingVM(
        pattern["program"], pattern["flags"], pattern["groups"], text, full
    )
    failed = False
    backtrack_matches = None
    try:
        backtrack_matches = scans(backtracking, search_kind)
    except TooManySteps:
        failed = True
    steps = [("backtrack", backtracking.steps)]
    if pattern["pike"]:
        pike = PikeVM(
            pattern["program"], pattern["flags"], pattern["groups"],
            text, full
        )
        pike_matches = scans(pike, search_kind)
        steps.append(("pike", pike.steps))
        if failed:
            engine = "pike (backtrack: TOO_MANY_STEPS)"
            matches = pike_matches
        elif backtrack_matches != pike_matches:
            return {"status": "MISMATCH", "steps": steps}
        else:
            engine, matches = "both", pike_matches
    else:
        if failed:
            return {"status": "TOO_MANY_STEPS", "steps": steps}
        engine, matches = "backtrack", backtrack_matches
    return {
        "status": "ok", "engine": engine, "matches": matches,
        "steps": steps, "template": template, "text": text,
    }


def match_lines(captures, pattern, text):
    a, b = captures[0:2]
    lines = [f"match {a}-{b} {quoted(text[a:b])}"]
    for group in range(1, pattern["groups"] + 1):
        start, stop = captures[2 * group:2 * group + 2]
        if start is None or stop is None:
            lines.append(f"group {group} -")
        else:
            lines.append(
                f"group {group} {start}-{stop} "
                f"{quoted(text[start:stop])}"
            )
    return lines


def split_text(text, matches):
    pieces = []
    previous = 0
    for captures in matches:
        pieces.append(text[previous:captures[0]])
        previous = captures[1]
    pieces.append(text[previous:])
    return pieces


def replacement_text(text, matches, parts):
    pieces = []
    previous = 0
    for captures in matches:
        pieces.append(text[previous:captures[0]])
        pieces.append(expand_template(parts, captures, text))
        previous = captures[1]
    pieces.append(text[previous:])
    return "".join(pieces)


def render_result(command, pattern, evaluated):
    lines = [
        f"#{command['number']} {command['line']}"
    ]
    status = evaluated["status"]
    if status == "list":
        lines.append(f"instructions {len(pattern['program'])}")
        return lines
    if status != "ok":
        lines.append(status)
        return lines
    text, captures_list = evaluated["text"], evaluated["matches"]
    lines.append("engine " + evaluated["engine"])
    kind = command["kind"]
    if kind in ("MATCH", "SEARCH"):
        if captures_list:
            lines.extend(match_lines(captures_list[0], pattern, text))
        else:
            lines.append("no match")
    elif kind == "FINDALL":
        lines.append(f"matches {len(captures_list)}")
        for captures in captures_list:
            lines.extend(match_lines(captures, pattern, text))
    elif kind == "REPLACE":
        lines.extend([
            f"replacements {len(captures_list)}",
            "result " + quoted(
                replacement_text(text, captures_list, evaluated["template"])
            ),
        ])
    elif kind == "SPLIT":
        pieces = split_text(text, captures_list)
        lines.append(f"pieces {len(pieces)}")
        lines.append("piece " + quoted(pieces[0]))
        for i, captures in enumerate(captures_list):
            for group in range(1, pattern["groups"] + 1):
                a, b = captures[2 * group:2 * group + 2]
                text_value = quoted(text[a:b]) if a is not None and b is not None else "-"
                lines.append(f"group {group} {text_value}")
            lines.append("piece " + quoted(pieces[i + 1]))
    return lines


def program_listing(pattern):
    root, program = pattern["root"], pattern["program"]
    lower, upper = length_range(root)
    charset, _ = first_characters(root, pattern["flags"])
    names = ",".join(
        f"{name}:{index}" for name, index in sorted(
            pattern["named"].items(), key=lambda pair: pair[1]
        )
    ) or "-"
    lines = [
        "=== " + pattern["name"],
        f"flags={pattern['flags_text']} groups={pattern['groups']} "
        f"names={names} length={lower}..{upper if upper is not None else 'inf'} "
        f"first={set_notation(charset) if charset else '-'} "
        f"pike={'yes' if pattern['pike'] else 'no'} size={len(program)}",
    ]
    lines.extend(
        f"{pc} {instruction_notation(instruction)}"
        for pc, instruction in enumerate(program)
    )
    return lines


def pattern_errors(patterns):
    result = []
    for pattern in patterns.values():
        if pattern["error"] is None:
            continue
        message, column = pattern["error"]
        result.extend([
            f"{pattern['name']}: {message} at column {column}",
            "  " + pattern["pattern"],
            "  " + " " * (column - 1) + "^",
        ])
    return result if result else ["no errors"]


def save(name, lines, allow_empty=False):
    target = Path("output") / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(
        "\n".join(lines) + ("\n" if lines else ""),
        encoding="ascii",
    )


def main():
    patterns = read_patterns()
    subjects = read_subjects()
    commands = read_commands()
    results = []
    program_lines = []
    step_lines = ["command,engine,steps"]
    for command in commands:
        pattern = patterns[command["name"]]
        evaluation = execute_command(command, pattern, subjects)
        results.extend(render_result(command, pattern, evaluation))
        if command["kind"] == "LIST" and pattern["error"] is None:
            program_lines.extend(program_listing(pattern))
        for name, count in evaluation["steps"]:
            step_lines.append(f"{command['number']},{name},{count}")
    save("results.txt", results)
    save("programs.txt", program_lines or ["no programs"])
    save("steps.csv", step_lines)
    save("errors.txt", pattern_errors(patterns))


if __name__ == "__main__":
    main()
