import sys
from math import gcd, isqrt


BUILTIN_FORMATS = (("HALF", 5, 10), ("E5M2", 5, 2), ("E4M3", 4, 3))
MODES = ("RNE", "RNA", "RTZ", "RUP", "RDN")
INTEGER_TYPES = {
    "I8": (-128, 127),
    "U8": (0, 255),
    "I16": (-32768, 32767),
    "U16": (0, 65535),
    "I32": (-2147483648, 2147483647),
    "U32": (0, 4294967295),
}
SPECIAL_VALUES = ("inf", "-inf", "nan")
FLAG_NAMES = ("invalid", "divbyzero", "overflow", "underflow", "inexact")
INVALID = 1
DIVBYZERO = 2
OVERFLOW = 4
UNDERFLOW = 8
INEXACT = 16
NO_REMAINDER = 0
BELOW_HALF = 1
AT_HALF = 2
ABOVE_HALF = 3


class CommandError(Exception):
    pass


def flag_text(flags):
    names = [name for index, name in enumerate(FLAG_NAMES) if flags & (1 << index)]
    return "flags=" + (",".join(names) if names else "none")


def decimal_text(numerator, exponent):
    sign = "-" if numerator < 0 else ""
    numerator = abs(numerator)
    if exponent >= 0:
        return sign + str(numerator << exponent)
    denominator = 1 << -exponent
    whole, remainder = divmod(numerator, denominator)
    digits = []
    while remainder != 0:
        digit, remainder = divmod(remainder * 10, denominator)
        digits.append(str(digit))
    text = sign + str(whole)
    if digits:
        text += "." + "".join(digits)
    return text


def ordering(first, second):
    if first < second:
        return "LT"
    if first > second:
        return "GT"
    return "EQ"


def remainder_class(remainder, divisor):
    if remainder == 0:
        return NO_REMAINDER
    if 2 * remainder < divisor:
        return BELOW_HALF
    if 2 * remainder == divisor:
        return AT_HALF
    return ABOVE_HALF


def rounds_up(mode, sign, value, remainder):
    if mode == "RNE":
        return remainder == ABOVE_HALF or (remainder == AT_HALF and value % 2 == 1)
    if mode == "RNA":
        return remainder >= AT_HALF
    if mode == "RUP":
        return remainder != NO_REMAINDER and sign == 0
    if mode == "RDN":
        return remainder != NO_REMAINDER and sign == 1
    return False


class Ratio:
    def __init__(self, numerator, exponent, denominator):
        common = gcd(numerator, denominator)
        numerator //= common
        denominator //= common
        while numerator != 0 and numerator % 2 == 0:
            numerator //= 2
            exponent += 1
        while denominator % 2 == 0:
            denominator //= 2
            exponent -= 1
        self.numerator = numerator
        self.exponent = exponent
        self.denominator = denominator

    def floor_log2(self):
        shift = self.numerator.bit_length() - self.denominator.bit_length()
        if shift >= 0:
            below = self.numerator < self.denominator << shift
        else:
            below = self.numerator << -shift < self.denominator
        return self.exponent + shift - (1 if below else 0)

    def split(self, exponent):
        numerator = self.numerator
        denominator = self.denominator
        shift = self.exponent - exponent
        if shift >= 0:
            numerator <<= shift
        else:
            denominator <<= -shift
        whole, remainder = divmod(numerator, denominator)
        return whole, remainder_class(remainder, denominator)

    def fraction_text(self, negative):
        if self.numerator == 0:
            return "0"
        numerator = self.numerator
        denominator = self.denominator
        if self.exponent >= 0:
            numerator <<= self.exponent
        else:
            denominator <<= -self.exponent
        text = ("-" if negative else "") + str(numerator)
        if denominator != 1:
            text += "/" + str(denominator)
        return text


class Root:
    def __init__(self, significand, exponent):
        if exponent % 2 != 0:
            significand *= 2
            exponent -= 1
        self.radicand = significand
        self.half_exponent = exponent // 2

    def floor_log2(self):
        return (self.radicand.bit_length() - 1) // 2 + self.half_exponent

    def split(self, exponent):
        radicand = self.radicand << (2 * (self.half_exponent - exponent))
        whole = isqrt(radicand)
        if whole * whole == radicand:
            return whole, NO_REMAINDER
        if 4 * radicand < (2 * whole + 1) ** 2:
            return whole, BELOW_HALF
        return whole, ABOVE_HALF


