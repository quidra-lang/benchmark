import math
import operator
import re
import sys


DELIMITERS = " ()'\";"
INTEGER_PATTERN = re.compile(r"[+-]?[0-9]+")
STRING_ESCAPES = {'"': '"', "\\": "\\", "n": "\n"}
END_OF_INPUT = "unexpected end of input"

NIL = object()
VOID = object()
UNINITIALIZED = object()


class LispError(Exception):
    pass


class ReadError(Exception):
    pass


class ArgumentError(Exception):
    pass


class Symbol:
    def __init__(self, name):
        self.name = name


SYMBOLS = {}


def intern(name):
    if name not in SYMBOLS:
        SYMBOLS[name] = Symbol(name)
    return SYMBOLS[name]


QUOTE = intern("quote")
ELSE = intern("else")


class Pair:
    def __init__(self, car, cdr):
        self.car = car
        self.cdr = cdr


class Procedure:
    def call(self, args):
        count = len(args)
        if count < self.min_args or (self.max_args is not None and count > self.max_args):
            if self.max_args is None:
                expected = f"at least {self.min_args}"
            else:
                expected = str(self.min_args)
            raise LispError(
                f"{self.name or 'lambda'}: wrong number of arguments "
                f"(expected {expected}, got {count})"
            )
        return self.invoke(args)


class Builtin(Procedure):
    def __init__(self, name, min_args, max_args, function):
        self.name = name
        self.min_args = min_args
        self.max_args = max_args
        self.function = function

    def invoke(self, args):
        try:
            return self.function(args)
        except ArgumentError as error:
            raise LispError(f"{self.name}: {error}") from None


class Closure(Procedure):
    def __init__(self, params, rest, body, env, name=None):
        self.params = params
        self.rest = rest
        self.body = body
        self.env = env
        self.name = name
        self.min_args = len(params)
        self.max_args = None if rest is not None else len(params)

    def invoke(self, args):
        scope = Environment(self.env)
        for param, arg in zip(self.params, args):
            scope.define(param, arg)
        if self.rest is not None:
            scope.define(self.rest, make_list(args[len(self.params):]))
        return evaluate_body(self.body, scope)


class Environment:
    def __init__(self, parent=None):
        self.frame = {}
        self.parent = parent

    def find(self, symbol):
        env = self
        while env is not None:
            if symbol in env.frame:
                return env
            env = env.parent
        raise LispError(f"unbound variable: {symbol.name}")

    def lookup(self, symbol):
        value = self.find(symbol).frame[symbol]
        if value is UNINITIALIZED:
            raise LispError(f"uninitialized variable: {symbol.name}")
        return value

    def define(self, symbol, value):
        self.frame[symbol] = value

    def assign(self, symbol, value):
        self.find(symbol).frame[symbol] = value


def is_integer(value):
    return type(value) is int


def is_list(value):
    while isinstance(value, Pair):
        value = value.cdr
    return value is NIL


def list_items(value):
    items = []
    while isinstance(value, Pair):
        items.append(value.car)
        value = value.cdr
    return items if value is NIL else None


def make_list(items, tail=NIL):
    result = tail
    for item in reversed(items):
        result = Pair(item, result)
    return result


def all_distinct(symbols):
    return len(set(symbols)) == len(symbols)


def represent(value, quote_strings=True):
    if value is True:
        return "#t"
    if value is False:
        return "#f"
    if is_integer(value):
        return str(value)
    if isinstance(value, str):
        if not quote_strings:
            return value
        escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
        return f'"{escaped}"'
    if isinstance(value, Symbol):
        return value.name
    if isinstance(value, Pair):
        parts = []
        while isinstance(value, Pair):
            parts.append(represent(value.car, quote_strings))
            value = value.cdr
        if value is not NIL:
            parts += [".", represent(value, quote_strings)]
        return "(" + " ".join(parts) + ")"
    if isinstance(value, Procedure):
        return f"#<procedure {value.name}>" if value.name else "#<procedure>"
    if value is NIL:
        return "()"
    return "#<void>"


