from collections import namedtuple

from parser import statement_children


Instruction = namedtuple("Instruction", "op args position")
BINARY = {"+": "ADD", "-": "SUB", "*": "MUL", "/": "DIV", "%": "MOD",
          "<": "LT", "<=": "LE", ">": "GT", ">=": "GE", "==": "EQ", "!=": "NE"}
JUMPS = frozenset(("JUMP", "JUMPF", "JUMPT"))
CONDITIONAL = frozenset(("JUMPF", "JUMPT"))
TRANSFERS = frozenset(("JUMP", "RET", "RETV", "HALT"))
NEGATED = {"LT": "GE", "LE": "GT", "GT": "LE", "GE": "LT", "EQ": "NE", "NE": "EQ"}
INVERSE = {"JUMPF": "JUMPT", "JUMPT": "JUMPF"}


class Label:
    def __init__(self):
        self.position = None


class Unit:
    def __init__(self, name, function, slots, code):
        self.name = name
        self.function = function
        self.slots = slots
        self.before = code
        self.after = []


class Generator:
    def __init__(self):
        self.code = []
        self.loops = []

    def emit(self, op, position, *args):
        self.code.append(Instruction(op, tuple(args), position))

    def mark(self, label):
        label.position = len(self.code)

    def finish(self):
        instructions = []
        for instruction in self.code:
            args = instruction.args
            if instruction.op in JUMPS:
                args = (args[0].position,)
            instructions.append(instruction._replace(args=args))
        return instructions

    def expression(self, node):
        kind, position = node.kind, node.position
        if kind in ("integer", "boolean"):
            self.emit("PUSH", position, int(node.value))
        elif kind == "variable":
            referent = node.referent
            if referent.kind == "global":
                self.emit("LOADG", position, referent.address)
            else:
                self.emit("LOADL", position, referent.slot)
        elif kind == "array":
            self.expression(node.index)
            self.emit("LOADA", position, node.referent.address, node.referent.size)
        elif kind == "read":
            self.emit("READ", position)
        elif kind == "call":
            for argument in node.arguments:
                self.expression(argument)
            self.emit("CALL", position, node.referent.name, len(node.arguments))
        elif kind == "unary":
            self.expression(node.operand)
            self.emit("NEG" if node.operator == "-" else "NOT", position)
        elif node.operator in ("&&", "||"):
            shortcut, end = Label(), Label()
            self.expression(node.left)
            self.emit("JUMPF" if node.operator == "&&" else "JUMPT", position, shortcut)
            self.expression(node.right)
            self.emit("JUMP", position, end)
            self.mark(shortcut)
            self.emit("PUSH", position, int(node.operator == "||"))
            self.mark(end)
        else:
            self.expression(node.left)
            self.expression(node.right)
            self.emit(BINARY[node.operator], position)

    def statement(self, node):
        kind, position = node.kind, node.position
        if kind == "declaration":
            if node.initializer is None:
                self.emit("PUSH", node.name_position, 0)
            else:
                self.expression(node.initializer)
            self.emit("STOREL", node.name_position, node.slot)
        elif kind == "assignment":
            if node.index is not None:
                self.expression(node.index)
            self.expression(node.value)
            referent = node.referent
            if node.index is not None:
                self.emit("STOREA", position, referent.address, referent.size)
            elif referent.kind == "global":
                self.emit("STOREG", position, referent.address)
            else:
                self.emit("STOREL", position, referent.slot)
        elif kind == "call_statement":
            self.expression(node.expression)
            if node.expression.type != "void":
                self.emit("POP", position)
        elif kind == "print":
            for argument in node.arguments:
                self.expression(argument)
            self.emit("PRINT", position, len(node.arguments))
        elif kind == "if":
            alternative, end = Label(), Label()
            self.expression(node.condition)
            self.emit("JUMPF", position, alternative)
            self.statement(node.then)
            if node.otherwise is None:
                self.mark(alternative)
            else:
                self.emit("JUMP", position, end)
                self.mark(alternative)
                self.statement(node.otherwise)
                self.mark(end)
        elif kind == "while":
            start, end = Label(), Label()
            self.mark(start)
            self.expression(node.condition)
            self.emit("JUMPF", position, end)
            self.loops.append((end, start))
            self.statement(node.body)
            self.loops.pop()
            self.emit("JUMP", position, start)
            self.mark(end)
        elif kind == "for":
            start, update, end = Label(), Label(), Label()
            if node.initial is not None:
                self.statement(node.initial)
            self.mark(start)
            if node.condition is not None:
                self.expression(node.condition)
                self.emit("JUMPF", position, end)
            self.loops.append((end, update))
            self.statement(node.body)
            self.loops.pop()
            self.mark(update)
            if node.update is not None:
                self.statement(node.update)
            self.emit("JUMP", position, start)
            self.mark(end)
        elif kind in ("break", "continue"):
            self.emit("JUMP", position, self.loops[-1][int(kind == "continue")])
        elif kind == "return":
            if node.value is None:
                self.emit("RET", position)
            else:
                self.expression(node.value)
                self.emit("RETV", position)
        elif kind == "block":
            for child in node.statements:
                self.statement(child)


def assign_slots(function):
    declarations = []
    pending = [function.body]
    while pending:
        node = pending.pop()
        if node.kind == "declaration":
            declarations.append(node)
        pending.extend(statement_children(node))
    declarations.sort(key=lambda node: node.name_position)
    slots = function.parameters + declarations
    for index, declaration in enumerate(slots):
        declaration.slot = index
    return slots


def generate(globals_, functions, main):
    address = 0
    for variable in globals_:
        variable.address = address
        address += variable.size if variable.size is not None else 1
    initialization = Generator()
    for variable in globals_:
        if variable.initializer is not None:
            initialization.expression(variable.initializer)
            initialization.emit("STOREG", variable.name_position, variable.address)
    initialization.emit("CALL", main.name_position, "main", 0)
    initialization.emit("HALT", main.name_position)
    units = [Unit("<init>", None, [], initialization.finish())]
    for function in functions:
        slots = assign_slots(function)
        generator = Generator()
        generator.emit("ENTER", function.name_position, len(slots))
        generator.statement(function.body)
        if function.type == "void":
            generator.emit("RET", function.body.end_position)
        units.append(Unit(function.name, function, slots, generator.finish()))
    return units, address
