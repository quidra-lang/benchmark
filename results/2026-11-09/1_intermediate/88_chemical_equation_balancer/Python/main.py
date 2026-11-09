import re
import sys
from collections import Counter
from dataclasses import dataclass
from fractions import Fraction
from math import floor, gcd, lcm

WEIGHTS = {
    "H": 1008,
    "He": 4003,
    "Li": 6941,
    "Be": 9012,
    "B": 10811,
    "C": 12011,
    "N": 14007,
    "O": 15999,
    "F": 18998,
    "Ne": 20180,
    "Na": 22990,
    "Mg": 24305,
    "Al": 26982,
    "Si": 28086,
    "P": 30974,
    "S": 32065,
    "Cl": 35453,
    "Ar": 39948,
    "K": 39098,
    "Ca": 40078,
    "Sc": 44956,
    "Ti": 47867,
    "V": 50942,
    "Cr": 51996,
    "Mn": 54938,
    "Fe": 55845,
    "Co": 58933,
    "Ni": 58693,
    "Cu": 63546,
    "Zn": 65380,
    "Ga": 69723,
    "Ge": 72630,
    "As": 74922,
    "Se": 78971,
    "Br": 79904,
    "Kr": 83798,
    "Rb": 85468,
    "Sr": 87620,
    "Y": 88906,
    "Zr": 91224,
    "Nb": 92906,
    "Mo": 95950,
    "Tc": 98000,
    "Ru": 101070,
    "Rh": 102906,
    "Pd": 106420,
    "Ag": 107868,
    "Cd": 112414,
    "In": 114818,
    "Sn": 118710,
    "Sb": 121760,
    "Te": 127600,
    "I": 126904,
    "Xe": 131293,
}
ATOMIC_NUMBERS = {symbol: number for number, symbol in enumerate(WEIGHTS, start=1)}
VALENCES = {
    "H": 1,
    "F": 1,
    "Cl": 1,
    "Br": 1,
    "I": 1,
    "O": 2,
    "S": 2,
    "Se": 2,
    "B": 3,
    "N": 3,
    "P": 3,
    "As": 3,
    "C": 4,
    "Si": 4,
    "Ge": 4,
}
FIXED_METALS = {
    "Li": 1,
    "Na": 1,
    "K": 1,
    "Rb": 1,
    "Be": 2,
    "Mg": 2,
    "Ca": 2,
    "Sr": 2,
    "Al": 3,
}
STATES = ("(s)", "(l)", "(g)", "(aq)")
RESERVED_SPECIES = ("H^+", "OH^-", "H2O")
GAS_MOLAR_VOLUME = 22414
ELEMENT_SYMBOL = re.compile(r"[A-Z][a-z]?")
LEADING_DIGITS = re.compile(r"[0-9]+")
QUANTITY = re.compile(r"(0|[1-9][0-9]{0,3})(?:\.([0-9]{1,3}))?")
ENTHALPY = re.compile(r"(-?)(0|[1-9][0-9]{0,4})(?:\.([0-9]{1,2}))?")


class ChemError(Exception):
    pass


class NoCoefficients(Exception):
    pass


@dataclass
class Formula:
    composition: Counter
    charge: int

    @property
    def molar_mass(self):
        return sum(
            count * WEIGHTS[element] for element, count in self.composition.items()
        )


@dataclass
class Species:
    formula_text: str
    formula: Formula
    state: str = ""
    coefficient: int = 1

    @property
    def name(self):
        return self.formula_text + self.state

    @property
    def is_gas(self):
        return self.state == "(g)"


@dataclass
class Equation:
    reactants: list
    products: list

    @property
    def species(self):
        return self.reactants + self.products

    @property
    def signs(self):
        return [1] * len(self.reactants) + [-1] * len(self.products)


SOLUTION_IONS = {
    "acidic": Species("H^+", Formula(Counter(H=1), 1)),
    "basic": Species("OH^-", Formula(Counter(O=1, H=1), -1)),
}
WATER = Species("H2O", Formula(Counter(H=2, O=1), 0))
ELECTRON = Species("e^-", Formula(Counter(), -1))

formation_enthalpies = {}


def decimal(value, digits):
    whole, fraction = divmod(value, 10**digits)
    return f"{whole}.{fraction:0{digits}d}"