def is_eq(a, b):
    if (is_integer(a) and is_integer(b)) or (isinstance(a, str) and isinstance(b, str)):
        return a == b
    return a is b


def is_equal(a, b):
    if isinstance(a, Pair) and isinstance(b, Pair):
        return is_equal(a.car, b.car) and is_equal(a.cdr, b.cdr)
    return is_eq(a, b)


def parse_atom(atom):
    if atom == ".":
        return ".", None
    if INTEGER_PATTERN.fullmatch(atom):
        return "datum", int(atom)
    if atom == "#t":
        return "datum", True
    if atom == "#f":
        return "datum", False
    if atom.startswith("#"):
        raise ReadError(f"bad token: {atom}")
    return "datum", intern(atom)


class Reader:
    def __init__(self, lines):
        self.lines = lines
        self.row = 0
        self.column = 0

    def at_end(self):
        while self.row < len(self.lines):
            line = self.lines[self.row]
            while self.column < len(line) and line[self.column] == " ":
                self.column += 1
            if self.column < len(line) and line[self.column] != ";":
                return False
            self.skip_line()
        return True

    def skip_line(self):
        self.row += 1
        self.column = 0

    def next_token(self):
        if self.at_end():
            raise ReadError(END_OF_INPUT)
        line = self.lines[self.row]
        start = self.column
        char = line[start]
        if char in "()'":
            self.column += 1
            return char, None
        if char == '"':
            return "datum", self.read_string(line)
        while self.column < len(line) and line[self.column] not in DELIMITERS:
            self.column += 1
        return parse_atom(line[start:self.column])

    def read_string(self, line):
        chars = []
        index = self.column + 1
        while index < len(line):
            char = line[index]
            if char == '"':
                self.column = index + 1
                return "".join(chars)
            if char == "\\":
                if index + 1 == len(line):
                    break
                escaped = line[index + 1]
                if escaped not in STRING_ESCAPES:
                    raise ReadError("bad escape")
                chars.append(STRING_ESCAPES[escaped])
                index += 2
            else:
                chars.append(char)
                index += 1
        raise ReadError("unterminated string")

    def read_datum(self):
        return self.datum_from(self.next_token())

    def datum_from(self, token):
        kind, value = token
        if kind == "datum":
            return value
        if kind == "(":
            return self.read_list()
        if kind == "'":
            return make_list([QUOTE, self.read_datum()])
        if kind == ")":
            raise ReadError("unexpected )")
        raise ReadError("unexpected .")

    def read_list(self):
        items = []
        while True:
            token = self.next_token()
            kind = token[0]
            if kind == ")":
                return make_list(items)
            if kind == "." and items:
                tail = self.read_datum()
                if self.next_token()[0] != ")":
                    raise ReadError("expected )")
                return make_list(items, tail)
            items.append(self.datum_from(token))


def require_shape(valid, form):
    if not valid:
        raise LispError(f"bad syntax: {represent(form)}")


def evaluate(expr, env):
    if isinstance(expr, Symbol):
        return env.lookup(expr)
    if not isinstance(expr, Pair):
        require_shape(expr is not NIL, expr)
        return expr
    items = list_items(expr)
    require_shape(items is not None, expr)
    head = items[0]
    if isinstance(head, Symbol) and head.name in SPECIAL_FORMS:
        return SPECIAL_FORMS[head.name](items, expr, env)
    procedure = evaluate(head, env)
    args = [evaluate(item, env) for item in items[1:]]
    if not isinstance(procedure, Procedure):
        raise LispError(f"not a procedure: {represent(procedure)}")
    return procedure.call(args)


def evaluate_body(body, env):
    value = VOID
    for expr in body:
        value = evaluate(expr, env)
    return value


