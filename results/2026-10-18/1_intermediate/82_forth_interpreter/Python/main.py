import sys
from dataclasses import dataclass, field

STACK_LIMIT = 1000
DEPTH_LIMIT = 100
CELL = 8
DIGITS = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'
PREFIXES = {'$': 16, '#': 10, '%': 2}
COMPILE_ONLY = {
    'IF', 'ELSE', 'THEN', 'DO', '?DO', 'LOOP', '+LOOP', 'LEAVE', 'UNLOOP', 'I', 'J', 'BEGIN',
    'UNTIL', 'WHILE', 'REPEAT', 'AGAIN', 'CASE', 'OF', 'ENDOF', 'ENDCASE', 'EXIT', 'RECURSE',
    'DOES>', ';', '>R', 'R>', 'R@', 'ABORT"', "[']", '{:',
}
INTERPRET_ONLY = {':', ':NONAME', 'FORGET'}
SPECIAL_WORDS = COMPILE_ONLY | INTERPRET_ONLY | {'."', '(', '\\', 'TO', 'IS'}
UNCLOSED_ALIASES = {'ELSE': 'IF', 'WHILE': 'BEGIN'}


class ForthError(Exception):
    def __init__(self, reason, code=None, word=None):
        super().__init__(reason)
        self.reason = reason
        self.code = code
        self.word = word


@dataclass
class Action:
    op: str
    token: str
    arg: object = None


@dataclass
class Control:
    kind: str
    origin: int = 0
    refs: list = field(default_factory=list)


@dataclass(eq=False)
class Definition:
    name: str | None
    display: str
    here: int
    body: list = field(default_factory=list)
    control: list = field(default_factory=list)
    local_names: dict = field(default_factory=dict)
    local_count: int = 0


@dataclass(eq=False)
class Word:
    name: str
    kind: str
    action: object = None
    address: int = 0
    value: int = 0
    here: int = 0
    does: tuple | None = None
    target: 'Word | None' = None
    xt: int = 0


def flag(condition):
    return -1 if condition else 0


def slash_mod(a, b):
    if b == 0:
        raise ForthError('division by zero', -10)
    quotient, remainder = divmod(a, b)
    return remainder, quotient


def parse_digits(text, base):
    negative = text.startswith('-')
    digits = text[1:] if negative else text
    if not digits:
        return None
    value = 0
    for char in digits.upper():
        digit = DIGITS.find(char)
        if not 0 <= digit < base:
            return None
        value = value * base + digit
    return -value if negative else value


