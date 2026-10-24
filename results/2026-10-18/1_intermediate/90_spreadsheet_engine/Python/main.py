import operator
import re
import string
import sys
from dataclasses import dataclass, replace
from enum import Enum
from typing import NamedTuple

COLUMNS = string.ascii_uppercase
ROWS = 99

ADDRESS_RE = re.compile(r"([A-Z])([1-9][0-9]?)")
ROW_RE = re.compile(r"[1-9][0-9]?")
COLUMN_RE = re.compile(r"[A-Z]")
INTEGER_RE = re.compile(r"0|-?[1-9][0-9]{0,8}")
DIGITS_RE = re.compile(r"[0-9]+")
WORD_RE = re.compile(r"[A-Za-z0-9$]+")
REFERENCE_RE = re.compile(r"(\$?)([A-Z])(\$?)([1-9][0-9]?)")
NAME_RE = re.compile(r"[A-Z][A-Z0-9]*")

SYMBOLS = "+-*/&(),:=<>"
TWO_CHAR_SYMBOLS = ("<>", "<=", ">=")
COMPARISONS = {
    "=": operator.eq,
    "<>": operator.ne,
    "<": operator.lt,
    "<=": operator.le,
    ">": operator.gt,
    ">=": operator.ge,
}
OPERATOR_LEVELS = [set(COMPARISONS), {"&"}, {"+", "-"}, {"*", "/"}]
PRECEDENCE = {op: level + 1 for level, ops in enumerate(OPERATOR_LEVELS) for op in ops}
AGGREGATES = {"SUM", "MIN", "MAX", "COUNT", "AVERAGE", "AND", "OR", "CONCAT"}


class CommandError(Exception):
    pass


class ErrorValue(Enum):
    DIV0 = "#DIV/0!"
    REF = "#REF!"
    NAME = "#NAME?"
    VALUE = "#VALUE!"
    CYCLE = "#CYCLE!"


@dataclass(frozen=True, order=True)
class Cell:
    row: int
    col: int

    def __str__(self):
        return f"{COLUMNS[self.col - 1]}{self.row}"

    def shifted(self, rows, cols):
        return Cell(self.row + rows, self.col + cols)

    def inside_sheet(self):
        return 1 <= self.row <= ROWS and 1 <= self.col <= len(COLUMNS)


@dataclass(frozen=True)
class CellRange:
    top: int
    left: int
    bottom: int
    right: int

    def cells(self):
        for row in range(self.top, self.bottom + 1):
            for col in range(self.left, self.right + 1):
                yield Cell(row, col)

    def contains(self, cell):
        return self.top <= cell.row <= self.bottom and self.left <= cell.col <= self.right

    def shifted(self, rows, cols):
        return CellRange(self.top + rows, self.left + cols, self.bottom + rows, self.right + cols)

    def fits_sheet(self):
        return 1 <= self.top and self.bottom <= ROWS and 1 <= self.left and self.right <= len(COLUMNS)


def parse_address(text):
    match = ADDRESS_RE.fullmatch(text)
    if match is None:
        raise CommandError("bad address")
    return Cell(int(match[2]), COLUMNS.index(match[1]) + 1)


def parse_range(text):
    parts = text.split(":")
    if len(parts) > 2:
        raise CommandError("bad address")
    first = parse_address(parts[0])
    last = parse_address(parts[-1])
    return CellRange(
        min(first.row, last.row),
        min(first.col, last.col),
        max(first.row, last.row),
        max(first.col, last.col),
    )


class Node:
    pass


@dataclass(frozen=True)
class Number(Node):
    value: int


@dataclass(frozen=True)
class Text(Node):
    value: str


@dataclass(frozen=True)
class Name(Node):
    word: str


@dataclass(frozen=True)
class Reference(Node):
    col: int
    row: int
    absolute_col: bool
    absolute_row: bool

    @property
    def cell(self):
        return Cell(self.row, self.col)

    def __str__(self):
        col_marker = "$" if self.absolute_col else ""
        row_marker = "$" if self.absolute_row else ""
        return f"{col_marker}{COLUMNS[self.col - 1]}{row_marker}{self.row}"


