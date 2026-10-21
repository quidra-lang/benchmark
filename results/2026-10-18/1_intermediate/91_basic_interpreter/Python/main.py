import math
import operator
import re
import string
import sys
from dataclasses import dataclass
from itertools import takewhile
from typing import NamedTuple

RESERVED_WORDS = {
    'REM', 'LET', 'PRINT', 'INPUT', 'READ', 'DATA', 'IF', 'THEN', 'ELSE', 'GOTO', 'GOSUB',
    'RETURN', 'ON', 'ERROR', 'RESUME', 'FOR', 'TO', 'STEP', 'NEXT', 'WHILE', 'WEND', 'DIM',
    'RESTORE', 'RANDOMIZE', 'END', 'STOP', 'TAB', 'SPC', 'AND', 'OR', 'NOT', 'MOD', 'ERR', 'ERL',
}
# Allowed argument type signatures: I = integer, S = string.
FUNCTIONS = {
    'ABS': ('I',),
    'SGN': ('I',),
    'INT': ('I',),
    'SQR': ('I',),
    'RND': ('I',),
    'LEN': ('S',),
    'ASC': ('S',),
    'VAL': ('S',),
    'CHR$': ('I',),
    'STR$': ('I',),
    'LEFT$': ('SI',),
    'RIGHT$': ('SI',),
    'MID$': ('SI', 'SII'),
    'INSTR': ('SS',),
}
COMPARISONS = {
    '=': operator.eq,
    '<>': operator.ne,
    '<': operator.lt,
    '>': operator.gt,
    '<=': operator.le,
    '>=': operator.ge,
}
NON_CLAUSE_STATEMENTS = {'IF', 'FOR', 'NEXT', 'WHILE', 'WEND', 'DATA'}
ERROR_CODES = {
    'NEXT WITHOUT FOR': 1,
    'RETURN WITHOUT GOSUB': 3,
    'OUT OF DATA': 4,
    'ILLEGAL FUNCTION CALL': 5,
    'OVERFLOW': 6,
    'OUT OF MEMORY': 7,
    'UNDEFINED LINE NUMBER': 8,
    'SUBSCRIPT OUT OF RANGE': 9,
    'DUPLICATE DEFINITION': 10,
    'DIVISION BY ZERO': 11,
    'TYPE MISMATCH': 13,
    'STRING TOO LONG': 15,
    'RESUME WITHOUT ERROR': 20,
    'FOR WITHOUT NEXT': 26,
    'WHILE WITHOUT WEND': 29,
    'WEND WITHOUT WHILE': 30,
    'INPUT PAST END': 62,
}
VARIABLE_NAMES = [
    letter + digit + suffix
    for letter in string.ascii_uppercase
    for digit in ['', *string.digits]
    for suffix in ['', '$']
]

TOKEN_PATTERN = re.compile(
    r' *(?:(?P<rem>REM).*|"(?P<string>[^"]*)"|(?P<number>[0-9]+)'
    r'|(?P<word>[A-Z][A-Z0-9]*\$?)|(?P<symbol><>|<=|>=|[-+*/^=<>(),;:]))'
)
VARIABLE_PATTERN = re.compile(r'[A-Z][0-9]?\$?')
INTEGER_INPUT_PATTERN = re.compile(r'-?[0-9]+')
VAL_PATTERN = re.compile(r' *([+-]?)([0-9]*)')

MIN_INTEGER = -32768
MAX_INTEGER = 32767
MAX_STRING_LENGTH = 255
MAX_ARRAY_ELEMENTS = 10000
DEFAULT_UPPER_BOUND = 10
STACK_LIMIT = 100
PRINT_ZONE_WIDTH = 10


class BasicSyntaxError(Exception):
    pass


class BasicError(Exception):
    pass


class Token(NamedTuple):
    kind: str
    value: int | str | None


class Expression:
    pass


@dataclass
class Constant(Expression):
    value: int | str


@dataclass
class Variable(Expression):
    name: str


@dataclass
class ArrayElement(Expression):
    name: str
    subscripts: list


@dataclass
class ErrorValue(Expression):
    name: str


@dataclass
class FunctionCall(Expression):
    name: str
    arguments: list


@dataclass
class UnaryOp(Expression):
    operator: str
    operand: Expression


