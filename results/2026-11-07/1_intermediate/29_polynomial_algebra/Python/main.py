from fractions import Fraction
import math
import sys


MAX_DEGREE = 30
INFINITIES = {"-inf": -1, "inf": 1}
PRODUCT_STARTS = ("*", "/", "x", "name", "(")
SPECIAL_KINDS = {
    "chebyshev": (1, 0),
    "chebyshev2": (2, 0),
    "legendre": (1, 0),
    "hermite": (2, 0),
    "laguerre": (-1, 1),
}


class CommandError(Exception):
    pass


def trim(coefficients):
    while coefficients and coefficients[-1] == 0:
        coefficients.pop()
    return coefficients


def constant(value):
    return trim([Fraction(value)])


def linear(slope, intercept):
    return trim([Fraction(intercept), Fraction(slope)])


def degree(polynomial):
    return len(polynomial) - 1


def add(first, second):
    if len(first) < len(second):
        first, second = second, first
    result = list(first)
    for i, value in enumerate(second):
        result[i] += value
    return trim(result)


def negate(polynomial):
    return [-value for value in polynomial]


def subtract(first, second):
    return add(first, negate(second))


def scale(polynomial, factor):
    return trim([value * factor for value in polynomial])


def divide_scalar(polynomial, divisor):
    return [value / divisor for value in polynomial]


def multiply(first, second):
    if not first or not second:
        return []
    product = [Fraction(0)] * (len(first) + len(second) - 1)
    for i, left in enumerate(first):
        for j, right in enumerate(second):
            product[i + j] += left * right
    return product


def divide(dividend, divisor):
    result = [Fraction(0)] * max(len(dividend) - len(divisor) + 1, 0)
    remainder = list(dividend)
    while remainder and len(remainder) >= len(divisor):
        factor = remainder[-1] / divisor[-1]
        shift = len(remainder) - len(divisor)
        result[shift] = factor
        for j, value in enumerate(divisor):
            remainder[shift + j] -= factor * value
        trim(remainder)
    return result, remainder


def quotient(dividend, divisor):
    return divide(dividend, divisor)[0]


def modulo(dividend, divisor):
    return divide(dividend, divisor)[1]


def derivative(polynomial):
    return [i * polynomial[i] for i in range(1, len(polynomial))]


def nth_derivative(polynomial, order):
    for _ in range(order):
        polynomial = derivative(polynomial)
    return polynomial


def integral(polynomial):
    if not polynomial:
        return []
    return [Fraction(0)] + [value / (i + 1) for i, value in enumerate(polynomial)]


def evaluate(polynomial, point):
    value = Fraction(0)
    for coefficient in reversed(polynomial):
        value = value * point + coefficient
    return value


def compose(outer, inner):
    result = []
    for coefficient in reversed(outer):
        result = add(multiply(result, inner), constant(coefficient))
    return result


def monic(polynomial):
    if not polynomial:
        return []
    return divide_scalar(polynomial, polynomial[-1])


def polynomial_gcd(first, second):
    while second:
        first, second = second, modulo(first, second)
    return monic(first)


def extended_gcd(first, second):
    r0, r1 = first, second
    s0, s1 = constant(1), []
    t0, t1 = [], constant(1)
    while r1:
        q, rest = divide(r0, r1)
        r0, r1 = r1, rest
        s0, s1 = s1, subtract(s0, multiply(q, s1))
        t0, t1 = t1, subtract(t0, multiply(q, t1))
    if not r0:
        return r0, s0, t0
    return monic(r0), divide_scalar(s0, r0[-1]), divide_scalar(t0, r0[-1])


def content(polynomial):
    denominator_lcm = 1
    numerator_gcd = 0
    for value in polynomial:
        denominator_lcm = math.lcm(denominator_lcm, value.denominator)
        numerator_gcd = math.gcd(numerator_gcd, abs(value.numerator))
    result = Fraction(numerator_gcd, denominator_lcm)
    return result if polynomial[-1] > 0 else -result


def primitive(polynomial):
    return divide_scalar(polynomial, content(polynomial))


def square_free_part(polynomial):
    if degree(polynomial) == 0:
        return polynomial
    return quotient(polynomial, polynomial_gcd(polynomial, derivative(polynomial)))


