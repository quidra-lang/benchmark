import math
import re
import sys
from dataclasses import dataclass
from fractions import Fraction
from functools import cmp_to_key

FUNCTION_NAMES = {'sin', 'cos', 'tan', 'exp', 'ln', 'sqrt'}
TOKEN_PATTERN = re.compile(
    r'(?P<number>[0-9]+)|(?P<word>[a-z][a-z0-9]*)|(?P<name>[A-Z][A-Z0-9]*)'
    r'|(?P<symbol>[-+*/^()])|(?P<space> +)|(?P<other>.)'
)
VARIABLE_PATTERN = re.compile(r'[a-z][a-z0-9]*')
NAME_PATTERN = re.compile(r'[A-Z][A-Z0-9]*')
ORDER_PATTERN = re.compile(r'[1-8]')
RATIONAL_PATTERN = re.compile(r'(-?[0-9]+)(?:/([0-9]+))?')
ASSIGNMENT_PATTERN = re.compile(r'([a-z][a-z0-9]*)=(-?[0-9]+(?:/[0-9]+)?)')
FLOAT_FUNCTIONS = {'sin': math.sin, 'cos': math.cos, 'tan': math.tan, 'exp': math.exp}


class CommandError(Exception):
    pass


class Expr:
    pass


@dataclass(frozen=True)
class Num(Expr):
    value: Fraction


@dataclass(frozen=True)
class Var(Expr):
    name: str


@dataclass(frozen=True)
class Sum(Expr):
    terms: tuple[Expr, ...]


@dataclass(frozen=True)
class Prod(Expr):
    factors: tuple[Expr, ...]


@dataclass(frozen=True)
class Pow(Expr):
    base: Expr
    exponent: Expr


@dataclass(frozen=True)
class Func(Expr):
    name: str
    argument: Expr


ZERO = Num(Fraction(0))
ONE = Num(Fraction(1))
MINUS_ONE = Num(Fraction(-1))
HALF = Num(Fraction(1, 2))


def compare(a, b):
    return (a > b) - (a < b)


def is_integer(f):
    return isinstance(f, Num) and f.value.denominator == 1


def has_negative_exponent(f):
    return isinstance(f, Pow) and isinstance(f.exponent, Num) and f.exponent.value < 0


def base_of(f):
    return f.base if isinstance(f, Pow) else f


def exponent_of(f):
    return f.exponent if isinstance(f, Pow) else ONE


def split_coefficient(f):
    match f:
        case Num(value):
            return value, ()
        case Prod(factors) if isinstance(factors[0], Num):
            return factors[0].value, factors[1:]
        case Prod(factors):
            return Fraction(1), factors
    return Fraction(1), (f,)


def order_key(f):
    match f:
        case Var(name):
            return (0, name)
        case Sum(terms):
            return (1, tuple(map(order_key, terms)))
        case Prod(factors):
            return (2, tuple(map(order_key, factors)))
        case Pow(base, exponent):
            return (3, order_key(base), order_key(exponent))
        case Func(name, argument):
            return (4, name, order_key(argument))
        case Num(value):
            return (5, value)


def compare_exponents(x, y):
    match x, y:
        case Num(a), Num(b):
            return compare(a, b)
        case Num(), _:
            return -1
        case _, Num():
            return 1
    return compare(order_key(x), order_key(y))


def monomial_exponents(term):
    return {base_of(factor): exponent_of(factor) for factor in split_coefficient(term)[1]}


def term_order(s, t):
    s_exponents = monomial_exponents(s)
    t_exponents = monomial_exponents(t)
    for base in sorted(s_exponents.keys() | t_exponents.keys(), key=order_key):
        order = compare_exponents(t_exponents.get(base, ZERO), s_exponents.get(base, ZERO))
        if order != 0:
            return order
    return 0


def make_product(coefficient, factors):
    if not factors:
        return Num(coefficient)
    if coefficient != 1:
        return Prod((Num(coefficient), *factors))
    return factors[0] if len(factors) == 1 else Prod(tuple(factors))


def add(*operands):
    terms = []
    for operand in operands:
        match operand:
            case Sum(items):
                terms.extend(items)
            case Prod((Num() as coefficient, Sum(items))):
                terms.extend(mul(coefficient, item) for item in items)
            case _:
                terms.append(operand)
    coefficients = {}
    for term in terms:
        coefficient, monomial = split_coefficient(term)
        coefficients[monomial] = coefficients.get(monomial, 0) + coefficient
    built = [make_product(c, monomial) for monomial, c in coefficients.items() if c != 0]
    built.sort(key=cmp_to_key(term_order))
    if not built:
        return ZERO
    return built[0] if len(built) == 1 else Sum(tuple(built))


