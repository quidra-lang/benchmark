from math import comb, gcd
import re
import sys


MAX_LENGTH = 24
MAX_DIMENSION = 12
MAX_REDUNDANCY = 12
MAX_FRAME = 30
MAX_CRC_GENERATOR = 17
CODE_NAME = r"[A-Za-z][A-Za-z0-9]{0,7}"
PATTERNS = {
    "name": CODE_NAME,
    "code": CODE_NAME,
    "number": r"0|[1-9][0-9]{0,3}",
    "bits": r"[01]{1,30}",
    "erasure": r"[01?]{1,30}",
}
REPEAT_LIMITS = {"GEN": 24, "PCHECK": 24, "PERMUTE": 24, "INTERLEAVE": 8, "MACWILLIAMS": 25}


class CommandError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise CommandError(message)


def require_dimension(length, dimension):
    require(
        1 <= dimension <= MAX_DIMENSION and 1 <= length - dimension <= MAX_REDUNDANCY,
        f"bad dimension {length} {dimension}",
    )


def yes_no(flag):
    return "yes" if flag else "no"


def bit_text(value, width):
    return f"{value:0{width}b}"


def weight(vector):
    return vector.bit_count()


def parity(vector):
    return vector.bit_count() % 2


def all_ones(length):
    return (1 << length) - 1


def bit(vector, length, position):
    return (vector >> (length - position)) & 1


def remove_bit(vector, length, position):
    low = length - position
    return ((vector >> (low + 1)) << low) | (vector & all_ones(low))


def swap_bits(vector, length, first, second):
    if bit(vector, length, first) != bit(vector, length, second):
        vector ^= (1 << (length - first)) | (1 << (length - second))
    return vector


def rotate(vector, length):
    return ((vector << 1) & all_ones(length)) | (vector >> (length - 1))


def burst_length(vector):
    return vector.bit_length() - (vector & -vector).bit_length() + 1


def column(rows, length, position):
    value = 0
    for row in rows:
        value = (value << 1) | bit(row, length, position)
    return value


def transpose(rows, length):
    return [column(rows, length, position) for position in range(1, length + 1)]


def permute(vector, length, order):
    result = 0
    for source in order:
        result = (result << 1) | bit(vector, length, source)
    return result


def kronecker(first, first_length, second, second_length):
    result = 0
    for position in range(1, first_length + 1):
        result <<= second_length
        if bit(first, first_length, position):
            result |= second
    return result