@dataclass(frozen=True)
class RangeRef(Node):
    first: Reference
    last: Reference

    @property
    def area(self):
        return CellRange(self.first.row, self.first.col, self.last.row, self.last.col)

    def __str__(self):
        return f"{self.first}:{self.last}"


@dataclass(frozen=True)
class InvalidRef(Node):
    pass


@dataclass(frozen=True)
class Call(Node):
    name: str
    args: tuple


@dataclass(frozen=True)
class Negate(Node):
    operand: Node


@dataclass(frozen=True)
class BinaryOp(Node):
    op: str
    left: Node
    right: Node


INVALID = InvalidRef()


def make_range(first, last):
    if first.col > last.col:
        first, last = (
            replace(first, col=last.col, absolute_col=last.absolute_col),
            replace(last, col=first.col, absolute_col=first.absolute_col),
        )
    if first.row > last.row:
        first, last = (
            replace(first, row=last.row, absolute_row=last.absolute_row),
            replace(last, row=first.row, absolute_row=first.absolute_row),
        )
    return RangeRef(first, last)


class Token(NamedTuple):
    kind: str
    value: object
    position: int


def syntax_error(position):
    return CommandError(f"syntax error at {position}")


def tokenize(formula):
    tokens = []
    index = 1
    while index < len(formula):
        char = formula[index]
        position = index + 1
        if char == " ":
            index += 1
        elif char.isdigit():
            digits = DIGITS_RE.match(formula, index)[0]
            if len(digits) >= 10:
                raise syntax_error(position)
            tokens.append(Token("number", int(digits), position))
            index += len(digits)
        elif char == '"':
            end = formula.find('"', index + 1)
            if end < 0:
                raise syntax_error(position)
            tokens.append(Token("string", formula[index + 1 : end], position))
            index = end + 1
        elif char.isalpha() or char == "$":
            word = WORD_RE.match(formula, index)[0]
            index += len(word)
            tokens.append(classify_word(word.upper(), formula[index:], position))
        elif formula[index : index + 2] in TWO_CHAR_SYMBOLS:
            tokens.append(Token("symbol", formula[index : index + 2], position))
            index += 2
        elif char in SYMBOLS:
            tokens.append(Token("symbol", char, position))
            index += 1
        else:
            raise syntax_error(position)
    tokens.append(Token("end", None, len(formula) + 1))
    return tokens


def classify_word(word, rest, position):
    match = REFERENCE_RE.fullmatch(word)
    if match:
        absolute_col, letter, absolute_row, row = match.groups()
        reference = Reference(
            COLUMNS.index(letter) + 1, int(row), absolute_col == "$", absolute_row == "$"
        )
        return Token("reference", reference, position)
    if NAME_RE.fullmatch(word):
        kind = "function" if rest.lstrip(" ").startswith("(") else "name"
        return Token(kind, word, position)
    raise syntax_error(position)


class Parser:
    def __init__(self, tokens):
        self.tokens = tokens
        self.index = 0

    def accept(self, symbols):
        token = self.tokens[self.index]
        if token.kind == "symbol" and token.value in symbols:
            self.index += 1
            return token.value
        return None

    def expect(self, symbol):
        if not self.accept({symbol}):
            raise syntax_error(self.tokens[self.index].position)

    def formula(self):
        tree = self.expression()
        token = self.tokens[self.index]
        if token.kind != "end":
            raise syntax_error(token.position)
        return tree

    def expression(self, level=0):
        if level == len(OPERATOR_LEVELS):
            return self.unary()
        left = self.expression(level + 1)
        while op := self.accept(OPERATOR_LEVELS[level]):
            left = BinaryOp(op, left, self.expression(level + 1))
        return left

    def unary(self):
        if self.accept({"-"}):
            return Negate(self.unary())
        return self.primary()

    def primary(self):
        token = self.tokens[self.index]
        self.index += 1
        match token.kind:
            case "number":
                return Number(token.value)
            case "string":
                return Text(token.value)
            case "name":
                return Name(token.value)
            case "reference":
                if not self.accept({":"}):
                    return token.value
                last = self.tokens[self.index]
                if last.kind != "reference":
                    raise syntax_error(last.position)
                self.index += 1
                return make_range(token.value, last.value)
            case "function":
                self.expect("(")
                args = []
                if not self.accept({")"}):
                    args.append(self.expression())
                    while self.accept({","}):
                        args.append(self.expression())
                    self.expect(")")
                return Call(token.value, tuple(args))
            case "symbol" if token.value == "(":
                inner = self.expression()
                self.expect(")")
                return inner
        raise syntax_error(token.position)