def mul(*operands):
    factors = []
    for operand in operands:
        if isinstance(operand, Prod):
            factors.extend(operand.factors)
        else:
            factors.append(operand)
    coefficient = Fraction(1)
    groups = {}
    for factor in factors:
        if isinstance(factor, Num):
            coefficient *= factor.value
        else:
            groups.setdefault(base_of(factor), []).append(factor)
    if coefficient == 0:
        return ZERO
    results = [
        group[0] if len(group) == 1 else power(base, add(*map(exponent_of, group)))
        for base, group in groups.items()
    ]
    bases = [base_of(result) for result in results]
    needs_regrouping = any(isinstance(result, (Num, Prod)) for result in results)
    if needs_regrouping or len(set(bases)) < len(bases):
        return mul(Num(coefficient), *results)
    results.sort(key=lambda result: order_key(base_of(result)))
    return make_product(coefficient, results)


def integer_root(value, degree):
    estimate = round(value ** (1 / degree))
    for candidate in (estimate - 1, estimate, estimate + 1):
        if candidate >= 0 and candidate**degree == value:
            return candidate
    return None


def power(base, exponent):
    if exponent == ZERO:
        return ONE
    if exponent == ONE:
        return base
    if isinstance(base, Num):
        if base.value == 1:
            return ONE
        if not isinstance(exponent, Num):
            return Pow(base, exponent)
        b, x = base.value, exponent.value
        if b == 0:
            if x > 0:
                return ZERO
            raise CommandError('division by zero')
        if x.denominator == 1:
            return Num(b**x.numerator)
        if b > 0:
            s = integer_root(b.numerator, x.denominator)
            t = integer_root(b.denominator, x.denominator)
            if s is not None and t is not None:
                return Num(Fraction(s, t) ** x.numerator)
        return Pow(base, exponent)
    if is_integer(exponent):
        if isinstance(base, Pow):
            return power(base.base, mul(base.exponent, exponent))
        if isinstance(base, Prod):
            return mul(*(power(factor, exponent) for factor in base.factors))
    return Pow(base, exponent)


def apply_function(name, argument):
    if name == 'sqrt':
        return power(argument, HALF)
    if argument == ZERO and name in ('sin', 'tan'):
        return ZERO
    if argument == ZERO and name in ('cos', 'exp'):
        return ONE
    if argument == ONE and name == 'ln':
        return ZERO
    if name in ('sin', 'cos', 'tan') and split_coefficient(argument)[0] < 0:
        negated = mul(MINUS_ONE, argument)
        if name == 'cos':
            return apply_function('cos', negated)
        return mul(MINUS_ONE, apply_function(name, negated))
    match name, argument:
        case ('exp', Func('ln', inner)) | ('ln', Func('exp', inner)):
            return inner
    return Func(name, argument)


def variables(f):
    match f:
        case Var(name):
            return {name}
        case Sum(items) | Prod(items):
            return set().union(*map(variables, items))
        case Pow(base, exponent):
            return variables(base) | variables(exponent)
        case Func(_, argument):
            return variables(argument)
    return set()


def derivative(f, v):
    match f:
        case Num():
            return ZERO
        case Var(name):
            return ONE if name == v else ZERO
        case Sum(terms):
            return add(*(derivative(term, v) for term in terms))
        case Prod(factors):
            return add(*(
                mul(*factors[:i], derivative(factor, v), *factors[i + 1:])
                for i, factor in enumerate(factors)
            ))
        case Pow(base, exponent):
            if v not in variables(exponent):
                return mul(exponent, power(base, add(exponent, MINUS_ONE)), derivative(base, v))
            if v not in variables(base):
                return mul(f, apply_function('ln', base), derivative(exponent, v))
            return mul(f, add(
                mul(derivative(exponent, v), apply_function('ln', base)),
                mul(exponent, derivative(base, v), power(base, MINUS_ONE)),
            ))
        case Func(name, argument):
            match name:
                case 'sin':
                    outer = apply_function('cos', argument)
                case 'cos':
                    outer = mul(MINUS_ONE, apply_function('sin', argument))
                case 'tan':
                    outer = power(apply_function('cos', argument), Num(Fraction(-2)))
                case 'exp':
                    outer = f
                case _:
                    outer = power(argument, MINUS_ONE)
            return mul(outer, derivative(argument, v))


