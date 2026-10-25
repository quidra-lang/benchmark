import re
import sys
from dataclasses import dataclass
from functools import reduce
from itertools import combinations, pairwise

NAME = re.compile(r'[a-z][a-z0-9]{0,7}')
VARIABLE = re.compile(r'[A-Z]')
ASSIGNMENT = re.compile(r'[A-Z]=[01]')
MINTERM = re.compile(r'0|[1-9][0-9]*')
TOKEN = re.compile(r'<->|->|[a-z][a-z0-9]*|[A-Z01~&^|()]')

PRECEDENCE = {'<->': 1, '->': 2, '|': 3, '^': 4, '&': 5}
OPERATIONS = {
    '&': lambda a, b: a & b,
    '^': lambda a, b: a ^ b,
    '|': lambda a, b: a | b,
    '->': lambda a, b: (1 - a) | b,
    '<->': lambda a, b: 1 - (a ^ b),
}
DUAL_OPERATORS = {'&': '|', '|': '&', '^': '<->', '<->': '^'}
PATTERN_ORDER = str.maketrans('10-', '012')
SWAP = str.maketrans('01', '10')
TABLE_COMMANDS = {
    'TABLE', 'MINTERMS', 'MAXTERMS', 'DNF', 'CNF', 'ANF', 'SAT', 'TAUT', 'COUNT',
    'EQUIV', 'IMPLIES', 'PROPS', 'KMAP', 'BDD', 'MINIMIZE', 'MINDC', 'MINPOS',
}


class CommandError(Exception):
    pass


@dataclass(frozen=True)
class Var:
    name: str


@dataclass(frozen=True)
class Const:
    value: int


@dataclass(frozen=True)
class Not:
    child: 'Formula'


@dataclass(frozen=True)
class Bin:
    op: str
    left: 'Formula'
    right: 'Formula'


Formula = Var | Const | Not | Bin
ZERO = Const(0)
ONE = Const(1)


def tokenize(text, start):
    tokens = []
    index = 0
    while index < len(text):
        if text[index] == ' ':
            index += 1
            continue
        token = TOKEN.match(text, index)
        if token is None:
            raise CommandError(f"invalid character '{text[index]}' at {start + index}")
        tokens.append((token.group(), start + index))
        index = token.end()
    return tokens


class Parser:
    def __init__(self, tokens, end, names):
        self.tokens = tokens
        self.end = end
        self.names = names
        self.index = 0

    def parse(self):
        tree = self.equivalence()
        if self.index < len(self.tokens):
            raise self.unexpected()
        return tree

    def peek(self):
        if self.index < len(self.tokens):
            return self.tokens[self.index][0]
        return None

    def unexpected(self):
        if self.index < len(self.tokens):
            text, position = self.tokens[self.index]
            return CommandError(f"unexpected '{text}' at {position}")
        return CommandError(f'unexpected end of formula at {self.end}')

    def left_assoc(self, op, operand):
        tree = operand()
        while self.peek() == op:
            self.index += 1
            tree = Bin(op, tree, operand())
        return tree

    def equivalence(self):
        return self.left_assoc('<->', self.implication)

    def implication(self):
        tree = self.disjunction()
        if self.peek() == '->':
            self.index += 1
            return Bin('->', tree, self.implication())
        return tree

    def disjunction(self):
        return self.left_assoc('|', self.xor)

    def xor(self):
        return self.left_assoc('^', self.conjunction)

    def conjunction(self):
        return self.left_assoc('&', self.unary)

    def unary(self):
        if self.peek() == '~':
            self.index += 1
            return Not(self.unary())
        return self.atom()

    def atom(self):
        if self.index == len(self.tokens):
            raise self.unexpected()
        text, position = self.tokens[self.index]
        if text == '(':
            self.index += 1
            tree = self.equivalence()
            if self.peek() != ')':
                raise self.unexpected()
        elif text in ('0', '1'):
            tree = Const(int(text))
        elif text.isupper():
            tree = Var(text)
        elif text[0].islower():
            if text not in self.names:
                raise CommandError(f"undefined name '{text}' at {position}")
            tree = self.names[text]
        else:
            raise self.unexpected()
        self.index += 1
        return tree