def checked_product(first, second):
    if first and second and degree(first) + degree(second) > MAX_DEGREE:
        raise CommandError("DEGREE LIMIT")
    return multiply(first, second)


def checked_power(polynomial, exponent):
    if polynomial and degree(polynomial) * exponent > MAX_DEGREE:
        raise CommandError("DEGREE LIMIT")
    result = constant(1)
    for _ in range(exponent):
        result = multiply(result, polynomial)
    return result


def checked_compose(outer, inner):
    if degree(outer) >= 1 and degree(inner) >= 1 and degree(outer) * degree(inner) > MAX_DEGREE:
        raise CommandError("DEGREE LIMIT")
    return compose(outer, inner)


def require_nonzero(*polynomials):
    for polynomial in polynomials:
        if not polynomial:
            raise CommandError("ZERO POLYNOMIAL")


def require_divisor(divisor):
    if not divisor:
        raise CommandError("DIVISION BY ZERO")


def lookup(polynomials, name):
    if name not in polynomials:
        raise CommandError(f"UNKNOWN {name}")
    return polynomials[name]


def literal(text):
    if "/" in text:
        numerator, denominator = map(int, text.split("/"))
    else:
        numerator, denominator = int(text), 1
    if denominator == 0:
        raise CommandError("ZERO DENOMINATOR")
    return Fraction(numerator, denominator)


def fraction_text(value):
    if value.denominator == 1:
        return str(value.numerator)
    return f"{value.numerator}/{value.denominator}"


def polynomial_text(polynomial, variable="x"):
    if not polynomial:
        return "0"
    parts = []
    for exponent in range(degree(polynomial), -1, -1):
        value = polynomial[exponent]
        if value == 0:
            continue
        if parts:
            parts.append(" - " if value < 0 else " + ")
        elif value < 0:
            parts.append("-")
        if abs(value) != 1 or exponent == 0:
            parts.append(fraction_text(abs(value)))
        if exponent == 1:
            parts.append(variable)
        elif exponent >= 2:
            parts.append(f"{variable}^{exponent}")
    return "".join(parts)


def factor_text(polynomial, multiplicity):
    if polynomial == linear(1, 0):
        text = "x"
    else:
        text = f"({polynomial_text(polynomial)})"
    if multiplicity >= 2:
        text += f"^{multiplicity}"
    return text


def sign(value):
    if value > 0:
        return 1
    if value < 0:
        return -1
    return 0


def sign_variations(signs):
    nonzero = [value for value in signs if value != 0]
    return sum(1 for left, right in zip(nonzero, nonzero[1:]) if left != right)


def bezout_coefficient(first, second):
    common, cofactor, _ = extended_gcd(first, second)
    if common != constant(1):
        raise CommandError("NOT COPRIME")
    return cofactor


def modular_power(base, exponent, modulus):
    result = modulo(constant(1), modulus)
    square = modulo(base, modulus)
    while exponent > 0:
        if exponent % 2 == 1:
            result = modulo(multiply(result, square), modulus)
        exponent //= 2
        if exponent:
            square = modulo(multiply(square, square), modulus)
    return result


def divisors(number):
    return [candidate for candidate in range(1, number + 1) if number % candidate == 0]


def root_candidates(constant_term, leading):
    candidates = []
    for numerator in divisors(constant_term):
        for denominator in divisors(leading):
            if math.gcd(numerator, denominator) == 1:
                candidates.append(Fraction(numerator, denominator))
                candidates.append(Fraction(-numerator, denominator))
    return sorted(candidates)


def rational_roots(polynomial):
    remaining = primitive(polynomial)
    zeros = 0
    while remaining[0] == 0:
        remaining = remaining[1:]
        zeros += 1
    roots = []
    for candidate in root_candidates(abs(remaining[0].numerator), remaining[-1].numerator):
        factor = linear(candidate.denominator, -candidate.numerator)
        multiplicity = 0
        while degree(remaining) >= 1 and evaluate(remaining, candidate) == 0:
            remaining = quotient(remaining, factor)
            multiplicity += 1
        if multiplicity:
            roots.append((candidate, multiplicity))
    if zeros:
        roots.append((Fraction(0), zeros))
        roots.sort()
    return roots, remaining