def substitute(f, values):
    match f:
        case Var(name):
            return values.get(name, f)
        case Sum(terms):
            return add(*(substitute(term, values) for term in terms))
        case Prod(factors):
            return mul(*(substitute(factor, values) for factor in factors))
        case Pow(base, exponent):
            return power(substitute(base, values), substitute(exponent, values))
        case Func(name, argument):
            return apply_function(name, substitute(argument, values))
    return f


def terms_of(f):
    return f.terms if isinstance(f, Sum) else (f,)


def multiply_out(g, h):
    return add(*(mul(a, b) for a in terms_of(g) for b in terms_of(h)))


def expand(f):
    match f:
        case Func(name, argument):
            return apply_function(name, expand(argument))
        case Sum(terms):
            return add(*map(expand, terms))
        case Prod(factors):
            result = expand(factors[0])
            for factor in factors[1:]:
                result = multiply_out(result, expand(factor))
            return result
        case Pow(base, exponent):
            base = expand(base)
            exponent = expand(exponent)
            if isinstance(base, Sum) and is_integer(exponent) and exponent.value > 0:
                result = base
                for _ in range(exponent.value.numerator - 1):
                    result = multiply_out(result, base)
                return result
            return power(base, exponent)
    return f


def numeric_value(f):
    match f:
        case Num(value):
            return value.numerator / value.denominator
        case Sum(terms):
            total = 0.0
            for term in terms:
                total += numeric_value(term)
            return total
        case Prod(factors):
            product = 1.0
            for factor in factors:
                product *= numeric_value(factor)
            return product
        case Pow(base, exponent):
            u = numeric_value(base)
            z = numeric_value(exponent)
            integral = is_integer(exponent) if isinstance(exponent, Num) else z.is_integer()
            if not integral and u < 0:
                raise CommandError('domain error')
            return math.sqrt(u) if exponent == HALF else u**z
        case Func(name, argument):
            a = numeric_value(argument)
            if name != 'ln':
                return FLOAT_FUNCTIONS[name](a)
            if a <= 0:
                raise CommandError('domain error')
            return math.log(a)


def show(f):
    match f:
        case Num(value):
            return str(value)
        case Var(name):
            return name
        case Func(name, argument):
            return f'{name}({show(argument)})'
        case Sum(terms):
            text = show(terms[0])
            for term in terms[1:]:
                part = show(term)
                text += f' - {part[1:]}' if part.startswith('-') else f' + {part}'
            return text
        case Prod():
            return show_quotient(*split_coefficient(f))
        case Pow(base, exponent):
            if has_negative_exponent(f):
                return show_quotient(Fraction(1), (f,))
            return show_power(base, exponent)


def is_atomic(f):
    match f:
        case Num(value):
            return value.denominator == 1 and value >= 0
        case Var() | Func():
            return True
        case Pow(_, exponent):
            return exponent == HALF
    return False


def show_atom(f):
    return show(f) if is_atomic(f) else f'({show(f)})'


def show_power(base, exponent):
    if exponent == HALF:
        return f'sqrt({show(base)})'
    return f'{show_atom(base)}^{show_atom(exponent)}'


def show_factor(f):
    match f:
        case Sum():
            return f'({show(f)})'
        case Pow(base, exponent):
            return show_power(base, exponent)
    return show(f)


def show_quotient(coefficient, factors):
    magnitude = abs(coefficient)
    numerator = [str(magnitude.numerator)] if magnitude.numerator != 1 else []
    denominator = [str(magnitude.denominator)] if magnitude.denominator != 1 else []
    for factor in factors:
        if not has_negative_exponent(factor):
            numerator.append(show_factor(factor))
            continue
        reciprocal = -factor.exponent.value
        if reciprocal == 1:
            denominator.append(show_factor(factor.base))
        else:
            denominator.append(show_power(factor.base, Num(reciprocal)))
    text = '*'.join(numerator) or '1'
    if len(denominator) == 1:
        text += '/' + denominator[0]
    elif denominator:
        text += '/(' + '*'.join(denominator) + ')'
    return '-' + text if coefficient < 0 else text


def tokenize(text):
    tokens = []
    for token in TOKEN_PATTERN.finditer(text):
        kind, value = token.lastgroup, token.group()
        if kind == 'other':
            raise CommandError(f"invalid character '{value}'")
        if kind == 'word':
            kind = 'function' if value in FUNCTION_NAMES else 'variable'
        if kind != 'space':
            tokens.append((kind, value))
    return tokens


