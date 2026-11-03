import operator
import re
import sys
from itertools import groupby

NUMBER = "number"
VARIABLE = "variable"
QUOTED = "quoted"
WORD = "word"
SYMBOL = "symbol"
SIGN_MINUS = "sign minus"

NAME_PATTERN = re.compile(r"[A-Z][A-Z0-9_]*")
DELIMITERS = " []()+-*/=<>"

COMMANDS = {
    "FD": "E", "BK": "E", "RT": "E", "LT": "E", "SETH": "E",
    "PU": "", "PD": "", "PE": "", "SETPEN": "E",
    "SETXY": "EE", "SETX": "E", "SETY": "E", "HOME": "", "CS": "", "CLEAN": "",
    "FILL": "", "LABEL": "P", "SNAPSHOT": "",
    "REPEAT": "EL", "FOR": "QEEL", "WHILE": "EL", "IF": "EL", "IFELSE": "ELL",
    "TEST": "E", "IFTRUE": "L", "IFFALSE": "L", "STOP": "", "OUTPUT": "E",
    "MAKE": "QE", "LOCAL": "Q", "LOCALMAKE": "QE", "TRACE": "Q", "UNTRACE": "Q",
    "SEED": "E", "PRINT": "P",
}
FUNCTIONS = {
    "XCOR": 0, "YCOR": 0, "HEADING": 0, "REPCOUNT": 0, "RANDOM": 1, "ABS": 1,
    "NOT": 1, "AND": 2, "OR": 2, "MAX": 2, "MIN": 2,
}
ALIASES = {
    "FORWARD": "FD", "BACK": "BK", "RIGHT": "RT", "LEFT": "LT", "SETHEADING": "SETH",
    "PENUP": "PU", "PENDOWN": "PD", "PENERASE": "PE", "CLEARSCREEN": "CS",
    "IFT": "IFTRUE", "IFF": "IFFALSE", "OP": "OUTPUT", "PR": "PRINT",
}
PRIMITIVES = set(COMMANDS) | set(FUNCTIONS) | set(ALIASES) | {"TO", "END", "MOD"}
PROCEDURE_ONLY = {"STOP", "OUTPUT", "LOCAL", "LOCALMAKE"}

OPERATOR_LEVELS = (("=", "<>", "<", ">", "<=", ">="), ("+", "-"), ("*", "/", "MOD"))
OPERATIONS = {
    "+": operator.add, "-": operator.sub, "*": operator.mul,
    "=": operator.eq, "<>": operator.ne, "<": operator.lt,
    ">": operator.gt, "<=": operator.le, ">=": operator.ge,
}

DIRECTIONS = {
    0: (0, 1), 45: (1, 1), 90: (1, 0), 135: (1, -1),
    180: (0, -1), 225: (-1, -1), 270: (-1, 0), 315: (-1, 1),
}
PEN_STATES = {"PU": "UP", "PD": "DOWN", "PE": "ERASE"}
MAX_CALL_DEPTH = 100
RANDOM_MULTIPLIER = 48271
RANDOM_MODULUS = 2147483647


class LogoError(Exception):
    def __init__(self, line, reason):
        super().__init__(f"ERROR line {line}: {reason}")


class ProcedureExit(Exception):
    def __init__(self, value=None):
        super().__init__()
        self.value = value


class Token:
    def __init__(self, kind, spelling, line, value=None):
        self.kind = kind
        self.spelling = spelling
        self.line = line
        self.value = value


class Procedure:
    def __init__(self, name, parameters, line):
        self.name = name
        self.parameters = parameters
        self.line = line
        self.tokens = []
        self.body = []


class Number:
    def __init__(self, value):
        self.value = value


class Variable:
    def __init__(self, name, line):
        self.name = name
        self.line = line


class Negation:
    def __init__(self, operand):
        self.operand = operand


class BinaryOperation:
    def __init__(self, operator, left, right, line):
        self.operator = operator
        self.left = left
        self.right = right
        self.line = line