def next_combination(vector):
    lowest = vector & -vector
    ripple = vector + lowest
    return ripple | (((vector ^ ripple) >> 2) // lowest)


def bursts(length, size):
    if size == 1:
        patterns = [1]
    else:
        patterns = [(1 << (size - 1)) | (inner << 1) | 1 for inner in range(1 << (size - 2))]
    for shift in range(length - size + 1):
        for pattern in patterns:
            yield pattern << shift


def degree(polynomial):
    return polynomial.bit_length() - 1


def poly_divmod(dividend, divisor):
    quotient = 0
    while degree(dividend) >= degree(divisor):
        shift = degree(dividend) - degree(divisor)
        quotient |= 1 << shift
        dividend ^= divisor << shift
    return quotient, dividend


def poly_mod(dividend, divisor):
    return poly_divmod(dividend, divisor)[1]


def factorize(polynomial):
    factors = []
    candidate = 2
    while 2 * degree(candidate) <= degree(polynomial):
        exponent = 0
        quotient, remainder = poly_divmod(polynomial, candidate)
        while remainder == 0:
            polynomial = quotient
            exponent += 1
            quotient, remainder = poly_divmod(polynomial, candidate)
        if exponent > 0:
            factors.append((candidate, exponent))
        candidate += 1
    if polynomial != 1:
        factors.append((polynomial, 1))
    return factors


def reduced_echelon(vectors, length):
    rows = list(vectors)
    pivots = []
    for position in range(1, length + 1):
        top = len(pivots)
        found = next((i for i in range(top, len(rows)) if bit(rows[i], length, position)), None)
        if found is None:
            continue
        rows[top], rows[found] = rows[found], rows[top]
        for i in range(len(rows)):
            if i != top and bit(rows[i], length, position):
                rows[i] ^= rows[top]
        pivots.append(position)
    return rows[:len(pivots)], pivots


def null_space(vectors, length):
    rows, pivots = reduced_echelon(vectors, length)
    result = []
    for free in range(1, length + 1):
        if free in pivots:
            continue
        vector = 1 << (length - free)
        for row, pivot in zip(rows, pivots):
            if bit(row, length, free):
                vector |= 1 << (length - pivot)
        result.append(vector)
    return result


class Echelon:
    def __init__(self):
        self.rows = []

    def reduce(self, vector):
        combination = 0
        for row, leading, row_combination in self.rows:
            if vector & leading:
                vector ^= row
                combination ^= row_combination
        return vector, combination

    def insert(self, vector, combination=0):
        residue, used = self.reduce(vector)
        if residue == 0:
            return False
        self.rows.append((residue, 1 << degree(residue), combination ^ used))
        return True


def basis(vectors):
    echelon = Echelon()
    kept = []
    for vector in vectors:
        if echelon.insert(vector):
            kept.append(vector)
    return kept


def span(rows):
    vectors = [0]
    for row in rows:
        vectors += [vector ^ row for vector in vectors]
    return vectors


def weight_counts(vectors, length):
    counts = [0] * (length + 1)
    for vector in vectors:
        counts[weight(vector)] += 1
    return counts


def count_items(counts):
    return " ".join(f"{i}:{count}" for i, count in enumerate(counts) if count > 0)


def krawtchouk(length, index, x):
    return sum((-1) ** y * comb(x, y) * comb(length - x, index - y) for y in range(index + 1))


def fraction_text(numerator, denominator):
    divisor = gcd(numerator, denominator)
    numerator //= divisor
    denominator //= divisor
    if denominator == 1:
        return str(numerator)
    return f"{numerator}/{denominator}"


def common_length(words):
    require(all(len(word) == len(words[0]) for word in words), "bad length")
    return len(words[0])


def hamming_rows(r):
    return transpose(list(range(1, 1 << r)), r)


def reed_muller(order, m):
    if order == 0:
        return [all_ones(1 << m)]
    half = 1 << (m - 1)
    doubled = [(row << half) | row for row in reed_muller(min(order, m - 1), m - 1)]
    return doubled + reed_muller(order - 1, m - 1)


def eliminate(rows, marked):
    if True not in marked:
        return list(rows)
    top = marked.index(True)
    result = []
    for i, row in enumerate(rows):
        if i != top:
            result.append(row ^ rows[top] if marked[i] else row)
    return result


def crc_degree(text):
    require(text[0] == "1" and 2 <= len(text) <= MAX_CRC_GENERATOR, "bad parameter")
    return len(text) - 1


class Code:
    def __init__(self, length, generator, check, polynomial):
        self.n = length
        self.k = len(generator)
        self.generator = generator
        self.check = check
        self.polynomial = polynomial

    def encoder(self):
        return "matrix" if self.polynomial is None else "polynomial"

    def syndrome(self, word):
        value = 0
        for row in self.check:
            value = (value << 1) | parity(row & word)
        return value

    def encode(self, message):
        if self.polynomial is not None:
            shifted = message << (self.n - self.k)
            return shifted | poly_mod(shifted, self.polynomial)
        codeword = 0
        for position, row in enumerate(self.generator, 1):
            if bit(message, self.k, position):
                codeword ^= row
        return codeword

    def message_of(self, codeword):
        if self.polynomial is not None:
            return codeword >> (self.n - self.k)
        echelon = Echelon()
        for position, row in enumerate(self.generator, 1):
            echelon.insert(row, 1 << (self.k - position))
        return echelon.reduce(codeword)[1]

    def codewords(self):
        return span(self.generator)

    def coset_leaders(self):
        leaders = [-1] * (1 << (self.n - self.k))
        leaders[0] = 0
        remaining = len(leaders) - 1
        for size in range(1, self.n + 1):
            vector = all_ones(size)
            while vector < 1 << self.n:
                syndrome = self.syndrome(vector)
                if leaders[syndrome] < 0:
                    leaders[syndrome] = vector
                    remaining -= 1
                    if remaining == 0:
                        return leaders
                vector = next_combination(vector)
        return leaders

    def decode(self, word, leaders):
        error = leaders[self.syndrome(word)]
        return word ^ error, error

    def burst_correction(self):
        seen = [False] * (1 << (self.n - self.k))
        seen[0] = True
        for size in range(1, self.n + 1):
            for burst in bursts(self.n, size):
                syndrome = self.syndrome(burst)
                if seen[syndrome]:
                    return size - 1
                seen[syndrome] = True
        return self.n

    def received(self, text):
        require(len(text) == self.n, "bad length")
        return int(text, 2)

    def decoding_fields(self, codeword, error):
        return [
            "codeword", bit_text(codeword, self.n),
            "message", bit_text(self.message_of(codeword), self.k),
            "error", bit_text(error, self.n),
            "weight", weight(error),
        ]


class CodeLab:
    def __init__(self):
        self.codes = {}
        self.output = []
        self.commands = {
            "GEN": (("name", "bits"), self.generator_code),
            "PCHECK": (("name", "bits"), self.check_code),
            "HAMMING": (("name", "number"), self.hamming_code),
            "SIMPLEX": (("name", "number"), self.simplex_code),
            "REPETITION": (("name", "number"), self.repetition_code),
            "PARITY": (("name", "number"), self.parity_code),
            "RM": (("name", "number", "number"), self.reed_muller_code),
            "CYCLIC": (("name", "number", "bits"), self.cyclic_code),
            "DUAL": (("name", "code"), self.dual_code),
            "EXTEND": (("name", "code"), self.extended_code),
            "PUNCTURE": (("name", "code", "number"), self.punctured_code),
            "SHORTEN": (("name", "code", "number"), self.shortened_code),
            "AUGMENT": (("name", "code"), self.augmented_code),
            "EXPURGATE": (("name", "code"), self.expurgated_code),
            "PERMUTE": (("name", "code", "number"), self.permuted_code),
            "DIRECTSUM": (("name", "code", "code"), self.direct_sum),
            "UUV": (("name", "code", "code"), self.u_u_plus_v),
            "PRODUCT": (("name", "code", "code"), self.product_code),
            "LIST": ((), self.list_codes),
            "DELETE": (("code",), self.delete),
            "SHOW": (("code",), self.show),
            "INFO": (("code",), self.info),
            "SYSTEMATIC": (("code",), self.systematic),
            "WEIGHTS": (("code",), self.weights),
            "COVERING": (("code",), self.covering),
            "BURST": (("code",), self.burst),
            "TRELLIS": (("code",), self.trellis),
            "STDARRAY": (("code",), self.standard_array),
            "EQUAL": (("code", "code"), self.equal),
            "ENCODE": (("code", "bits"), self.encode),
            "SYNDROME": (("code", "bits"), self.syndrome),
            "DECODE": (("code", "bits"), self.decode),
            "BOUNDED": (("code", "number", "bits"), self.bounded),
            "COSET": (("code", "bits"), self.coset),
            "ERASURE": (("code", "erasure"), self.erasure),
            "INTERLEAVE": (("code", "number", "number", "bits"), self.interleave),
            "CRC": (("bits", "bits"), self.crc),
            "CRCCHECK": (("bits", "bits"), self.crc_check),
            "FACTOR": (("number",), self.factor),
            "MACWILLIAMS": (("number", "number"), self.macwilliams),
            "BOUNDS": (("number", "number"), self.bounds),
        }

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def check_arguments(self, command, kinds, arguments):
        if command in REPEAT_LIMITS:
            extra = len(arguments) - len(kinds)
            if 0 <= extra < REPEAT_LIMITS[command]:
                kinds = kinds + (kinds[-1],) * extra
        well_formed = len(kinds) == len(arguments) and all(
            re.fullmatch(PATTERNS[kind], argument) for kind, argument in zip(kinds, arguments)
        )
        require(well_formed, "bad arguments")
        for kind, argument in zip(kinds, arguments):
            if kind == "code" and argument not in self.codes:
                raise CommandError(f"no code {argument}")

    def define(self, name, length, generator, check=None, polynomial=None):
        require_dimension(length, len(generator))
        if check is None:
            check = null_space(generator, length)
        verb = "redefined" if name in self.codes else "defined"
        self.codes[name] = Code(length, generator, check, polynomial)
        self.emit(verb, name, "n", length, "k", len(generator))

    def generator_code(self, arguments):
        length = common_length(arguments[1:])
        rows = basis([int(text, 2) for text in arguments[1:]])
        self.define(arguments[0], length, rows)

    def check_code(self, arguments):
        length = common_length(arguments[1:])
        check = basis([int(text, 2) for text in arguments[1:]])
        self.define(arguments[0], length, null_space(check, length), check)

    def hamming_code(self, arguments):
        r = int(arguments[1])
        require(2 <= r <= 4, "bad parameter")
        length = (1 << r) - 1
        check = hamming_rows(r)
        self.define(arguments[0], length, null_space(check, length), check)

    def simplex_code(self, arguments):
        r = int(arguments[1])
        require(2 <= r <= 4, "bad parameter")
        self.define(arguments[0], (1 << r) - 1, hamming_rows(r))

    def repetition_code(self, arguments):
        length = int(arguments[1])
        require(2 <= length <= MAX_LENGTH, "bad parameter")
        self.define(arguments[0], length, [all_ones(length)])

    def parity_code(self, arguments):
        length = int(arguments[1])
        require(2 <= length <= MAX_LENGTH, "bad parameter")
        rows = [(1 << (length - i)) | 1 for i in range(1, length)]
        self.define(arguments[0], length, rows)

    def reed_muller_code(self, arguments):
        order, m = int(arguments[1]), int(arguments[2])
        require(1 <= m <= 4 and order <= m, "bad parameter")
        self.define(arguments[0], 1 << m, reed_muller(order, m))

    def cyclic_code(self, arguments):
        length, text = int(arguments[1]), arguments[2]
        require(
            2 <= length <= MAX_LENGTH and text[0] == "1" and 2 <= len(text) <= length,
            "bad parameter",
        )
        generator = int(text, 2)
        redundancy = len(text) - 1
        require(poly_mod((1 << length) | 1, generator) == 0, "not a divisor")
        dimension = length - redundancy
        rows = [generator << (dimension - i) for i in range(1, dimension + 1)]
        columns = [poly_mod(1 << (length - j), generator) for j in range(1, length + 1)]
        self.define(arguments[0], length, rows, transpose(columns, redundancy), generator)

    def dual_code(self, arguments):
        code = self.codes[arguments[1]]
        self.define(arguments[0], code.n, list(code.check), list(code.generator))

    def extended_code(self, arguments):
        code = self.codes[arguments[1]]
        rows = [(row << 1) | parity(row) for row in code.generator]
        self.define(arguments[0], code.n + 1, rows)

    def punctured_code(self, arguments):
        code = self.codes[arguments[1]]
        position = int(arguments[2])
        require(1 <= position <= code.n, "bad position")
        rows = basis([remove_bit(row, code.n, position) for row in code.generator])
        self.define(arguments[0], code.n - 1, rows)

    def shortened_code(self, arguments):
        code = self.codes[arguments[1]]
        position = int(arguments[2])
        require(1 <= position <= code.n, "bad position")
        marked = [bit(row, code.n, position) == 1 for row in code.generator]
        rows = eliminate(code.generator, marked)
        self.define(arguments[0], code.n - 1, [remove_bit(row, code.n, position) for row in rows])

    def augmented_code(self, arguments):
        code = self.codes[arguments[1]]
        self.define(arguments[0], code.n, basis(code.generator + [all_ones(code.n)]))

    def expurgated_code(self, arguments):
        code = self.codes[arguments[1]]
        marked = [parity(row) == 1 for row in code.generator]
        self.define(arguments[0], code.n, eliminate(code.generator, marked))

    def permuted_code(self, arguments):
        code = self.codes[arguments[1]]
        order = [int(text) for text in arguments[2:]]
        require(sorted(order) == list(range(1, code.n + 1)), "bad permutation")
        self.define(arguments[0], code.n, [permute(row, code.n, order) for row in code.generator])

    def direct_sum(self, arguments):
        first, second = self.codes[arguments[1]], self.codes[arguments[2]]
        length = first.n + second.n
        require_dimension(length, first.k + second.k)
        rows = [row << second.n for row in first.generator] + second.generator
        self.define(arguments[0], length, rows)

    def u_u_plus_v(self, arguments):
        first, second = self.codes[arguments[1]], self.codes[arguments[2]]
        require(first.n == second.n, "bad length")
        length = 2 * first.n
        require_dimension(length, first.k + second.k)
        rows = [(row << first.n) | row for row in first.generator] + second.generator
        self.define(arguments[0], length, rows)

    def product_code(self, arguments):
        first, second = self.codes[arguments[1]], self.codes[arguments[2]]
        length = first.n * second.n
        require_dimension(length, first.k * second.k)
        rows = [
            kronecker(x, first.n, y, second.n)
            for x in first.generator for y in second.generator
        ]
        self.define(arguments[0], length, rows)

    def list_codes(self, arguments):
        self.emit("codes", len(self.codes))
        for name in sorted(self.codes):
            code = self.codes[name]
            self.emit(name, "n", code.n, "k", code.k, "encoder", code.encoder())

    def delete(self, arguments):
        del self.codes[arguments[0]]
        self.emit("deleted", arguments[0])

    def show(self, arguments):
        name = arguments[0]
        code = self.codes[name]
        self.emit("code", name, "n", code.n, "k", code.k, "encoder", code.encoder())
        if code.polynomial is not None:
            quotient = poly_divmod((1 << code.n) | 1, code.polynomial)[0]
            self.emit(
                "poly", "g", bit_text(code.polynomial, code.n - code.k + 1),
                "h", bit_text(quotient, code.k + 1),
            )
        for row in code.generator:
            self.emit("G", bit_text(row, code.n))
        for row in code.check:
            self.emit("H", bit_text(row, code.n))

    def info(self, arguments):
        name = arguments[0]
        code = self.codes[name]
        n, k = code.n, code.k
        nonzero = [word for word in code.codewords() if word != 0]
        distance = min(weight(word) for word in nonzero)
        correctable = (distance - 1) // 2
        perfect = sum(comb(n, i) for i in range(correctable + 1)) == (1 << (n - k))
        cyclic = "no"
        if all(code.syndrome(rotate(row, n)) == 0 for row in code.generator):
            cyclic = f"{min(nonzero):b}"
        self.emit(
            "info", name, "n", n, "k", k, "rate", fraction_text(k, n),
            "d", distance, "t", correctable, "perfect", yes_no(perfect),
            "mds", yes_no(distance == n - k + 1), "cyclic", cyclic,
        )

    def systematic(self, arguments):
        name = arguments[0]
        code = self.codes[name]
        n, k = code.n, code.k
        matrix = list(code.generator)
        order = list(range(1, n + 1))
        for r in range(1, k + 1):
            if not any(bit(row, n, r) for row in matrix[r - 1:]):
                target = next(
                    c for c in range(r + 1, n + 1)
                    if any(bit(row, n, c) for row in matrix[r - 1:])
                )
                matrix = [swap_bits(row, n, r, target) for row in matrix]
                order[r - 1], order[target - 1] = order[target - 1], order[r - 1]
            found = next(i for i in range(r - 1, k) if bit(matrix[i], n, r))
            matrix[r - 1], matrix[found] = matrix[found], matrix[r - 1]
            for i in range(k):
                if i != r - 1 and bit(matrix[i], n, r):
                    matrix[i] ^= matrix[r - 1]
        self.emit("systematic", name, "perm", *order)
        for row in matrix:
            self.emit("G", bit_text(row, n))
        for j in range(1, n - k + 1):
            identity = bit_text(1 << (n - k - j), n - k)
            self.emit("H", bit_text(column(matrix, n, k + j), k) + identity)

    def weights(self, arguments):
        name = arguments[0]
        code = self.codes[name]
        primal = weight_counts(code.codewords(), code.n)
        dual = weight_counts(span(code.check), code.n)
        orthogonal = all(
            parity(first & second) == 0
            for first in code.generator for second in code.generator
        )
        self.emit("weights", name, count_items(primal))
        self.emit("dual", name, count_items(dual))
        self.emit(
            "duality", name, "self-orthogonal", yes_no(orthogonal),
            "self-dual", yes_no(orthogonal and code.n == 2 * code.k),
            "formally-self-dual", yes_no(primal == dual),
        )

    def covering(self, arguments):
        name = arguments[0]
        leader_weights = [weight(leader) for leader in self.codes[name].coset_leaders()]
        radius = max(leader_weights)
        items = [f"{w}:{leader_weights.count(w)}" for w in range(radius + 1)]
        self.emit("covering", name, "radius", radius, "leaders", *items)

    def burst(self, arguments):
        name = arguments[0]
        code = self.codes[name]
        detect = min(burst_length(word) for word in code.codewords() if word != 0) - 1
        self.emit("burst", name, "detect", detect, "correct", code.burst_correction())

    def trellis(self, arguments):
        name = arguments[0]
        code = self.codes[name]
        n = code.n
        profile = []
        for i in range(n + 1):
            head = len(basis([row >> (n - i) for row in code.generator]))
            tail = len(basis([row & all_ones(n - i) for row in code.generator]))
            profile.append(head + tail - code.k)
        self.emit("trellis", name, "profile", *profile, "max", max(profile))

    def standard_array(self, arguments):
        name = arguments[0]
        code = self.codes[name]
        require(code.n - code.k <= 6 and code.k <= 4, "too large")
        leaders = code.coset_leaders()
        words = sorted(code.codewords())
        self.emit("stdarray", name, "rows", len(leaders), "columns", len(words))
        syndromes = sorted(range(len(leaders)), key=lambda s: (weight(leaders[s]), leaders[s]))
        for syndrome in syndromes:
            row = [bit_text(leaders[syndrome] ^ word, code.n) for word in words]
            self.emit(bit_text(syndrome, code.n - code.k) + ":", *row)

    def equal(self, arguments):
        first_name, second_name = arguments
        first, second = self.codes[first_name], self.codes[second_name]
        if first.n != second.n:
            self.emit("equal", first_name, second_name, "no", "lengths", first.n, second.n)
            return
        common = first.k + second.k - len(basis(first.generator + second.generator))
        same = first.k == second.k == common
        self.emit("equal", first_name, second_name, yes_no(same), "intersection", common)

    def encode(self, arguments):
        name, text = arguments
        code = self.codes[name]
        require(len(text) == code.k, "bad length")
        codeword = code.encode(int(text, 2))
        self.emit("encode", name, "message", text, "codeword", bit_text(codeword, code.n))

    def syndrome(self, arguments):
        name = arguments[0]
        code = self.codes[name]
        syndrome = code.syndrome(code.received(arguments[1]))
        self.emit(
            "syndrome", name, bit_text(syndrome, code.n - code.k),
            "codeword", yes_no(syndrome == 0),
        )

    def decode(self, arguments):
        name = arguments[0]
        code = self.codes[name]
        word = code.received(arguments[1])
        codeword, error = code.decode(word, code.coset_leaders())
        self.emit("decode", name, *code.decoding_fields(codeword, error))

    def bounded(self, arguments):
        name, limit = arguments[0], int(arguments[1])
        code = self.codes[name]
        word = code.received(arguments[2])
        codeword, error = code.decode(word, code.coset_leaders())
        if weight(error) <= limit:
            self.emit("bounded", name, *code.decoding_fields(codeword, error))
        else:
            self.emit("bounded", name, "fail", "weight", weight(error))

    def coset(self, arguments):
        name = arguments[0]
        code = self.codes[name]
        word = code.received(arguments[1])
        syndrome = code.syndrome(word)
        leader = code.coset_leaders()[syndrome]
        counts = weight_counts([word ^ codeword for codeword in code.codewords()], code.n)
        self.emit(
            "coset", name, "syndrome", bit_text(syndrome, code.n - code.k),
            "leader", bit_text(leader, code.n), "weights", count_items(counts),
        )

    def erasure(self, arguments):
        name, text = arguments
        code = self.codes[name]
        require(len(text) == code.n, "bad length")
        known = int("".join("0" if symbol == "?" else "1" for symbol in text), 2)
        value = int(text.replace("?", "0"), 2)
        candidates = [word for word in code.codewords() if (word & known) == value]
        erased = text.count("?")
        if len(candidates) == 1:
            candidate = candidates[0]
            self.emit(
                "erasure", name, "erased", erased, "candidates", 1,
                "codeword", bit_text(candidate, code.n),
                "message", bit_text(code.message_of(candidate), code.k),
            )
        else:
            self.emit("erasure", name, "erased", erased, "candidates", len(candidates))

    def interleave(self, arguments):
        name, start, size = arguments[0], int(arguments[1]), int(arguments[2])
        code = self.codes[name]
        n = code.n
        messages = arguments[3:]
        depth = len(messages)
        require(all(len(text) == code.k for text in messages), "bad length")
        require(start >= 1 and size >= 1 and start + size - 1 <= depth * n, "bad burst")
        codewords = [code.encode(int(text, 2)) for text in messages]
        sent = [0] * (depth * n)
        for i, codeword in enumerate(codewords):
            for j in range(n):
                sent[j * depth + i] = bit(codeword, n, j + 1)
        received = list(sent)
        for position in range(start - 1, start + size - 1):
            received[position] ^= 1
        self.emit("interleave", name, "depth", depth, "burst", start, size)
        self.emit("sent", "".join(str(value) for value in sent))
        self.emit("recv", "".join(str(value) for value in received))
        leaders = code.coset_leaders()
        correct_rows = 0
        for i, codeword in enumerate(codewords):
            word = 0
            for j in range(n):
                word = (word << 1) | received[j * depth + i]
            decoded, error = code.decode(word, leaders)
            message = code.message_of(decoded)
            correct = message == int(messages[i], 2)
            if correct:
                correct_rows += 1
            self.emit(
                "row", i + 1, "errors", weight(word ^ codeword), "corrected", weight(error),
                "message", bit_text(message, code.k), "ok" if correct else "wrong",
            )
        self.emit("result", "ok", correct_rows, "wrong", depth - correct_rows)

    def crc(self, arguments):
        generator, data = arguments
        size = crc_degree(generator)
        require(len(data) + size <= MAX_FRAME, "bad length")
        remainder = bit_text(poly_mod(int(data, 2) << size, int(generator, 2)), size)
        self.emit("crc", "remainder", remainder, "frame", data + remainder)

    def crc_check(self, arguments):
        generator, frame = arguments
        size = crc_degree(generator)
        remainder = poly_mod(int(frame, 2), int(generator, 2))
        status = "ok" if remainder == 0 else "error"
        self.emit("crccheck", status, "remainder", bit_text(remainder, size))

    def factor(self, arguments):
        n = int(arguments[0])
        require(1 <= n <= MAX_LENGTH, "bad parameter")
        factors = factorize((1 << n) | 1)
        divisors = 1
        for _, exponent in factors:
            divisors *= exponent + 1
        items = [f"{factor:b}^{exponent}" for factor, exponent in factors]
        self.emit("factor", n, *items, "divisors", divisors)

    def macwilliams(self, arguments):
        n = int(arguments[0])
        counts = [int(text) for text in arguments[1:]]
        require(1 <= n <= MAX_LENGTH, "bad parameter")
        require(len(counts) == n + 1, "bad length")
        require(counts[0] == 1, "bad parameter")
        size = sum(counts)
        numerators = [
            sum(count * krawtchouk(n, j, x) for x, count in enumerate(counts))
            for j in range(n + 1)
        ]
        power_of_two = (size & (size - 1)) == 0
        integral = all(value >= 0 and value % size == 0 for value in numerators)
        self.emit("macwilliams", "n", n, "size", size)
        self.emit("dual", *(fraction_text(value, size) for value in numerators))
        self.emit("feasible", yes_no(power_of_two and integral))

    def bounds(self, arguments):
        n, d = int(arguments[0]), int(arguments[1])
        require(1 <= d <= n <= MAX_LENGTH, "bad parameter")
        volume = sum(comb(n, i) for i in range((d - 1) // 2 + 1))
        hamming = max(k for k in range(n + 1) if (volume << k) <= (1 << n))
        griesmer = max(
            k for k in range(1, n + 1)
            if sum((d + (1 << i) - 1) >> i for i in range(k)) <= n
        )
        self.emit(
            "bounds", "n", n, "d", d, "singleton", n - d + 1,
            "hamming", hamming, "griesmer", griesmer,
        )

    def execute(self, line):
        command, *arguments = line.split(" ")
        try:
            require(command in self.commands, f"unknown command {command}")
            kinds, handler = self.commands[command]
            self.check_arguments(command, kinds, arguments)
            handler(arguments)
        except CommandError as error:
            self.emit(f"error: {error}")


def main():
    lab = CodeLab()
    count = int(sys.stdin.readline())
    for _ in range(count):
        lab.execute(sys.stdin.readline().rstrip("\n"))
    sys.stdout.write("\n".join(lab.output) + "\n")


if __name__ == "__main__":
    main()