def children(f):
    match f:
        case Not(child):
            return (child,)
        case Bin(_, left, right):
            return (left, right)
        case _:
            return ()


def size(f):
    return 1 + sum(size(child) for child in children(f))


def depth(f):
    return 1 + max((depth(child) for child in children(f)), default=0)


def collect_variables(f, found):
    if isinstance(f, Var):
        found.add(f.name)
    for child in children(f):
        collect_variables(child, found)


def variables_of(*formulas):
    found = set()
    for f in formulas:
        collect_variables(f, found)
    return sorted(found)


def chain(op, trees):
    return reduce(lambda left, right: Bin(op, left, right), trees)


def notation(f):
    match f:
        case Var(name):
            return name
        case Const(value):
            return str(value)
        case Not(child):
            text = notation(child)
            return f'~({text})' if isinstance(child, Bin) else '~' + text
        case Bin(op, left, right):
            left_text = notation(left)
            right_text = notation(right)
            if isinstance(left, Bin) and (
                PRECEDENCE[left.op] < PRECEDENCE[op] or left.op == op == '->'
            ):
                left_text = f'({left_text})'
            if isinstance(right, Bin) and (
                PRECEDENCE[right.op] < PRECEDENCE[op] or (right.op == op and op != '->')
            ):
                right_text = f'({right_text})'
            return f'{left_text} {op} {right_text}'


def nnf(f, positive=True):
    match f:
        case Var():
            return f if positive else Not(f)
        case Const(value):
            return f if positive else Const(1 - value)
        case Not(child):
            return nnf(child, not positive)
        case Bin('&' | '|' as op, left, right):
            if not positive:
                op = DUAL_OPERATORS[op]
            return Bin(op, nnf(left, positive), nnf(right, positive))
        case Bin('->', left, right):
            if positive:
                return Bin('|', nnf(left, False), nnf(right))
            return Bin('&', nnf(left), nnf(right, False))
        case Bin(op, left, right):
            left_true, left_false = nnf(left), nnf(left, False)
            right_true, right_false = nnf(right), nnf(right, False)
            if (op == '<->') == positive:
                return Bin('|', Bin('&', left_true, right_true), Bin('&', left_false, right_false))
            return Bin('|', Bin('&', left_true, right_false), Bin('&', left_false, right_true))


def dual(f):
    match f:
        case Var():
            return f
        case Const(value):
            return Const(1 - value)
        case Not(child):
            return Not(dual(child))
        case Bin('->', left, right):
            return Bin('&', Not(dual(left)), dual(right))
        case Bin(op, left, right):
            return Bin(DUAL_OPERATORS[op], dual(left), dual(right))


def negate(f):
    match f:
        case Const(value):
            return Const(1 - value)
        case Not(child):
            return child
        case _:
            return Not(f)


def combine(op, a, b):
    equal = a == b
    complementary = a == Not(b) or b == Not(a)
    match op:
        case '&':
            if a == ZERO or b == ZERO:
                return ZERO
            if a == ONE:
                return b
            if b == ONE:
                return a
            if equal:
                return a
            if complementary:
                return ZERO
        case '|':
            if a == ONE or b == ONE:
                return ONE
            if a == ZERO:
                return b
            if b == ZERO:
                return a
            if equal:
                return a
            if complementary:
                return ONE
        case '^':
            if a == ZERO:
                return b
            if b == ZERO:
                return a
            if a == ONE:
                return negate(b)
            if b == ONE:
                return negate(a)
            if equal:
                return ZERO
            if complementary:
                return ONE
        case '->':
            if a == ZERO or b == ONE:
                return ONE
            if a == ONE:
                return b
            if b == ZERO:
                return negate(a)
            if equal:
                return ONE
            if complementary:
                return b
        case '<->':
            if a == ONE:
                return b
            if b == ONE:
                return a
            if a == ZERO:
                return negate(b)
            if b == ZERO:
                return negate(a)
            if equal:
                return ONE
            if complementary:
                return ZERO
    return Bin(op, a, b)