class Call:
    def __init__(self, name, spelling, line, inputs):
        self.name = name
        self.spelling = spelling
        self.line = line
        self.inputs = inputs


class Environment:
    def __init__(self, procedure, variables):
        self.procedure = procedure
        self.variables = variables
        self.test = None


def rejection(line, owner, value):
    return LogoError(line, f"{owner} doesn't like {value} as input")


def truncated_divide(dividend, divisor):
    quotient = abs(dividend) // abs(divisor)
    return quotient if (dividend < 0) == (divisor < 0) else -quotient


def classify(lexeme, line):
    if lexeme.isdigit():
        return Token(NUMBER, lexeme, line, int(lexeme))
    if NAME_PATTERN.fullmatch(lexeme):
        return Token(WORD, lexeme, line)
    if lexeme[0] in ':"' and NAME_PATTERN.fullmatch(lexeme[1:]):
        return Token(VARIABLE if lexeme[0] == ":" else QUOTED, lexeme, line, lexeme[1:])
    raise LogoError(line, f"bad token '{lexeme}'")


def tokenize(text, line):
    text = text.partition(";")[0].upper()
    tokens = []
    index = 0
    while index < len(text):
        char = text[index]
        following = text[index + 1:index + 2]
        if char == " ":
            index += 1
        elif char == "-":
            starts_term = index == 0 or text[index - 1] in " [("
            is_sign = starts_term and following not in ("", " ")
            tokens.append(Token(SIGN_MINUS if is_sign else SYMBOL, char, line))
            index += 1
        elif char in "<>":
            pair = char + following
            spelling = pair if pair in ("<=", "<>", ">=") else char
            tokens.append(Token(SYMBOL, spelling, line))
            index += len(spelling)
        elif char in DELIMITERS:
            tokens.append(Token(SYMBOL, char, line))
            index += 1
        else:
            end = index
            while end < len(text) and text[end] not in DELIMITERS:
                end += 1
            tokens.append(classify(text[index:end], line))
            index = end
    return tokens


def is_word(token, spelling):
    return token.kind == WORD and token.spelling == spelling


def parse_header(tokens, procedures, line):
    if len(tokens) < 2 or tokens[1].kind != WORD:
        raise LogoError(line, "bad procedure header")
    name = tokens[1].spelling
    if name in PRIMITIVES:
        raise LogoError(line, f"{name} is a primitive")
    if name in procedures:
        raise LogoError(line, f"{name} is already defined")
    parameters = []
    for token in tokens[2:]:
        if token.kind != VARIABLE:
            raise LogoError(line, "bad procedure header")
        if token.value in parameters:
            raise LogoError(line, f"duplicate input {token.spelling}")
        parameters.append(token.value)
    return Procedure(name, parameters, line)


def extract_procedures(source_lines):
    procedures = {}
    top_level = []
    current = None
    for line, text in source_lines:
        tokens = tokenize(text, line)
        if not tokens:
            continue
        if is_word(tokens[0], "TO"):
            if current is not None:
                raise LogoError(line, f"TO inside definition of {current.name}")
            current = parse_header(tokens, procedures, line)
            procedures[current.name] = current
        elif len(tokens) == 1 and is_word(tokens[0], "END"):
            if current is None:
                raise LogoError(line, "END without TO")
            current = None
        elif current is not None:
            current.tokens.extend(tokens)
        else:
            top_level.extend(tokens)
    if current is not None:
        raise LogoError(current.line, f"missing END for {current.name}")
    return procedures, top_level


