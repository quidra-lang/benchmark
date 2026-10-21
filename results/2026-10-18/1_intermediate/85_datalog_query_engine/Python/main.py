import operator
import re
import sys
from collections import Counter, defaultdict, namedtuple
from dataclasses import dataclass

RESERVED = {
    'not', 'mod', 'count', 'sum', 'min', 'max', 'retract', 'dump', 'why',
    'forget', 'listing', 'strata', 'stats', 'check', 'predicates', 'undo', 'halt',
}
TWO_CHAR_SYMBOLS = (':-', '?-', '!=', '<=', '>=')
ONE_CHAR_SYMBOLS = '(),.:=<>+-*/'
WORD = re.compile(r'[A-Za-z0-9_]+')
PLAIN_SYMBOL = re.compile(r'[a-z][A-Za-z0-9_]*')
MAX_INTEGER = 1_000_000_000

COMPARISONS = {
    '=': operator.eq,
    '!=': operator.ne,
    '<': operator.lt,
    '<=': operator.le,
    '>': operator.gt,
    '>=': operator.ge,
}
ARITHMETIC = {
    '+': operator.add,
    '-': operator.sub,
    '*': operator.mul,
    '/': operator.floordiv,
    'mod': operator.mod,
}
OPERATORS = COMPARISONS.keys() | ARITHMETIC.keys()

Token = namedtuple('Token', 'kind text value')


class DatalogError(Exception):
    pass


@dataclass
class Const:
    value: int | str


@dataclass
class Var:
    name: str


@dataclass
class Anon:
    pass


@dataclass
class Paren:
    inner: object


@dataclass
class BinOp:
    op: str
    left: object
    right: object


@dataclass
class Atom:
    predicate: str
    terms: list
    negated: bool = False


@dataclass
class Comparison:
    op: str
    left: object
    right: object


@dataclass
class Rule:
    number: int
    head: Atom | None
    body: list
    notation: str


@dataclass
class Model:
    tuples: dict
    derivation: dict
    deriving_rule: dict
    stratum_stats: list


def tokenize(line):
    tokens = []
    pos = 0
    while pos < len(line):
        char = line[pos]
        pair = line[pos:pos + 2]
        if char == ' ':
            pos += 1
        elif char == '%':
            break
        elif char == '"':
            end = line.find('"', pos + 1)
            if end < 0:
                raise DatalogError('unterminated string')
            tokens.append(Token('STRING', line[pos:end + 1], line[pos + 1:end]))
            pos = end + 1
        elif pair in TWO_CHAR_SYMBOLS:
            tokens.append(Token(pair, pair, None))
            pos += 2
        elif char in ONE_CHAR_SYMBOLS:
            tokens.append(Token(char, char, None))
            pos += 1
        elif match := WORD.match(line, pos):
            tokens.append(word_token(match.group()))
            pos = match.end()
        else:
            raise DatalogError(f"bad character '{char}'")
    return tokens


def word_token(word):
    first = word[0]
    if first.islower():
        return Token(word if word in RESERVED else 'NAME', word, word)
    if first.isupper():
        return Token('VARIABLE', word, word)
    if word == '_':
        return Token('ANONYMOUS', word, None)
    if word.isdigit():
        if int(word) > MAX_INTEGER:
            raise DatalogError(f"integer out of range '{word}'")
        return Token('INTEGER', word, int(word))
    raise DatalogError(f"bad token '{word}'")