@dataclass
class BinaryOp(Expression):
    operator: str
    left: Expression
    right: Expression


@dataclass
class PrintFunction:
    name: str
    argument: Expression


class Statement:
    line = 0
    next = None


class Rem(Statement):
    pass


@dataclass
class Let(Statement):
    target: Expression
    expression: Expression


@dataclass
class Print(Statement):
    items: list


@dataclass
class Input(Statement):
    targets: list


@dataclass
class Read(Statement):
    targets: list


@dataclass
class Data(Statement):
    values: list


@dataclass
class If(Statement):
    condition: Expression
    then_clause: int | list
    else_clause: int | list | None


@dataclass
class Goto(Statement):
    target_line: int


@dataclass
class Gosub(Statement):
    target_line: int


class Return(Statement):
    pass


@dataclass
class OnJump(Statement):
    selector: Expression
    target_lines: list
    is_gosub: bool


@dataclass
class OnError(Statement):
    target_line: int


@dataclass
class Resume(Statement):
    target: int | str | None


@dataclass
class For(Statement):
    variable: str
    start: Expression
    limit: Expression
    step: Expression


@dataclass
class Next(Statement):
    variable: str | None


@dataclass
class While(Statement):
    condition: Expression


class Wend(Statement):
    pass


@dataclass
class Dim(Statement):
    arrays: list


@dataclass
class Restore(Statement):
    target_line: int | None


@dataclass
class Randomize(Statement):
    seed: Expression


class End(Statement):
    pass


class Stop(Statement):
    pass


@dataclass
class GosubFrame:
    return_position: Statement | None


@dataclass
class ForFrame:
    variable: str
    limit: int
    step: int
    loop_start: Statement | None


@dataclass
class WhileFrame:
    statement: While


def default_value(name):
    return '' if name.endswith('$') else 0


class Array:
    def __init__(self, name, bounds):
        self.bounds = bounds
        self.values = [default_value(name)] * math.prod(bound + 1 for bound in bounds)

    def index(self, subscripts):
        if len(subscripts) != len(self.bounds):
            raise BasicError('SUBSCRIPT OUT OF RANGE')
        index = 0
        for subscript, bound in zip(subscripts, self.bounds):
            if not 0 <= subscript <= bound:
                raise BasicError('SUBSCRIPT OUT OF RANGE')
            index = index * (bound + 1) + subscript
        return index


def tokenize(content):
    tokens = []
    position = 0
    while position < len(content):
        found = TOKEN_PATTERN.match(content, position)
        if found is None:
            raise BasicSyntaxError()
        kind = found.lastgroup
        value = found.group(kind)
        if kind == 'number':
            value = int(value)
            if value > MAX_INTEGER:
                raise BasicSyntaxError()
        elif kind == 'word' and VARIABLE_PATTERN.fullmatch(value):
            kind = 'variable'
        elif kind == 'word' and value not in RESERVED_WORDS and value not in FUNCTIONS:
            raise BasicSyntaxError()
        elif kind != 'string':
            kind = 'keyword'
        tokens.append(Token(kind, value))
        position = found.end()
    return tokens


def is_string(expression):
    match expression:
        case Constant(value):
            return isinstance(value, str)
        case Variable(name) | ArrayElement(name) | FunctionCall(name):
            return name.endswith('$')
        case BinaryOp('+', left):
            return is_string(left)
    return False


def require_integer(expression):
    if is_string(expression):
        raise BasicSyntaxError()
    return expression


def make_binary(symbol, left, right):
    if symbol == '+' or symbol in COMPARISONS:
        if is_string(left) != is_string(right):
            raise BasicSyntaxError()
    else:
        require_integer(left)
        require_integer(right)
    return BinaryOp(symbol, left, right)