def parse_number(text):
    negative = text.startswith("-")
    body = text[1:] if negative else text
    if "/" in body:
        numerator_text, denominator_text = body.split("/")
        denominator = int(denominator_text)
        if denominator == 0:
            raise CommandError(f"BAD OPERAND {text}")
        return negative, Ratio(int(numerator_text), 0, denominator)
    whole, _, fraction = body.partition(".")
    return negative, Ratio(int(whole + fraction), 0, 10 ** len(fraction))


class Format:
    def __init__(self, name, exponent_bits, fraction_bits):
        self.name = name
        self.exponent_bits = exponent_bits
        self.fraction_bits = fraction_bits
        self.width = 1 + exponent_bits + fraction_bits
        self.bias = 2 ** (exponent_bits - 1) - 1
        self.emin = 1 - self.bias
        self.emax = self.bias
        self.top_field = 2 ** exponent_bits - 1
        self.hidden_bit = 1 << fraction_bits
        self.sign_bit = 1 << (exponent_bits + fraction_bits)
        self.hex_digits = (self.width + 3) // 4
        self.nan = self.compose(0, self.top_field, self.hidden_bit // 2)
        self.largest = self.compose(0, self.top_field - 1, self.hidden_bit - 1)

    def compose(self, sign, field, fraction):
        return sign * self.sign_bit + (field << self.fraction_bits) + fraction

    def sign(self, pattern):
        return pattern // self.sign_bit

    def field(self, pattern):
        return (pattern >> self.fraction_bits) & self.top_field

    def fraction(self, pattern):
        return pattern & (self.hidden_bit - 1)

    def is_nan(self, pattern):
        return self.field(pattern) == self.top_field and self.fraction(pattern) != 0

    def is_signaling(self, pattern):
        return self.is_nan(pattern) and self.fraction(pattern) < self.hidden_bit // 2

    def is_infinity(self, pattern):
        return self.field(pattern) == self.top_field and self.fraction(pattern) == 0

    def is_finite(self, pattern):
        return self.field(pattern) != self.top_field

    def is_zero(self, pattern):
        return pattern % self.sign_bit == 0

    def flip(self, pattern):
        return pattern ^ self.sign_bit

    def zero(self, sign):
        return self.compose(sign, 0, 0)

    def infinity(self, sign):
        return self.compose(sign, self.top_field, 0)

    def special(self, text):
        if text == "nan":
            return self.nan
        return self.infinity(1 if text == "-inf" else 0)

    def term(self, pattern):
        field = self.field(pattern)
        fraction = self.fraction(pattern)
        if field == 0:
            return self.sign(pattern), fraction, self.emin - self.fraction_bits
        return self.sign(pattern), self.hidden_bit + fraction, field - self.bias - self.fraction_bits

    def power_of_two(self, exponent):
        if exponent >= self.emin:
            return self.compose(0, exponent + self.bias, 0)
        return 1 << (exponent - self.emin + self.fraction_bits)

    def order_key(self, pattern):
        if self.sign(pattern) == 0:
            return pattern
        return -(pattern - self.sign_bit) - 1

    def classify(self, pattern):
        field = self.field(pattern)
        fraction = self.fraction(pattern)
        if field == self.top_field:
            if fraction == 0:
                return "infinity"
            return "qnan" if fraction >= self.hidden_bit // 2 else "snan"
        if field == 0:
            return "zero" if fraction == 0 else "subnormal"
        return "normal"

    def bit_text(self, pattern):
        field = f"{self.field(pattern):0{self.exponent_bits}b}"
        fraction = f"{self.fraction(pattern):0{self.fraction_bits}b}"
        return f"{self.sign(pattern)}|{field}|{fraction}"

    def hex_text(self, pattern):
        return f"0x{pattern:0{self.hex_digits}X}"

    def value_text(self, pattern):
        if self.is_nan(pattern):
            return "nan"
        if self.is_infinity(pattern):
            return "-inf" if self.sign(pattern) == 1 else "inf"
        sign, significand, exponent = self.term(pattern)
        return ("-" if sign == 1 else "") + decimal_text(significand, exponent)

    def pattern_text(self, pattern):
        return f"{self.bit_text(pattern)} {self.hex_text(pattern)} {self.value_text(pattern)}"

    def result_text(self, pattern, flags):
        return f"{self.pattern_text(pattern)} {flag_text(flags)}"

    def overflow(self, sign, mode):
        if mode in ("RNE", "RNA") or (mode == "RUP" and sign == 0) or (mode == "RDN" and sign == 1):
            return self.infinity(sign), OVERFLOW | INEXACT
        return self.largest + sign * self.sign_bit, OVERFLOW | INEXACT

    def tiny_after_rounding(self, sign, magnitude, mode, top):
        if top < self.emin - 1:
            return True
        value, remainder = magnitude.split(top - self.fraction_bits)
        if rounds_up(mode, sign, value, remainder):
            value += 1
        return value < 2 * self.hidden_bit

    def round(self, sign, magnitude, mode):
        top = magnitude.floor_log2()
        if top > self.emax:
            return self.overflow(sign, mode)
        exponent = max(top, self.emin) - self.fraction_bits
        value, remainder = magnitude.split(exponent)
        if rounds_up(mode, sign, value, remainder):
            value += 1
        if value == 2 * self.hidden_bit:
            value = self.hidden_bit
            exponent += 1
            if exponent > self.emax - self.fraction_bits:
                return self.overflow(sign, mode)
        flags = 0
        if remainder != NO_REMAINDER:
            flags |= INEXACT
            if top < self.emin and self.tiny_after_rounding(sign, magnitude, mode, top):
                flags |= UNDERFLOW
        if value >= self.hidden_bit:
            field = exponent + self.fraction_bits + self.bias
            return self.compose(sign, field, value - self.hidden_bit), flags
        return self.compose(sign, 0, value), flags

    def encode(self, negative, ratio, mode):
        sign = 1 if negative else 0
        if ratio.numerator == 0:
            return self.zero(sign), 0
        return self.round(sign, ratio, mode)


def exact_sum(terms):
    exponents = [exponent for _, significand, exponent in terms if significand != 0]
    lowest = min(exponents) if exponents else 0
    total = 0
    for sign, significand, exponent in terms:
        if significand != 0:
            part = significand << (exponent - lowest)
            total += -part if sign == 1 else part
    return total, lowest


def round_sum(fmt, terms, mode):
    total, exponent = exact_sum(terms)
    if total == 0:
        first_sign, _, _ = terms[0]
        if all(significand == 0 and sign == first_sign for sign, significand, _ in terms):
            return fmt.zero(first_sign), 0
        return fmt.zero(1 if mode == "RDN" else 0), 0
    return fmt.round(1 if total < 0 else 0, Ratio(abs(total), exponent, 1), mode)


def aligned_difference(first, first_exponent, second, second_exponent):
    lowest = min(first_exponent, second_exponent)
    difference = (first << (first_exponent - lowest)) - (second << (second_exponent - lowest))
    return difference, lowest


def error_text(fmt, pattern, exact):
    if not fmt.is_finite(pattern):
        return fmt.value_text(pattern)
    sign, significand, exponent = fmt.term(pattern)
    value = -significand if sign == 1 else significand
    difference, lowest = aligned_difference(value, exponent, *exact)
    return Ratio(abs(difference), lowest, 1).fraction_text(difference < 0)


def product_term(fmt, a, b):
    a_sign, a_significand, a_exponent = fmt.term(a)
    b_sign, b_significand, b_exponent = fmt.term(b)
    return a_sign ^ b_sign, a_significand * b_significand, a_exponent + b_exponent


def nan_rule(fmt, operands):
    if not any(fmt.is_nan(pattern) for pattern in operands):
        return None
    signaling = any(fmt.is_signaling(pattern) for pattern in operands)
    return fmt.nan, INVALID if signaling else 0


def add(fmt, a, b, mode):
    result = nan_rule(fmt, (a, b))
    if result is not None:
        return result
    if fmt.is_infinity(a) and fmt.is_infinity(b) and fmt.sign(a) != fmt.sign(b):
        return fmt.nan, INVALID
    if fmt.is_infinity(a):
        return a, 0
    if fmt.is_infinity(b):
        return b, 0
    return round_sum(fmt, [fmt.term(a), fmt.term(b)], mode)


def subtract(fmt, a, b, mode):
    return add(fmt, a, fmt.flip(b), mode)


def multiply(fmt, a, b, mode):
    result = nan_rule(fmt, (a, b))
    if result is not None:
        return result
    sigma = fmt.sign(a) ^ fmt.sign(b)
    if fmt.is_infinity(a) or fmt.is_infinity(b):
        if fmt.is_zero(a) or fmt.is_zero(b):
            return fmt.nan, INVALID
        return fmt.infinity(sigma), 0
    if fmt.is_zero(a) or fmt.is_zero(b):
        return fmt.zero(sigma), 0
    sign, significand, exponent = product_term(fmt, a, b)
    return fmt.round(sign, Ratio(significand, exponent, 1), mode)


def divide(fmt, a, b, mode):
    result = nan_rule(fmt, (a, b))
    if result is not None:
        return result
    sigma = fmt.sign(a) ^ fmt.sign(b)
    if fmt.is_infinity(a):
        if fmt.is_infinity(b):
            return fmt.nan, INVALID
        return fmt.infinity(sigma), 0
    if fmt.is_infinity(b):
        return fmt.zero(sigma), 0
    if fmt.is_zero(b):
        if fmt.is_zero(a):
            return fmt.nan, INVALID
        return fmt.infinity(sigma), DIVBYZERO
    if fmt.is_zero(a):
        return fmt.zero(sigma), 0
    _, dividend, dividend_exponent = fmt.term(a)
    _, divisor, divisor_exponent = fmt.term(b)
    quotient = Ratio(dividend, dividend_exponent - divisor_exponent, divisor)
    return fmt.round(sigma, quotient, mode)


def square_root(fmt, a, mode):
    result = nan_rule(fmt, (a,))
    if result is not None:
        return result
    if fmt.is_zero(a):
        return a, 0
    if fmt.sign(a) == 1:
        return fmt.nan, INVALID
    if fmt.is_infinity(a):
        return a, 0
    _, significand, exponent = fmt.term(a)
    return fmt.round(0, Root(significand, exponent), mode)


def fused_multiply_add(fmt, a, b, c, mode):
    result = nan_rule(fmt, (a, b, c))
    if result is not None:
        return result
    sigma = fmt.sign(a) ^ fmt.sign(b)
    if fmt.is_infinity(a) or fmt.is_infinity(b):
        if fmt.is_zero(a) or fmt.is_zero(b):
            return fmt.nan, INVALID
        if fmt.is_infinity(c) and fmt.sign(c) != sigma:
            return fmt.nan, INVALID
        return fmt.infinity(sigma), 0
    if fmt.is_infinity(c):
        return c, 0
    return round_sum(fmt, [product_term(fmt, a, b), fmt.term(c)], mode)


def convert_value(source, target, a, mode):
    if source.is_nan(a):
        return target.nan, INVALID if source.is_signaling(a) else 0
    sign = source.sign(a)
    if source.is_infinity(a):
        return target.infinity(sign), 0
    if source.is_zero(a):
        return target.zero(sign), 0
    _, significand, exponent = source.term(a)
    return target.round(sign, Ratio(significand, exponent, 1), mode)


def next_up(fmt, a):
    result = nan_rule(fmt, (a,))
    if result is not None:
        return result
    if a == fmt.infinity(0):
        return a, 0
    if fmt.is_zero(a):
        return 1, 0
    if fmt.sign(a) == 0:
        return a + 1, 0
    return a - 1, 0


def next_down(fmt, a):
    result = nan_rule(fmt, (a,))
    if result is not None:
        return result
    pattern, flags = next_up(fmt, fmt.flip(a))
    return fmt.flip(pattern), flags


def unit_in_last_place(fmt, a):
    result = nan_rule(fmt, (a,))
    if result is not None:
        return result
    if fmt.is_infinity(a):
        return fmt.infinity(0), 0
    _, _, exponent = fmt.term(a)
    return fmt.power_of_two(exponent), 0


ARITHMETIC = {
    "ADD": (2, add),
    "SUB": (2, subtract),
    "MUL": (2, multiply),
    "DIV": (2, divide),
    "SQRT": (1, square_root),
    "FMA": (3, fused_multiply_add),
}
NEIGHBORS = {
    "NEXTUP": next_up,
    "NEXTDOWN": next_down,
    "ULP": unit_in_last_place,
}


def operand(fmt, text):
    if text.startswith("0b"):
        digits = text[2:]
        if len(digits) != fmt.width:
            raise CommandError(f"BAD OPERAND {text}")
        return int(digits, 2)
    if text.startswith("0x"):
        digits = text[2:]
        if len(digits) != fmt.hex_digits or int(digits, 16) >= 1 << fmt.width:
            raise CommandError(f"BAD OPERAND {text}")
        return int(digits, 16)
    if text in SPECIAL_VALUES:
        return fmt.special(text)
    negative, ratio = parse_number(text)
    pattern, _ = fmt.encode(negative, ratio, "RNE")
    return pattern


def checked_mode(text):
    if text not in MODES:
        raise CommandError(f"BAD MODE {text}")
    return text


def optional_mode(arguments, index):
    if len(arguments) > index:
        return checked_mode(arguments[index])
    return "RNE"


def require_finite(fmt, patterns):
    if not all(fmt.is_finite(pattern) for pattern in patterns):
        raise CommandError("NOT FINITE")


class MinifloatLab:
    def __init__(self):
        self.formats = {
            name: Format(name, exponent_bits, fraction_bits)
            for name, exponent_bits, fraction_bits in BUILTIN_FORMATS
        }
        self.output = []
        self.handlers = {
            "FORMAT": self.define_format,
            "ENCODE": self.encode,
            "DECODE": self.decode,
            "CONVERT": self.convert,
            "COMPARE": self.compare,
            "TOINT": self.to_integer,
            "TABLE": self.table,
            "SUM": self.sequential_sum,
            "KAHAN": self.kahan_sum,
            "DOT": self.dot_product,
        }

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def lookup(self, name):
        if name not in self.formats:
            raise CommandError(f"UNKNOWN FORMAT {name}")
        return self.formats[name]

    def define_format(self, arguments):
        name, exponent_text, fraction_text = arguments
        if name in self.formats:
            raise CommandError(f"FORMAT EXISTS {name}")
        exponent_bits, fraction_bits = int(exponent_text), int(fraction_text)
        if not (2 <= exponent_bits <= 5 and 1 <= fraction_bits <= 10):
            raise CommandError("BAD FORMAT")
        fmt = Format(name, exponent_bits, fraction_bits)
        self.formats[name] = fmt
        self.emit(
            "FORMAT", name, f"e={exponent_bits}", f"m={fraction_bits}", f"bits={fmt.width}",
            f"bias={fmt.bias}", f"emin={fmt.emin}", f"emax={fmt.emax}",
        )

    def encode(self, arguments):
        fmt = self.lookup(arguments[0])
        text = arguments[1]
        if text.startswith("0b") or text.startswith("0x"):
            raise CommandError(f"BAD OPERAND {text}")
        if text in SPECIAL_VALUES:
            mode = optional_mode(arguments, 2)
            value, pattern, flags = text, fmt.special(text), 0
        else:
            negative, ratio = parse_number(text)
            mode = optional_mode(arguments, 2)
            pattern, flags = fmt.encode(negative, ratio, mode)
            value = ratio.fraction_text(negative)
        self.emit("ENCODE", fmt.name, mode, value, fmt.result_text(pattern, flags))

    def decode(self, arguments):
        fmt = self.lookup(arguments[0])
        pattern = operand(fmt, arguments[1])
        self.emit(
            "DECODE", fmt.name, fmt.bit_text(pattern), fmt.hex_text(pattern),
            fmt.classify(pattern), f"sign={fmt.sign(pattern)}",
        )
        field = fmt.field(pattern)
        fraction = fmt.fraction(pattern)
        fields = [f"exponent={field}", f"fraction={fraction}"]
        if fmt.is_finite(pattern):
            sign, significand, exponent = fmt.term(pattern)
            leading = "0" if field == 0 else "1"
            fields.append(f"unbiased={exponent + fmt.fraction_bits}")
            fields.append(f"significand={leading}.{fraction:0{fmt.fraction_bits}b}")
            self.emit("FIELDS", *fields)
            number = Ratio(significand, exponent, 1).fraction_text(sign == 1)
            self.emit("VALUE", number, fmt.value_text(pattern))
        elif fmt.is_infinity(pattern):
            self.emit("FIELDS", *fields)
        else:
            self.emit("FIELDS", *fields, f"payload={fraction % (fmt.hidden_bit // 2)}")

    def arithmetic(self, command, arguments):
        count, operation = ARITHMETIC[command]
        fmt = self.lookup(arguments[0])
        operands = [operand(fmt, text) for text in arguments[1:count + 1]]
        mode = optional_mode(arguments, count + 1)
        pattern, flags = operation(fmt, *operands, mode)
        self.emit(command, fmt.name, mode, fmt.result_text(pattern, flags))

    def convert(self, arguments):
        source = self.lookup(arguments[0])
        target = self.lookup(arguments[1])
        value = operand(source, arguments[2])
        mode = optional_mode(arguments, 3)
        pattern, flags = convert_value(source, target, value, mode)
        self.emit("CONVERT", source.name, target.name, mode, target.result_text(pattern, flags))

    def compare(self, arguments):
        fmt = self.lookup(arguments[0])
        a = operand(fmt, arguments[1])
        b = operand(fmt, arguments[2])
        flags = INVALID if fmt.is_signaling(a) or fmt.is_signaling(b) else 0
        total = ordering(fmt.order_key(a), fmt.order_key(b))
        if fmt.is_nan(a) or fmt.is_nan(b):
            relation = "UN"
        elif fmt.is_zero(a) and fmt.is_zero(b):
            relation = "EQ"
        else:
            relation = total
        self.emit(
            "COMPARE", fmt.name, fmt.hex_text(a), fmt.hex_text(b),
            relation, f"total={total}", flag_text(flags),
        )

    def neighbor(self, command, arguments):
        fmt = self.lookup(arguments[0])
        value = operand(fmt, arguments[1])
        pattern, flags = NEIGHBORS[command](fmt, value)
        self.emit(command, fmt.name, fmt.result_text(pattern, flags))

    def to_integer(self, arguments):
        fmt = self.lookup(arguments[0])
        value = operand(fmt, arguments[1])
        kind = arguments[2]
        if kind not in INTEGER_TYPES:
            raise CommandError(f"BAD TYPE {kind}")
        mode = optional_mode(arguments, 3)
        prefix = ("TOINT", fmt.name, kind, mode)
        if not fmt.is_finite(value):
            self.emit(*prefix, "invalid", flag_text(INVALID))
            return
        sign, significand, exponent = fmt.term(value)
        whole, remainder = Ratio(significand, exponent, 1).split(0)
        if rounds_up(mode, sign, whole, remainder):
            whole += 1
        result = -whole if sign == 1 else whole
        lowest, highest = INTEGER_TYPES[kind]
        if not lowest <= result <= highest:
            self.emit(*prefix, "invalid", flag_text(INVALID))
            return
        flags = INEXACT if remainder != NO_REMAINDER else 0
        self.emit(*prefix, result, flag_text(flags))

    def table(self, arguments):
        fmt = self.lookup(arguments[0])
        if fmt.width > 8:
            raise CommandError("TABLE TOO LARGE")
        count = fmt.top_field * fmt.hidden_bit
        self.emit("TABLE", fmt.name, f"count={count}")
        for index in range(count):
            if index == count - 1:
                gap = "-"
            else:
                _, upper, upper_exponent = fmt.term(index + 1)
                _, lower, lower_exponent = fmt.term(index)
                gap = decimal_text(*aligned_difference(upper, upper_exponent, lower, lower_exponent))
            self.emit("ENTRY", index, fmt.pattern_text(index), f"gap={gap}")
        self.emit("MAX", fmt.pattern_text(fmt.largest))
        self.emit("MINNORMAL", fmt.pattern_text(fmt.hidden_bit))
        self.emit("MINSUBNORMAL", fmt.pattern_text(1))
        self.emit("EPSILON", decimal_text(1, -fmt.fraction_bits))
        self.emit(
            "PATTERNS", f"finite={2 * count}", "infinite=2",
            f"nan={2 * (fmt.hidden_bit - 1)}", f"total={2 ** fmt.width}",
        )

    def summation_arguments(self, arguments):
        fmt = self.lookup(arguments[0])
        mode = checked_mode(arguments[1])
        values = [operand(fmt, text) for text in arguments[2:]]
        require_finite(fmt, values)
        return fmt, mode, values

    def summary(self, fmt, mode, values, result, flags):
        terms = [fmt.term(value) for value in values]
        exact = exact_sum(terms)
        rounded, rounded_flags = round_sum(fmt, terms, mode)
        self.emit("RESULT", fmt.pattern_text(result), flag_text(flags))
        self.emit("EXACT", decimal_text(*exact))
        self.emit("ROUNDED", fmt.result_text(rounded, rounded_flags))
        self.emit("DIFF", error_text(fmt, result, exact))

    def sequential_sum(self, arguments):
        fmt, mode, values = self.summation_arguments(arguments)
        self.emit("SUM", fmt.name, mode, f"count={len(values)}")
        total = values[0]
        flags = 0
        for index in range(1, len(values)):
            total, step_flags = add(fmt, total, values[index], mode)
            flags |= step_flags
            self.emit("PARTIAL", index + 1, fmt.result_text(total, step_flags))
        self.summary(fmt, mode, values, total, flags)

    def kahan_sum(self, arguments):
        fmt, mode, values = self.summation_arguments(arguments)
        self.emit("KAHAN", fmt.name, mode, f"count={len(values)}")
        total = values[0]
        compensation = fmt.zero(0)
        flags = 0
        for index in range(1, len(values)):
            corrected, corrected_flags = subtract(fmt, values[index], compensation, mode)
            updated, updated_flags = add(fmt, total, corrected, mode)
            change, change_flags = subtract(fmt, updated, total, mode)
            compensation, compensation_flags = subtract(fmt, change, corrected, mode)
            step_flags = corrected_flags | updated_flags | change_flags | compensation_flags
            total = updated
            flags |= step_flags
            self.emit(
                "KSTEP", index + 1, f"sum={fmt.value_text(total)}",
                f"comp={fmt.value_text(compensation)}", flag_text(step_flags),
            )
        self.summary(fmt, mode, values, total, flags)

    def dot_product(self, arguments):
        fmt = self.lookup(arguments[0])
        mode = checked_mode(arguments[1])
        separator = arguments.index("|")
        left = [operand(fmt, text) for text in arguments[2:separator]]
        right = [operand(fmt, text) for text in arguments[separator + 1:]]
        if len(left) != len(right):
            raise CommandError("LENGTH MISMATCH")
        require_finite(fmt, left + right)
        naive, naive_flags = multiply(fmt, left[0], right[0], mode)
        for index in range(1, len(left)):
            product, product_flags = multiply(fmt, left[index], right[index], mode)
            naive, sum_flags = add(fmt, naive, product, mode)
            naive_flags |= product_flags | sum_flags
        chained, chained_flags = multiply(fmt, left[0], right[0], mode)
        for index in range(1, len(left)):
            chained, step_flags = fused_multiply_add(fmt, left[index], right[index], chained, mode)
            chained_flags |= step_flags
        terms = [product_term(fmt, a, b) for a, b in zip(left, right)]
        exact = exact_sum(terms)
        fused, fused_flags = round_sum(fmt, terms, mode)
        self.emit("DOT", fmt.name, mode, f"n={len(left)}")
        self.emit("NAIVE", fmt.result_text(naive, naive_flags))
        self.emit("CHAINED", fmt.result_text(chained, chained_flags))
        self.emit("EXACT", decimal_text(*exact))
        self.emit("FUSED", fmt.result_text(fused, fused_flags))
        self.emit(
            "DIFF", f"naive={error_text(fmt, naive, exact)}",
            f"chained={error_text(fmt, chained, exact)}",
        )

    def execute(self, line):
        command, *arguments = line.split(" ")
        try:
            if command in ARITHMETIC:
                self.arithmetic(command, arguments)
            elif command in NEIGHBORS:
                self.neighbor(command, arguments)
            else:
                self.handlers[command](arguments)
        except CommandError as error:
            self.emit("ERROR", error)


def main():
    lab = MinifloatLab()
    count = int(sys.stdin.readline())
    for _ in range(count):
        lab.execute(sys.stdin.readline().rstrip("\n"))
    sys.stdout.write("\n".join(lab.output) + "\n")


if __name__ == "__main__":
    main()
