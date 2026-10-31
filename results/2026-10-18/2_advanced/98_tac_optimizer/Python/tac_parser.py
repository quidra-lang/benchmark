"""Immutable TAC instructions, source reading, and canonical program text."""

from collections import namedtuple


KINDS = ("copy", "bin", "load", "store", "goto", "if", "param", "call",
         "return", "read", "print")


class Instruction(namedtuple("InstructionFields",
                            "kind destination a b operation name count",
                            defaults=(None, None, None, None, None, 0))):
    __slots__ = ()

    def operand_fields(self):
        if self.kind in ("bin", "if", "store"):
            return ("a", "b")
        if self.kind in ("copy", "load", "param", "print"):
            return ("a",)
        if self.kind == "return" and self.a is not None:
            return ("a",)
        return ()

    def used_variables(self):
        return [getattr(self, field) for field in self.operand_fields()
                if isinstance(getattr(self, field), str)]

    def expression(self):
        if self.kind == "bin":
            return "bin", self.operation, self.a, self.b
        if self.kind == "load":
            return "load", self.name, self.a
        return None


class Function:
    def __init__(self, name, parameters, code=()):
        self.name = name
        self.parameters = tuple(parameters)
        self.code = list(code)
        self.temporary_serial = 0
        self.preheader_serial = 0

    def copy(self):
        return Function(self.name, self.parameters, self.code)

    def instructions(self):
        return [line for line in self.code if isinstance(line, Instruction)]


class Program:
    def __init__(self, arrays, functions):
        self.arrays = list(arrays)
        self.functions = list(functions)


def operand(word):
    return int(word) if word[0] == "-" or word[0].isdigit() else word


def array_operand(word):
    name, index = word[:-1].split("[", 1)
    return name, operand(index)


def parse_instruction(words):
    first = words[0]
    if first == "goto":
        return Instruction("goto", name=words[1])
    if first == "if":
        return Instruction("if", a=operand(words[1]), b=operand(words[3]),
                           operation=words[2], name=words[5])
    if first in ("param", "print"):
        return Instruction(first, a=operand(words[1]))
    if first == "return":
        return Instruction("return", a=operand(words[1]) if len(words) == 2 else None)
    if first == "read":
        return Instruction("read", destination=words[1])
    if first == "call":
        return Instruction("call", name=words[1], count=int(words[2]))
    if "[" in first:
        name, index = array_operand(first)
        return Instruction("store", a=index, b=operand(words[2]), name=name)
    if words[2] == "call":
        return Instruction("call", destination=first, name=words[3], count=int(words[4]))
    if len(words) == 5:
        return Instruction("bin", first, operand(words[2]), operand(words[4]), words[3])
    if "[" in words[2]:
        name, index = array_operand(words[2])
        return Instruction("load", first, a=index, name=name)
    return Instruction("copy", first, operand(words[2]))


def read_program(path):
    arrays, functions = [], []
    current = None
    for line in path.read_text(encoding="ascii").splitlines():
        words = line.split()
        if not words or words[0].startswith("#"):
            continue
        if words[0] == "array":
            arrays.append((words[1], int(words[2])))
        elif words[0] == "func":
            current = Function(words[1], words[2:])
            functions.append(current)
        elif words[0] == "end":
            current = None
        elif len(words) == 1 and words[0].endswith(":"):
            current.code.append(words[0][:-1])
        else:
            current.code.append(parse_instruction(words))
    return Program(arrays, functions)


def calculate(operation, first, second):
    if operation == "+":
        return first + second
    if operation == "-":
        return first - second
    if operation == "*":
        return first * second
    if operation in ("/", "%"):
        quotient = abs(first) // abs(second)
        if (first < 0) != (second < 0):
            quotient = -quotient
        return quotient if operation == "/" else first - second * quotient
    return int({"<": first < second, "<=": first <= second,
                ">": first > second, ">=": first >= second,
                "==": first == second, "!=": first != second}[operation])


def expression_string(expression):
    if expression[0] == "load":
        return f"{expression[1]}[{expression[2]}]"
    return f"{expression[2]}{expression[1]}{expression[3]}"


def instruction_string(instruction):
    kind = instruction.kind
    if kind == "copy":
        return f"{instruction.destination} = {instruction.a}"
    if kind == "bin":
        return f"{instruction.destination} = {instruction.a} {instruction.operation} {instruction.b}"
    if kind == "load":
        return f"{instruction.destination} = {instruction.name}[{instruction.a}]"
    if kind == "store":
        return f"{instruction.name}[{instruction.a}] = {instruction.b}"
    if kind == "goto":
        return "goto " + instruction.name
    if kind == "if":
        return f"if {instruction.a} {instruction.operation} {instruction.b} goto {instruction.name}"
    if kind == "call":
        prefix = "" if instruction.destination is None else instruction.destination + " = "
        return prefix + f"call {instruction.name} {instruction.count}"
    if kind == "read":
        return "read " + instruction.destination
    if kind == "return" and instruction.a is None:
        return "return"
    return f"{kind} {instruction.a}"


def function_lines(function):
    lines = [" ".join(("func", function.name, *function.parameters))]
    for line in function.code:
        lines.append(line + ":" if isinstance(line, str) else "    " + instruction_string(line))
    lines.append("end")
    return lines


def program_lines(program):
    sections = []
    if program.arrays:
        sections.append([f"array {name} {size}" for name, size in program.arrays])
    sections.extend(function_lines(function) for function in program.functions)
    lines = []
    for section in sections:
        if lines:
            lines.append("")
        lines.extend(section)
    return lines
