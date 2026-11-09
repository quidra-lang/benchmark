from fractions import Fraction
from math import isqrt
import sys


BASE_UNITS = ("kg", "m", "s", "A", "K", "mol", "cd")
DIMENSIONLESS = (0, 0, 0, 0, 0, 0, 0)
KINDS = (
    ("dimensionless", (0, 0, 0, 0, 0, 0, 0)),
    ("length", (0, 1, 0, 0, 0, 0, 0)),
    ("mass", (1, 0, 0, 0, 0, 0, 0)),
    ("time", (0, 0, 1, 0, 0, 0, 0)),
    ("current", (0, 0, 0, 1, 0, 0, 0)),
    ("temperature", (0, 0, 0, 0, 1, 0, 0)),
    ("amount", (0, 0, 0, 0, 0, 1, 0)),
    ("luminous_intensity", (0, 0, 0, 0, 0, 0, 1)),
    ("area", (0, 2, 0, 0, 0, 0, 0)),
    ("volume", (0, 3, 0, 0, 0, 0, 0)),
    ("speed", (0, 1, -1, 0, 0, 0, 0)),
    ("acceleration", (0, 1, -2, 0, 0, 0, 0)),
    ("density", (1, -3, 0, 0, 0, 0, 0)),
    ("momentum", (1, 1, -1, 0, 0, 0, 0)),
    ("force", (1, 1, -2, 0, 0, 0, 0)),
    ("energy", (1, 2, -2, 0, 0, 0, 0)),
    ("power", (1, 2, -3, 0, 0, 0, 0)),
    ("pressure", (1, -1, -2, 0, 0, 0, 0)),
    ("frequency", (0, 0, -1, 0, 0, 0, 0)),
    ("charge", (0, 0, 1, 1, 0, 0, 0)),
    ("voltage", (1, 2, -3, -1, 0, 0, 0)),
    ("resistance", (1, 2, -3, -2, 0, 0, 0)),
    ("conductance", (-1, -2, 3, 2, 0, 0, 0)),
    ("capacitance", (-1, -2, 4, 2, 0, 0, 0)),
    ("magnetic_flux", (1, 2, -2, -1, 0, 0, 0)),
    ("flux_density", (1, 0, -2, -1, 0, 0, 0)),
    ("inductance", (1, 2, -2, -2, 0, 0, 0)),
    ("illuminance", (0, -2, 0, 0, 0, 0, 1)),
    ("catalytic_activity", (0, 0, -1, 0, 0, 1, 0)),
)
KIND_DIMENSIONS = dict(KINDS)
KIND_NAMES = {dimension: name for name, dimension in KINDS}
BUILTIN_UNITS = (
    ("m", 1, 1, "length", True),
    ("g", 1, 1000, "mass", True),
    ("s", 1, 1, "time", True),
    ("A", 1, 1, "current", True),
    ("K", 1, 1, "temperature", True),
    ("mol", 1, 1, "amount", True),
    ("cd", 1, 1, "luminous_intensity", True),
    ("N", 1, 1, "force", True),
    ("J", 1, 1, "energy", True),
    ("W", 1, 1, "power", True),
    ("Pa", 1, 1, "pressure", True),
    ("Hz", 1, 1, "frequency", True),
    ("C", 1, 1, "charge", True),
    ("V", 1, 1, "voltage", True),
    ("ohm", 1, 1, "resistance", True),
    ("S", 1, 1, "conductance", True),
    ("F", 1, 1, "capacitance", True),
    ("Wb", 1, 1, "magnetic_flux", True),
    ("T", 1, 1, "flux_density", True),
    ("H", 1, 1, "inductance", True),
    ("lx", 1, 1, "illuminance", True),
    ("kat", 1, 1, "catalytic_activity", True),
    ("L", 1, 1000, "volume", True),
    ("t", 1000, 1, "mass", False),
    ("min", 60, 1, "time", False),
    ("h", 3600, 1, "time", False),
    ("day", 86400, 1, "time", False),
    ("in", 127, 5000, "length", False),
    ("ft", 381, 1250, "length", False),
    ("yd", 1143, 1250, "length", False),
    ("mi", 201168, 125, "length", False),
    ("nmi", 1852, 1, "length", False),
    ("ha", 10000, 1, "area", False),
    ("kn", 463, 900, "speed", False),
    ("bar", 100000, 1, "pressure", True),
    ("atm", 101325, 1, "pressure", False),
    ("Torr", 20265, 152, "pressure", False),
    ("cal", 523, 125, "energy", True),
    ("Wh", 3600, 1, "energy", True),
    ("Ah", 3600, 1, "charge", True),
    ("dC", 1, 1, "temperature", False),
    ("dF", 5, 9, "temperature", False),
)
PREFIXES = (
    ("G", 9), ("M", 6), ("k", 3), ("h", 2), ("da", 1),
    ("d", -1), ("c", -2), ("m", -3), ("u", -6), ("n", -9),
)
AUTO_PREFIXES = {9: "G", 6: "M", 3: "k", 0: "", -3: "m", -6: "u", -9: "n"}
EXPONENTS = (-3, -2, -1, 1, 2, 3)
FUNCTION_ARITY = {"abs": 1, "sqrt": 1, "min": 2, "max": 2}
SCALES = ("C", "F", "K", "R")
CELSIUS_OFFSET = Fraction(5463, 20)
FAHRENHEIT_OFFSET = Fraction(45967, 100)
UNIT_SYMBOLS = "*/^()-"
QUANTITY_SYMBOLS = "+-*/^(),"