class Parser:
    def __init__(self, tokens):
        self.tokens = tokens
        self.pos = 0

    def kind(self, offset=0):
        index = self.pos + offset
        return self.tokens[index].kind if index < len(self.tokens) else None

    def advance(self):
        token = self.tokens[self.pos]
        self.pos += 1
        return token

    def accept(self, kind):
        if self.kind() != kind:
            return False
        self.pos += 1
        return True

    def expect(self, kind):
        if self.kind() != kind:
            raise self.error()
        return self.advance()

    def error(self):
        if self.pos == len(self.tokens):
            return DatalogError('syntax error at end of line')
        return DatalogError(f"syntax error at '{self.tokens[self.pos].text}'")

    def statement(self):
        kind = self.kind()
        if kind == 'NAME':
            head = self.atom()
            body = self.body() if self.accept(':-') else []
            result = ('clause', head, body)
        elif kind == ':-':
            self.advance()
            result = ('clause', None, self.body())
        elif kind == '?-':
            self.advance()
            result = self.query()
        elif kind in ('retract', 'why'):
            self.advance()
            result = (kind, self.atom())
        elif kind == 'dump':
            self.advance()
            result = (kind, self.expect('NAME').value)
        elif kind == 'forget':
            self.advance()
            result = (kind, self.expect('INTEGER').value)
        elif kind == 'listing':
            self.advance()
            result = (kind, self.advance().value if self.kind() == 'NAME' else None)
        elif kind in ('strata', 'stats', 'check', 'predicates', 'undo', 'halt'):
            self.advance()
            result = (kind,)
        else:
            raise self.error()
        self.expect('.')
        if self.pos < len(self.tokens):
            raise self.error()
        return result

    def query(self):
        aggregate = variable = None
        if self.kind() in ('count', 'sum', 'min', 'max'):
            aggregate = self.advance().kind
            if aggregate != 'count':
                variable = self.expect('VARIABLE').value
                self.expect(':')
        return ('query', aggregate, variable, self.body())

    def body(self):
        literals = [self.literal()]
        while self.accept(','):
            literals.append(self.literal())
        return literals

    def literal(self):
        if self.accept('not'):
            return self.atom(negated=True)
        if self.kind() == 'NAME' and self.kind(1) not in OPERATORS:
            return self.atom()
        left = self.expression()
        if self.kind() not in COMPARISONS:
            raise self.error()
        op = self.advance().kind
        return Comparison(op, left, self.expression())

    def atom(self, negated=False):
        predicate = self.expect('NAME').value
        terms = []
        if self.accept('('):
            terms.append(self.term())
            while self.accept(','):
                terms.append(self.term())
            self.expect(')')
        return Atom(predicate, terms, negated)

    def term(self):
        match self.kind():
            case 'NAME' | 'STRING' | 'INTEGER':
                return Const(self.advance().value)
            case '-':
                self.advance()
                return Const(-self.expect('INTEGER').value)
            case 'VARIABLE':
                return Var(self.advance().value)
            case 'ANONYMOUS':
                self.advance()
                return Anon()
        raise self.error()

    def expression(self):
        left = self.product()
        while self.kind() in ('+', '-'):
            op = self.advance().kind
            left = BinOp(op, left, self.product())
        return left

    def product(self):
        left = self.factor()
        while self.kind() in ('*', '/', 'mod'):
            op = self.advance().kind
            left = BinOp(op, left, self.factor())
        return left

    def factor(self):
        if not self.accept('('):
            return self.term()
        inner = self.expression()
        self.expect(')')
        return Paren(inner)


def value_key(value):
    return (isinstance(value, str), value)


def row_key(row):
    return tuple(value_key(value) for value in row)


def value_notation(value):
    if isinstance(value, int):
        return str(value)
    if PLAIN_SYMBOL.fullmatch(value) and value not in RESERVED:
        return value
    return f'"{value}"'


def tuple_notation(predicate, row):
    if not row:
        return predicate
    return f'{predicate}({", ".join(map(value_notation, row))})'


def term_notation(term, binding):
    match term:
        case Const(value):
            return value_notation(value)
        case Var(name):
            return value_notation(binding[name]) if name in binding else name
    return '_'


def expression_notation(expression, binding):
    match expression:
        case Paren(inner):
            return f'({expression_notation(inner, binding)})'
        case BinOp(op, left, right):
            left_text = expression_notation(left, binding)
            right_text = expression_notation(right, binding)
            return f'{left_text} {op} {right_text}'
    return term_notation(expression, binding)


def literal_notation(literal, binding):
    if isinstance(literal, Comparison):
        left = expression_notation(literal.left, binding)
        right = expression_notation(literal.right, binding)
        return f'{left} {literal.op} {right}'
    text = literal.predicate
    if literal.terms:
        text += f'({", ".join(term_notation(term, binding) for term in literal.terms)})'
    return f'not {text}' if literal.negated else text


def rule_notation(head, body):
    literals = ', '.join(literal_notation(literal, {}) for literal in body)
    if head is None:
        return f':- {literals}.'
    return f'{literal_notation(head, {})} :- {literals}.'