def parse_content(text):
    if text.startswith("="):
        return Parser(tokenize(text)).formula()
    if len(text) >= 2 and text[0] == text[-1] == '"' and '"' not in text[1:-1]:
        return text[1:-1]
    if INTEGER_RE.fullmatch(text):
        return int(text)
    raise CommandError("bad value")


def canonical(node):
    match node:
        case Number(value):
            return str(value)
        case Text(value):
            return f'"{value}"'
        case Name(word):
            return word
        case Reference() | RangeRef():
            return str(node)
        case InvalidRef():
            return "#REF!"
        case Call(name, args):
            return f"{name}({','.join(map(canonical, args))})"
        case Negate(operand):
            text = canonical(operand)
            return f"-({text})" if isinstance(operand, BinaryOp) else f"-{text}"
        case BinaryOp(op, left, right):
            left_text = canonical(left)
            right_text = canonical(right)
            if isinstance(left, BinaryOp) and PRECEDENCE[left.op] < PRECEDENCE[op]:
                left_text = f"({left_text})"
            if isinstance(right, BinaryOp) and PRECEDENCE[right.op] <= PRECEDENCE[op]:
                right_text = f"({right_text})"
            return left_text + op + right_text


def display(value):
    match value:
        case None:
            return ""
        case ErrorValue():
            return value.value
    return str(value)


def notation(item):
    match item:
        case None:
            return "(empty)"
        case str():
            return f'"{item}"'
        case Node():
            return "=" + canonical(item)
    return display(item)


def format_cells(cells):
    return ",".join(map(str, sorted(cells))) or "none"


def collect_precedents(node):
    match node:
        case Reference():
            return {node.cell}
        case RangeRef():
            return set(node.area.cells())
        case Call(args=args):
            return set().union(*map(collect_precedents, args))
        case Negate(operand):
            return collect_precedents(operand)
        case BinaryOp(left=left, right=right):
            return collect_precedents(left) | collect_precedents(right)
    return set()


def rewrite(node, on_reference, on_range):
    match node:
        case Reference():
            return on_reference(node)
        case RangeRef():
            return on_range(node)
        case Call(name, args):
            return Call(name, tuple(rewrite(arg, on_reference, on_range) for arg in args))
        case Negate(operand):
            return Negate(rewrite(operand, on_reference, on_range))
        case BinaryOp(op, left, right):
            return BinaryOp(
                op, rewrite(left, on_reference, on_range), rewrite(right, on_reference, on_range)
            )
    return node


def with_axis(item, axis, value):
    return replace(item, **{axis: value})


def place(contents, cell, content):
    if content is None:
        contents.pop(cell, None)
    else:
        contents[cell] = content


def to_number(value):
    if value is None:
        return 0
    if isinstance(value, (str, CellRange)):
        return ErrorValue.VALUE
    return value


def to_string(value):
    if value is None:
        return ""
    if isinstance(value, CellRange):
        return ErrorValue.VALUE
    if isinstance(value, int):
        return str(value)
    return value


def compare(x, y):
    if isinstance(x, str) and isinstance(y, int):
        return 1
    if isinstance(x, int) and isinstance(y, str):
        return -1
    blank = "" if isinstance(x, str) or isinstance(y, str) else 0
    x = blank if x is None else x
    y = blank if y is None else y
    return (x > y) - (x < y)


def quotient(a, b):
    result = abs(a) // abs(b)
    return result if (a < 0) == (b < 0) else -result