class Parser:
    def __init__(self, tokens, names):
        self.tokens = tokens
        self.names = names
        self.position = 0

    def peek(self):
        return self.tokens[self.position] if self.position < len(self.tokens) else None

    def accept(self, *symbols):
        token = self.peek()
        if token is not None and token[0] == 'symbol' and token[1] in symbols:
            self.position += 1
            return token[1]
        return None

    def expect(self, symbol):
        if not self.accept(symbol):
            raise self.unexpected()

    def unexpected(self):
        token = self.peek()
        if token is None:
            return CommandError('unexpected end of expression')
        return CommandError(f"unexpected '{token[1]}'")

    def parse(self):
        tree = self.expression()
        if self.peek() is not None:
            raise self.unexpected()
        return tree

    def expression(self):
        tree = self.term()
        while operator := self.accept('+', '-'):
            tree = (operator, tree, self.term())
        return tree

    def term(self):
        tree = self.unary()
        while operator := self.accept('*', '/'):
            tree = (operator, tree, self.unary())
        return tree

    def unary(self):
        if self.accept('-'):
            return ('neg', self.unary())
        return self.power_expression()

    def power_expression(self):
        base = self.atom()
        if self.accept('^'):
            return ('^', base, self.unary())
        return base

    def atom(self):
        token = self.peek()
        if token is None or (token[0] == 'symbol' and token[1] != '('):
            raise self.unexpected()
        kind, text = token
        self.position += 1
        match kind:
            case 'number':
                return Num(Fraction(int(text)))
            case 'variable':
                return Var(text)
            case 'name':
                if text not in self.names:
                    raise CommandError(f"undefined name '{text}'")
                return self.names[text]
            case 'function':
                self.expect('(')
                argument = self.expression()
                self.expect(')')
                return ('fn', text, argument)
        inner = self.expression()
        self.expect(')')
        return inner


def evaluate(tree):
    match tree:
        case ('neg', operand):
            return mul(MINUS_ONE, evaluate(operand))
        case ('fn', name, argument):
            return apply_function(name, evaluate(argument))
        case (operator, left, right):
            left, right = evaluate(left), evaluate(right)
            match operator:
                case '+':
                    return add(left, right)
                case '-':
                    return add(left, mul(MINUS_ONE, right))
                case '*':
                    return mul(left, right)
                case '/':
                    return mul(left, power(right, MINUS_ONE))
                case '^':
                    return power(left, right)
    return tree


def parse_expression(text, names):
    return evaluate(Parser(tokenize(text), names).parse())


def parse_rational(text):
    found = RATIONAL_PATTERN.fullmatch(text)
    if found is None:
        raise CommandError(f"invalid number '{text}'")
    denominator = int(found[2]) if found[2] else 1
    if denominator == 0:
        raise CommandError('division by zero')
    return Fraction(int(found[1]), denominator)


def is_variable_name(text):
    return VARIABLE_PATTERN.fullmatch(text) is not None and text not in FUNCTION_NAMES


def check_field(kind, field, names):
    match kind:
        case 'e':
            return parse_expression(field, names)
        case 'v':
            if not is_variable_name(field):
                raise CommandError(f"invalid variable '{field}'")
        case 'n':
            if ORDER_PATTERN.fullmatch(field) is None:
                raise CommandError(f"invalid order '{field}'")
            return int(field)
        case 'c':
            return parse_rational(field)
    return field


def run_let(argument, names):
    if '=' not in argument:
        raise CommandError('wrong number of arguments')
    name, _, text = argument.partition('=')
    name = name.strip(' ')
    if NAME_PATTERN.fullmatch(name) is None:
        raise CommandError(f"invalid name '{name}'")
    form = parse_expression(text.strip(' '), names)
    names[name] = form
    return [f'{name} = {show(form)}']


def run_simplify(f):
    return [f'simplified: {show(f)}']


def run_expand(f):
    return [f'expanded: {show(expand(f))}']


def run_diff(f, v):
    return [f'd/d{v} = {show(derivative(f, v))}']


def run_diffn(f, v, order):
    lines = []
    for k in range(1, order + 1):
        f = derivative(f, v)
        lines.append(f'd^{k}/d{v}^{k} = {show(f)}')
    return lines


def run_grad(f):
    variable_names = sorted(variables(f))
    if not variable_names:
        return ['no variables']
    return [f'd/d{v} = {show(derivative(f, v))}' for v in variable_names]


def run_hessian(f):
    variable_names = sorted(variables(f))
    if not variable_names:
        return ['no variables']
    lines = []
    for i, first in enumerate(variable_names):
        partial = derivative(f, first)
        for second in variable_names[i:]:
            lines.append(f'd2/d{first}d{second} = {show(derivative(partial, second))}')
    return lines