def enthalpy_notation(value):
    return ("-" if value < 0 else "") + decimal(abs(value), 2)


def signed(value):
    return f"+{value}" if value > 0 else str(value)


def hill_order(elements):
    ordered = sorted(elements)
    if "C" not in ordered:
        return ordered
    rest = [element for element in ordered if element not in ("C", "H")]
    return ["C", "H", *rest] if "H" in ordered else ["C", *rest]


def hill_items(composition):
    return [(element, composition[element]) for element in hill_order(composition)]


def count_suffix(count):
    return str(count) if count > 1 else ""


def hill_notation(composition, charge=0):
    text = "".join(
        element + count_suffix(count) for element, count in hill_items(composition)
    )
    if charge:
        text += "^" + count_suffix(abs(charge)) + ("+" if charge > 0 else "-")
    return text


def scaled(composition, factor):
    return Counter({element: count * factor for element, count in composition.items()})


def add_scaled(target, source, factor):
    for element, count in source.items():
        target[element] += count * factor


class FormulaParser:
    def __init__(self, text):
        self.text = text
        self.pos = 0
        self.symbols = []

    def peek(self):
        return self.text[self.pos] if self.pos < len(self.text) else ""

    def parse(self):
        composition = self.sequence()
        while self.peek() == ".":
            self.pos += 1
            multiplier = self.number()
            add_scaled(composition, self.sequence(), multiplier)
        charge = 0
        if self.peek() == "^":
            self.pos += 1
            magnitude = self.number()
            sign = self.peek()
            if sign not in ("+", "-"):
                raise ValueError
            self.pos += 1
            charge = magnitude if sign == "+" else -magnitude
        if self.pos != len(self.text):
            raise ValueError
        return Formula(composition, charge)

    def sequence(self):
        composition = Counter()
        while True:
            char = self.peek()
            if char.isupper():
                item = Counter({self.symbol(): 1})
            elif char == "(":
                item = self.group(")")
            elif char == "[":
                item = self.group("]")
            else:
                break
            add_scaled(composition, item, self.number())
        if not composition:
            raise ValueError
        return composition

    def symbol(self):
        start = self.pos
        self.pos += 1
        if self.peek().islower():
            self.pos += 1
        symbol = self.text[start : self.pos]
        self.symbols.append(symbol)
        return symbol

    def group(self, closing):
        self.pos += 1
        composition = self.sequence()
        if self.peek() != closing:
            raise ValueError
        self.pos += 1
        return composition

    def number(self):
        start = self.pos
        while self.peek().isdigit():
            self.pos += 1
        digits = self.text[start : self.pos]
        if not digits:
            return 1
        if digits.startswith("0"):
            raise ValueError
        return int(digits)


def read_formula(text, word=None):
    parser = FormulaParser(text)
    try:
        formula = parser.parse()
    except ValueError:
        raise ChemError(f"invalid formula {word or text}") from None
    for symbol in parser.symbols:
        if symbol not in WEIGHTS:
            raise ChemError(f"unknown element {symbol}")
    return formula


def read_species(word, allow_coefficient=False):
    state = next((suffix for suffix in STATES if word.endswith(suffix)), "")
    text = word.removesuffix(state)
    coefficient = 1
    if allow_coefficient:
        match = LEADING_DIGITS.match(text)
        if match:
            if text.startswith("0"):
                raise ChemError(f"invalid formula {word}")
            coefficient = int(match.group())
            text = text[match.end() :]
    return Species(text, read_formula(text, word), state, coefficient)


def read_equation(words, allow_coefficients=False):
    operators = words[1::2]
    if (
        len(words) % 2 == 0
        or any(word not in ("+", "->") for word in operators)
        or operators.count("->") != 1
        or any(word in ("+", "->") for word in words[::2])
    ):
        raise ChemError("malformed equation")
    species = [read_species(word, allow_coefficients) for word in words[::2]]
    split = operators.index("->") + 1
    return Equation(species[:split], species[split:])


def read_quantity(word):
    match = QUANTITY.fullmatch(word)
    if match:
        whole, fraction = match.groups()
        value = int(whole) * 1000 + int((fraction or "").ljust(3, "0"))
        if value > 0:
            return value
    raise ChemError(f"invalid quantity {word}")