class Parser:
    def __init__(self, tokens):
        self.tokens = [*tokens, Token('end', None)]
        self.position = 0

    def peek(self):
        return self.tokens[self.position]

    def advance(self):
        token = self.tokens[self.position]
        self.position += 1
        return token

    def at(self, *keywords):
        token = self.peek()
        return token.kind == 'keyword' and token.value in keywords

    def accept(self, keyword):
        if self.at(keyword):
            self.position += 1
            return True
        return False

    def expect(self, keyword):
        if not self.accept(keyword):
            raise BasicSyntaxError()

    def expect_end(self):
        if self.peek().kind != 'end':
            raise BasicSyntaxError()

    def at_statement_end(self):
        return self.peek().kind == 'end' or self.at(':', 'ELSE')

    def parse_list(self, parse_item, separator=','):
        items = [parse_item()]
        while self.accept(separator):
            items.append(parse_item())
        return items

    def parse_line(self):
        statements = self.parse_statements(in_clause=False)
        self.expect_end()
        return statements

    def parse_statements(self, in_clause):
        return self.parse_list(lambda: self.parse_statement(in_clause), ':')

    def parse_statement(self, in_clause):
        token = self.peek()
        if token.kind == 'variable':
            return self.parse_assignment()
        if token.kind != 'keyword' or in_clause and token.value in NON_CLAUSE_STATEMENTS:
            raise BasicSyntaxError()
        self.advance()
        match token.value:
            case 'REM':
                return Rem()
            case 'LET':
                return self.parse_assignment()
            case 'PRINT':
                return Print(self.parse_print_items())
            case 'INPUT':
                return Input(self.parse_list(self.parse_target))
            case 'READ':
                return Read(self.parse_list(self.parse_target))
            case 'DATA':
                return Data(self.parse_list(self.parse_data_item))
            case 'IF':
                return self.parse_if()
            case 'GOTO':
                return Goto(self.parse_line_number())
            case 'GOSUB':
                return Gosub(self.parse_line_number())
            case 'RETURN':
                return Return()
            case 'ON':
                return self.parse_on()
            case 'RESUME':
                if self.accept('NEXT'):
                    return Resume('NEXT')
                return Resume(self.parse_optional_line_number())
            case 'FOR':
                return self.parse_for()
            case 'NEXT':
                has_variable = self.peek().kind == 'variable'
                return Next(self.parse_integer_variable() if has_variable else None)
            case 'WHILE':
                return While(self.parse_integer_expression())
            case 'WEND':
                return Wend()
            case 'DIM':
                return Dim(self.parse_list(self.parse_array_declaration))
            case 'RESTORE':
                return Restore(self.parse_optional_line_number())
            case 'RANDOMIZE':
                return Randomize(self.parse_integer_expression())
            case 'END':
                return End()
            case 'STOP':
                return Stop()
        raise BasicSyntaxError()

    def parse_assignment(self):
        target = self.parse_target()
        self.expect('=')
        expression = self.parse_expression()
        if is_string(target) != is_string(expression):
            raise BasicSyntaxError()
        return Let(target, expression)

    def parse_print_items(self):
        items = []
        while not self.at_statement_end():
            if self.at(';', ','):
                items.append(self.advance().value)
            elif self.at('TAB', 'SPC'):
                name = self.advance().value
                self.expect('(')
                argument = self.parse_integer_expression()
                self.expect(')')
                items.append(PrintFunction(name, argument))
            elif items and isinstance(items[-1], Expression):
                raise BasicSyntaxError()
            else:
                items.append(self.parse_expression())
        return items

    def parse_data_item(self):
        negative = self.accept('-')
        token = self.advance()
        if token.kind == 'number':
            return -token.value if negative else token.value
        if token.kind == 'string' and not negative:
            return token.value
        raise BasicSyntaxError()

    def parse_if(self):
        condition = self.parse_integer_expression()
        self.expect('THEN')
        then_clause = self.parse_clause()
        else_clause = self.parse_clause() if self.accept('ELSE') else None
        self.expect_end()
        return If(condition, then_clause, else_clause)

    def parse_clause(self):
        if self.peek().kind == 'number':
            return self.advance().value
        return self.parse_statements(in_clause=True)

    def parse_on(self):
        if self.accept('ERROR'):
            self.expect('GOTO')
            return OnError(self.parse_line_number())
        selector = self.parse_integer_expression()
        if not self.at('GOTO', 'GOSUB'):
            raise BasicSyntaxError()
        is_gosub = self.advance().value == 'GOSUB'
        return OnJump(selector, self.parse_list(self.parse_line_number), is_gosub)

    def parse_for(self):
        variable = self.parse_integer_variable()
        self.expect('=')
        start = self.parse_integer_expression()
        self.expect('TO')
        limit = self.parse_integer_expression()
        step = self.parse_integer_expression() if self.accept('STEP') else Constant(1)
        return For(variable, start, limit, step)

    def parse_line_number(self):
        token = self.advance()
        if token.kind != 'number':
            raise BasicSyntaxError()
        return token.value

    def parse_optional_line_number(self):
        return self.advance().value if self.peek().kind == 'number' else None

    def parse_integer_variable(self):
        token = self.advance()
        if token.kind != 'variable' or token.value.endswith('$'):
            raise BasicSyntaxError()
        return token.value

    def parse_target(self):
        token = self.advance()
        if token.kind != 'variable':
            raise BasicSyntaxError()
        return self.parse_reference(token.value)

    def parse_reference(self, name):
        if not self.accept('('):
            return Variable(name)
        subscripts = self.parse_list(self.parse_integer_expression)
        self.expect(')')
        if len(subscripts) > 2:
            raise BasicSyntaxError()
        return ArrayElement(name, subscripts)

    def parse_array_declaration(self):
        declaration = self.parse_target()
        if not isinstance(declaration, ArrayElement):
            raise BasicSyntaxError()
        return declaration

    def parse_integer_expression(self):
        return require_integer(self.parse_expression())

    def parse_binary(self, operators, parse_operand):
        left = parse_operand()
        while self.at(*operators):
            symbol = self.advance().value
            left = make_binary(symbol, left, parse_operand())
        return left

    def parse_expression(self):
        return self.parse_binary(('OR',), self.parse_conjunction)

    def parse_conjunction(self):
        return self.parse_binary(('AND',), self.parse_negation)

    def parse_negation(self):
        if self.accept('NOT'):
            return UnaryOp('NOT', require_integer(self.parse_negation()))
        return self.parse_comparison()

    def parse_comparison(self):
        return self.parse_binary(COMPARISONS, self.parse_sum)

    def parse_sum(self):
        return self.parse_binary(('+', '-'), self.parse_product)

    def parse_product(self):
        return self.parse_binary(('*', '/', 'MOD'), self.parse_unary)

    def parse_unary(self):
        if self.accept('-'):
            return UnaryOp('-', require_integer(self.parse_unary()))
        return self.parse_power()

    def parse_power(self):
        base = self.parse_primary()
        if self.accept('^'):
            return make_binary('^', base, self.parse_unary())
        return base

    def parse_primary(self):
        token = self.advance()
        match token:
            case Token('number' | 'string', value):
                return Constant(value)
            case Token('variable', name):
                return self.parse_reference(name)
            case Token('keyword', 'ERR' | 'ERL'):
                return ErrorValue(token.value)
            case Token('keyword', '('):
                expression = self.parse_expression()
                self.expect(')')
                return expression
            case Token('keyword', name) if name in FUNCTIONS:
                return self.parse_function_call(name)
        raise BasicSyntaxError()

    def parse_function_call(self, name):
        self.expect('(')
        arguments = self.parse_list(self.parse_expression)
        self.expect(')')
        signature = ''.join('S' if is_string(argument) else 'I' for argument in arguments)
        if signature not in FUNCTIONS[name]:
            raise BasicSyntaxError()
        return FunctionCall(name, arguments)