def parse_parameters(formals):
    params = []
    while isinstance(formals, Pair):
        if not isinstance(formals.car, Symbol):
            return None
        params.append(formals.car)
        formals = formals.cdr
    if isinstance(formals, Symbol):
        rest = formals
    elif formals is NIL:
        rest = None
    else:
        return None
    if not all_distinct(params if rest is None else params + [rest]):
        return None
    return params, rest


def parse_bindings(value, unique=True):
    entries = list_items(value)
    if entries is None:
        return None
    bindings = []
    for entry in entries:
        parts = list_items(entry)
        if parts is None or len(parts) != 2 or not isinstance(parts[0], Symbol):
            return None
        bindings.append((parts[0], parts[1]))
    if unique and not all_distinct([name for name, _ in bindings]):
        return None
    return bindings


def eval_quote(items, form, env):
    require_shape(len(items) == 2, form)
    return items[1]


def eval_if(items, form, env):
    require_shape(len(items) in (3, 4), form)
    if evaluate(items[1], env) is not False:
        return evaluate(items[2], env)
    return evaluate(items[3], env) if len(items) == 4 else VOID


def eval_define(items, form, env):
    target = items[1] if len(items) > 1 else NIL
    if isinstance(target, Symbol):
        require_shape(len(items) == 3, form)
        value = evaluate(items[2], env)
        if isinstance(value, Closure) and value.name is None:
            value.name = target.name
        env.define(target, value)
        return VOID
    valid = isinstance(target, Pair) and isinstance(target.car, Symbol) and len(items) >= 3
    parameters = parse_parameters(target.cdr) if valid else None
    require_shape(parameters is not None, form)
    env.define(target.car, Closure(*parameters, items[2:], env, target.car.name))
    return VOID


def eval_set(items, form, env):
    require_shape(len(items) == 3 and isinstance(items[1], Symbol), form)
    value = evaluate(items[2], env)
    env.assign(items[1], value)
    return VOID


def eval_lambda(items, form, env):
    parameters = parse_parameters(items[1]) if len(items) >= 3 else None
    require_shape(parameters is not None, form)
    return Closure(*parameters, items[2:], env)


def eval_begin(items, form, env):
    return evaluate_body(items[1:], env)


def eval_let(items, form, env):
    if len(items) > 1 and isinstance(items[1], Symbol):
        return eval_named_let(items, form, env)
    bindings = parse_bindings(items[1]) if len(items) >= 3 else None
    require_shape(bindings is not None, form)
    values = [evaluate(expr, env) for _, expr in bindings]
    scope = Environment(env)
    for (name, _), value in zip(bindings, values):
        scope.define(name, value)
    return evaluate_body(items[2:], scope)


def eval_named_let(items, form, env):
    bindings = parse_bindings(items[2]) if len(items) >= 4 else None
    require_shape(bindings is not None, form)
    values = [evaluate(expr, env) for _, expr in bindings]
    scope = Environment(env)
    names = [name for name, _ in bindings]
    loop = Closure(names, None, items[3:], scope, items[1].name)
    scope.define(items[1], loop)
    return loop.call(values)


def eval_let_star(items, form, env):
    bindings = parse_bindings(items[1], unique=False) if len(items) >= 3 else None
    require_shape(bindings is not None, form)
    scope = env if bindings else Environment(env)
    for name, expr in bindings:
        value = evaluate(expr, scope)
        scope = Environment(scope)
        scope.define(name, value)
    return evaluate_body(items[2:], scope)


def eval_letrec(items, form, env):
    bindings = parse_bindings(items[1]) if len(items) >= 3 else None
    require_shape(bindings is not None, form)
    scope = Environment(env)
    for name, _ in bindings:
        scope.define(name, UNINITIALIZED)
    for name, expr in bindings:
        scope.define(name, evaluate(expr, scope))
    return evaluate_body(items[2:], scope)


def eval_cond(items, form, env):
    clauses = [list_items(clause) for clause in items[1:]]
    for index, clause in enumerate(clauses):
        require_shape(bool(clause), form)
        if clause[0] is ELSE:
            require_shape(len(clause) >= 2 and index == len(clauses) - 1, form)
    for clause in clauses:
        if clause[0] is ELSE:
            return evaluate_body(clause[1:], env)
        test = evaluate(clause[0], env)
        if test is not False:
            return evaluate_body(clause[1:], env) if len(clause) > 1 else test
    return VOID