def run_implicit(f, v, w):
    if v == w:
        raise CommandError('same variable')
    slope = mul(MINUS_ONE, derivative(f, v), power(derivative(f, w), MINUS_ONE))
    return [f'd{w}/d{v} = {show(slope)}']


def run_subst(f, v, replacement):
    return [f'substituted: {show(substitute(f, {v: replacement}))}']


def run_eval(f, assignment_text=''):
    values = {}
    for word in assignment_text.split():
        found = ASSIGNMENT_PATTERN.fullmatch(word)
        if found is None or found[1] in FUNCTION_NAMES:
            raise CommandError(f"invalid assignment '{word}'")
        value = parse_rational(found[2])
        if found[1] in values:
            raise CommandError(f'duplicate variable {found[1]}')
        values[found[1]] = Num(value)
    for name in sorted(variables(f)):
        if name not in values:
            raise CommandError(f'no value for {name}')
    result = substitute(f, values)
    if isinstance(result, Num):
        return [f'exact: {show(result)}']
    return [f'approx: {numeric_value(result):.6f}']


def run_tangent(f, v, x0):
    point = {v: Num(x0)}
    slope = substitute(derivative(f, v), point)
    y0 = substitute(f, point)
    tangent = f'tangent: y = {show(add(mul(slope, Var(v)), y0, mul(Num(-x0), slope)))}'
    if slope == ZERO:
        return [tangent, f'normal: {v} = {show(Num(x0))}']
    k = power(slope, MINUS_ONE)
    normal = add(mul(MINUS_ONE, k, Var(v)), y0, mul(Num(x0), k))
    return [tangent, f'normal: y = {show(normal)}']


def run_limit(f, v, x0):
    numerator = []
    denominator = []
    for factor in f.factors if isinstance(f, Prod) else (f,):
        if has_negative_exponent(factor):
            denominator.append(power(factor.base, Num(-factor.exponent.value)))
        else:
            numerator.append(factor)
    top, bottom = mul(*numerator), mul(*denominator)
    point = {v: Num(x0)}
    for k in range(6):
        top_value = substitute(top, point)
        bottom_value = substitute(bottom, point)
        if bottom_value != ZERO:
            return [f'limit: {show(mul(top_value, power(bottom_value, MINUS_ONE)))}']
        if top_value != ZERO:
            return ['limit: unbounded']
        if k < 5:
            top, bottom = derivative(top, v), derivative(bottom, v)
    return ['limit: unknown']


def run_taylor(f, v, x0, order):
    derivatives = [f]
    for _ in range(order):
        derivatives.append(derivative(derivatives[-1], v))
    point = {v: Num(x0)}
    terms = []
    for k, fk in enumerate(derivatives):
        coefficient = mul(substitute(fk, point), Num(Fraction(1, math.factorial(k))))
        terms.append(mul(coefficient, power(add(Var(v), Num(-x0)), Num(Fraction(k)))))
    return [f'taylor: {show(expand(add(*terms)))}']


COMMANDS = {
    'SIMPLIFY': ('e', run_simplify),
    'EXPAND': ('e', run_expand),
    'DIFF': ('ev', run_diff),
    'DIFFN': ('evn', run_diffn),
    'GRAD': ('e', run_grad),
    'HESSIAN': ('e', run_hessian),
    'IMPLICIT': ('evv', run_implicit),
    'SUBST': ('eve', run_subst),
    'EVAL': ('ea', run_eval),
    'TANGENT': ('evc', run_tangent),
    'LIMIT': ('evc', run_limit),
    'TAYLOR': ('evcn', run_taylor),
}


def run_command(line, names):
    command, separator, argument = line.partition(' ')
    if command == 'LET':
        return run_let(argument, names)
    if command not in COMMANDS:
        raise CommandError(f'unknown command {command}')
    kinds, handler = COMMANDS[command]
    fields = [field.strip(' ') for field in argument.split(';')] if separator else []
    allowed_counts = (1, 2) if command == 'EVAL' else (len(kinds),)
    if len(fields) not in allowed_counts:
        raise CommandError('wrong number of arguments')
    return handler(*(check_field(kind, field, names) for kind, field in zip(kinds, fields)))


def main():
    lines = sys.stdin.read().splitlines()
    names = {}
    for line in lines[1 : int(lines[0]) + 1]:
        try:
            output = run_command(line, names)
        except CommandError as error:
            output = [f'error: {error}']
        print('\n'.join(output))


if __name__ == '__main__':
    main()