def read_enthalpy(word):
    match = ENTHALPY.fullmatch(word)
    if not match:
        raise ChemError(f"invalid enthalpy {word}")
    sign, whole, fraction = match.groups()
    value = int(whole) * 100 + int((fraction or "").ljust(2, "0"))
    return -value if sign else value


def composition_matrix(species, signs):
    formulas = [item.formula for item in species]
    elements = hill_order(
        {element for formula in formulas for element in formula.composition}
    )
    rows = [
        [sign * formula.composition[element] for formula, sign in zip(formulas, signs)]
        for element in elements
    ]
    rows.append([sign * formula.charge for formula, sign in zip(formulas, signs)])
    return elements + ["charge"], rows


def null_space(rows, column_count):
    matrix = [[Fraction(entry) for entry in row] for row in rows]
    pivot_columns = []
    free_columns = []
    for column in range(column_count):
        rank = len(pivot_columns)
        pivot_row = next(
            (i for i in range(rank, len(matrix)) if matrix[i][column] != 0), None
        )
        if pivot_row is None:
            free_columns.append(column)
            continue
        matrix[rank], matrix[pivot_row] = matrix[pivot_row], matrix[rank]
        pivot = matrix[rank][column]
        matrix[rank] = [entry / pivot for entry in matrix[rank]]
        for i, row in enumerate(matrix):
            factor = row[column]
            if i != rank and factor != 0:
                matrix[i] = [
                    entry - factor * base for entry, base in zip(row, matrix[rank])
                ]
        pivot_columns.append(column)
    basis = []
    for free in free_columns:
        values = [Fraction(0)] * column_count
        values[free] = Fraction(1)
        for row, pivot_column in enumerate(pivot_columns):
            values[pivot_column] = -matrix[row][free]
        multiple = lcm(*(value.denominator for value in values))
        integers = [int(value * multiple) for value in values]
        divisor = gcd(*integers)
        basis.append([integer // divisor for integer in integers])
    return len(pivot_columns), basis


def determine_coefficients(species, signs, required):
    _, rows = composition_matrix(species, signs)
    _, basis = null_space(rows, len(species))
    if len(basis) >= 2:
        raise NoCoefficients(f"AMBIGUOUS (nullity {len(basis)})")
    if not basis:
        raise NoCoefficients("IMPOSSIBLE")
    coefficients = basis[0]
    if coefficients[0] < 0:
        coefficients = [-value for value in coefficients]
    if any(value <= 0 for value in coefficients[:required]):
        raise NoCoefficients("IMPOSSIBLE")
    return coefficients


def balance(equation):
    species = equation.species
    return determine_coefficients(species, equation.signs, len(species))


def term(name, coefficient):
    return name if coefficient == 1 else f"{coefficient}{name}"


def join_sides(left, right):
    return " + ".join(left) + " -> " + " + ".join(right)


def equation_notation(equation, coefficients):
    terms = [
        term(item.name, value) for item, value in zip(equation.species, coefficients)
    ]
    split = len(equation.reactants)
    return join_sides(terms[:split], terms[split:])


def find_species(species, name):
    return next(
        (index for index, item in enumerate(species) if item.name == name), None
    )


def gas_volume(species, amount, divisor):
    if not species.is_gas:
        return ""
    return f" {decimal(amount * GAS_MOLAR_VOLUME // divisor, 3)} L"


def split_at_separator(args):
    if args.count(":") != 1:
        raise ChemError("invalid separator")
    index = args.index(":")
    return args[:index], args[index + 1 :]


def ratio_report(amounts):
    elements = hill_order(amounts)
    moles = {
        element: Fraction(amounts[element], WEIGHTS[element]) for element in elements
    }
    smallest = min(moles.values())
    ratios = {element: moles[element] / smallest for element in elements}
    lines = [
        f"{element} {decimal(floor(1000 * ratios[element]), 3)}" for element in elements
    ]
    for multiplier in range(1, 13):
        counts = {element: round(multiplier * ratios[element]) for element in elements}
        if all(
            abs(multiplier * ratios[element] - counts[element]) <= Fraction(1, 20)
            for element in elements
        ):
            lines.append(f"{hill_notation(counts)} (k = {multiplier})")
            return lines
    lines.append("no simple ratio")
    return lines


def command_element(args):
    symbol = args[0]
    if symbol not in WEIGHTS:
        raise ChemError(f"unknown element {symbol}")
    return [f"{symbol} (Z = {ATOMIC_NUMBERS[symbol]}) {decimal(WEIGHTS[symbol], 3)} u"]


def command_parse(args):
    formula = read_formula(args[0])
    counts = ", ".join(
        f"{element} {count}" for element, count in hill_items(formula.composition)
    )
    notation = hill_notation(formula.composition, formula.charge)
    return [f"{notation} ({counts}; charge {signed(formula.charge)})"]


def command_mass(args):
    formula = read_formula(args[0])
    return [f"M({args[0]}) = {decimal(formula.molar_mass, 3)} g/mol"]


def command_percent(args):
    formula = read_formula(args[0])
    molar_mass = formula.molar_mass
    return [
        f"{element} {decimal(10000 * count * WEIGHTS[element] // molar_mass, 2)}%"
        for element, count in hill_items(formula.composition)
    ]


def command_empirical(args):
    composition = read_formula(args[0]).composition
    divisor = gcd(*composition.values())
    reduced = Counter(
        {element: count // divisor for element, count in composition.items()}
    )
    return [f"{hill_notation(reduced)} (n = {divisor})"]


def command_dbe(args):
    formula = read_formula(args[0])
    if formula.charge != 0:
        raise ChemError(f"charged formula {args[0]}")
    total = 2
    for element, count in hill_items(formula.composition):
        if element not in VALENCES:
            raise ChemError(f"no valence for {element}")
        total += count * (VALENCES[element] - 2)
    sign = "-" if total < 0 else ""
    magnitude = abs(total)
    return [f"DBE = {sign}{magnitude // 2}.{5 if magnitude % 2 else 0}"]


def assign_oxidation_states(elements):
    assigned = {}
    if "F" in elements:
        assigned["F"] = -1
    for element in elements:
        if element in FIXED_METALS:
            assigned[element] = FIXED_METALS[element]
    if "H" in elements:
        only_metals = all(
            element in FIXED_METALS for element in elements if element != "H"
        )
        assigned["H"] = -1 if only_metals else 1
    if "O" in elements:
        assigned["O"] = -2
    elif "F" not in elements:
        for halogen in ("Cl", "Br", "I"):
            if halogen in elements:
                assigned[halogen] = -1
                break
    return assigned


def command_oxstate(args):
    formula = read_formula(args[0])
    composition = formula.composition
    charge = formula.charge
    elements = hill_order(composition)
    if len(elements) == 1:
        states = {elements[0]: Fraction(charge, composition[elements[0]])}
    else:
        assigned = assign_oxidation_states(elements)
        undetermined = [element for element in elements if element not in assigned]
        if len(undetermined) >= 2:
            return ["indeterminate: " + " ".join(undetermined)]
        total = sum(composition[element] * value for element, value in assigned.items())
        states = {element: Fraction(value) for element, value in assigned.items()}
        if undetermined:
            unknown = undetermined[0]
            states[unknown] = Fraction(charge - total, composition[unknown])
        elif total != charge:
            last = list(assigned)[-1]
            others = total - composition[last] * assigned[last]
            states[last] = Fraction(charge - others, composition[last])
    return [", ".join(f"{element} {signed(states[element])}" for element in elements)]


def command_moles(args):
    formula = read_formula(args[0])
    quantity = read_quantity(args[1])
    moles = quantity * 1000000 // formula.molar_mass
    return [f"{decimal(quantity, 3)} g {args[0]} = {decimal(moles, 6)} mol"]


def command_grams(args):
    formula = read_formula(args[0])
    quantity = read_quantity(args[1])
    grams = quantity * formula.molar_mass // 1000
    return [f"{decimal(quantity, 3)} mol {args[0]} = {decimal(grams, 3)} g"]


def command_molecular(args):
    formula = read_formula(args[0])
    if formula.charge != 0:
        raise ChemError(f"charged formula {args[0]}")
    quantity = read_quantity(args[1])
    molar_mass = formula.molar_mass
    multiple = (2 * quantity + molar_mass) // (2 * molar_mass)
    if multiple == 0 or 10 * abs(quantity - multiple * molar_mass) > molar_mass:
        return [
            f"no integer multiple (ratio {decimal(1000 * quantity // molar_mass, 3)})"
        ]
    molecule = hill_notation(scaled(formula.composition, multiple))
    return [f"{molecule} (n = {multiple}, {decimal(multiple * molar_mass, 3)} g/mol)"]


def closing_bracket(text):
    depth = 0
    for index, char in enumerate(text):
        if char == "[":
            depth += 1
        elif char == "]":
            depth -= 1
            if depth == 0:
                return index
    return -1


def group_notation(word, count):
    core = word.partition("^")[0]
    if count == 1:
        return core
    if ELEMENT_SYMBOL.fullmatch(core) or (
        core.startswith("[") and closing_bracket(core) == len(core) - 1
    ):
        return f"{core}{count}"
    return f"({core}){count}"


def command_salt(args):
    cation_word, anion_word = args
    cation = read_formula(cation_word)
    anion = read_formula(anion_word)
    if cation.charge <= 0:
        raise ChemError(f"not a cation {cation_word}")
    if anion.charge >= 0:
        raise ChemError(f"not an anion {anion_word}")
    for word in args:
        if "." in word:
            raise ChemError(f"hydrate ion {word}")
    divisor = gcd(cation.charge, anion.charge)
    cation_count = -anion.charge // divisor
    anion_count = cation.charge // divisor
    salt = Formula(scaled(cation.composition, cation_count), 0)
    add_scaled(salt.composition, anion.composition, anion_count)
    name = group_notation(cation_word, cation_count) + group_notation(
        anion_word, anion_count
    )
    notation = hill_notation(salt.composition)
    return [f"{name} ({notation}, {decimal(salt.molar_mass, 3)} g/mol)"]


def command_derive(args):
    amounts = {}
    for symbol, word in zip(args[::2], args[1::2]):
        if symbol not in WEIGHTS:
            raise ChemError(f"unknown element {symbol}")
        if symbol in amounts:
            raise ChemError(f"duplicate element {symbol}")
        quantity = read_quantity(word)
        if quantity > 100000:
            raise ChemError(f"invalid percentage {word}")
        amounts[symbol] = quantity
    total = sum(amounts.values())
    if abs(total - 100000) > 1000:
        raise ChemError(f"percentages sum to {decimal(total, 3)}")
    return ratio_report(amounts)


def command_combust(args):
    sample, carbon_dioxide, water = [read_quantity(word) for word in args]
    carbon = carbon_dioxide * 12011 // 44009
    hydrogen = water * 2016 // 18015
    oxygen = sample - carbon - hydrogen
    if carbon == 0 or hydrogen == 0 or 100 * oxygen < -sample:
        raise ChemError("inconsistent masses")
    amounts = {"C": carbon, "H": hydrogen}
    if 100 * oxygen > sample:
        amounts["O"] = oxygen
    lines = [
        f"mass {element} {decimal(mass, 3)} g" for element, mass in amounts.items()
    ]
    return lines + ratio_report(amounts)


def command_balance(args):
    equation = read_equation(args)
    return [equation_notation(equation, balance(equation))]


def command_matrix(args):
    equation = read_equation(args)
    species = equation.species
    labels, rows = composition_matrix(species, equation.signs)
    rank, basis = null_space(rows, len(species))
    lines = ["columns: " + " ".join(item.name for item in species)]
    lines += [
        f"{label}: " + " ".join(map(str, row)) for label, row in zip(labels, rows)
    ]
    lines.append(f"rank {rank}, nullity {len(basis)}")
    lines += ["null: " + " ".join(map(str, vector)) for vector in basis]
    return lines


def command_check(args):
    equation = read_equation(args, allow_coefficients=True)
    species = equation.species
    labels, rows = composition_matrix(species, equation.signs)
    coefficients = [item.coefficient for item in species]
    split = len(equation.reactants)
    differences = []
    for label, row in zip(labels, rows):
        amounts = [value * entry for value, entry in zip(coefficients, row)]
        left = sum(amounts[:split])
        right = -sum(amounts[split:])
        if left != right:
            show = signed if label == "charge" else str
            differences.append(f"{label}: {show(left)} != {show(right)}")
    if differences:
        return ["not balanced", *differences]
    divisor = gcd(*coefficients)
    if divisor == 1:
        return ["balanced"]
    return [f"balanced, not in lowest terms (gcd {divisor})"]


def balance_in_solution(args, with_electrons):
    medium = args[0]
    if medium not in SOLUTION_IONS:
        raise ChemError(f"invalid medium {medium}")
    equation = read_equation(args[1:])
    species = equation.species
    for item in species:
        if item.formula_text in RESERVED_SPECIES:
            raise ChemError(f"reserved species {item.name}")
    auxiliary = [SOLUTION_IONS[medium], WATER]
    if with_electrons:
        auxiliary.append(ELECTRON)
    coefficients = determine_coefficients(
        species + auxiliary, equation.signs + [1] * len(auxiliary), len(species)
    )
    terms = [term(item.name, value) for item, value in zip(species, coefficients)]
    split = len(equation.reactants)
    left = terms[:split]
    right = terms[split:]
    for item, value in zip(auxiliary, coefficients[len(species) :]):
        if value > 0:
            left.append(term(item.name, value))
        elif value < 0:
            right.append(term(item.name, -value))
    lines = [join_sides(left, right)]
    if with_electrons:
        electrons = coefficients[-1]
        if electrons > 0:
            lines.append("reduction")
        elif electrons < 0:
            lines.append("oxidation")
        else:
            lines.append("no electron transfer")
    return lines


def command_redox(args):
    return balance_in_solution(args, with_electrons=False)


def command_half(args):
    return balance_in_solution(args, with_electrons=True)


def command_stoich(args):
    equation_words, rest = split_at_separator(args)
    if len(rest) != 2:
        raise ChemError("wrong argument count for STOICH")
    equation = read_equation(equation_words)
    target, quantity_word = rest
    species = equation.species
    index = find_species(species, target)
    if index is None:
        raise ChemError(f"species {target} not in equation")
    quantity = read_quantity(quantity_word)
    coefficients = balance(equation)
    divisor = coefficients[index] * species[index].formula.molar_mass
    lines = [equation_notation(equation, coefficients)]
    for item, value in zip(species, coefficients):
        amount = quantity * value
        moles = decimal(amount * 1000000 // divisor, 6)
        grams = decimal(amount * item.formula.molar_mass // divisor, 3)
        lines.append(
            f"{item.name} {moles} mol {grams} g" + gas_volume(item, amount, divisor)
        )
    return lines


def command_limiting(args):
    equation_words, mass_words = split_at_separator(args)
    equation = read_equation(equation_words)
    reactants = equation.reactants
    if len(mass_words) != len(reactants):
        raise ChemError(f"expected {len(reactants)} masses, got {len(mass_words)}")
    masses = [read_quantity(word) for word in mass_words]
    coefficients = balance(equation)
    reaction_masses = [
        value * reactant.formula.molar_mass
        for value, reactant in zip(coefficients, reactants)
    ]
    extents = [Fraction(mass, weight) for mass, weight in zip(masses, reaction_masses)]
    limiting = extents.index(min(extents))
    limiting_mass = masses[limiting]
    divisor = reaction_masses[limiting]
    lines = [
        equation_notation(equation, coefficients),
        f"limiting {reactants[limiting].name}",
        f"extent {decimal(limiting_mass * 1000000 // divisor, 6)} mol",
    ]
    for product, value in zip(equation.products, coefficients[len(reactants) :]):
        amount = limiting_mass * value
        grams = decimal(amount * product.formula.molar_mass // divisor, 3)
        volume = gas_volume(product, amount, divisor)
        lines.append(f"product {product.name} {grams} g{volume}")
    for index, reactant in enumerate(reactants):
        if index != limiting:
            consumed = limiting_mass * reaction_masses[index]
            remaining = (masses[index] * divisor - consumed) // divisor
            lines.append(f"remaining {reactant.name} {decimal(remaining, 3)} g")
    return lines


def command_yield(args):
    equation_words, rest = split_at_separator(args)
    if len(rest) != 4:
        raise ChemError("wrong argument count for YIELD")
    equation = read_equation(equation_words)
    reactant_name, reactant_word, product_name, product_word = rest
    reactant_index = find_species(equation.reactants, reactant_name)
    if reactant_index is None:
        raise ChemError(f"{reactant_name} is not a reactant")
    product_index = find_species(equation.products, product_name)
    if product_index is None:
        raise ChemError(f"{product_name} is not a product")
    reactant_mass = read_quantity(reactant_word)
    actual = read_quantity(product_word)
    coefficients = balance(equation)
    reactant_coefficient = coefficients[reactant_index]
    product_coefficient = coefficients[len(equation.reactants) + product_index]
    reactant_molar_mass = equation.reactants[reactant_index].formula.molar_mass
    product_molar_mass = equation.products[product_index].formula.molar_mass
    produced = reactant_mass * product_coefficient * product_molar_mass
    theoretical = produced // (reactant_coefficient * reactant_molar_mass)
    lines = [
        equation_notation(equation, coefficients),
        f"theoretical {decimal(theoretical, 3)} g",
        f"actual {decimal(actual, 3)} g",
    ]
    if theoretical == 0:
        lines.append("yield undefined")
    else:
        lines.append(f"yield {decimal(actual * 10000 // theoretical, 2)}%")
    return lines


def command_heat(args):
    name, word = args
    read_species(name)
    value = read_enthalpy(word)
    line = f"dHf({name}) = {enthalpy_notation(value)} kJ/mol"
    if name in formation_enthalpies:
        line += f" (was {enthalpy_notation(formation_enthalpies[name])})"
    formation_enthalpies[name] = value
    return [line]


def command_deltah(args):
    equation = read_equation(args)
    for item in equation.species:
        if item.name not in formation_enthalpies:
            raise ChemError(f"no enthalpy for {item.name}")
    coefficients = balance(equation)
    contributions = [
        value * formation_enthalpies[item.name]
        for item, value in zip(equation.species, coefficients)
    ]
    split = len(equation.reactants)
    change = sum(contributions[split:]) - sum(contributions[:split])
    if change < 0:
        kind = "exothermic"
    elif change > 0:
        kind = "endothermic"
    else:
        kind = "thermoneutral"
    return [
        equation_notation(equation, coefficients),
        f"dH = {enthalpy_notation(change)} kJ ({kind})",
    ]


def command_heats(args):
    if not formation_enthalpies:
        return ["no enthalpies"]
    return [
        f"{name} {enthalpy_notation(value)} kJ/mol"
        for name, value in sorted(formation_enthalpies.items())
    ]


def exactly(count):
    return lambda actual: actual == count


def at_least(count):
    return lambda actual: actual >= count


def any_count(actual):
    return True


COMMANDS = {
    "ELEMENT": (command_element, exactly(1)),
    "PARSE": (command_parse, exactly(1)),
    "MASS": (command_mass, exactly(1)),
    "PERCENT": (command_percent, exactly(1)),
    "EMPIRICAL": (command_empirical, exactly(1)),
    "DBE": (command_dbe, exactly(1)),
    "OXSTATE": (command_oxstate, exactly(1)),
    "MOLES": (command_moles, exactly(2)),
    "GRAMS": (command_grams, exactly(2)),
    "MOLECULAR": (command_molecular, exactly(2)),
    "SALT": (command_salt, exactly(2)),
    "DERIVE": (command_derive, lambda actual: actual >= 2 and actual % 2 == 0),
    "COMBUST": (command_combust, exactly(3)),
    "BALANCE": (command_balance, at_least(1)),
    "MATRIX": (command_matrix, at_least(1)),
    "CHECK": (command_check, at_least(1)),
    "REDOX": (command_redox, at_least(2)),
    "HALF": (command_half, at_least(2)),
    "STOICH": (command_stoich, any_count),
    "LIMITING": (command_limiting, any_count),
    "YIELD": (command_yield, any_count),
    "HEAT": (command_heat, exactly(2)),
    "DELTAH": (command_deltah, at_least(1)),
    "HEATS": (command_heats, exactly(0)),
}


def execute(line):
    name, *args = line.split(" ")
    try:
        if name not in COMMANDS:
            raise ChemError(f"unknown command {name}")
        handler, accepts = COMMANDS[name]
        if not accepts(len(args)):
            raise ChemError(f"wrong argument count for {name}")
        return handler(args)
    except ChemError as error:
        return [f"error: {error}"]
    except NoCoefficients as result:
        return [str(result)]


def main():
    lines = sys.stdin.read().splitlines()
    output = []
    for line in lines[1 : int(lines[0]) + 1]:
        output.extend(execute(line))
    print("\n".join(output))


if __name__ == "__main__":
    main()