def eval_and(items, form, env):
    value = True
    for expr in items[1:]:
        value = evaluate(expr, env)
        if value is False:
            return False
    return value


def eval_or(items, form, env):
    for expr in items[1:]:
        value = evaluate(expr, env)
        if value is not False:
            return value
    return False


def eval_when(items, form, env):
    require_shape(len(items) >= 3, form)
    if evaluate(items[1], env) is not False:
        return evaluate_body(items[2:], env)
    return VOID


def eval_unless(items, form, env):
    require_shape(len(items) >= 3, form)
    if evaluate(items[1], env) is False:
        return evaluate_body(items[2:], env)
    return VOID


SPECIAL_FORMS = {
    "quote": eval_quote,
    "if": eval_if,
    "define": eval_define,
    "set!": eval_set,
    "lambda": eval_lambda,
    "begin": eval_begin,
    "let": eval_let,
    "let*": eval_let_star,
    "letrec": eval_letrec,
    "cond": eval_cond,
    "and": eval_and,
    "or": eval_or,
    "when": eval_when,
    "unless": eval_unless,
}

KIND_TESTS = {
    "integer": is_integer,
    "pair": lambda value: isinstance(value, Pair),
    "list": is_list,
    "procedure": lambda value: isinstance(value, Procedure),
    "string": lambda value: isinstance(value, str),
}


def expect(value, kind):
    if not KIND_TESTS[kind](value):
        raise ArgumentError(f"expected {kind}, got {represent(value)}")
    return value


def integers(args):
    return [expect(arg, "integer") for arg in args]


def subtract(args):
    numbers = integers(args)
    if len(numbers) == 1:
        return -numbers[0]
    return numbers[0] - sum(numbers[1:])


def division_operands(args):
    a, b = integers(args)
    if b == 0:
        raise ArgumentError("division by zero")
    return a, b


def truncated_quotient(a, b):
    magnitude = abs(a) // abs(b)
    return magnitude if (a < 0) == (b < 0) else -magnitude


def quotient(args):
    return truncated_quotient(*division_operands(args))


def remainder(args):
    a, b = division_operands(args)
    return a - b * truncated_quotient(a, b)


def modulo(args):
    a, b = division_operands(args)
    return a % b


def comparison(test):
    def compare(args):
        numbers = integers(args)
        return all(test(a, b) for a, b in zip(numbers, numbers[1:]))

    return compare


def append(args):
    if not args:
        return NIL
    items = []
    for arg in args[:-1]:
        items.extend(list_items(expect(arg, "list")))
    return make_list(items, args[-1])


def list_ref(args):
    items = list_items(expect(args[0], "list"))
    index = expect(args[1], "integer")
    if not 0 <= index < len(items):
        raise ArgumentError(f"index out of range: {index}")
    return items[index]


def map_lists(args):
    function = expect(args[0], "procedure")
    lists = [list_items(expect(arg, "list")) for arg in args[1:]]
    return make_list([function.call(list(row)) for row in zip(*lists)])


def filter_list(args):
    function = expect(args[0], "procedure")
    items = list_items(expect(args[1], "list"))
    return make_list([item for item in items if function.call([item]) is not False])


def fold_left(args):
    function = expect(args[0], "procedure")
    lists = [list_items(expect(arg, "list")) for arg in args[2:]]
    accumulator = args[1]
    for row in zip(*lists):
        accumulator = function.call([accumulator, *row])
    return accumulator


def apply_procedure(args):
    function = expect(args[0], "procedure")
    spread = list_items(expect(args[-1], "list"))
    return function.call(args[1:-1] + spread)


def display(args):
    output.write(represent(args[0], quote_strings=False))
    return VOID


def newline(args):
    output.write("\n")
    return VOID