class CommandError(Exception):
    pass


class Token:
    def __init__(self, kind, text, position):
        self.kind = kind
        self.text = text
        self.position = position


class UnitAtom:
    def __init__(self, kind, text, group=None):
        self.kind = kind
        self.text = text
        self.group = group


class UnitTerm:
    def __init__(self, atom, exponent):
        self.atom = atom
        self.exponent = exponent


class Node:
    def __init__(self, kind, text=None, children=(), unit=None):
        self.kind = kind
        self.text = text
        self.children = list(children)
        self.unit = unit


class Unit:
    def __init__(self, symbol, factor, dimension, prefixable, builtin, definition=None):
        self.symbol = symbol
        self.factor = factor
        self.dimension = dimension
        self.prefixable = prefixable
        self.builtin = builtin
        self.definition = definition


class Amount:
    def __init__(self, number, expression, factor, dimension):
        self.number = number
        self.expression = expression
        self.factor = factor
        self.dimension = dimension

    def base_value(self):
        return self.number * self.factor

    def label(self):
        return f"{fraction_text(self.number)} {self.expression}"


def fraction_text(value):
    if value.denominator == 1:
        return str(value.numerator)
    return f"{value.numerator}/{value.denominator}"


def decimal_text(value):
    whole, remainder = divmod(abs(value.numerator), value.denominator)
    digits = remainder * 10 ** 6 // value.denominator
    sign = "-" if value < 0 else ""
    return f"{sign}{whole}.{digits:06d}"


def quantity_text(value, unit):
    return f"{fraction_text(value)} {unit} ({decimal_text(value)})"


def add_dimensions(first, second):
    return tuple(a + b for a, b in zip(first, second))


def subtract_dimensions(first, second):
    return tuple(a - b for a, b in zip(first, second))


def scale_dimension(dimension, k):
    return tuple(exponent * k for exponent in dimension)


def dimension_text(dimension):
    parts = []
    for symbol, exponent in zip(BASE_UNITS, dimension):
        if exponent == 1:
            parts.append(symbol)
        elif exponent != 0:
            parts.append(f"{symbol}^{exponent}")
    return " ".join(parts) if parts else "1"


def kind_name(dimension):
    return KIND_NAMES.get(dimension, "-")


def check_dimensions(first, second):
    if first != second:
        raise CommandError(
            f"DIMENSION MISMATCH {dimension_text(first)} vs {dimension_text(second)}"
        )


def decimal_value(text):
    whole, _, fraction = text.partition(".")
    return Fraction(int(whole + fraction), 10 ** len(fraction))