def counted(count, singular, plural):
    return f'{count} {singular if count == 1 else plural}'


def format_answer(names, answer):
    return ', '.join(f'{name} = {value_notation(value)}' for name, value in zip(names, answer))


def is_positive(literal):
    return isinstance(literal, Atom) and not literal.negated


def body_atoms(body):
    return [literal for literal in body if isinstance(literal, Atom)]


def variables(terms):
    return [term.name for term in terms if isinstance(term, Var)]


def expression_terms(expression):
    match expression:
        case Paren(inner):
            return expression_terms(inner)
        case BinOp(_, left, right):
            return expression_terms(left) + expression_terms(right)
    return [expression]


def literal_terms(literal):
    if isinstance(literal, Atom):
        return literal.terms
    return expression_terms(literal.left) + expression_terms(literal.right)


def body_variables(body):
    names = (name for literal in body for name in variables(literal_terms(literal)))
    return list(dict.fromkeys(names))


def arity_error(predicate, expected, actual):
    return DatalogError(f'arity mismatch for {predicate}: expected {expected}, got {actual}')


def check_safety(head, body, first_variables):
    if head and any(isinstance(term, Anon) for term in head.terms):
        raise DatalogError('anonymous variable in head')
    filters = [literal for literal in body if not is_positive(literal)]
    for literal in filters:
        if isinstance(literal, Comparison) and any(
            isinstance(term, Anon) for term in literal_terms(literal)
        ):
            raise DatalogError('anonymous variable in comparison')
    bound = {name for literal in body if is_positive(literal) for name in variables(literal.terms)}
    candidates = first_variables + [
        name for literal in filters for name in variables(literal_terms(literal))
    ]
    for name in candidates:
        if name not in bound:
            raise DatalogError(f'unsafe variable {name}')


def compute_strata(predicates, rules):
    strata = dict.fromkeys(predicates, 0)
    edges = [
        (rule.head.predicate, atom.predicate, int(atom.negated))
        for rule in rules
        if rule.head
        for atom in body_atoms(rule.body)
    ]
    changed = True
    while changed:
        changed = False
        for head, dependency, weight in edges:
            if strata[head] < strata[dependency] + weight:
                strata[head] = strata[dependency] + weight
                # A stratum can never exceed the number of predicates without a negative cycle.
                if strata[head] > len(strata):
                    return None
                changed = True
    return strata


def recursive_predicates(rules):
    graph = defaultdict(set)
    for rule in rules:
        if rule.head:
            graph[rule.head.predicate].update(atom.predicate for atom in body_atoms(rule.body))
    recursive = set()
    for start in graph:
        seen = set()
        stack = list(graph[start])
        while stack:
            current = stack.pop()
            if current == start:
                recursive.add(start)
                break
            if current not in seen:
                seen.add(current)
                stack.extend(graph.get(current, ()))
    return recursive


def term_value(term, binding):
    return term.value if isinstance(term, Const) else binding[term.name]


def unify(terms, row, binding):
    result = dict(binding)
    for term, value in zip(terms, row):
        if isinstance(term, Const):
            if term.value != value:
                return None
        elif isinstance(term, Var):
            if result.setdefault(term.name, value) != value:
                return None
    return result


def evaluate(expression, binding):
    match expression:
        case Paren(inner):
            return evaluate(inner, binding)
        case BinOp(op, left, right):
            left_value = evaluate(left, binding)
            right_value = evaluate(right, binding)
            if not isinstance(left_value, int) or not isinstance(right_value, int):
                return None
            if right_value == 0 and op in ('/', 'mod'):
                return None
            return ARITHMETIC[op](left_value, right_value)
    return term_value(expression, binding)


def compare(op, left, right):
    if left is None or right is None:
        return False
    if op not in ('=', '!=') and not (isinstance(left, int) and isinstance(right, int)):
        return False
    return COMPARISONS[op](left, right)


def holds(literal, binding, negative):
    if isinstance(literal, Comparison):
        return compare(
            literal.op, evaluate(literal.left, binding), evaluate(literal.right, binding)
        )
    rows = negative[literal.predicate]
    if any(isinstance(term, Anon) for term in literal.terms):
        return all(unify(literal.terms, row, binding) is None for row in rows)
    return tuple(term_value(term, binding) for term in literal.terms) not in rows