def square_free_factors(polynomial):
    factors = []
    if degree(polynomial) == 0:
        return factors
    base = monic(polynomial)
    common = polynomial_gcd(base, derivative(base))
    rest = quotient(base, common)
    multiplicity = 1
    while degree(rest) >= 1:
        shared = polynomial_gcd(rest, common)
        factor = quotient(rest, shared)
        if degree(factor) >= 1:
            factors.append((primitive(factor), multiplicity))
        common = quotient(common, shared)
        rest = shared
        multiplicity += 1
    return factors


def descartes_counts(polynomial):
    positive = []
    negative = []
    for exponent in range(degree(polynomial), -1, -1):
        value = sign(polynomial[exponent])
        positive.append(value)
        negative.append(-value if exponent % 2 == 1 else value)
    return sign_variations(positive), sign_variations(negative)


def sturm_sequence(polynomial):
    sequence = [square_free_part(polynomial)]
    following = derivative(sequence[0])
    while following:
        sequence.append(following)
        following = negate(modulo(sequence[-2], sequence[-1]))
    return sequence


def variations_at(sequence, point):
    return sign_variations([sign(evaluate(polynomial, point)) for polynomial in sequence])


def root_count(sequence, low, high):
    return variations_at(sequence, low) - variations_at(sequence, high)


class Bound:
    def __init__(self, text):
        self.infinity = INFINITIES.get(text, 0)
        self.value = Fraction(0) if self.infinity else literal(text)
        self.text = text if self.infinity else fraction_text(self.value)

    def key(self):
        return self.infinity, self.value

    def variations(self, sequence):
        if not self.infinity:
            return variations_at(sequence, self.value)
        signs = []
        for polynomial in sequence:
            direction = self.infinity if degree(polynomial) % 2 == 1 else 1
            signs.append(direction * sign(polynomial[-1]))
        return sign_variations(signs)


def examine(sequence, low, high, width, intervals):
    count = root_count(sequence, low, high)
    if count >= 2:
        middle = (low + high) / 2
        examine(sequence, low, middle, width, intervals)
        examine(sequence, middle, high, width, intervals)
    elif count == 1:
        while high - low > width:
            middle = (low + high) / 2
            if root_count(sequence, low, middle) >= 1:
                high = middle
            else:
                low = middle
        intervals.append((low, high))


def isolating_intervals(polynomial, precision):
    sequence = sturm_sequence(polynomial)
    base = sequence[0]
    largest = max((abs(value / base[-1]) for value in base[:-1]), default=Fraction(0))
    beta = 1 + largest
    intervals = []
    examine(sequence, -beta, beta, Fraction(1, 2 ** precision), intervals)
    return intervals


def fraction_power(base, exponent):
    result = Fraction(1)
    for _ in range(exponent):
        result *= base
    return result


def resultant(first, second):
    result = Fraction(1)
    p, q = first, second
    while degree(q) >= 1:
        rest = modulo(p, q)
        if not rest:
            return Fraction(0)
        result *= fraction_power(q[-1], degree(p) - degree(rest))
        if degree(p) * degree(q) % 2 == 1:
            result = -result
        p, q = q, rest
    return result * fraction_power(q[0], degree(p))


def power_sums(polynomial, count):
    size = degree(polynomial)
    normalized = monic(polynomial)
    sums = []
    for j in range(1, count + 1):
        total = j * normalized[size - j] if j <= size else Fraction(0)
        for i in range(1, min(j - 1, size) + 1):
            total += normalized[size - i] * sums[j - i - 1]
        sums.append(-total)
    return sums


def interpolate(xs, ys):
    count = len(xs)
    differences = list(ys)
    for j in range(1, count):
        for i in range(count - 1, j - 1, -1):
            differences[i] = (differences[i] - differences[i - 1]) / (xs[i] - xs[i - j])
    result = []
    for i in range(count - 1, -1, -1):
        result = add(multiply(result, linear(1, -xs[i])), constant(differences[i]))
    return result