def check_overflow(value):
    if not MIN_INTEGER <= value <= MAX_INTEGER:
        raise BasicError('OVERFLOW')
    return value


def truncated_quotient(dividend, divisor):
    quotient = abs(dividend) // abs(divisor)
    return quotient if (dividend < 0) == (divisor < 0) else -quotient


def apply_operator(symbol, left, right):
    match symbol:
        case '+' if isinstance(left, str):
            if len(left) + len(right) > MAX_STRING_LENGTH:
                raise BasicError('STRING TOO LONG')
            return left + right
        case '+':
            return check_overflow(left + right)
        case '-':
            return check_overflow(left - right)
        case '*':
            return check_overflow(left * right)
        case '/' | 'MOD' if right == 0:
            raise BasicError('DIVISION BY ZERO')
        case '/':
            return check_overflow(truncated_quotient(left, right))
        case 'MOD':
            return left - right * truncated_quotient(left, right)
        case '^':
            if right < 0:
                raise BasicError('ILLEGAL FUNCTION CALL')
            return check_overflow(left ** right)
        case 'AND':
            return left & right
        case 'OR':
            return left | right
    return -1 if COMPARISONS[symbol](left, right) else 0


def val(text):
    sign, digits = VAL_PATTERN.match(text).groups()
    if not digits:
        return 0
    value = int(digits)
    return check_overflow(-value if sign == '-' else value)