class Interpreter:
    def __init__(self):
        self.stack = []
        self.return_stack = []
        self.memory = [10]
        self.dictionary = []
        self.builtins = {
            name: Word(name, 'builtin', action) for name, action in self.builtin_actions().items()
        }
        self.xts = []
        self.depth = 0
        self.definition = None
        self.pending = ''
        self.line = ''
        self.pos = 0

    def builtin_actions(self):
        def calc(count, func):
            return lambda: self.push(func(*self.take(count)))

        def shuffle(count, func):
            def run():
                for value in func(*self.take(count)):
                    self.push(value)

            return run

        return {
            '+': calc(2, lambda a, b: a + b),
            '-': calc(2, lambda a, b: a - b),
            '*': calc(2, lambda a, b: a * b),
            '/': calc(2, lambda a, b: slash_mod(a, b)[1]),
            'MOD': calc(2, lambda a, b: slash_mod(a, b)[0]),
            '/MOD': shuffle(2, slash_mod),
            '*/': calc(3, lambda a, b, c: slash_mod(a * b, c)[1]),
            '*/MOD': shuffle(3, lambda a, b, c: slash_mod(a * b, c)),
            'NEGATE': calc(1, lambda a: -a),
            'ABS': calc(1, abs),
            'MIN': calc(2, min),
            'MAX': calc(2, max),
            '1+': calc(1, lambda a: a + 1),
            '1-': calc(1, lambda a: a - 1),
            '2*': calc(1, lambda a: a * 2),
            '2/': calc(1, lambda a: a // 2),
            '=': calc(2, lambda a, b: flag(a == b)),
            '<>': calc(2, lambda a, b: flag(a != b)),
            '<': calc(2, lambda a, b: flag(a < b)),
            '>': calc(2, lambda a, b: flag(a > b)),
            '0=': calc(1, lambda a: flag(a == 0)),
            '0<>': calc(1, lambda a: flag(a != 0)),
            '0<': calc(1, lambda a: flag(a < 0)),
            '0>': calc(1, lambda a: flag(a > 0)),
            'WITHIN': calc(3, lambda n, low, high: flag(low <= n < high)),
            'TRUE': lambda: self.push(-1),
            'FALSE': lambda: self.push(0),
            'AND': calc(2, lambda a, b: a & b),
            'OR': calc(2, lambda a, b: a | b),
            'XOR': calc(2, lambda a, b: a ^ b),
            'INVERT': calc(1, lambda a: ~a),
            'DUP': shuffle(1, lambda a: (a, a)),
            '?DUP': shuffle(1, lambda a: (a, a) if a else (a,)),
            'DROP': shuffle(1, lambda a: ()),
            'SWAP': shuffle(2, lambda a, b: (b, a)),
            'OVER': shuffle(2, lambda a, b: (a, b, a)),
            'ROT': shuffle(3, lambda a, b, c: (b, c, a)),
            '-ROT': shuffle(3, lambda a, b, c: (c, a, b)),
            'NIP': shuffle(2, lambda a, b: (b,)),
            'TUCK': shuffle(2, lambda a, b: (b, a, b)),
            '2DUP': shuffle(2, lambda a, b: (a, b, a, b)),
            '2DROP': shuffle(2, lambda a, b: ()),
            '2SWAP': shuffle(4, lambda a, b, c, d: (c, d, a, b)),
            '2OVER': shuffle(4, lambda a, b, c, d: (a, b, c, d, a, b)),
            'DEPTH': lambda: self.push(len(self.stack)),
            'PICK': self.pick,
            'ROLL': self.roll,
            '.': lambda: self.print_number(self.pop()),
            '.R': self.dot_r,
            '.S': self.dot_s,
            '?': lambda: self.print_number(self.memory[self.cell(self.pop())]),
            'CR': self.flush,
            'EMIT': self.emit_char,
            'SPACE': lambda: self.write(' '),
            'SPACES': lambda: self.write(' ' * self.pop()),
            'BL': lambda: self.push(32),
            '!': self.store,
            '@': lambda: self.push(self.memory[self.cell(self.pop())]),
            '+!': self.add_store,
            ',': lambda: self.memory.append(self.pop()),
            'ALLOT': self.allot,
            'HERE': lambda: self.push(self.here()),
            'CELLS': calc(1, lambda n: n * CELL),
            'CELL+': calc(1, lambda a: a + CELL),
            'BASE': lambda: self.push(0),
            'HEX': lambda: self.set_base(16),
            'DECIMAL': lambda: self.set_base(10),
            'CREATE': self.define_create,
            'VARIABLE': self.define_variable,
            'CONSTANT': self.define_constant,
            'VALUE': self.define_value,
            'DEFER': self.define_defer,
            "'": lambda: self.push(self.xt_of(self.find_existing(self.read_name()))),
            'EXECUTE': self.execute_xt,
            'CATCH': self.catch,
            'THROW': self.throw,
            'ABORT': self.abort,
            'WORDS': self.words,
        }

    def push(self, value):
        if len(self.stack) >= STACK_LIMIT:
            raise ForthError('stack overflow', -3)
        self.stack.append(value)

    def pop(self):
        if not self.stack:
            raise ForthError('stack underflow', -4)
        return self.stack.pop()

    def take(self, count):
        split = len(self.stack) - count
        if split < 0:
            raise ForthError('stack underflow', -4)
        values = self.stack[split:]
        del self.stack[split:]
        return values

    def push_return(self, value):
        if len(self.return_stack) >= STACK_LIMIT:
            raise ForthError('return stack overflow', -5)
        self.return_stack.append(value)

    def require_return(self, count):
        if len(self.return_stack) < count:
            raise ForthError('return stack underflow', -6)

    def check_stack_index(self, index):
        if index < 0:
            raise ForthError('invalid argument', -24)
        if len(self.stack) <= index:
            raise ForthError('stack underflow', -4)

    def pick(self):
        index = self.pop()
        self.check_stack_index(index)
        self.push(self.stack[-1 - index])

    def roll(self):
        index = self.pop()
        self.check_stack_index(index)
        self.stack.append(self.stack.pop(-1 - index))

    def here(self):
        return len(self.memory) * CELL

    def cell(self, address):
        if address < 0 or address % CELL or address >= self.here():
            raise ForthError('invalid address', -9)
        return address // CELL

    def store(self):
        value, address = self.take(2)
        self.memory[self.cell(address)] = value

    def add_store(self):
        value, address = self.take(2)
        self.memory[self.cell(address)] += value

    def allot(self):
        size = self.pop()
        if size < 0 or size % CELL:
            raise ForthError('invalid argument', -24)
        self.memory.extend([0] * (size // CELL))

    def set_base(self, base):
        self.memory[0] = base

    def radix(self):
        base = self.memory[0]
        if not 2 <= base <= 36:
            raise ForthError('invalid base', -40)
        return base

    def parse_number(self, text, base=None):
        if len(text) == 3 and text[0] == text[2] == "'":
            return ord(text[1])
        if text[0] in PREFIXES:
            return parse_digits(text[1:], PREFIXES[text[0]])
        return parse_digits(text, self.radix() if base is None else base)

    def parse_literal(self, token):
        value = self.parse_number(token)
        if value is None:
            raise ForthError('undefined word', -13)
        return value

    def format_number(self, number):
        base = self.radix()
        value = abs(number)
        digits = DIGITS[value % base]
        while value >= base:
            value //= base
            digits = DIGITS[value % base] + digits
        return '-' + digits if number < 0 else digits

    def write(self, text):
        self.pending += text

    def flush(self):
        print(self.pending.rstrip(' '))
        self.pending = ''

    def print_number(self, number):
        self.write(self.format_number(number) + ' ')

    def dot_r(self):
        number, width = self.take(2)
        self.write(self.format_number(number).rjust(width))

    def dot_s(self):
        text = f'<{self.format_number(len(self.stack))}> '
        self.write(text + ''.join(self.format_number(value) + ' ' for value in self.stack))

    def emit_char(self):
        code = self.pop()
        if not 32 <= code <= 126:
            raise ForthError('invalid argument', -24)
        self.write(chr(code))

    def words(self):
        for word in reversed(self.dictionary):
            self.write(word.name + ' ')

    def read_word(self):
        line = self.line
        start = self.pos
        while start < len(line) and line[start] == ' ':
            start += 1
        end = start
        while end < len(line) and line[end] != ' ':
            end += 1
        self.pos = end
        return line[start:end] or None

    def read_name(self):
        name = self.read_word()
        if name is None:
            raise ForthError('missing name', -16)
        return name

    def read_string(self):
        start = self.pos + 1
        end = self.line.find('"', start)
        if end < 0:
            raise ForthError('unterminated string')
        self.pos = end + 1
        return self.line[start:end]

    def find(self, name):
        for word in reversed(self.dictionary):
            if word.name == name:
                return word
        return self.builtins.get(name)

    def find_existing(self, name):
        word = self.find(name.upper())
        if word is None:
            raise ForthError('undefined word', -13, name)
        return word

    def check_name(self, name):
        if name.upper() in SPECIAL_WORDS or self.parse_number(name, 10) is not None:
            raise ForthError('invalid name', -19, name)

    def new_name(self):
        name = self.read_name()
        self.check_name(name)
        return name.upper()

    def add_word(self, word):
        word.here = self.here()
        self.dictionary.append(word)

    def define_create(self):
        self.add_word(Word(self.new_name(), 'create', address=self.here()))

    def define_variable(self):
        self.add_word(Word(self.new_name(), 'variable', address=self.here()))
        self.memory.append(0)

    def define_constant(self):
        name = self.new_name()
        self.add_word(Word(name, 'constant', value=self.pop()))

    def define_value(self):
        name = self.new_name()
        initial = self.pop()
        self.add_word(Word(name, 'value', address=self.here()))
        self.memory.append(initial)

    def define_defer(self):
        self.add_word(Word(self.new_name(), 'defer'))

    def xt_of(self, word):
        if not word.xt:
            self.xts.append(word)
            word.xt = len(self.xts)
        return word.xt

    def xt_word(self, xt):
        if not 1 <= xt <= len(self.xts):
            raise ForthError('invalid argument', -24)
        return self.xts[xt - 1]

    def execute_xt(self):
        word = self.xt_word(self.pop())
        self.execute(word, word.name)

    def set_deferred(self, word):
        word.target = self.xt_word(self.pop())

    def catch(self):
        word = self.xt_word(self.pop())
        saved_stack = self.stack.copy()
        saved_return_depth = len(self.return_stack)
        saved_depth = self.depth
        try:
            self.execute(word, word.name)
        except ForthError as error:
            if error.code is None:
                raise
            self.stack[:] = saved_stack
            del self.return_stack[saved_return_depth:]
            self.depth = saved_depth
            self.push(error.code)
        else:
            self.push(0)

    def throw(self):
        code = self.pop()
        if code:
            raise ForthError(f'exception {code}', code)

    def abort(self):
        raise ForthError('aborted', -1)

    def execute(self, word, token):
        try:
            match word.kind:
                case 'builtin':
                    word.action()
                case 'colon':
                    self.run(word.action, 0)
                case 'create' | 'variable':
                    self.push(word.address)
                    if word.does is not None:
                        self.run(*word.does)
                case 'constant':
                    self.push(word.value)
                case 'value':
                    self.push(self.memory[word.address // CELL])
                case 'defer':
                    if word.target is None:
                        raise ForthError('deferred word not set', -21)
                    self.execute(word.target, word.target.name)
        except ForthError as error:
            if error.word is None:
                error.word = token
            raise

    def run(self, definition, start):
        if self.depth == DEPTH_LIMIT:
            raise ForthError('nesting too deep', -7)
        self.depth += 1
        return_depth = len(self.return_stack)
        frame = [0] * definition.local_count
        body = definition.body
        ip = start
        try:
            while ip < len(body):
                action = body[ip]
                ip = self.step(definition, action, ip + 1, frame)
        except ForthError as error:
            if error.word is None:
                error.word = action.token
            raise
        del self.return_stack[return_depth:]
        self.depth -= 1

    def step(self, definition, action, ip, frame):
        match action.op:
            case 'call':
                self.execute(action.arg, action.token)
            case 'push':
                self.push(action.arg)
            case 'local':
                self.push(frame[action.arg])
            case '."':
                self.write(action.arg)
            case 'branch':
                return action.arg
            case 'zbranch':
                if self.pop() == 0:
                    return action.arg
            case 'DO' | '?DO':
                limit, index = self.take(2)
                if action.op == '?DO' and limit == index:
                    return action.arg
                self.push_return(limit)
                self.push_return(index)
            case 'LOOP' | '+LOOP':
                increment = 1 if action.op == 'LOOP' else self.pop()
                self.require_return(2)
                limit, index = self.return_stack[-2:]
                if (index - limit < 0) != (index + increment - limit < 0):
                    del self.return_stack[-2:]
                else:
                    self.return_stack[-1] = index + increment
                    return action.arg
            case 'LEAVE':
                self.require_return(2)
                del self.return_stack[-2:]
                return action.arg
            case 'UNLOOP':
                self.require_return(2)
                del self.return_stack[-2:]
            case '>R':
                self.push_return(self.pop())
            case 'R>':
                self.require_return(1)
                self.push(self.return_stack.pop())
            case 'R@' | 'I':
                self.require_return(1)
                self.push(self.return_stack[-1])
            case 'J':
                self.require_return(3)
                self.push(self.return_stack[-3])
            case 'OF':
                selector, candidate = self.take(2)
                if selector != candidate:
                    self.push(selector)
                    return action.arg
            case 'ENDCASE':
                self.pop()
            case 'ABORT"':
                if self.pop():
                    raise ForthError(action.arg, -2)
            case '{:':
                for slot, value in zip(action.arg, self.take(len(action.arg))):
                    frame[slot] = value
            case 'to_local':
                frame[action.arg] = self.pop()
            case 'to_value':
                self.memory[action.arg.address // CELL] = self.pop()
            case 'IS':
                self.set_deferred(action.arg)
            case 'RECURSE':
                self.run(action.arg, 0)
            case 'DOES>':
                if not self.dictionary or self.dictionary[-1].kind != 'create':
                    raise ForthError('no CREATE word', -31)
                self.dictionary[-1].does = (definition, action.arg)
                return len(definition.body)
            case 'EXIT':
                return len(definition.body)
        return ip

    def process_line(self, line):
        self.line = line
        self.pos = 0
        try:
            while (token := self.read_word()) is not None:
                self.interpret_token(token)
        except ForthError as error:
            self.report(error, token)
        if self.pending:
            self.flush()

    def report(self, error, token):
        if self.pending:
            self.flush()
        print(f'ERROR {token if error.word is None else error.word}: {error.reason}')
        self.stack.clear()
        self.return_stack.clear()
        self.depth = 0
        self.definition = None

    def interpret_token(self, token):
        name = token.upper()
        compiling = self.definition is not None
        match name:
            case '\\':
                self.pos = len(self.line)
            case '(':
                end = self.line.find(')', self.pos)
                if end < 0:
                    raise ForthError('unterminated comment')
                self.pos = end + 1
            case _ if not compiling and name in COMPILE_ONLY:
                raise ForthError('compile only')
            case _ if compiling and name in INTERPRET_ONLY:
                raise ForthError('interpret only')
            case '."' | 'ABORT"':
                text = self.read_string()
                if compiling:
                    self.emit(name, token, text)
                else:
                    self.write(text)
            case 'TO':
                self.assign_value(token)
            case 'IS':
                self.assign_deferred(token)
            case ':' | ':NONAME':
                self.start_definition(token, name)
            case 'FORGET':
                self.forget()
            case _ if compiling:
                self.compile_token(token, name)
            case _:
                word = self.find(name)
                if word is None:
                    self.push(self.parse_literal(token))
                else:
                    self.execute(word, token)

    def assign_value(self, token):
        name = self.read_name()
        definition = self.definition
        if definition is not None and name.upper() in definition.local_names:
            self.emit('to_local', token, definition.local_names[name.upper()])
            return
        word = self.find_existing(name)
        if word.kind != 'value':
            raise ForthError('not a value', word=name)
        if definition is None:
            self.memory[word.address // CELL] = self.pop()
        else:
            self.emit('to_value', token, word)

    def assign_deferred(self, token):
        name = self.read_name()
        word = self.find_existing(name)
        if word.kind != 'defer':
            raise ForthError('not deferred', word=name)
        if self.definition is None:
            self.set_deferred(word)
        else:
            self.emit('IS', token, word)

    def start_definition(self, token, name):
        if name == ':NONAME':
            self.definition = Definition(None, token, self.here())
        else:
            new_name = self.read_name()
            self.check_name(new_name)
            self.definition = Definition(new_name.upper(), new_name, self.here())

    def end_definition(self):
        definition = self.definition
        if definition.control:
            kind = definition.control[-1].kind
            raise ForthError(f'unclosed {UNCLOSED_ALIASES.get(kind, kind)}')
        self.definition = None
        if definition.name is None:
            self.push(self.xt_of(Word(':NONAME', 'colon', definition)))
        else:
            word = Word(definition.name, 'colon', definition, here=definition.here)
            self.dictionary.append(word)

    def forget(self):
        name = self.read_name()
        key = name.upper()
        for index in range(len(self.dictionary) - 1, -1, -1):
            word = self.dictionary[index]
            if word.name == key:
                del self.dictionary[index:]
                del self.memory[word.here // CELL:]
                return
        raise ForthError('undefined word', -13, name)

    def emit(self, op, token, arg=None):
        body = self.definition.body
        body.append(Action(op, token, arg))
        return len(body) - 1

    def patch(self, *indices):
        body = self.definition.body
        for index in indices:
            body[index].arg = len(body)

    def check_top(self, *kinds):
        control = self.definition.control
        if not control or control[-1].kind not in kinds:
            raise ForthError('control structure mismatch')

    def declare_locals(self, token):
        names = []
        while (word := self.read_word()) != ':}':
            if word is None:
                raise ForthError('unterminated locals')
            names.append(word)
        if '--' in names:
            names = names[:names.index('--')]
        for name in names:
            self.check_name(name)
        definition = self.definition
        slots = []
        for name in names:
            definition.local_names[name.upper()] = definition.local_count
            slots.append(definition.local_count)
            definition.local_count += 1
        self.emit('{:', token, slots)

    def compile_token(self, token, name):
        definition = self.definition
        control = definition.control
        match name:
            case 'IF':
                control.append(Control('IF', self.emit('zbranch', token)))
            case 'ELSE':
                self.check_top('IF')
                branch = self.emit('branch', token)
                self.patch(control.pop().origin)
                control.append(Control('ELSE', branch))
            case 'THEN':
                self.check_top('IF', 'ELSE')
                self.patch(control.pop().origin)
            case 'BEGIN':
                control.append(Control('BEGIN', len(definition.body)))
            case 'UNTIL' | 'AGAIN':
                self.check_top('BEGIN')
                op = 'zbranch' if name == 'UNTIL' else 'branch'
                self.emit(op, token, control.pop().origin)
            case 'WHILE':
                self.check_top('BEGIN')
                exit_branch = self.emit('zbranch', token)
                control[-1] = Control('WHILE', control[-1].origin, [exit_branch])
            case 'REPEAT':
                self.check_top('WHILE')
                loop = control.pop()
                self.emit('branch', token, loop.origin)
                self.patch(*loop.refs)
            case 'DO' | '?DO':
                start = self.emit(name, token)
                control.append(Control(name, start + 1, [start] if name == '?DO' else []))
            case 'LOOP' | '+LOOP':
                self.check_top('DO', '?DO')
                loop = control.pop()
                self.emit(name, token, loop.origin)
                self.patch(*loop.refs)
            case 'LEAVE':
                loops = [record for record in control if record.kind in ('DO', '?DO')]
                if not loops:
                    raise ForthError('control structure mismatch')
                loops[-1].refs.append(self.emit('LEAVE', token))
            case 'CASE':
                control.append(Control('CASE'))
            case 'OF':
                self.check_top('CASE')
                control.append(Control('OF', self.emit('OF', token)))
            case 'ENDOF':
                self.check_top('OF')
                branch = self.emit('branch', token)
                self.patch(control.pop().origin)
                control[-1].refs.append(branch)
            case 'ENDCASE':
                self.check_top('CASE')
                self.emit('ENDCASE', token)
                self.patch(*control.pop().refs)
            case 'RECURSE':
                self.emit('RECURSE', token, definition)
            case 'DOES>':
                if control:
                    raise ForthError('control structure mismatch')
                self.emit('DOES>', token, len(definition.body) + 1)
            case ';':
                self.end_definition()
            case "[']":
                word = self.find_existing(self.read_name())
                self.emit('push', token, self.xt_of(word))
            case '{:':
                self.declare_locals(token)
            case 'EXIT' | '>R' | 'R>' | 'R@' | 'I' | 'J' | 'UNLOOP':
                self.emit(name, token)
            case _ if name in definition.local_names:
                self.emit('local', token, definition.local_names[name])
            case _:
                word = self.find(name)
                if word is None:
                    self.emit('push', token, self.parse_literal(token))
                else:
                    self.emit('call', token, word)

    def finish(self):
        if self.definition is not None:
            print(f'ERROR {self.definition.display}: unterminated definition')


def main():
    sys.setrecursionlimit(10000)
    interpreter = Interpreter()
    for line in sys.stdin:
        line = line.rstrip('\n')
        if line == 'BYE':
            break
        interpreter.process_line(line)
    interpreter.finish()


if __name__ == '__main__':
    main()