def solve(body, positive, negative, start):
    # Positive atoms are joined left to right through indexes on their bound positions;
    # negated atoms and comparisons are checked as soon as their variables are bound.
    atoms = [literal for literal in body if is_positive(literal)]
    known = set(start)
    stages = [set(known)]
    plans = []
    for atom in atoms:
        keys = [
            index
            for index, term in enumerate(atom.terms)
            if isinstance(term, Const) or (isinstance(term, Var) and term.name in known)
        ]
        table = defaultdict(list)
        for row in positive[atom.predicate]:
            table[tuple(row[index] for index in keys)].append(row)
        plans.append((atom, keys, table))
        known.update(variables(atom.terms))
        stages.append(set(known))
    checks = [[] for _ in stages]
    for literal in body:
        if not is_positive(literal):
            needed = set(variables(literal_terms(literal)))
            stage = next(depth for depth, bound in enumerate(stages) if needed <= bound)
            checks[stage].append(literal)

    def search(depth, binding):
        if not all(holds(literal, binding, negative) for literal in checks[depth]):
            return
        if depth == len(plans):
            yield binding
            return
        atom, keys, table = plans[depth]
        key = tuple(term_value(atom.terms[index], binding) for index in keys)
        for row in table.get(key, ()):
            extended = unify(atom.terms, row, binding)
            if extended is not None:
                yield from search(depth + 1, extended)

    return search(0, start)