class Parser:
    def __init__(self, tokens, procedures, in_procedure):
        self.tokens = tokens
        self.procedures = procedures
        self.in_procedure = in_procedure
        self.position = 0

    def peek(self):
        if self.position < len(self.tokens):
            return self.tokens[self.position]
        return None

    def advance(self):
        token = self.tokens[self.position]
        self.position += 1
        return token

    def next_is(self, spellings):
        token = self.peek()
        return token is not None and token.kind != SIGN_MINUS and token.spelling in spellings

    def is_unknown(self, token):
        return (
            token.kind == WORD
            and token.spelling not in PRIMITIVES
            and token.spelling not in self.procedures
        )

    def parse_sequence(self):
        commands = []
        while (token := self.peek()) is not None:
            if token.spelling == "]":
                raise LogoError(token.line, "unexpected ]")
            commands.append(self.parse_command())
        return commands

    def parse_list(self):
        bracket = self.advance()
        commands = []
        while not self.next_is(("]",)):
            if self.peek() is None:
                raise LogoError(bracket.line, "missing ]")
            commands.append(self.parse_command())
        self.advance()
        return commands

    def parse_command(self):
        token = self.advance()
        if token.spelling == "(" and self.next_is(("PRINT", "PR")):
            return self.parse_multi_print(token)
        if token.kind == WORD:
            name = ALIASES.get(token.spelling, token.spelling)
            if name in ("TO", "END"):
                raise LogoError(token.line, f"misplaced {name}")
            if name in COMMANDS:
                return self.parse_primitive_command(token, name)
            if name in self.procedures:
                return self.parse_call(token, len(self.procedures[name].parameters))
            if self.is_unknown(token):
                raise LogoError(token.line, f"I don't know how to {name}")
        raise LogoError(token.line, f"you don't say what to do with {token.spelling}")

    def parse_multi_print(self, parenthesis):
        word = self.advance()
        items = []
        while not self.next_is((")",)):
            if self.peek() is None or self.next_is(("]",)):
                raise LogoError(parenthesis.line, "missing )")
            items.append(self.parse_input(word, "P"))
        self.advance()
        return Call("PRINT", word.spelling, parenthesis.line, items)

    def parse_primitive_command(self, token, name):
        if name in PROCEDURE_ONLY and not self.in_procedure:
            raise LogoError(token.line, f"can only use {token.spelling} inside a procedure")
        inputs = [self.parse_input(token, kind) for kind in COMMANDS[name]]
        if name in ("TRACE", "UNTRACE") and inputs[0].value not in self.procedures:
            raise LogoError(inputs[0].line, f"I don't know how to {inputs[0].value}")
        return Call(name, token.spelling, token.line, inputs)

    def parse_call(self, token, count):
        inputs = [self.parse_expression(token) for _ in range(count)]
        return Call(token.spelling, token.spelling, token.line, inputs)

    def check_input(self, owner):
        token = self.peek()
        if token is None or token.spelling in ("]", ")"):
            raise LogoError(owner.line, f"not enough inputs to {owner.spelling}")
        if self.is_unknown(token):
            raise LogoError(token.line, f"I don't know how to {token.spelling}")
        return token

    def parse_input(self, owner, kind):
        token = self.check_input(owner)
        match kind:
            case "L" if token.spelling == "[":
                return self.parse_list()
            case "Q" | "P" if token.kind == QUOTED:
                return self.advance()
            case "E" | "P":
                return self.parse_expression(owner)
        raise rejection(token.line, owner.spelling, token.spelling)

    def parse_expression(self, owner, level=0):
        if level == len(OPERATOR_LEVELS):
            return self.parse_term(owner)
        left = self.parse_expression(owner, level + 1)
        while self.next_is(OPERATOR_LEVELS[level]):
            operator_token = self.advance()
            right = self.parse_expression(operator_token, level + 1)
            left = BinaryOperation(operator_token.spelling, left, right, operator_token.line)
        return left

    def parse_term(self, owner):
        token = self.check_input(owner)
        self.advance()
        if token.kind == NUMBER:
            return Number(token.value)
        if token.kind == VARIABLE:
            return Variable(token.value, token.line)
        if token.spelling == "-":
            return Negation(self.parse_term(token))
        if token.spelling == "(":
            expression = self.parse_expression(token)
            if not self.next_is((")",)):
                raise LogoError(token.line, "missing )")
            self.advance()
            return expression
        if token.spelling in FUNCTIONS:
            return self.parse_call(token, FUNCTIONS[token.spelling])
        if token.spelling in self.procedures:
            return self.parse_call(token, len(self.procedures[token.spelling].parameters))
        raise rejection(token.line, owner.spelling, token.spelling)