def simplify(f, constants=None):
    match f:
        case Var(name) if constants and name in constants:
            return constants[name]
        case Var() | Const():
            return f
        case Not(child):
            return negate(simplify(child, constants))
        case Bin(op, left, right):
            return combine(op, simplify(left, constants), simplify(right, constants))


def evaluate(f, env):
    match f:
        case Var(name):
            return env[name]
        case Const(value):
            return value
        case Not(child):
            return 1 - evaluate(child, env)
        case Bin(op, left, right):
            return OPERATIONS[op](evaluate(left, env), evaluate(right, env))


def row_pattern(row, n):
    return format(row, f'0{n}b') if n else ''


def truth_table(f, variables):
    n = len(variables)
    values = []
    for row in range(1 << n):
        env = dict(zip(variables, map(int, row_pattern(row, n))))
        values.append(evaluate(f, env))
    return values


def rows_where(values, wanted):
    return [row for row, value in enumerate(values) if value == wanted]


def anf_coefficients(values, n):
    coefficients = list(values)
    for i in range(n):
        bit = 1 << i
        for s in range(len(coefficients)):
            if s & bit:
                coefficients[s] ^= coefficients[s ^ bit]
    return coefficients


def pattern_key(pattern):
    return pattern.translate(PATTERN_ORDER)


def literal_count(pattern):
    return len(pattern) - pattern.count('-')


def contains(pattern, bits):
    return all(p == '-' or p == b for p, b in zip(pattern, bits))


def literals(pattern, variables):
    return [v if c == '1' else '~' + v for v, c in zip(variables, pattern) if c != '-']


def term(pattern, variables):
    return ' & '.join(literals(pattern, variables)) or '1'


def clause(pattern, variables):
    return ' | '.join(literals(pattern, variables)) or '0'


def sum_of_products(patterns, variables):
    return ' | '.join(term(p, variables) for p in patterns) or '0'


def product_of_sums(patterns, variables):
    clauses = [clause(p, variables) for p in patterns]
    if len(clauses) >= 2:
        clauses = [f'({c})' if literal_count(p) >= 2 else c for p, c in zip(patterns, clauses)]
    return ' & '.join(clauses) or '1'


def term_list(patterns, variables):
    return ', '.join(term(p, variables) for p in sorted(patterns, key=pattern_key)) or 'none'


def assignment(row, variables):
    bits = row_pattern(row, len(variables))
    return '{' + ' '.join(f'{v}={b}' for v, b in zip(variables, bits)) + '}'


def gray_code(k):
    return [row_pattern(i ^ (i >> 1), k) for i in range(1 << k)]


def yes_no(flag):
    return 'yes' if flag else 'no'


def print_formula(f, variables):
    return [
        f'formula: {notation(f)}',
        'variables: ' + (' '.join(variables) or 'none'),
        f'size {size(f)} depth {depth(f)}',
    ]


def show_table(f, variables):
    n = len(variables)
    lines = [' '.join([*variables, '|', 'F'])]
    for row, value in enumerate(truth_table(f, variables)):
        lines.append(' '.join([*row_pattern(row, n), '|', str(value)]))
    return lines


def show_minterms(f, variables):
    rows = rows_where(truth_table(f, variables), 1)
    return ['minterms: ' + (' '.join(map(str, rows)) or 'none')]


def show_maxterms(f, variables):
    rows = rows_where(truth_table(f, variables), 0)
    return ['maxterms: ' + (' '.join(map(str, rows)) or 'none')]