def special_step(kind, j, previous, current):
    if kind in ("chebyshev", "chebyshev2"):
        return subtract(multiply(linear(2, 0), current), previous)
    if kind == "legendre":
        combined = subtract(multiply(linear(2 * j + 1, 0), current), scale(previous, j))
        return scale(combined, Fraction(1, j + 1))
    if kind == "hermite":
        return subtract(multiply(linear(2, 0), current), scale(previous, 2 * j))
    combined = subtract(multiply(linear(-1, 2 * j + 1), current), scale(previous, j))
    return scale(combined, Fraction(1, j + 1))


def special_polynomial(kind, order):
    previous = constant(1)
    if order == 0:
        return previous
    current = linear(*SPECIAL_KINDS[kind])
    for j in range(1, order):
        previous, current = current, special_step(kind, j, previous, current)
    return current


class Token:
    def __init__(self, kind, text, position):
        self.kind = kind
        self.text = text
        self.position = position


def tokenize(expression):
    tokens = []
    index = 0
    while index < len(expression):
        start = index
        character = expression[index]
        index += 1
        if character == " ":
            continue
        if character.isdigit():
            while index < len(expression) and expression[index].isdigit():
                index += 1
            kind = "number"
        elif character.isupper():
            while index < len(expression) and (
                expression[index].isupper() or expression[index].isdigit()
            ):
                index += 1
            kind = "name"
        else:
            kind = character
        tokens.append(Token(kind, expression[start:index], start + 1))
    return tokens


class Constant:
    def __init__(self, polynomial):
        self.polynomial = polynomial

    def evaluate(self, polynomials):
        return self.polynomial


class Reference:
    def __init__(self, name, primes):
        self.name = name
        self.primes = primes

    def evaluate(self, polynomials):
        return nth_derivative(lookup(polynomials, self.name), self.primes)


class Call:
    def __init__(self, function, argument):
        self.function = function
        self.argument = argument

    def evaluate(self, polynomials):
        outer = self.function.evaluate(polynomials)
        inner = self.argument.evaluate(polynomials)
        return checked_compose(outer, inner)


class Factor:
    def __init__(self, base, exponent):
        self.base = base
        self.exponent = exponent

    def evaluate(self, polynomials):
        value = self.base.evaluate(polynomials)
        if self.exponent is None:
            return value
        return checked_power(value, self.exponent)


class Term:
    def __init__(self, first, rest):
        self.first = first
        self.rest = rest

    def evaluate(self, polynomials):
        value = self.first.evaluate(polynomials)
        for operator, factor in self.rest:
            right = factor.evaluate(polynomials)
            if operator == "*":
                value = checked_product(value, right)
            elif not right:
                raise CommandError("DIVISION BY ZERO")
            elif degree(right) >= 1:
                raise CommandError("NONCONSTANT DIVISOR")
            else:
                value = divide_scalar(value, right[0])
        return value


class Expression:
    def __init__(self, negated, first, rest):
        self.negated = negated
        self.first = first
        self.rest = rest

    def evaluate(self, polynomials):
        value = self.first.evaluate(polynomials)
        if self.negated:
            value = negate(value)
        for operator, term in self.rest:
            right = term.evaluate(polynomials)
            if operator == "+":
                value = add(value, right)
            else:
                value = subtract(value, right)
        return value


class Parser:
    def __init__(self, tokens):
        self.tokens = tokens
        self.index = 0

    def peek(self):
        if self.index < len(self.tokens):
            return self.tokens[self.index].kind
        return None

    def error(self):
        if self.index < len(self.tokens):
            return CommandError(f"SYNTAX AT {self.tokens[self.index].position}")
        return CommandError("SYNTAX AT END")

    def advance(self):
        token = self.tokens[self.index]
        self.index += 1
        return token

    def accept(self, kind):
        if self.peek() == kind:
            self.index += 1
            return True
        return False

    def take(self, kind):
        if self.peek() != kind:
            raise self.error()
        return self.advance()

    def parse(self):
        expression = self.expression()
        if self.peek() is not None:
            raise self.error()
        return expression

    def expression(self):
        negated = self.accept("-")
        first = self.term()
        rest = []
        while self.peek() in ("+", "-"):
            operator = self.advance().kind
            rest.append((operator, self.term()))
        return Expression(negated, first, rest)

    def term(self):
        first = self.factor()
        rest = []
        while self.peek() in PRODUCT_STARTS:
            operator = "*"
            if self.peek() in ("*", "/"):
                operator = self.advance().kind
            rest.append((operator, self.factor()))
        return Term(first, rest)

    def factor(self):
        base = self.primary()
        exponent = None
        if self.accept("^"):
            exponent = int(self.take("number").text)
        return Factor(base, exponent)

    def primary(self):
        kind = self.peek()
        if kind == "number":
            return Constant(constant(int(self.advance().text)))
        if kind == "x":
            self.advance()
            return Constant(linear(1, 0))
        if kind == "name":
            name = self.advance().text
            primes = 0
            while self.accept("'"):
                primes += 1
            reference = Reference(name, primes)
            if not self.accept("("):
                return reference
            argument = self.expression()
            self.take(")")
            return Call(reference, argument)
        if kind == "(":
            self.advance()
            inner = self.expression()
            self.take(")")
            return inner
        raise self.error()