def raise_user_error(args):
    message = expect(args[0], "string")
    raise LispError(" ".join([message, *(represent(arg) for arg in args[1:])]))


BUILTINS = {
    "+": (0, None, lambda args: sum(integers(args))),
    "*": (0, None, lambda args: math.prod(integers(args))),
    "-": (1, None, subtract),
    "quotient": (2, 2, quotient),
    "remainder": (2, 2, remainder),
    "modulo": (2, 2, modulo),
    "abs": (1, 1, lambda args: abs(expect(args[0], "integer"))),
    "min": (1, None, lambda args: min(integers(args))),
    "max": (1, None, lambda args: max(integers(args))),
    "gcd": (0, None, lambda args: math.gcd(*integers(args))),
    "=": (1, None, comparison(operator.eq)),
    "<": (1, None, comparison(operator.lt)),
    ">": (1, None, comparison(operator.gt)),
    "<=": (1, None, comparison(operator.le)),
    ">=": (1, None, comparison(operator.ge)),
    "not": (1, 1, lambda args: args[0] is False),
    "eq?": (2, 2, lambda args: is_eq(*args)),
    "equal?": (2, 2, lambda args: is_equal(*args)),
    "null?": (1, 1, lambda args: args[0] is NIL),
    "pair?": (1, 1, lambda args: isinstance(args[0], Pair)),
    "list?": (1, 1, lambda args: is_list(args[0])),
    "number?": (1, 1, lambda args: is_integer(args[0])),
    "symbol?": (1, 1, lambda args: isinstance(args[0], Symbol)),
    "procedure?": (1, 1, lambda args: isinstance(args[0], Procedure)),
    "cons": (2, 2, lambda args: Pair(args[0], args[1])),
    "car": (1, 1, lambda args: expect(args[0], "pair").car),
    "cdr": (1, 1, lambda args: expect(args[0], "pair").cdr),
    "cadr": (1, 1, lambda args: expect(expect(args[0], "pair").cdr, "pair").car),
    "list": (0, None, make_list),
    "length": (1, 1, lambda args: len(list_items(expect(args[0], "list")))),
    "append": (0, None, append),
    "reverse": (1, 1, lambda args: make_list(list_items(expect(args[0], "list"))[::-1])),
    "list-ref": (2, 2, list_ref),
    "map": (2, None, map_lists),
    "filter": (2, 2, filter_list),
    "fold-left": (3, None, fold_left),
    "apply": (2, None, apply_procedure),
    "string-append": (0, None, lambda args: "".join(expect(arg, "string") for arg in args)),
    "number->string": (1, 1, lambda args: str(expect(args[0], "integer"))),
    "display": (1, 1, display),
    "newline": (0, 0, newline),
    "error": (1, None, raise_user_error),
}


class Output:
    def __init__(self):
        self.mid_line = False

    def write(self, text):
        if text:
            sys.stdout.write(text)
            self.mid_line = not text.endswith("\n")

    def write_line(self, line):
        if self.mid_line:
            self.write("\n")
        self.write(line + "\n")

    def finish(self):
        if self.mid_line:
            self.write("\n")


output = Output()


def create_global_environment():
    env = Environment()
    for name, (min_args, max_args, function) in BUILTINS.items():
        env.define(intern(name), Builtin(name, min_args, max_args, function))
    return env


def main():
    sys.setrecursionlimit(100000)
    lines = sys.stdin.read().split("\n")
    reader = Reader(lines[:lines.index("(exit)")])
    global_env = create_global_environment()
    while not reader.at_end():
        try:
            expr = reader.read_datum()
        except ReadError as error:
            output.write_line(f"Error: read: {error}")
            if str(error) == END_OF_INPUT:
                break
            reader.skip_line()
            continue
        try:
            value = evaluate(expr, global_env)
        except LispError as error:
            output.write_line(f"Error: {error}")
        else:
            if value is not VOID:
                output.write_line(represent(value))
    output.finish()


if __name__ == "__main__":
    main()