def canonical_dnf(f, variables):
    n = len(variables)
    patterns = [row_pattern(row, n) for row in rows_where(truth_table(f, variables), 1)]
    return ['dnf: ' + sum_of_products(patterns, variables)]


def canonical_cnf(f, variables):
    n = len(variables)
    patterns = [
        row_pattern(row, n).translate(SWAP) for row in rows_where(truth_table(f, variables), 0)
    ]
    return ['cnf: ' + product_of_sums(patterns, variables)]


def algebraic_normal_form(f, variables):
    n = len(variables)
    coefficients = anf_coefficients(truth_table(f, variables), n)
    patterns = [row_pattern(s, n).replace('0', '-') for s, c in enumerate(coefficients) if c]
    patterns.sort(key=lambda p: (literal_count(p), pattern_key(p)))
    return ['anf: ' + (' ^ '.join(term(p, variables) for p in patterns) or '0')]


def satisfiable(f, variables):
    values = truth_table(f, variables)
    if 1 in values:
        return [f'satisfiable: {assignment(values.index(1), variables)}']
    return ['unsatisfiable']


def tautology(f, variables):
    values = truth_table(f, variables)
    if 0 in values:
        return [f'not a tautology: {assignment(values.index(0), variables)}']
    return ['tautology']


def count_models(f, variables):
    values = truth_table(f, variables)
    return [f'models: {sum(values)} of {len(values)}']


def equivalent(f, g, variables):
    pairs = zip(truth_table(f, variables), truth_table(g, variables))
    for row, (a, b) in enumerate(pairs):
        if a != b:
            return [f'not equivalent: {assignment(row, variables)} f={a} g={b}']
    return ['equivalent']


def implies(f, g, variables):
    pairs = zip(truth_table(f, variables), truth_table(g, variables))
    for row, (a, b) in enumerate(pairs):
        if a and not b:
            return [f'does not imply: {assignment(row, variables)}']
    return ['implies']


def properties(f, variables):
    n = len(variables)
    values = truth_table(f, variables)
    rows = range(len(values))
    bits = [1 << (n - 1 - i) for i in range(n)]
    depends = [
        variable
        for variable, bit in zip(variables, bits)
        if any(values[row] != values[row ^ bit] for row in rows)
    ]
    coefficients = anf_coefficients(values, n)
    self_dual = all(values[row] != values[-1 - row] for row in rows)
    monotone = all(values[row] <= values[row | bit] for row in rows for bit in bits)
    linear = all(s.bit_count() <= 1 for s in rows if coefficients[s])
    symmetric = all(values[row] == values[(1 << row.bit_count()) - 1] for row in rows)
    return [
        'depends: ' + (' '.join(depends) or 'none'),
        'zero-preserving: ' + yes_no(values[0] == 0),
        'one-preserving: ' + yes_no(values[-1] == 1),
        'self-dual: ' + yes_no(self_dual),
        'monotone: ' + yes_no(monotone),
        'linear: ' + yes_no(linear),
        'symmetric: ' + yes_no(symmetric),
    ]