class Calculator:
    def __init__(self):
        self.polynomials = {}
        self.output = []
        self.operations = {
            "ADD": add, "SUB": subtract, "MUL": checked_product,
            "GCD": polynomial_gcd, "COMPOSE": checked_compose,
        }
        self.handlers = {
            "DEF": self.define, "PRINT": self.print_polynomial,
            "DELETE": self.delete, "LIST": self.list_polynomials,
            "DEGREE": self.show_degree, "POW": self.raise_power,
            "DIV": self.divide_polynomials, "XGCD": self.extended_euclid,
            "LCM": self.least_common_multiple, "INVMOD": self.inverse_modulo,
            "CRT": self.chinese_remainder, "MODPOW": self.power_modulo,
            "DERIV": self.differentiate, "INTEG": self.integrate,
            "AREA": self.area, "TANGENT": self.tangent,
            "TAYLOR": self.taylor, "EVAL": self.evaluate_points,
            "ROOTS": self.show_roots, "FACTOR": self.show_factorization,
            "SQFREE": self.show_square_free, "DESCARTES": self.show_descartes,
            "STURM": self.count_real_roots, "ISOLATE": self.isolate_roots,
            "RESULTANT": self.show_resultant, "DISCRIM": self.show_discriminant,
            "POWERSUM": self.show_power_sums, "INTERP": self.interpolate_points,
            "SPECIAL": self.special,
        }

    def emit(self, line):
        self.output.append(line)

    def lookup(self, name):
        return lookup(self.polynomials, name)

    def nonzero(self, name):
        polynomial = self.lookup(name)
        require_nonzero(polynomial)
        return polynomial

    def store(self, name, polynomial):
        self.polynomials[name] = polynomial
        self.emit(f"{name} = {polynomial_text(polynomial)}")

    def combine(self, operation, arguments):
        target, first, second = arguments
        left, right = self.lookup(first), self.lookup(second)
        self.store(target, operation(left, right))

    def define(self, arguments):
        name, expression = arguments
        tree = Parser(tokenize(expression)).parse()
        self.store(name, tree.evaluate(self.polynomials))

    def print_polynomial(self, arguments):
        name = arguments[0]
        self.emit(f"{name} = {polynomial_text(self.lookup(name))}")

    def delete(self, arguments):
        name = arguments[0]
        self.lookup(name)
        del self.polynomials[name]
        self.emit(f"deleted {name}")

    def list_polynomials(self, arguments):
        if not self.polynomials:
            self.emit("no polynomials")
        for name in sorted(self.polynomials):
            self.emit(f"{name} = {polynomial_text(self.polynomials[name])}")

    def show_degree(self, arguments):
        name = arguments[0]
        polynomial = self.lookup(name)
        text = str(degree(polynomial)) if polynomial else "-inf"
        self.emit(f"deg({name}) = {text}")

    def raise_power(self, arguments):
        target, name, exponent = arguments
        self.store(target, checked_power(self.lookup(name), int(exponent)))

    def divide_polynomials(self, arguments):
        quotient_name, remainder_name, first, second = arguments
        if quotient_name == remainder_name:
            raise CommandError("SAME NAME")
        dividend, divisor = self.lookup(first), self.lookup(second)
        require_divisor(divisor)
        result, remainder = divide(dividend, divisor)
        self.store(quotient_name, result)
        self.store(remainder_name, remainder)

    def extended_euclid(self, arguments):
        targets = arguments[:3]
        if len(set(targets)) < 3:
            raise CommandError("SAME NAME")
        left, right = self.lookup(arguments[3]), self.lookup(arguments[4])
        for target, result in zip(targets, extended_gcd(left, right)):
            self.store(target, result)

    def least_common_multiple(self, arguments):
        target, first, second = arguments
        left, right = self.lookup(first), self.lookup(second)
        if not left or not right:
            self.store(target, [])
            return
        common = polynomial_gcd(left, right)
        if degree(left) + degree(right) - degree(common) > MAX_DEGREE:
            raise CommandError("DEGREE LIMIT")
        self.store(target, monic(multiply(quotient(left, common), right)))

    def inverse_modulo(self, arguments):
        target, name, modulus_name = arguments
        value, modulus = self.lookup(name), self.lookup(modulus_name)
        require_divisor(modulus)
        if degree(modulus) == 0:
            raise CommandError("DEGREE TOO LOW")
        cofactor = bezout_coefficient(value, modulus)
        self.store(target, modulo(cofactor, modulus))

    def chinese_remainder(self, arguments):
        target = arguments[0]
        first, first_modulus, second, second_modulus = [self.lookup(name) for name in arguments[1:]]
        require_divisor(first_modulus)
        require_divisor(second_modulus)
        if degree(first_modulus) + degree(second_modulus) > MAX_DEGREE:
            raise CommandError("DEGREE LIMIT")
        cofactor = bezout_coefficient(first_modulus, second_modulus)
        first_residue = modulo(first, first_modulus)
        second_residue = modulo(second, second_modulus)
        difference = subtract(second_residue, first_residue)
        correction = modulo(multiply(difference, cofactor), second_modulus)
        self.store(target, add(first_residue, multiply(first_modulus, correction)))

    def power_modulo(self, arguments):
        target, name, exponent, modulus_name = arguments
        base, modulus = self.lookup(name), self.lookup(modulus_name)
        require_divisor(modulus)
        if 2 * degree(modulus) - 2 > MAX_DEGREE:
            raise CommandError("DEGREE LIMIT")
        self.store(target, modular_power(base, int(exponent), modulus))

    def differentiate(self, arguments):
        target, name, order = arguments
        self.store(target, nth_derivative(self.lookup(name), int(order)))

    def integrate(self, arguments):
        target, name = arguments
        polynomial = self.lookup(name)
        if polynomial and degree(polynomial) + 1 > MAX_DEGREE:
            raise CommandError("DEGREE LIMIT")
        self.store(target, integral(polynomial))

    def area(self, arguments):
        name, low_text, high_text = arguments
        polynomial = self.lookup(name)
        low, high = literal(low_text), literal(high_text)
        antiderivative = integral(polynomial)
        value = evaluate(antiderivative, high) - evaluate(antiderivative, low)
        interval = f"{fraction_text(low)}, {fraction_text(high)}"
        self.emit(f"integral({name}, {interval}) = {fraction_text(value)}")

    def tangent(self, arguments):
        target, name, point_text = arguments
        polynomial = self.lookup(name)
        point = literal(point_text)
        height = evaluate(polynomial, point)
        slope = evaluate(derivative(polynomial), point)
        self.store(target, linear(slope, height - slope * point))

    def taylor(self, arguments):
        name, center_text = arguments
        polynomial = self.lookup(name)
        center = literal(center_text)
        shifted = compose(polynomial, linear(1, center))
        if center == 0:
            variable = "x"
        elif center > 0:
            variable = f"(x - {fraction_text(center)})"
        else:
            variable = f"(x + {fraction_text(-center)})"
        self.emit(f"taylor({name}, {fraction_text(center)}) = {polynomial_text(shifted, variable)}")

    def evaluate_points(self, arguments):
        name = arguments[0]
        polynomial = self.lookup(name)
        points = [literal(text) for text in arguments[1:]]
        for point in points:
            value = evaluate(polynomial, point)
            self.emit(f"{name}({fraction_text(point)}) = {fraction_text(value)}")

    def show_roots(self, arguments):
        name = arguments[0]
        roots, _ = rational_roots(self.nonzero(name))
        text = ", ".join(f"{fraction_text(root)} ({multiplicity})" for root, multiplicity in roots)
        self.emit(f"roots({name}) = {text or 'none'}")

    def show_factorization(self, arguments):
        name = arguments[0]
        polynomial = self.nonzero(name)
        roots, remaining = rational_roots(polynomial)
        parts = [f"factor({name}) = {fraction_text(content(polynomial))}"]
        for root, multiplicity in roots:
            parts.append(factor_text(linear(root.denominator, -root.numerator), multiplicity))
        if degree(remaining) >= 1:
            parts.append(factor_text(remaining, 1))
        self.emit(" * ".join(parts))

    def show_square_free(self, arguments):
        name = arguments[0]
        polynomial = self.nonzero(name)
        parts = [f"sqfree({name}) = {fraction_text(content(polynomial))}"]
        for factor, multiplicity in square_free_factors(polynomial):
            parts.append(factor_text(factor, multiplicity))
        self.emit(" * ".join(parts))

    def show_descartes(self, arguments):
        name = arguments[0]
        positive, negative = descartes_counts(self.nonzero(name))
        self.emit(f"descartes({name}) = positive {positive}, negative {negative}")

    def count_real_roots(self, arguments):
        name, low_text, high_text = arguments
        polynomial = self.lookup(name)
        low, high = Bound(low_text), Bound(high_text)
        require_nonzero(polynomial)
        if low.key() >= high.key():
            raise CommandError("BAD INTERVAL")
        sequence = sturm_sequence(polynomial)
        count = low.variations(sequence) - high.variations(sequence)
        self.emit(f"sturm({name}, {low.text}, {high.text}) = {count}")

    def isolate_roots(self, arguments):
        name, precision = arguments[0], int(arguments[1])
        intervals = isolating_intervals(self.nonzero(name), precision)
        text = ", ".join(
            f"({fraction_text(low)}, {fraction_text(high)}]" for low, high in intervals
        )
        self.emit(f"isolate({name}, {precision}) = {text or 'none'}")

    def show_resultant(self, arguments):
        first, second = arguments
        left, right = self.lookup(first), self.lookup(second)
        require_nonzero(left, right)
        self.emit(f"res({first}, {second}) = {fraction_text(resultant(left, right))}")

    def show_discriminant(self, arguments):
        name = arguments[0]
        polynomial = self.nonzero(name)
        size = degree(polynomial)
        if size == 0:
            raise CommandError("DEGREE TOO LOW")
        value = resultant(polynomial, derivative(polynomial)) / polynomial[-1]
        if size * (size - 1) // 2 % 2 == 1:
            value = -value
        self.emit(f"disc({name}) = {fraction_text(value)}")

    def show_power_sums(self, arguments):
        name, count = arguments[0], int(arguments[1])
        polynomial = self.nonzero(name)
        if degree(polynomial) == 0:
            raise CommandError("DEGREE TOO LOW")
        sums = power_sums(polynomial, count)
        self.emit(f"powersum({name}) = {', '.join(fraction_text(value) for value in sums)}")

    def interpolate_points(self, arguments):
        target = arguments[0]
        values = [literal(text) for text in arguments[1:]]
        xs, ys = values[0::2], values[1::2]
        for j in range(1, len(xs)):
            if xs[j] in xs[:j]:
                raise CommandError(f"DUPLICATE X {fraction_text(xs[j])}")
        self.store(target, interpolate(xs, ys))

    def special(self, arguments):
        target, kind, order = arguments[0], arguments[1], int(arguments[2])
        if kind not in SPECIAL_KINDS:
            raise CommandError(f"UNKNOWN KIND {kind}")
        if order > MAX_DEGREE:
            raise CommandError("DEGREE LIMIT")
        self.store(target, special_polynomial(kind, order))

    def execute(self, line):
        if line.startswith("DEF "):
            words = line.split(" ", 2)
        else:
            words = line.split(" ")
        command, arguments = words[0], words[1:]
        try:
            if command in self.operations:
                self.combine(self.operations[command], arguments)
            else:
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