def strongly_connected_components(graph):
    index = {}
    lowlink = {}
    stack = []
    on_stack = set()
    components = []

    def visit(node):
        index[node] = lowlink[node] = len(index)
        stack.append(node)
        on_stack.add(node)
        for successor in graph[node]:
            if successor not in index:
                visit(successor)
                lowlink[node] = min(lowlink[node], lowlink[successor])
            elif successor in on_stack:
                lowlink[node] = min(lowlink[node], index[successor])
        if lowlink[node] == index[node]:
            component = []
            while True:
                member = stack.pop()
                on_stack.remove(member)
                component.append(member)
                if member == node:
                    break
            components.append(component)

    for node in graph:
        if node not in index:
            visit(node)
    return components


class Sheet:
    def __init__(self):
        self.contents = {}
        self.values = {}
        self.precedents = {}
        self.history = []

    def execute(self, line):
        name, _, argument = line.partition(" ")
        match name:
            case "SET":
                self.set_cell(argument)
            case "CLEAR":
                self.modify(name, self.cleared(argument))
            case "COPY":
                self.modify(name, self.copied(*argument.split(" ")))
            case "MOVE":
                self.modify(name, self.moved(*argument.split(" ")))
            case "INSERTROW" | "DELETEROW" | "INSERTCOL" | "DELETECOL":
                self.modify(name, self.lines_changed(name, argument))
            case "PRINT":
                self.print_range(argument)
            case "SHOW":
                cell = parse_address(argument)
                print(self.describe(argument, cell))
            case "DEPS":
                self.show_dependencies(argument)
            case "LIST":
                self.list_cells()
            case "UNDO":
                self.undo()
            case _:
                raise CommandError("unknown command")

    def commit(self, name, contents):
        self.history.append((name, self.contents))
        return self.replace_contents(contents)

    def modify(self, name, contents):
        print(f"{name} changed={self.commit(name, contents)}")

    def replace_contents(self, contents):
        old_values = self.values
        self.contents = contents
        self.recalculate()
        cells = old_values.keys() | self.values.keys()
        return sum(1 for cell in cells if old_values.get(cell) != self.values.get(cell))

    def recalculate(self):
        formulas = {
            cell: content for cell, content in self.contents.items() if isinstance(content, Node)
        }
        self.precedents = {cell: collect_precedents(tree) for cell, tree in formulas.items()}
        graph = {
            cell: [other for other in cells if other in formulas]
            for cell, cells in self.precedents.items()
        }
        self.values = {
            cell: content for cell, content in self.contents.items() if cell not in formulas
        }
        for component in strongly_connected_components(graph):
            in_cycle = len(component) > 1 or component[0] in graph[component[0]]
            for cell in component:
                if in_cycle:
                    self.values[cell] = ErrorValue.CYCLE
                else:
                    self.values[cell] = self.formula_value(formulas[cell])

    def formula_value(self, tree):
        value = self.evaluate(tree)
        if value is None:
            return 0
        if isinstance(value, CellRange):
            return ErrorValue.VALUE
        return value

    def evaluate(self, node):
        match node:
            case Number(value) | Text(value):
                return value
            case Reference():
                return self.values.get(node.cell)
            case RangeRef():
                return node.area
            case Name():
                return ErrorValue.NAME
            case InvalidRef():
                return ErrorValue.REF
            case Call(name, args):
                return self.call(name, args)
            case Negate(operand):
                number = to_number(self.evaluate(operand))
                return number if isinstance(number, ErrorValue) else -number
            case BinaryOp(op, left, right):
                return self.apply_operator(op, self.evaluate(left), self.evaluate(right))

    def apply_operator(self, op, x, y):
        if isinstance(x, ErrorValue):
            return x
        if isinstance(y, ErrorValue):
            return y
        if op in COMPARISONS:
            if isinstance(x, CellRange) or isinstance(y, CellRange):
                return ErrorValue.VALUE
            return 1 if COMPARISONS[op](compare(x, y), 0) else 0
        convert = to_string if op == "&" else to_number
        a = convert(x)
        if isinstance(a, ErrorValue):
            return a
        b = convert(y)
        if isinstance(b, ErrorValue):
            return b
        match op:
            case "&" | "+":
                return a + b
            case "-":
                return a - b
            case "*":
                return a * b
        return ErrorValue.DIV0 if b == 0 else quotient(a, b)

    def call(self, name, args):
        if name in AGGREGATES:
            return self.aggregate(name, args) if args else ErrorValue.VALUE
        if name == "IF":
            if len(args) not in (2, 3):
                return ErrorValue.VALUE
            condition = to_number(self.evaluate(args[0]))
            if isinstance(condition, ErrorValue):
                return condition
            if condition != 0:
                return self.evaluate(args[1])
            return self.evaluate(args[2]) if len(args) == 3 else 0
        if name not in ("ABS", "NOT", "LEN"):
            return ErrorValue.NAME
        if len(args) != 1:
            return ErrorValue.VALUE
        value = self.evaluate(args[0])
        if name == "LEN":
            text = to_string(value)
            return text if isinstance(text, ErrorValue) else len(text)
        number = to_number(value)
        if isinstance(number, ErrorValue):
            return number
        if name == "ABS":
            return abs(number)
        return 1 if number == 0 else 0

    def aggregate(self, name, args):
        items = []
        for arg in args:
            value = self.evaluate(arg)
            if isinstance(value, CellRange):
                items.extend(self.values.get(cell) for cell in value.cells())
            else:
                items.append(value)
        numbers = [item for item in items if isinstance(item, int)]
        if name == "COUNT":
            return len(numbers)
        error = next((item for item in items if isinstance(item, ErrorValue)), None)
        if error is not None:
            return error
        match name:
            case "SUM":
                return sum(numbers)
            case "MIN":
                return min(numbers, default=0)
            case "MAX":
                return max(numbers, default=0)
            case "AVERAGE":
                return quotient(sum(numbers), len(numbers)) if numbers else ErrorValue.DIV0
            case "AND" | "OR":
                if not numbers:
                    return ErrorValue.VALUE
                test = all if name == "AND" else any
                return 1 if test(numbers) else 0
        return "".join(map(to_string, items))

    def set_cell(self, argument):
        address, _, text = argument.partition(" ")
        cell = parse_address(address)
        contents = dict(self.contents)
        contents[cell] = parse_content(text)
        changed = self.commit("SET", contents)
        print(f"SET {address}={notation(self.values[cell])} changed={changed}")

    def cleared(self, argument):
        area = parse_range(argument)
        return {cell: content for cell, content in self.contents.items() if not area.contains(cell)}

    def transfer(self, source_text, target_text):
        source = parse_range(source_text)
        target = parse_address(target_text)
        rows = target.row - source.top
        cols = target.col - source.left
        destination = source.shifted(rows, cols)
        if not destination.fits_sheet():
            raise CommandError("out of grid")
        return source, destination, rows, cols

    def rewritten(self, on_reference, on_range):
        return {
            cell: rewrite(content, on_reference, on_range) if isinstance(content, Node) else content
            for cell, content in self.contents.items()
        }

    def copied(self, source_text, target_text):
        source, _, rows, cols = self.transfer(source_text, target_text)

        def shift(ref):
            return replace(
                ref,
                row=ref.row if ref.absolute_row else ref.row + rows,
                col=ref.col if ref.absolute_col else ref.col + cols,
            )

        def on_reference(ref):
            shifted = shift(ref)
            return shifted if shifted.cell.inside_sheet() else INVALID

        def on_range(area):
            first = shift(area.first)
            last = shift(area.last)
            if first.cell.inside_sheet() and last.cell.inside_sheet():
                return make_range(first, last)
            return INVALID

        contents = dict(self.contents)
        for cell in source.cells():
            content = self.contents.get(cell)
            if isinstance(content, Node):
                content = rewrite(content, on_reference, on_range)
            place(contents, cell.shifted(rows, cols), content)
        return contents

    def moved(self, source_text, target_text):
        source, destination, rows, cols = self.transfer(source_text, target_text)

        def on_reference(ref):
            if source.contains(ref.cell):
                return replace(ref, row=ref.row + rows, col=ref.col + cols)
            return INVALID if destination.contains(ref.cell) else ref

        def on_range(area):
            if source.contains(area.first.cell) and source.contains(area.last.cell):
                return RangeRef(on_reference(area.first), on_reference(area.last))
            return area

        contents = self.rewritten(on_reference, on_range)
        moving = {cell: contents.pop(cell, None) for cell in source.cells()}
        for cell, content in moving.items():
            place(contents, cell.shifted(rows, cols), content)
        return contents

    def lines_changed(self, name, argument):
        if name.endswith("ROW"):
            if not ROW_RE.fullmatch(argument):
                raise CommandError("bad address")
            axis, index, limit, label = "row", int(argument), ROWS, "row"
        else:
            if not COLUMN_RE.fullmatch(argument):
                raise CommandError("bad address")
            axis, index, limit, label = "col", COLUMNS.index(argument) + 1, len(COLUMNS), "column"
        if name.startswith("DELETE"):
            return self.line_deleted(axis, index)
        if any(getattr(cell, axis) == limit for cell in self.contents):
            raise CommandError(f"last {label} not empty")
        return self.line_inserted(axis, index, limit)

    def line_inserted(self, axis, index, limit):
        def bump(item):
            value = getattr(item, axis)
            return with_axis(item, axis, value + 1) if value >= index else item

        def on_reference(ref):
            ref = bump(ref)
            return INVALID if getattr(ref, axis) > limit else ref

        def on_range(area):
            last = bump(area.last)
            if getattr(last, axis) > limit:
                return INVALID
            return RangeRef(bump(area.first), last)

        contents = self.rewritten(on_reference, on_range)
        return {bump(cell): content for cell, content in contents.items()}

    def line_deleted(self, axis, index):
        def pull_back(item, threshold):
            value = getattr(item, axis)
            return with_axis(item, axis, value - 1) if value >= threshold else item

        def on_reference(ref):
            return INVALID if getattr(ref, axis) == index else pull_back(ref, index + 1)

        def on_range(area):
            if getattr(area.first, axis) == index == getattr(area.last, axis):
                return INVALID
            return RangeRef(pull_back(area.first, index + 1), pull_back(area.last, index))

        contents = self.rewritten(on_reference, on_range)
        return {
            pull_back(cell, index + 1): content
            for cell, content in contents.items()
            if getattr(cell, axis) != index
        }

    def print_range(self, argument):
        area = parse_range(argument)
        rows = range(area.top, area.bottom + 1)
        cols = range(area.left, area.right + 1)
        texts = {cell: display(self.values.get(cell)) for cell in area.cells()}
        label_width = len(str(area.bottom))
        widths = [max(1, max(len(texts[Cell(row, col)]) for row in rows)) for col in cols]
        separator = "+" + "-" * label_width + "+" + "".join("-" * width + "+" for width in widths)
        header = "".join(COLUMNS[col - 1].ljust(width) + "|" for col, width in zip(cols, widths))
        print(separator)
        print("|" + " " * label_width + "|" + header)
        print(separator)
        for row in rows:
            line = "|" + str(row).rjust(label_width) + "|"
            for col, width in zip(cols, widths):
                cell = Cell(row, col)
                if isinstance(self.values.get(cell), int):
                    line += texts[cell].rjust(width) + "|"
                else:
                    line += texts[cell].ljust(width) + "|"
            print(line)
        print(separator)

    def describe(self, label, cell):
        content = notation(self.contents.get(cell))
        return f"{label}: {content} -> {notation(self.values.get(cell))}"

    def show_dependencies(self, address):
        cell = parse_address(address)
        precedents = self.precedents.get(cell, set())
        dependents = {other for other, cells in self.precedents.items() if cell in cells}
        print(
            f"{address}: precedents={format_cells(precedents)} "
            f"dependents={format_cells(dependents)}"
        )

    def list_cells(self):
        if not self.contents:
            print("(no cells)")
        for cell in sorted(self.contents):
            print(self.describe(cell, cell))

    def undo(self):
        if not self.history:
            raise CommandError("nothing to undo")
        name, contents = self.history.pop()
        print(f"UNDO {name} changed={self.replace_contents(contents)}")


def main():
    lines = sys.stdin.read().splitlines()
    sheet = Sheet()
    for line in lines[1 : int(lines[0]) + 1]:
        try:
            sheet.execute(line)
        except CommandError as error:
            print(f"ERROR {error}")


if __name__ == "__main__":
    main()