def karnaugh_map(f, variables):
    n = len(variables)
    if not 2 <= n <= 4:
        raise CommandError('kmap needs 2 to 4 variables')
    values = truth_table(f, variables)
    row_variables = variables[:n // 2]
    column_variables = variables[n // 2:]
    columns = gray_code(len(column_variables))
    label = ''.join(row_variables) + '\\' + ''.join(column_variables)
    lines = [label + ''.join(' ' + column for column in columns)]
    padding = ' ' * len(column_variables)
    for row in gray_code(len(row_variables)):
        cells = ''.join(padding + str(values[int(row + column, 2)]) for column in columns)
        lines.append(row.ljust(len(label)) + cells)
    return lines


def decision_diagram(f, variables):
    nodes = []
    numbers = {}

    def build(level, values):
        if len(values) == 1:
            return values[0]
        half = len(values) // 2
        low = build(level + 1, values[:half])
        high = build(level + 1, values[half:])
        if low == high:
            return low
        node = (level, low, high)
        if node not in numbers:
            numbers[node] = len(nodes) + 2
            nodes.append(node)
        return numbers[node]

    root = build(0, truth_table(f, variables))
    paths = [0, 1]
    lines = [f'nodes: {len(nodes)}']
    for number, (level, low, high) in enumerate(nodes, 2):
        paths.append(paths[low] + paths[high])
        lines.append(f'{number} = ite({variables[level]}, {high}, {low})')
    lines += [f'root: {root}', f'paths: {paths[root]}']
    return lines


def quine_mccluskey(rows, n):
    stage = {row_pattern(row, n) for row in rows}
    stages = []
    primes = []
    while True:
        merged = set()
        combined = set()
        for pattern in stage:
            for i, c in enumerate(pattern):
                if c == '-':
                    continue
                partner = pattern[:i] + ('0' if c == '1' else '1') + pattern[i + 1:]
                if partner in stage:
                    merged.add(pattern[:i] + '-' + pattern[i + 1:])
                    combined.add(pattern)
        stages.append((len(stage), len(stage) - len(combined)))
        primes.extend(stage - combined)
        if not merged:
            return stages, primes
        stage = merged


def choose_cover(primes, on, n, swap):
    bits = {row: row_pattern(row, n) for row in on}
    coverage = {p: {row for row in on if contains(p, bits[row])} for p in primes}
    targets = [p for p in primes if coverage[p]]
    essential = set()
    for row in on:
        covering = [p for p in targets if row in coverage[p]]
        if len(covering) == 1:
            essential.add(covering[0])
    uncovered = on - set().union(*(coverage[p] for p in essential))
    optional = [p for p in targets if p not in essential]

    def cover_key(cover):
        shown = [p.translate(SWAP) if swap else p for p in cover]
        return sum(map(literal_count, cover)), sorted(map(pattern_key, shown))

    for count in range(len(optional) + 1):
        covers = [
            essential.union(chosen)
            for chosen in combinations(optional, count)
            if uncovered <= set().union(*(coverage[p] for p in chosen))
        ]
        if covers:
            return targets, essential, min(covers, key=cover_key)


def minimization_report(on, dont_care, variables):
    n = len(variables)
    stages, primes = quine_mccluskey(on | dont_care, n)
    targets, essential, cover = choose_cover(primes, on, n, swap=False)
    lines = [
        f'stage {k}: implicants {count} primes {prime_count}'
        for k, (count, prime_count) in enumerate(stages)
    ]
    lines.append('primes: ' + term_list(targets, variables))
    lines.append('essential: ' + term_list(essential, variables))
    lines.append('minimal: ' + sum_of_products(sorted(cover, key=pattern_key), variables))
    lines.append(f'terms {len(cover)} literals {sum(map(literal_count, cover))}')
    return lines


def minimize_sum(f, variables):
    on = set(rows_where(truth_table(f, variables), 1))
    return minimization_report(on, set(), variables)


def minimize_dont_care(f, d, variables):
    dont_care = set(rows_where(truth_table(d, variables), 1))
    on = set(rows_where(truth_table(f, variables), 1)) - dont_care
    return minimization_report(on, dont_care, variables)


def minimize_product(f, variables):
    n = len(variables)
    off = set(rows_where(truth_table(f, variables), 0))
    _, primes = quine_mccluskey(off, n)
    _, _, cover = choose_cover(primes, off, n, swap=True)
    clauses = sorted((p.translate(SWAP) for p in cover), key=pattern_key)
    return [
        'minimal: ' + product_of_sums(clauses, variables),
        f'clauses {len(cover)} literals {sum(map(literal_count, cover))}',
    ]


def clauses_of(f):
    match f:
        case Var(name):
            return {frozenset([name])}
        case Not(Var(name)):
            return {frozenset(['~' + name])}
        case Const(value):
            return set() if value else {frozenset()}
        case Bin('&', left, right):
            return clauses_of(left) | clauses_of(right)
        case Bin('|', left, right):
            right_clauses = clauses_of(right)
            return {c | e for c in clauses_of(left) for e in right_clauses}


def is_tautological(literal_set):
    return any('~' + literal in literal_set for literal in literal_set)


def tidy(clauses):
    clauses = {c for c in clauses if not is_tautological(c)}
    return {c for c in clauses if not any(other < c for other in clauses)}


def clause_pattern(literal_set, variables):
    return ''.join(
        '1' if v in literal_set else '0' if '~' + v in literal_set else '-' for v in variables
    )


def clause_form(f, variables):
    clauses = tidy(clauses_of(nnf(f)))
    patterns = sorted((clause_pattern(c, variables) for c in clauses), key=pattern_key)
    return ['clauses: ' + product_of_sums(patterns, variables)]


def davis_putnam(f, variables):
    clauses = tidy(clauses_of(nnf(f)))
    lines = [f'start: clauses {len(clauses)}']
    for variable in variables:
        if not clauses or frozenset() in clauses:
            break
        negated = '~' + variable
        positive = {c for c in clauses if variable in c}
        negative = {c for c in clauses if negated in c}
        resolvents = {(p - {variable}) | (q - {negated}) for p in positive for q in negative}
        resolvents = {r for r in resolvents if not is_tautological(r)}
        clauses = tidy((clauses - positive - negative) | resolvents)
        lines.append(f'eliminate {variable}: resolvents {len(resolvents)} clauses {len(clauses)}')
    lines.append('result: unsatisfiable' if frozenset() in clauses else 'result: satisfiable')
    return lines


def restrict(f, text):
    words = text.split()
    if not words:
        raise CommandError('missing assignment')
    constants = {}
    for word in words:
        if not ASSIGNMENT.fullmatch(word):
            raise CommandError(f"bad assignment '{word}'")
        if word[0] in constants:
            raise CommandError(f'duplicate variable {word[0]}')
        constants[word[0]] = Const(int(word[2]))
    return [f'restricted: {notation(simplify(f, constants))}']


def cofactor(f, text):
    words = text.split()
    if len(words) != 1 or not VARIABLE.fullmatch(words[0]):
        raise CommandError('bad variable')
    variable = words[0]
    high = simplify(f, {variable: ONE})
    low = simplify(f, {variable: ZERO})
    return [
        f'cofactor {variable}=1: {notation(high)}',
        f'cofactor {variable}=0: {notation(low)}',
        f'difference: {notation(combine("^", high, low))}',
    ]


FORMULA_COMMANDS = {
    'PRINT': print_formula,
    'TABLE': show_table,
    'MINTERMS': show_minterms,
    'MAXTERMS': show_maxterms,
    'DNF': canonical_dnf,
    'CNF': canonical_cnf,
    'NNF': lambda f, variables: [f'nnf: {notation(nnf(f))}'],
    'DUAL': lambda f, variables: [f'dual: {notation(dual(f))}'],
    'ANF': algebraic_normal_form,
    'SIMPLIFY': lambda f, variables: [f'simplified: {notation(simplify(f))}'],
    'MINIMIZE': minimize_sum,
    'MINPOS': minimize_product,
    'KMAP': karnaugh_map,
    'SAT': satisfiable,
    'TAUT': tautology,
    'COUNT': count_models,
    'PROPS': properties,
    'BDD': decision_diagram,
    'CLAUSES': clause_form,
    'DP': davis_putnam,
}
PAIR_COMMANDS = {'MINDC': minimize_dont_care, 'EQUIV': equivalent, 'IMPLIES': implies}
SUBSTITUTION_COMMANDS = {'RESTRICT': restrict, 'COFACTOR': cofactor}
COMMAND_NAMES = {
    'DEF', 'DEFSUM', 'DEL', 'LIST', *FORMULA_COMMANDS, *PAIR_COMMANDS, *SUBSTITUTION_COMMANDS,
}


class Workbench:
    def __init__(self):
        self.names = {}

    def execute(self, line):
        name, has_argument, argument = line.partition(' ')
        if name not in COMMAND_NAMES:
            raise CommandError(f'unknown command {name}')
        if name == 'LIST':
            if has_argument:
                raise CommandError('unexpected argument')
            return self.list_names()
        if not has_argument:
            raise CommandError('missing argument')
        if name == 'DEF':
            return self.define(argument)
        if name == 'DEFSUM':
            return self.define_sum(argument)
        if name == 'DEL':
            return self.delete(argument)
        start = len(name) + 2
        if name in FORMULA_COMMANDS:
            formulas = [self.parse(argument, start)]
            handler = FORMULA_COMMANDS[name]
        else:
            if ';' not in argument:
                raise CommandError("missing ';'")
            front, _, back = argument.partition(';')
            f = self.parse(front, start)
            if name in SUBSTITUTION_COMMANDS:
                return SUBSTITUTION_COMMANDS[name](f, back)
            formulas = [f, self.parse(back, start + len(front) + 1)]
            handler = PAIR_COMMANDS[name]
        variables = variables_of(*formulas)
        if name in TABLE_COMMANDS and len(variables) >= 9:
            raise CommandError(f'too many variables: {len(variables)}')
        return handler(*formulas, variables)

    def parse(self, text, start):
        return Parser(tokenize(text, start), start + len(text), self.names).parse()

    def assign(self, name, f):
        verb = 'redefined' if name in self.names else 'defined'
        self.names[name] = f
        return [f'{verb} {name} = {notation(f)}']

    def define(self, argument):
        name, has_formula, text = argument.partition(' ')
        if not has_formula:
            raise CommandError('missing argument')
        if not NAME.fullmatch(name):
            raise CommandError(f"invalid name '{name}'")
        return self.assign(name, self.parse(text, len(name) + 6))

    def define_sum(self, argument):
        if ';' not in argument:
            raise CommandError("missing ';'")
        front, _, back = argument.partition(';')
        words = front.split()
        if not words:
            raise CommandError('missing argument')
        name, variables = words[0], words[1:]
        if not NAME.fullmatch(name):
            raise CommandError(f"invalid name '{name}'")
        if (
            not variables
            or not all(VARIABLE.fullmatch(v) for v in variables)
            or any(a >= b for a, b in pairwise(variables))
        ):
            raise CommandError('bad variable list')
        if len(variables) >= 9:
            raise CommandError(f'too many variables: {len(variables)}')
        minterms = []
        for word in back.split():
            if (
                not MINTERM.fullmatch(word)
                or int(word) >= 1 << len(variables)
                or (minterms and int(word) <= minterms[-1])
            ):
                raise CommandError(f"bad minterm '{word}'")
            minterms.append(int(word))
        terms = []
        for minterm in minterms:
            bits = row_pattern(minterm, len(variables))
            factors = [Var(v) if bit == '1' else Not(Var(v)) for v, bit in zip(variables, bits)]
            terms.append(chain('&', factors))
        return self.assign(name, chain('|', terms) if terms else ZERO)

    def delete(self, name):
        if not NAME.fullmatch(name):
            raise CommandError(f"invalid name '{name}'")
        if name not in self.names:
            raise CommandError(f"undefined name '{name}'")
        del self.names[name]
        return [f'deleted {name}']

    def list_names(self):
        lines = [f'names: {len(self.names)}']
        lines += [f'{name} = {notation(self.names[name])}' for name in sorted(self.names)]
        return lines


def main():
    lines = sys.stdin.read().splitlines()
    workbench = Workbench()
    for line in lines[1:int(lines[0]) + 1]:
        try:
            output = workbench.execute(line)
        except CommandError as error:
            output = [f'error: {error}']
        print('\n'.join(output))


if __name__ == '__main__':
    main()