def parse_number(text):
    negative = text.startswith("-")
    body = text[1:] if negative else text
    value = None
    if body.isdigit():
        value = Fraction(int(body))
    elif "." in body:
        whole, _, fraction = body.partition(".")
        if whole.isdigit() and fraction.isdigit():
            value = decimal_value(body)
    elif "/" in body:
        numerator, _, denominator = body.partition("/")
        if numerator.isdigit() and denominator.isdigit() and int(denominator) != 0:
            value = Fraction(int(numerator), int(denominator))
    if value is None:
        raise CommandError(f"BAD NUMBER {text}")
    return -value if negative else value


def check_name(name, reserved=()):
    if len(name) > 12 or not name.isalpha() or name in reserved:
        raise CommandError(f"BAD NAME {name}")


def exponent_value(text):
    value = int(text)
    if value not in EXPONENTS:
        raise CommandError(f"BAD EXPONENT {text}")
    return value


def square_root(value, dimension):
    if value < 0:
        raise CommandError("NEGATIVE ROOT")
    if any(exponent % 2 != 0 for exponent in dimension):
        raise CommandError(f"ODD DIMENSION {dimension_text(dimension)}")
    numerator_root = isqrt(value.numerator)
    denominator_root = isqrt(value.denominator)
    exact_numerator = numerator_root * numerator_root == value.numerator
    exact_denominator = denominator_root * denominator_root == value.denominator
    if not exact_numerator or not exact_denominator:
        raise CommandError("NOT EXACT")
    root_dimension = tuple(exponent // 2 for exponent in dimension)
    return Fraction(numerator_root, denominator_root), root_dimension


def to_kelvin(value, scale):
    if scale == "C":
        return value + CELSIUS_OFFSET
    if scale == "F":
        return (value + FAHRENHEIT_OFFSET) * 5 / 9
    if scale == "R":
        return value * 5 / 9
    return value


def from_kelvin(kelvin, scale):
    if scale == "C":
        return kelvin - CELSIUS_OFFSET
    if scale == "F":
        return kelvin * 9 / 5 - FAHRENHEIT_OFFSET
    if scale == "R":
        return kelvin * 9 / 5
    return kelvin


def prefix_exponent(value):
    size = abs(value)
    k = 0
    if size >= 1:
        while k < 9 and size >= Fraction(10) ** (k + 3):
            k += 3
    elif size > 0:
        while k > -9 and size < Fraction(10) ** k:
            k -= 3
    return k


def run_end(text, index, predicate):
    while index < len(text) and predicate(text[index]):
        index += 1
    return index


def tokenize(text, quantity):
    symbols = QUANTITY_SYMBOLS if quantity else UNIT_SYMBOLS
    tokens = []
    index = 0
    while index < len(text):
        char = text[index]
        kind = "invalid"
        end = index + 1
        if char.isalpha():
            kind = "name"
            end = run_end(text, index, str.isalpha)
        elif char.isdigit():
            kind = "digits"
            end = run_end(text, index, str.isdigit)
            if quantity and end + 1 < len(text) and text[end] == "." and text[end + 1].isdigit():
                kind = "decimal"
                end = run_end(text, end + 1, str.isdigit)
        elif char in symbols:
            kind = "symbol"
        elif quantity and char == "[":
            close = text.find("]", index + 1)
            if close > index + 1:
                kind = "unit"
                end = close + 1
        tokens.append(Token(kind, text[index:end], index + 1))
        index = end
    return tokens


class Parser:
    def __init__(self, text, quantity):
        self.text = text
        self.tokens = tokenize(text, quantity)
        self.index = 0

    def peek(self):
        if self.index < len(self.tokens):
            return self.tokens[self.index]
        return None

    def at_kind(self, kind):
        token = self.peek()
        return token is not None and token.kind == kind

    def at_symbol(self, symbol):
        return self.at_kind("symbol") and self.peek().text == symbol

    def advance(self):
        token = self.tokens[self.index]
        self.index += 1
        return token

    def fail(self):
        token = self.peek()
        position = "END" if token is None else token.position
        raise CommandError(f"SYNTAX {self.text} AT {position}")

    def expect_kind(self, kind):
        if not self.at_kind(kind):
            self.fail()
        return self.advance()

    def expect_symbol(self, symbol):
        if not self.at_symbol(symbol):
            self.fail()
        self.advance()

    def exponent(self):
        sign = ""
        if self.at_symbol("-"):
            self.advance()
            sign = "-"
        return sign + self.expect_kind("digits").text

    def parse(self):
        tree = self.expression()
        if self.peek() is not None:
            self.fail()
        return tree


class UnitParser(Parser):
    def __init__(self, text):
        super().__init__(text, False)

    def expression(self):
        terms = [("*", self.term())]
        while self.at_symbol("*") or self.at_symbol("/"):
            operator = self.advance().text
            terms.append((operator, self.term()))
        return terms

    def term(self):
        atom = self.atom()
        exponent = None
        if self.at_symbol("^"):
            self.advance()
            exponent = self.exponent()
        return UnitTerm(atom, exponent)

    def atom(self):
        if self.at_kind("name"):
            return UnitAtom("name", self.advance().text)
        if self.at_kind("digits") and not self.peek().text.startswith("0"):
            return UnitAtom("number", self.advance().text)
        self.expect_symbol("(")
        group = self.expression()
        self.expect_symbol(")")
        return UnitAtom("group", None, group)


class QuantityParser(Parser):
    def __init__(self, text):
        super().__init__(text, True)

    def expression(self):
        node = self.product()
        while self.at_symbol("+") or self.at_symbol("-"):
            operator = self.advance().text
            node = Node("binary", operator, (node, self.product()))
        return node

    def product(self):
        node = self.unary()
        while self.at_symbol("*") or self.at_symbol("/"):
            operator = self.advance().text
            node = Node("binary", operator, (node, self.unary()))
        return node

    def unary(self):
        if self.at_symbol("-"):
            self.advance()
            return Node("negate", None, (self.unary(),))
        return self.power()

    def power(self):
        node = self.primary()
        if self.at_symbol("^"):
            self.advance()
            return Node("power", self.exponent(), (node,))
        return node

    def primary(self):
        if self.at_kind("digits") or self.at_kind("decimal"):
            numeral = self.advance().text
            unit = None
            if self.at_kind("unit"):
                unit = self.advance().text[1:-1]
            return Node("numeral", numeral, unit=unit)
        if self.at_kind("unit"):
            return Node("numeral", "1", unit=self.advance().text[1:-1])
        if self.at_kind("name"):
            name = self.advance().text
            if not self.at_symbol("("):
                return Node("variable", name)
            self.advance()
            arguments = [self.expression()]
            while self.at_symbol(","):
                self.advance()
                arguments.append(self.expression())
            self.expect_symbol(")")
            return Node("call", name, arguments)
        self.expect_symbol("(")
        node = self.expression()
        self.expect_symbol(")")
        return node


def reduce_terms(terms):
    coefficient = Fraction(1)
    exponents = {}
    for operator, term in terms:
        term_coefficient, term_exponents = reduce_term(term)
        sign = -1 if operator == "/" else 1
        if operator == "/":
            coefficient /= term_coefficient
        else:
            coefficient *= term_coefficient
        for name, exponent in term_exponents.items():
            exponents[name] = exponents.get(name, 0) + sign * exponent
    return coefficient, exponents


def reduce_term(term):
    atom = term.atom
    if atom.kind == "name":
        coefficient, exponents = Fraction(1), {atom.text: 1}
    elif atom.kind == "number":
        coefficient, exponents = Fraction(int(atom.text)), {}
    else:
        coefficient, exponents = reduce_terms(atom.group)
    if term.exponent is not None:
        k = int(term.exponent)
        coefficient = coefficient ** k
        exponents = {name: exponent * k for name, exponent in exponents.items()}
    return coefficient, exponents


def reduced_text(coefficient, exponents):
    parts = []
    for name, exponent in exponents.items():
        if exponent == 1:
            parts.append(name)
        elif exponent != 0:
            parts.append(f"{name}^{exponent}")
    if coefficient != 1:
        parts.insert(0, fraction_text(coefficient))
    return " ".join(parts) if parts else "1"


class UnitRegistry:
    def __init__(self):
        self.units = [
            Unit(symbol, Fraction(numerator, denominator), KIND_DIMENSIONS[kind], prefixable, True)
            for symbol, numerator, denominator, kind, prefixable in BUILTIN_UNITS
        ]

    def find(self, symbol):
        for unit in self.units:
            if unit.symbol == symbol:
                return unit
        return None

    def resolve(self, name):
        unit = self.find(name)
        if unit is not None:
            return unit.factor, unit.dimension
        for prefix, exponent in PREFIXES:
            if name.startswith(prefix):
                unit = self.find(name[len(prefix):])
                if unit is not None and unit.prefixable:
                    return Fraction(10) ** exponent * unit.factor, unit.dimension
        return None

    def evaluate(self, terms):
        factor = Fraction(1)
        dimension = DIMENSIONLESS
        for operator, term in terms:
            term_factor, term_dimension = self.evaluate_term(term)
            if operator == "/":
                factor /= term_factor
                dimension = subtract_dimensions(dimension, term_dimension)
            else:
                factor *= term_factor
                dimension = add_dimensions(dimension, term_dimension)
        return factor, dimension

    def evaluate_term(self, term):
        atom = term.atom
        if atom.kind == "name":
            resolved = self.resolve(atom.text)
            if resolved is None:
                raise CommandError(f"UNKNOWN UNIT {atom.text}")
            factor, dimension = resolved
        elif atom.kind == "number":
            factor, dimension = Fraction(int(atom.text)), DIMENSIONLESS
        else:
            factor, dimension = self.evaluate(atom.group)
        if term.exponent is not None:
            k = exponent_value(term.exponent)
            factor = factor ** k
            dimension = scale_dimension(dimension, k)
        return factor, dimension

    def measure(self, text):
        return self.evaluate(UnitParser(text).parse())

    def simplified(self, dimension):
        for unit in self.units:
            if unit.factor == 1 and unit.dimension == dimension:
                return unit.symbol
        return dimension_text(dimension)

    def matching(self, dimension):
        units = [unit for unit in self.units if unit.dimension == dimension]
        return sorted(units, key=lambda unit: (unit.factor, unit.symbol))

    def reference(self, dimension):
        for unit in self.units:
            if unit.prefixable and unit.dimension == dimension:
                return unit
        return None

    def user_units(self):
        return [unit for unit in self.units if not unit.builtin]


class Calculator:
    def __init__(self):
        self.registry = UnitRegistry()
        self.variables = {}
        self.output = []
        self.handlers = {
            "DEFINE": self.define, "UNDEF": self.undefine,
            "DEFS": self.show_definitions, "CONVERT": self.convert,
            "INVERT": self.invert, "DIM": self.show_dimension,
            "REDUCE": self.reduce, "SIMPLIFY": self.simplify,
            "ADD": self.add, "SUB": self.subtract,
            "MUL": self.multiply, "DIV": self.divide,
            "TEMP": self.temperature, "COMPARE": self.compare,
            "LIST": self.list_units, "TABLE": self.table,
            "AUTO": self.auto, "SPLIT": self.split,
            "LET": self.let, "EVAL": self.evaluate_command,
            "VARS": self.show_variables,
        }

    def emit(self, line):
        self.output.append(line)

    def amount(self, number_text, expression):
        number = parse_number(number_text)
        factor, dimension = self.registry.measure(expression)
        return Amount(number, expression, factor, dimension)

    def quantity(self, text):
        return self.evaluate(QuantityParser(text).parse())

    def evaluate(self, node):
        if node.kind == "numeral":
            value = decimal_value(node.text)
            if node.unit is None:
                return value, DIMENSIONLESS
            factor, dimension = self.registry.measure(node.unit)
            return value * factor, dimension
        if node.kind == "variable":
            if node.text not in self.variables:
                raise CommandError(f"UNKNOWN VARIABLE {node.text}")
            return self.variables[node.text]
        if node.kind == "call":
            return self.call(node)
        if node.kind == "negate":
            value, dimension = self.evaluate(node.children[0])
            return -value, dimension
        if node.kind == "power":
            value, dimension = self.evaluate(node.children[0])
            k = exponent_value(node.text)
            if value == 0 and k < 0:
                raise CommandError("DIVISION BY ZERO")
            return value ** k, scale_dimension(dimension, k)
        return self.binary(node)

    def binary(self, node):
        left_value, left_dimension = self.evaluate(node.children[0])
        right_value, right_dimension = self.evaluate(node.children[1])
        if node.text == "+" or node.text == "-":
            check_dimensions(left_dimension, right_dimension)
            if node.text == "+":
                return left_value + right_value, left_dimension
            return left_value - right_value, left_dimension
        if node.text == "*":
            return left_value * right_value, add_dimensions(left_dimension, right_dimension)
        if right_value == 0:
            raise CommandError("DIVISION BY ZERO")
        return left_value / right_value, subtract_dimensions(left_dimension, right_dimension)

    def call(self, node):
        name = node.text
        if name not in FUNCTION_ARITY:
            raise CommandError(f"UNKNOWN FUNCTION {name}")
        if len(node.children) != FUNCTION_ARITY[name]:
            raise CommandError(f"BAD ARGUMENTS {name}")
        arguments = [self.evaluate(child) for child in node.children]
        if name == "abs":
            value, dimension = arguments[0]
            return abs(value), dimension
        if name == "sqrt":
            value, dimension = arguments[0]
            return square_root(value, dimension)
        first, second = arguments
        check_dimensions(first[1], second[1])
        if name == "min":
            return first if first[0] <= second[0] else second
        return first if first[0] >= second[0] else second

    def define(self, arguments):
        name, _, number_text, expression = arguments
        check_name(name)
        number = parse_number(number_text)
        factor, dimension = self.registry.measure(expression)
        if name in KIND_DIMENSIONS or self.registry.resolve(name) is not None:
            raise CommandError(f"NAME TAKEN {name}")
        if number <= 0:
            raise CommandError(f"NOT POSITIVE {number_text}")
        unit_factor = number * factor
        unit = Unit(name, unit_factor, dimension, False, False, (number, expression))
        self.registry.units.append(unit)
        self.emit(
            f"DEFINE {name} factor={fraction_text(unit_factor)} "
            f"dim={dimension_text(dimension)} kind={kind_name(dimension)}"
        )

    def undefine(self, arguments):
        name = arguments[0]
        unit = self.registry.find(name)
        if unit is not None and unit.builtin:
            raise CommandError(f"BUILTIN UNIT {name}")
        if unit is None:
            raise CommandError(f"NOT DEFINED {name}")
        self.registry.units.remove(unit)
        self.emit(f"UNDEF {name}")

    def show_definitions(self, arguments):
        units = self.registry.user_units()
        self.emit(f"DEFS count={len(units)}")
        for unit in units:
            number, expression = unit.definition
            self.emit(
                f"DEF {unit.symbol} = {fraction_text(number)} {expression} "
                f"factor={fraction_text(unit.factor)} dim={dimension_text(unit.dimension)}"
            )

    def convert(self, arguments):
        source = self.amount(arguments[0], arguments[1])
        target = arguments[3]
        factor, dimension = self.registry.measure(target)
        check_dimensions(source.dimension, dimension)
        result = source.base_value() / factor
        self.emit(f"CONVERT {source.label()} = {quantity_text(result, target)}")

    def invert(self, arguments):
        source = self.amount(arguments[0], arguments[1])
        target = arguments[3]
        factor, dimension = self.registry.measure(target)
        product = add_dimensions(source.dimension, dimension)
        if source.dimension == DIMENSIONLESS or product != DIMENSIONLESS:
            raise CommandError(
                f"NOT RECIPROCAL {dimension_text(source.dimension)} vs {dimension_text(dimension)}"
            )
        if source.number == 0:
            raise CommandError("DIVISION BY ZERO")
        result = 1 / source.base_value() / factor
        self.emit(f"INVERT {source.label()} = {quantity_text(result, target)}")

    def show_dimension(self, arguments):
        expression = arguments[0]
        factor, dimension = self.registry.measure(expression)
        self.emit(
            f"DIM {expression} = {dimension_text(dimension)} "
            f"factor={fraction_text(factor)} kind={kind_name(dimension)}"
        )

    def reduce(self, arguments):
        expression = arguments[0]
        terms = UnitParser(expression).parse()
        self.registry.evaluate(terms)
        coefficient, exponents = reduce_terms(terms)
        self.emit(f"REDUCE {expression} = {reduced_text(coefficient, exponents)}")

    def simplify(self, arguments):
        expression = arguments[0]
        factor, dimension = self.registry.measure(expression)
        unit = self.registry.simplified(dimension)
        self.emit(f"SIMPLIFY {expression} = {quantity_text(factor, unit)}")

    def operands(self, arguments):
        first = self.amount(arguments[0], arguments[1])
        second = self.amount(arguments[2], arguments[3])
        target = None
        if len(arguments) == 6:
            factor, dimension = self.registry.measure(arguments[5])
            target = (arguments[5], factor, dimension)
        return first, second, target

    def add(self, arguments):
        self.add_or_subtract("ADD", "+", arguments)

    def subtract(self, arguments):
        self.add_or_subtract("SUB", "-", arguments)

    def add_or_subtract(self, command, symbol, arguments):
        first, second, target = self.operands(arguments)
        check_dimensions(first.dimension, second.dimension)
        result_text, result_factor = first.expression, first.factor
        if target is not None:
            result_text, result_factor, result_dimension = target
            check_dimensions(first.dimension, result_dimension)
        if command == "ADD":
            total = first.base_value() + second.base_value()
        else:
            total = first.base_value() - second.base_value()
        result = total / result_factor
        self.emit(
            f"{command} {first.label()} {symbol} {second.label()} = "
            f"{quantity_text(result, result_text)}"
        )

    def multiply(self, arguments):
        self.multiply_or_divide("MUL", "*", arguments)

    def divide(self, arguments):
        self.multiply_or_divide("DIV", "/", arguments)

    def multiply_or_divide(self, command, symbol, arguments):
        first, second, target = self.operands(arguments)
        if command == "MUL":
            dimension = add_dimensions(first.dimension, second.dimension)
        else:
            dimension = subtract_dimensions(first.dimension, second.dimension)
            if second.number == 0:
                raise CommandError("DIVISION BY ZERO")
        if target is not None:
            target_text, target_factor, target_dimension = target
            check_dimensions(dimension, target_dimension)
        if command == "MUL":
            product = first.number * second.number
            total = first.base_value() * second.base_value()
            combined = f"{first.expression}*{second.expression}"
        else:
            product = first.number / second.number
            total = first.base_value() / second.base_value()
            denominator = second.expression
            if "*" in denominator or "/" in denominator:
                denominator = f"({denominator})"
            combined = f"{first.expression}/{denominator}"
        prefix = f"{command} {first.label()} {symbol} {second.label()} = "
        if target is not None:
            self.emit(prefix + quantity_text(total / target_factor, target_text))
        else:
            unit = self.registry.simplified(dimension)
            self.emit(
                prefix + f"{fraction_text(product)} {combined} = {quantity_text(total, unit)}"
            )

    def temperature(self, arguments):
        value = parse_number(arguments[0])
        source, target = arguments[1], arguments[3]
        for scale in (source, target):
            if scale not in SCALES:
                raise CommandError(f"UNKNOWN SCALE {scale}")
        kelvin = to_kelvin(value, source)
        if kelvin < 0:
            raise CommandError("BELOW ABSOLUTE ZERO")
        result = from_kelvin(kelvin, target)
        self.emit(f"TEMP {fraction_text(value)} {source} = {quantity_text(result, target)}")

    def compare(self, arguments):
        first = self.amount(arguments[0], arguments[1])
        second = self.amount(arguments[2], arguments[3])
        check_dimensions(first.dimension, second.dimension)
        a, b = first.base_value(), second.base_value()
        if a < b:
            relation = "<"
        elif a == b:
            relation = "="
        else:
            relation = ">"
        ratio = fraction_text(a / b) if b != 0 else "undefined"
        self.emit(f"COMPARE {first.label()} {relation} {second.label()} ratio={ratio}")

    def list_units(self, arguments):
        argument = arguments[0]
        if argument in KIND_DIMENSIONS:
            dimension = KIND_DIMENSIONS[argument]
        else:
            _, dimension = self.registry.measure(argument)
        units = self.registry.matching(dimension)
        self.emit(
            f"LIST {argument} dim={dimension_text(dimension)} "
            f"kind={kind_name(dimension)} count={len(units)}"
        )
        for unit in units:
            origin = "builtin" if unit.builtin else "user"
            prefix = "yes" if unit.prefixable else "no"
            self.emit(
                f"UNIT {unit.symbol} factor={fraction_text(unit.factor)} "
                f"origin={origin} prefix={prefix}"
            )

    def table(self, arguments):
        source = self.amount(arguments[0], arguments[1])
        units = self.registry.matching(source.dimension)
        self.emit(
            f"TABLE {source.label()} dim={dimension_text(source.dimension)} count={len(units)}"
        )
        for unit in units:
            result = source.base_value() / unit.factor
            self.emit(f"ROW {quantity_text(result, unit.symbol)}")

    def auto(self, arguments):
        source = self.amount(arguments[0], arguments[1])
        reference = self.registry.reference(source.dimension)
        if reference is None:
            raise CommandError(f"NO PREFIXABLE UNIT {dimension_text(source.dimension)}")
        value = source.base_value() / reference.factor
        k = prefix_exponent(value)
        scaled = value / Fraction(10) ** k
        unit = AUTO_PREFIXES[k] + reference.symbol
        self.emit(f"AUTO {source.label()} = {quantity_text(scaled, unit)}")

    def split(self, arguments):
        source = self.amount(arguments[0], arguments[1])
        parts = arguments[3].split(",")
        measures = [self.registry.measure(part) for part in parts]
        if source.number < 0:
            raise CommandError("NEGATIVE VALUE")
        for _, dimension in measures:
            check_dimensions(source.dimension, dimension)
        for index in range(len(measures) - 1):
            if measures[index][0] <= measures[index + 1][0]:
                raise CommandError("UNIT ORDER")
        remaining = source.base_value()
        pieces = []
        for part, (factor, _) in zip(parts[:-1], measures[:-1]):
            count = remaining // factor
            remaining = remaining - count * factor
            pieces.append(f"{count} {part}")
        pieces.append(quantity_text(remaining / measures[-1][0], parts[-1]))
        self.emit(f"SPLIT {source.label()} = " + " ".join(pieces))

    def let(self, arguments):
        name, _, expression = arguments
        check_name(name, FUNCTION_ARITY)
        value, dimension = self.quantity(expression)
        self.variables[name] = (value, dimension)
        unit = self.registry.simplified(dimension)
        self.emit(f"LET {name} = {quantity_text(value, unit)}")

    def evaluate_command(self, arguments):
        expression = arguments[0]
        value, dimension = self.quantity(expression)
        if len(arguments) == 3:
            target = arguments[2]
            factor, target_dimension = self.registry.measure(target)
            check_dimensions(dimension, target_dimension)
            self.emit(f"EVAL {expression} = {quantity_text(value / factor, target)}")
        else:
            unit = self.registry.simplified(dimension)
            self.emit(f"EVAL {expression} = {quantity_text(value, unit)}")

    def show_variables(self, arguments):
        self.emit(f"VARS count={len(self.variables)}")
        for name in sorted(self.variables):
            value, dimension = self.variables[name]
            unit = self.registry.simplified(dimension)
            self.emit(f"VAR {name} = {quantity_text(value, unit)}")

    def execute(self, line):
        command, *arguments = line.split(" ")
        try:
            if command not in self.handlers:
                raise CommandError(f"UNKNOWN COMMAND {command}")
            self.handlers[command](arguments)
        except CommandError as error:
            self.emit(f"ERROR {error}")


def main():
    calculator = Calculator()
    count = int(sys.stdin.readline())
    for _ in range(count):
        calculator.execute(sys.stdin.readline().rstrip("\n"))
    sys.stdout.write("\n".join(calculator.output) + "\n")


if __name__ == "__main__":
    main()