class Engine:
    def __init__(self):
        self.arities = {}
        self.facts = {}
        self.rules = {}
        self.next_rule = 1
        self.history = []
        self.cached_model = None

    def register(self, predicate, arity):
        if predicate not in self.arities:
            self.arities[predicate] = arity
            self.facts[predicate] = set()

    def record(self, line):
        facts = {predicate: set(rows) for predicate, rows in self.facts.items()}
        self.history.append((line, dict(self.arities), facts, dict(self.rules)))
        self.cached_model = None

    def proper_rules(self):
        return [rule for rule in self.rules.values() if rule.head]

    def model(self):
        if self.cached_model is None:
            self.cached_model = self.compute_model()
        return self.cached_model

    def compute_model(self):
        rules = self.proper_rules()
        strata = compute_strata(self.arities, rules)
        tuples = {predicate: set(rows) for predicate, rows in self.facts.items()}
        derivation = {(predicate, row): 0 for predicate, rows in self.facts.items() for row in rows}
        deriving_rule = {}
        stratum_stats = []
        round_number = 0
        for level in range(max(strata.values(), default=-1) + 1):
            level_rules = [rule for rule in rules if strata[rule.head.predicate] == level]
            rounds = added = 0
            while True:
                new = {}
                for rule in level_rules:
                    for binding in solve(rule.body, tuples, tuples, {}):
                        row = tuple(term_value(term, binding) for term in rule.head.terms)
                        if row not in tuples[rule.head.predicate]:
                            new.setdefault((rule.head.predicate, row), rule.number)
                if not new:
                    break
                round_number += 1
                rounds += 1
                added += len(new)
                for (predicate, row), number in new.items():
                    tuples[predicate].add(row)
                    derivation[predicate, row] = round_number
                    deriving_rule[predicate, row] = number
            stratum_stats.append((rounds, added))
        return Model(tuples, derivation, deriving_rule, stratum_stats)

    def answers(self, body):
        names = body_variables(body)
        tuples = self.model().tuples
        rows = {
            tuple(binding[name] for name in names)
            for binding in solve(body, tuples, tuples, {})
        }
        return names, sorted(rows, key=row_key)

    def check_known(self, atoms):
        for atom in atoms:
            if atom.predicate not in self.arities:
                raise DatalogError(f'unknown predicate {atom.predicate}')
            expected = self.arities[atom.predicate]
            if expected != len(atom.terms):
                raise arity_error(atom.predicate, expected, len(atom.terms))

    def execute(self, statement, line):
        match statement:
            case ('clause', head, body):
                self.add_clause(head, body, line)
            case ('query', aggregate, variable, body):
                self.query(aggregate, variable, body)
            case ('retract', atom):
                self.retract(atom, line)
            case ('why', atom):
                self.why(atom)
            case ('dump', name):
                self.dump(name)
            case ('forget', number):
                self.forget(number, line)
            case ('listing', name):
                self.listing(name)
            case ('strata',):
                self.show_strata()
            case ('stats',):
                self.stats()
            case ('check',):
                self.check()
            case ('predicates',):
                self.show_predicates()
            case ('undo',):
                self.undo()

    def add_clause(self, head, body, line):
        atoms = ([head] if head else []) + body_atoms(body)
        seen = {}
        for atom in atoms:
            expected = self.arities.get(atom.predicate, seen.get(atom.predicate))
            if expected is not None and expected != len(atom.terms):
                raise arity_error(atom.predicate, expected, len(atom.terms))
            seen[atom.predicate] = len(atom.terms)
        check_safety(head, body, variables(head.terms) if head else [])
        if not body:
            self.add_fact(head, line)
            return
        notation = rule_notation(head, body)
        for rule in self.rules.values():
            if rule.notation == notation:
                raise DatalogError(f'duplicate of rule {rule.number}')
        rule = Rule(self.next_rule, head, body, notation)
        new_predicates = {
            atom.predicate: len(atom.terms) for atom in atoms if atom.predicate not in self.arities
        }
        strata = compute_strata(self.arities | new_predicates, [*self.rules.values(), rule])
        if head and strata is None:
            raise DatalogError(f'negative cycle through {head.predicate}')
        self.record(line)
        self.rules[rule.number] = rule
        self.next_rule += 1
        for predicate, arity in new_predicates.items():
            self.register(predicate, arity)
        terms = (head.terms if head else []) + [
            term for literal in body for term in literal_terms(literal)
        ]
        for name, count in Counter(variables(terms)).items():
            if count == 1:
                print(f'WARNING line {line}: singleton variable {name}')

    def add_fact(self, head, line):
        row = tuple(term.value for term in head.terms)
        if row in self.facts.get(head.predicate, ()):
            return
        self.record(line)
        self.register(head.predicate, len(row))
        self.facts[head.predicate].add(row)

    def query(self, aggregate, variable, body):
        self.check_known(body_atoms(body))
        check_safety(None, body, [variable] if variable else [])
        names, answers = self.answers(body)
        if aggregate == 'count':
            print(len(answers))
        elif aggregate is None and not names:
            print('true.' if answers else 'false.')
        elif aggregate is None:
            for answer in answers:
                print(format_answer(names, answer))
            print(counted(len(answers), 'answer', 'answers'))
        else:
            position = names.index(variable)
            values = [answer[position] for answer in answers]
            if aggregate == 'sum':
                if any(isinstance(value, str) for value in values):
                    raise DatalogError('non-integer value in sum')
                print(sum(values))
            elif not values:
                print('no answers')
            else:
                pick = min if aggregate == 'min' else max
                print(value_notation(pick(values, key=value_key)))

    def retract(self, atom, line):
        self.check_known([atom])
        facts = self.facts[atom.predicate]
        matching = [row for row in facts if unify(atom.terms, row, {}) is not None]
        if not matching:
            raise DatalogError('no matching facts')
        self.record(line)
        facts.difference_update(matching)
        print(counted(len(matching), 'fact', 'facts') + ' retracted')

    def why(self, atom):
        self.check_known([atom])
        if not all(isinstance(term, Const) for term in atom.terms):
            raise DatalogError('why needs a ground atom')
        row = tuple(term.value for term in atom.terms)
        model = self.model()
        if row in model.tuples[atom.predicate]:
            self.prove(model, atom.predicate, row, 0)
        else:
            print('false.')

    def prove(self, model, predicate, row, depth):
        indent = '  ' * depth
        level = model.derivation[predicate, row]
        if level == 0:
            print(f'{indent}{tuple_notation(predicate, row)} [fact]')
            return
        rule = self.rules[model.deriving_rule[predicate, row]]
        earlier = {
            atom.predicate: [
                candidate
                for candidate in model.tuples[atom.predicate]
                if model.derivation[atom.predicate, candidate] < level
            ]
            for atom in rule.body
            if is_positive(atom)
        }
        order = list(dict.fromkeys(variables(rule.head.terms) + body_variables(rule.body)))
        start = unify(rule.head.terms, row, {})
        theta = min(
            solve(rule.body, earlier, model.tuples, start),
            key=lambda binding: row_key([binding[name] for name in order]),
        )
        print(f'{indent}{tuple_notation(predicate, row)} [rule {rule.number}]')
        for literal in rule.body:
            if not is_positive(literal):
                print(f'{indent}  {literal_notation(literal, theta)}')
            elif any(isinstance(term, Anon) for term in literal.terms):
                candidates = [
                    candidate
                    for candidate in earlier[literal.predicate]
                    if unify(literal.terms, candidate, theta) is not None
                ]
                self.prove(model, literal.predicate, min(candidates, key=row_key), depth + 1)
            else:
                values = tuple(term_value(term, theta) for term in literal.terms)
                self.prove(model, literal.predicate, values, depth + 1)

    def dump(self, name):
        if name not in self.arities:
            raise DatalogError(f'unknown predicate {name}')
        rows = sorted(self.model().tuples[name], key=row_key)
        for row in rows:
            print(tuple_notation(name, row) + '.')
        print(counted(len(rows), 'tuple', 'tuples'))

    def forget(self, number, line):
        if number not in self.rules:
            raise DatalogError(f'no rule {number}')
        self.record(line)
        del self.rules[number]

    def undo(self):
        if not self.history:
            raise DatalogError('nothing to undo')
        line, self.arities, self.facts, self.rules = self.history.pop()
        self.cached_model = None
        print(f'undid line {line}')

    def listing(self, name):
        if name is None:
            rules = list(self.rules.values())
        elif name not in self.arities:
            raise DatalogError(f'unknown predicate {name}')
        else:
            rules = [rule for rule in self.proper_rules() if rule.head.predicate == name]
        for rule in rules:
            print(f'{rule.number}: {rule.notation}')
        if not rules:
            print('no rules')

    def show_strata(self):
        if not self.arities:
            print('no predicates')
            return
        strata = compute_strata(self.arities, self.rules.values())
        recursive = recursive_predicates(self.rules.values())
        for level in range(max(strata.values()) + 1):
            names = sorted(name for name, stratum in strata.items() if stratum == level)
            listed = ', '.join(name + '*' if name in recursive else name for name in names)
            print(f'stratum {level}: {listed}')

    def stats(self):
        model = self.model()
        rules = self.proper_rules()
        facts = sum(len(rows) for rows in self.facts.values())
        tuples = sum(len(rows) for rows in model.tuples.values())
        constraints = len(self.rules) - len(rules)
        print(f'facts {facts}, rules {len(rules)}, constraints {constraints}, tuples {tuples}')
        for level, (rounds, added) in enumerate(model.stratum_stats):
            print(f'stratum {level}: rounds {rounds}, new {added}')
        derived = Counter(model.deriving_rule.values())
        for rule in rules:
            print(f'rule {rule.number}: new {derived[rule.number]}')

    def show_predicates(self):
        if not self.arities:
            print('no predicates')
            return
        model = self.model()
        heads = Counter(rule.head.predicate for rule in self.proper_rules())
        for name in sorted(self.arities):
            print(
                f'{name}/{self.arities[name]}: facts {len(self.facts[name])}, '
                f'rules {heads[name]}, tuples {len(model.tuples[name])}'
            )

    def check(self):
        constraints = [rule for rule in self.rules.values() if rule.head is None]
        if not constraints:
            print('no constraints')
        for constraint in constraints:
            names, answers = self.answers(constraint.body)
            if not answers:
                print(f'constraint {constraint.number}: ok')
                continue
            violations = counted(len(answers), 'violation', 'violations')
            print(f'constraint {constraint.number}: {violations}')
            if names:
                for answer in answers:
                    print('  ' + format_answer(names, answer))


def main():
    engine = Engine()
    for number, line in enumerate(sys.stdin.read().splitlines(), start=1):
        try:
            tokens = tokenize(line)
            if not tokens:
                continue
            statement = Parser(tokens).statement()
            if statement == ('halt',):
                break
            engine.execute(statement, number)
        except DatalogError as error:
            print(f'ERROR line {number}: {error}')


if __name__ == '__main__':
    main()