class Interpreter:
    def __init__(self, procedures, output):
        self.procedures = procedures
        self.output = output
        self.x = 0
        self.y = 0
        self.heading = 0
        self.pen = "DOWN"
        self.pen_char = "*"
        self.canvas = {}
        self.environments = [Environment(None, {})]
        self.repcounts = []
        self.traced = set()
        self.random_state = 1

    def run_list(self, commands):
        for command in commands:
            self.execute(command)

    def execute(self, command):
        if command.name in self.procedures:
            value = self.call_procedure(command)
            if value is not None:
                raise LogoError(command.line, f"you don't say what to do with {value}")
            return
        inputs = command.inputs
        match command.name:
            case "FD":
                self.forward(self.evaluate(inputs[0]))
            case "BK":
                self.forward(-self.evaluate(inputs[0]))
            case "RT":
                self.heading = (self.heading + self.angle_input(command)) % 360
            case "LT":
                self.heading = (self.heading - self.angle_input(command)) % 360
            case "SETH":
                self.heading = self.angle_input(command) % 360
            case "PU" | "PD" | "PE":
                self.pen = PEN_STATES[command.name]
            case "SETPEN":
                code = self.evaluate(inputs[0])
                if not 33 <= code <= 126:
                    raise rejection(command.line, command.spelling, code)
                self.pen_char = chr(code)
            case "SETXY":
                x = self.evaluate(inputs[0])
                y = self.evaluate(inputs[1])
                self.move_to(x, y)
            case "SETX":
                x = self.evaluate(inputs[0])
                self.move_to(x, self.y)
            case "SETY":
                y = self.evaluate(inputs[0])
                self.move_to(self.x, y)
            case "HOME":
                self.move_to(0, 0)
                self.heading = 0
            case "CS":
                self.canvas.clear()
                self.x = self.y = self.heading = 0
            case "CLEAN":
                self.canvas.clear()
            case "FILL":
                self.fill()
            case "LABEL":
                self.label(self.print_string(inputs[0]))
            case "SNAPSHOT":
                self.write_canvas()
            case "REPEAT":
                self.repeat(self.evaluate(inputs[0]), inputs[1])
            case "FOR":
                self.for_loop(inputs[0].value, inputs[1], inputs[2], inputs[3])
            case "WHILE":
                while self.evaluate(inputs[0]) != 0:
                    self.run_list(inputs[1])
            case "IF":
                if self.evaluate(inputs[0]) != 0:
                    self.run_list(inputs[1])
            case "IFELSE":
                condition = self.evaluate(inputs[0])
                self.run_list(inputs[1] if condition != 0 else inputs[2])
            case "TEST":
                self.environments[-1].test = self.evaluate(inputs[0]) != 0
            case "IFTRUE" | "IFFALSE":
                test = self.environments[-1].test
                if test is None:
                    raise LogoError(command.line, f"{command.spelling} without TEST")
                if test == (command.name == "IFTRUE"):
                    self.run_list(inputs[0])
            case "STOP":
                raise ProcedureExit()
            case "OUTPUT":
                raise ProcedureExit(self.evaluate(inputs[0]))
            case "MAKE":
                self.make(inputs[0].value, self.evaluate(inputs[1]))
            case "LOCAL":
                self.environments[-1].variables[inputs[0].value] = 0
            case "LOCALMAKE":
                value = self.evaluate(inputs[1])
                self.environments[-1].variables[inputs[0].value] = value
            case "TRACE":
                self.traced.add(inputs[0].value)
            case "UNTRACE":
                self.traced.discard(inputs[0].value)
            case "SEED":
                seed = self.evaluate(inputs[0])
                if seed < 1:
                    raise rejection(command.line, command.spelling, seed)
                self.random_state = seed
            case "PRINT":
                self.output.append(" ".join([self.print_string(item) for item in inputs]))

    def angle_input(self, command):
        angle = self.evaluate(command.inputs[0])
        if angle % 45 != 0:
            raise rejection(command.line, command.spelling, angle)
        return angle

    def repeat(self, count, commands):
        for number in range(1, count + 1):
            self.repcounts.append(number)
            try:
                self.run_list(commands)
            finally:
                self.repcounts.pop()

    def for_loop(self, name, start_expression, end_expression, commands):
        start = self.evaluate(start_expression)
        end = self.evaluate(end_expression)
        step = 1 if start <= end else -1
        for value in range(start, end + step, step):
            self.make(name, value)
            self.run_list(commands)

    def print_string(self, item):
        if isinstance(item, Token):
            return item.value
        return str(self.evaluate(item))

    def lookup(self, variable):
        for environment in reversed(self.environments):
            if variable.name in environment.variables:
                return environment.variables[variable.name]
        raise LogoError(variable.line, f"{variable.name} has no value")

    def make(self, name, value):
        target = next(
            (env for env in reversed(self.environments) if name in env.variables),
            self.environments[0],
        )
        target.variables[name] = value

    def call_procedure(self, call):
        procedure = self.procedures[call.name]
        values = [self.evaluate(argument) for argument in call.inputs]
        depth = len(self.environments) - 1
        if depth >= MAX_CALL_DEPTH:
            raise LogoError(call.line, "recursion too deep")
        traced = procedure.name in self.traced
        indent = "  " * depth
        if traced:
            words = " ".join([procedure.name, *map(str, values)])
            self.output.append(f"{indent}( {words} )")
        variables = dict(zip(procedure.parameters, values))
        self.environments.append(Environment(procedure.name, variables))
        result = None
        try:
            self.run_list(procedure.body)
        except ProcedureExit as exit_signal:
            result = exit_signal.value
        self.environments.pop()
        if traced:
            outcome = "stops" if result is None else f"outputs {result}"
            self.output.append(f"{indent}{procedure.name} {outcome}")
        return result

    def evaluate(self, node):
        match node:
            case Number():
                return node.value
            case Variable():
                return self.lookup(node)
            case Negation():
                return -self.evaluate(node.operand)
            case BinaryOperation():
                left = self.evaluate(node.left)
                right = self.evaluate(node.right)
                return self.apply_operator(node, left, right)
            case Call() if node.name in self.procedures:
                value = self.call_procedure(node)
                if value is None:
                    raise LogoError(node.line, f"{node.name} did not output")
                return value
            case Call():
                arguments = [self.evaluate(argument) for argument in node.inputs]
                return self.call_function(node, arguments)

    def apply_operator(self, node, left, right):
        if node.operator in ("/", "MOD"):
            if right == 0:
                raise rejection(node.line, node.operator, 0)
            quotient = truncated_divide(left, right)
            return quotient if node.operator == "/" else left - right * quotient
        return int(OPERATIONS[node.operator](left, right))

    def call_function(self, call, arguments):
        match call.name:
            case "XCOR":
                return self.x
            case "YCOR":
                return self.y
            case "HEADING":
                return self.heading
            case "REPCOUNT":
                if not self.repcounts:
                    raise LogoError(call.line, "REPCOUNT outside REPEAT")
                return self.repcounts[-1]
            case "RANDOM":
                limit = arguments[0]
                if limit < 1:
                    raise rejection(call.line, call.spelling, limit)
                self.random_state = RANDOM_MULTIPLIER * self.random_state % RANDOM_MODULUS
                return self.random_state % limit
            case "ABS":
                return abs(arguments[0])
            case "NOT":
                return int(arguments[0] == 0)
            case "AND":
                return int(arguments[0] != 0 and arguments[1] != 0)
            case "OR":
                return int(arguments[0] != 0 or arguments[1] != 0)
            case "MAX":
                return max(arguments)
            case "MIN":
                return min(arguments)

    def apply_pen(self, x, y):
        if self.pen == "DOWN":
            self.canvas[(x, y)] = self.pen_char
        elif self.pen == "ERASE":
            self.canvas.pop((x, y), None)

    def forward(self, steps):
        dx, dy = DIRECTIONS[self.heading]
        if steps < 0:
            dx, dy, steps = -dx, -dy, -steps
        self.apply_pen(self.x, self.y)
        for _ in range(steps):
            self.x += dx
            self.y += dy
            self.apply_pen(self.x, self.y)

    def move_to(self, x, y):
        dx = x - self.x
        dy = y - self.y
        steps = max(abs(dx), abs(dy))
        if steps == 0:
            self.apply_pen(self.x, self.y)
        else:
            for i in range(steps + 1):
                cell_x = self.x + (2 * i * dx + steps) // (2 * steps)
                cell_y = self.y + (2 * i * dy + steps) // (2 * steps)
                self.apply_pen(cell_x, cell_y)
        self.x = x
        self.y = y

    def bounds(self):
        xs = [x for x, _ in self.canvas]
        ys = [y for _, y in self.canvas]
        return min(xs), max(xs), min(ys), max(ys)

    def fill(self):
        start = (self.x, self.y)
        if not self.canvas or start in self.canvas:
            return
        min_x, max_x, min_y, max_y = self.bounds()
        if not (min_x <= self.x <= max_x and min_y <= self.y <= max_y):
            return
        self.canvas[start] = self.pen_char
        pending = [start]
        while pending:
            x, y = pending.pop()
            for cell in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                inside = min_x <= cell[0] <= max_x and min_y <= cell[1] <= max_y
                if inside and cell not in self.canvas:
                    self.canvas[cell] = self.pen_char
                    pending.append(cell)

    def label(self, text):
        dx, dy = DIRECTIONS[self.heading]
        for offset, char in enumerate(text):
            self.canvas[(self.x + offset * dx, self.y + offset * dy)] = char

    def write_canvas(self):
        if not self.canvas:
            self.output.append("CANVAS 0 0 0")
            return
        min_x, max_x, min_y, max_y = self.bounds()
        width = max_x - min_x + 1
        height = max_y - min_y + 1
        self.output.append(f"CANVAS {width} {height} {len(self.canvas)}")
        for y in range(max_y, min_y - 1, -1):
            row = "".join(self.canvas.get((x, y), " ") for x in range(min_x, max_x + 1))
            self.output.append(row.rstrip(" "))

    def write_state(self):
        self.output.append(
            f"TURTLE {self.x} {self.y} {self.heading} {self.pen} {self.pen_char}"
        )
        self.write_canvas()

    def active_calls(self):
        names = [environment.procedure for environment in reversed(self.environments[1:])]
        lines = []
        for name, group in groupby(names):
            count = len(list(group))
            lines.append(f"  in {name}" if count == 1 else f"  in {name} x{count}")
        return lines


def run_program(name, source_lines, output):
    output.append(f"PROGRAM {name}")
    try:
        procedures, top_level = extract_procedures(source_lines)
        for procedure in procedures.values():
            procedure.body = Parser(procedure.tokens, procedures, True).parse_sequence()
        commands = Parser(top_level, procedures, False).parse_sequence()
    except LogoError as error:
        output.append(str(error))
        return
    interpreter = Interpreter(procedures, output)
    try:
        interpreter.run_list(commands)
    except LogoError as error:
        output.append(str(error))
        output.extend(interpreter.active_calls())
    else:
        interpreter.write_state()


def read_programs(lines):
    programs = []
    for number, line in enumerate(lines, start=1):
        if line == "#EOF":
            break
        if line.startswith("#PROGRAM "):
            programs.append((line.removeprefix("#PROGRAM "), []))
        else:
            programs[-1][1].append((number, line))
    return programs


def main():
    sys.setrecursionlimit(20000)
    output = []
    for name, source_lines in read_programs(sys.stdin.read().splitlines()):
        run_program(name, source_lines, output)
    sys.stdout.write("\n".join(output) + "\n")


if __name__ == "__main__":
    main()