def link(statements, following):
    for statement, successor in zip(statements, [*statements[1:], following]):
        statement.next = successor
        if isinstance(statement, If):
            for clause in (statement.then_clause, statement.else_clause):
                if isinstance(clause, list):
                    for inner in clause:
                        inner.line = statement.line
                    link(clause, successor)


def find_matching(statement, opening, closing):
    depth = 0
    current = statement.next
    while current is not None:
        if isinstance(current, opening):
            depth += 1
        elif isinstance(current, closing):
            if depth == 0:
                return current
            depth -= 1
        current = current.next
    return None


def loop_finished(step, value, limit):
    return value > limit if step > 0 else value < limit


class Interpreter:
    def __init__(self, program, input_lines):
        self.line_starts = {number: statements[0] for number, statements in program.items()}
        self.data = []
        sequence = []
        for number, statements in program.items():
            for statement in statements:
                statement.line = number
                if isinstance(statement, Data):
                    self.data.extend((number, value) for value in statement.values)
            sequence.extend(statements)
        link(sequence, None)
        self.first_statement = sequence[0] if sequence else None
        self.variables = {name: default_value(name) for name in VARIABLE_NAMES}
        self.arrays = {}
        self.stack = []
        self.data_position = 0
        self.input_lines = iter(input_lines)
        self.random_state = 1
        self.handler_line = 0
        self.handling_error = False
        self.error_code = 0
        self.error_line = 0
        self.error_statement = None
        self.output = ''

    def run(self):
        statement = self.first_statement
        while statement is not None:
            try:
                statement = self.execute(statement)
            except BasicError as error:
                if self.handler_line == 0 or self.handling_error:
                    self.message(f'ERROR IN LINE {statement.line}: {error}')
                    break
                self.error_code = ERROR_CODES[str(error)]
                self.error_line = statement.line
                self.error_statement = statement
                self.handling_error = True
                statement = self.line_starts[self.handler_line]
        if self.output:
            self.end_line()

    def end_line(self):
        print(self.output.rstrip(' '))
        self.output = ''

    def message(self, text):
        if self.output:
            self.end_line()
        print(text)

    def check_line(self, line):
        if line not in self.line_starts:
            raise BasicError('UNDEFINED LINE NUMBER')

    def go_to(self, line):
        self.check_line(line)
        return self.line_starts[line]

    def gosub(self, target_line, return_position):
        target = self.go_to(target_line)
        self.push(GosubFrame(return_position))
        return target

    def push(self, frame):
        if len(self.stack) >= STACK_LIMIT:
            raise BasicError('OUT OF MEMORY')
        self.stack.append(frame)

    def find_frame(self, kind, variable=None):
        for index in reversed(range(len(self.stack))):
            frame = self.stack[index]
            if isinstance(frame, kind) and (variable is None or frame.variable == variable):
                return index
            if isinstance(frame, GosubFrame):
                return None
        return None

    def pop_frame(self, kind, error):
        index = self.find_frame(kind)
        if index is None:
            raise BasicError(error)
        frame = self.stack[index]
        del self.stack[index:]
        return frame

    def locate(self, target):
        if isinstance(target, Variable):
            return self.variables, target.name
        subscripts = [self.evaluate(subscript) for subscript in target.subscripts]
        if target.name not in self.arrays:
            bounds = [DEFAULT_UPPER_BOUND] * len(subscripts)
            self.arrays[target.name] = Array(target.name, bounds)
        array = self.arrays[target.name]
        return array.values, array.index(subscripts)

    def evaluate(self, expression):
        match expression:
            case Constant(value):
                return value
            case Variable() | ArrayElement():
                container, key = self.locate(expression)
                return container[key]
            case ErrorValue(name):
                return self.error_code if name == 'ERR' else self.error_line
            case FunctionCall(name, arguments):
                return self.call(name, [self.evaluate(argument) for argument in arguments])
            case UnaryOp('-', operand):
                return check_overflow(-self.evaluate(operand))
            case UnaryOp('NOT', operand):
                return ~self.evaluate(operand)
            case BinaryOp(symbol, left, right):
                return apply_operator(symbol, self.evaluate(left), self.evaluate(right))

    def call(self, name, arguments):
        match name, arguments:
            case 'ABS', [number]:
                return check_overflow(abs(number))
            case 'SGN', [number]:
                return (number > 0) - (number < 0)
            case 'INT', [number]:
                return number
            case 'SQR', [number]:
                if number < 0:
                    raise BasicError('ILLEGAL FUNCTION CALL')
                return math.isqrt(number)
            case 'RND', [limit]:
                if limit < 1:
                    raise BasicError('ILLEGAL FUNCTION CALL')
                self.random_state = 48271 * self.random_state % 2147483647
                return self.random_state % limit + 1
            case 'LEN', [text]:
                return len(text)
            case 'ASC', [text]:
                if not text:
                    raise BasicError('ILLEGAL FUNCTION CALL')
                return ord(text[0])
            case 'VAL', [text]:
                return val(text)
            case 'CHR$', [code]:
                if not 32 <= code <= 126:
                    raise BasicError('ILLEGAL FUNCTION CALL')
                return chr(code)
            case 'STR$', [number]:
                return str(number)
            case 'LEFT$', [text, count]:
                if count < 0:
                    raise BasicError('ILLEGAL FUNCTION CALL')
                return text[:count]
            case 'RIGHT$', [text, count]:
                if count < 0:
                    raise BasicError('ILLEGAL FUNCTION CALL')
                return text[max(len(text) - count, 0):]
            case 'MID$', [text, start, *length]:
                if start < 1 or length and length[0] < 0:
                    raise BasicError('ILLEGAL FUNCTION CALL')
                part = text[start - 1:]
                return part[:length[0]] if length else part
            case 'INSTR', [text, pattern]:
                return text.find(pattern) + 1

    def execute(self, statement):
        match statement:
            case Let(target, expression):
                container, key = self.locate(target)
                container[key] = self.evaluate(expression)
            case Print(items):
                self.print_items(items)
            case Input(targets):
                for target in targets:
                    self.read_input(target)
            case Read(targets):
                for target in targets:
                    self.read_data(target)
            case If(condition, then_clause, else_clause):
                clause = then_clause if self.evaluate(condition) != 0 else else_clause
                if isinstance(clause, int):
                    return self.go_to(clause)
                if clause is not None:
                    return clause[0]
            case Goto(target_line):
                return self.go_to(target_line)
            case Gosub(target_line):
                return self.gosub(target_line, statement.next)
            case Return():
                return self.pop_frame(GosubFrame, 'RETURN WITHOUT GOSUB').return_position
            case OnJump(selector, target_lines, is_gosub):
                choice = self.evaluate(selector)
                if choice < 0:
                    raise BasicError('ILLEGAL FUNCTION CALL')
                if 1 <= choice <= len(target_lines):
                    target_line = target_lines[choice - 1]
                    if is_gosub:
                        return self.gosub(target_line, statement.next)
                    return self.go_to(target_line)
            case OnError(target_line):
                if target_line != 0:
                    self.check_line(target_line)
                self.handler_line = target_line
            case Resume(target):
                return self.resume(target)
            case For():
                return self.start_loop(statement)
            case Next():
                return self.next_iteration(statement)
            case While(condition):
                if self.evaluate(condition) != 0:
                    self.push(WhileFrame(statement))
                else:
                    wend = find_matching(statement, While, Wend)
                    if wend is None:
                        raise BasicError('WHILE WITHOUT WEND')
                    return wend.next
            case Wend():
                return self.pop_frame(WhileFrame, 'WEND WITHOUT WHILE').statement
            case Dim(arrays):
                for declaration in arrays:
                    self.declare(declaration)
            case Restore(None):
                self.data_position = 0
            case Restore(target_line):
                self.check_line(target_line)
                self.data_position = next(
                    (index for index, (line, _) in enumerate(self.data) if line >= target_line),
                    len(self.data),
                )
            case Randomize(seed):
                value = self.evaluate(seed)
                if value < 1:
                    raise BasicError('ILLEGAL FUNCTION CALL')
                self.random_state = value
            case End():
                return None
            case Stop():
                self.message(f'BREAK IN LINE {statement.line}')
                return None
        return statement.next

    def print_items(self, items):
        for item in items:
            match item:
                case ';':
                    pass
                case ',':
                    self.output += ' ' * (PRINT_ZONE_WIDTH - len(self.output) % PRINT_ZONE_WIDTH)
                case PrintFunction(name, argument):
                    width = self.evaluate(argument)
                    if width < 0:
                        raise BasicError('ILLEGAL FUNCTION CALL')
                    if name == 'TAB':
                        self.output = self.output.ljust(width)
                    else:
                        self.output += ' ' * width
                case _:
                    self.output += str(self.evaluate(item))
        if not items or items[-1] not in (';', ','):
            self.end_line()

    def read_input(self, target):
        container, key = self.locate(target)
        while True:
            line = next(self.input_lines, None)
            if line is None:
                raise BasicError('INPUT PAST END')
            if is_string(target):
                container[key] = line
                return
            if INTEGER_INPUT_PATTERN.fullmatch(line) and MIN_INTEGER <= int(line) <= MAX_INTEGER:
                container[key] = int(line)
                return
            self.message('?REDO FROM START')

    def read_data(self, target):
        container, key = self.locate(target)
        if self.data_position == len(self.data):
            raise BasicError('OUT OF DATA')
        _, value = self.data[self.data_position]
        self.data_position += 1
        if isinstance(value, str) != is_string(target):
            raise BasicError('TYPE MISMATCH')
        container[key] = value

    def resume(self, target):
        if not self.handling_error:
            raise BasicError('RESUME WITHOUT ERROR')
        match target:
            case None:
                position = self.error_statement
            case 'NEXT':
                position = self.error_statement.next
            case line:
                position = self.go_to(line)
        self.handling_error = False
        return position

    def start_loop(self, statement):
        start = self.evaluate(statement.start)
        limit = self.evaluate(statement.limit)
        step = self.evaluate(statement.step)
        if step == 0:
            raise BasicError('ILLEGAL FUNCTION CALL')
        index = self.find_frame(ForFrame, statement.variable)
        if index is not None:
            del self.stack[index:]
        self.variables[statement.variable] = start
        if loop_finished(step, start, limit):
            matching = find_matching(statement, For, Next)
            if matching is None:
                raise BasicError('FOR WITHOUT NEXT')
            return matching.next
        self.push(ForFrame(statement.variable, limit, step, statement.next))
        return statement.next

    def next_iteration(self, statement):
        index = self.find_frame(ForFrame, statement.variable)
        if index is None:
            raise BasicError('NEXT WITHOUT FOR')
        del self.stack[index + 1:]
        frame = self.stack[index]
        value = check_overflow(self.variables[frame.variable] + frame.step)
        self.variables[frame.variable] = value
        if loop_finished(frame.step, value, frame.limit):
            self.stack.pop()
            return statement.next
        return frame.loop_start

    def declare(self, declaration):
        bounds = [self.evaluate(bound) for bound in declaration.subscripts]
        if declaration.name in self.arrays:
            raise BasicError('DUPLICATE DEFINITION')
        if any(bound < 0 for bound in bounds):
            raise BasicError('ILLEGAL FUNCTION CALL')
        if math.prod(bound + 1 for bound in bounds) > MAX_ARRAY_ELEMENTS:
            raise BasicError('OUT OF MEMORY')
        self.arrays[declaration.name] = Array(declaration.name, bounds)


def run_program(program, input_lines):
    parsed = {}
    for number, content in sorted(program.items()):
        try:
            parsed[number] = Parser(tokenize(content)).parse_line()
        except BasicSyntaxError:
            print(f'ERROR IN LINE {number}: SYNTAX ERROR')
            break
    else:
        Interpreter(parsed, input_lines).run()
    print('READY')


def main():
    sys.setrecursionlimit(10000)
    lines = iter(sys.stdin.read().splitlines())
    for _ in range(int(next(lines))):
        program = {}
        for line in takewhile(lambda line: line != 'RUN', lines):
            number, _, content = line.partition(' ')
            if content:
                program[int(number)] = content.lstrip(' ')
            else:
                program.pop(int(number), None)
        input_lines = list(takewhile(lambda line: line != 'END', lines))
        run_program(program, input_lines)


if __name__ == '__main__':
    main()
