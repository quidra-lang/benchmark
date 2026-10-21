import functools
import re
import sys
from dataclasses import dataclass
from itertools import count
from typing import NamedTuple


VARIABLE = "variable"
NAME = "name"
NUMERAL = "numeral"
SYMBOL = "symbol"
END = "end"
TOKEN_PATTERN = re.compile(
    r"(?P<variable>[a-z][a-z0-9]*)|(?P<name>[A-Z][A-Z0-9_]*)|(?P<numeral>#[0-9]+)"
    r"|(?P<symbol>[\\.()=;])"
)
NAME_PATTERN = re.compile(r"[A-Z][A-Z0-9_]*")
LIMIT_PATTERN = re.compile(r"[0-9]{1,5}")
EXPECTED = {
    VARIABLE: "variable",
    NAME: "macro name",
    ".": "'.'",
    ")": "')'",
    "=": "'='",
    ";": "';'",
}
NORMAL = "NORMAL"
APPLICATIVE = "APPLICATIVE"
CBN = "CBN"
CBV = "CBV"
STRATEGIES = (NORMAL, APPLICATIVE, CBN, CBV)
PREDEFINED = {"S": r"\x y z. x z (y z)", "K": r"\x y. x", "I": r"\x. x"}
RESERVED = {*PREDEFINED, *STRATEGIES}
WORD_COMMANDS = ("unlet", "macros", "steps", "eta", "limit")
TERM_COMMANDS = (
    "let", "expand", "subst", "reduce", "equal", "alpha", "debruijn", "fv", "size", "depth",
    "type", "church", "ski", "skireduce", "kam",
)
MAX_LIMIT = 10000


class CommandError(Exception):
    pass


class NotTypable(Exception):
    pass


@dataclass(frozen=True)
class Var:
    name: str


@dataclass(frozen=True)
class Macro:
    name: str


@dataclass(frozen=True)
class Numeral:
    value: int


@dataclass(frozen=True)
class Lam:
    var: str
    body: "Term"


@dataclass(frozen=True)
class App:
    func: "Term"
    arg: "Term"


@dataclass(frozen=True)
class Const:
    name: str


@dataclass(frozen=True)
class Index:
    value: int


@dataclass(frozen=True)
class DeBruijnLam:
    body: "Term"


type Term = Var | Macro | Numeral | Lam | App | Const | Index | DeBruijnLam


@dataclass(frozen=True)
class Arrow:
    domain: "int | Arrow"
    codomain: "int | Arrow"


class Token(NamedTuple):
    kind: str
    text: str
    column: int


class Step(NamedTuple):
    term: Term
    kind: str


def tokenize(text, first_column, end_column):
    tokens = []
    position = 0
    while position < len(text):
        if text[position] == " ":
            position += 1
            continue
        column = first_column + position
        matched = TOKEN_PATTERN.match(text, position)
        if matched is None:
            raise CommandError(f"column {column}: unexpected character '{text[position]}'")
        kind = matched[0] if matched.lastgroup == SYMBOL else matched.lastgroup
        tokens.append(Token(kind, matched[0], column))
        position = matched.end()
    tokens.append(Token(END, "", end_column))
    return tokens


class Parser:
    def __init__(self, tokens):
        self.tokens = tokens
        self.position = 0

    def peek(self):
        return self.tokens[self.position]

    def advance(self):
        token = self.tokens[self.position]
        self.position += 1
        return token

    def expect(self, kind):
        token = self.peek()
        if token.kind != kind:
            raise CommandError(f"column {token.column}: expected {EXPECTED[kind]}")
        return self.advance()

    def finish(self):
        token = self.peek()
        if token.kind != END:
            raise CommandError(f"column {token.column}: unexpected '{token.text}'")

    def term(self):
        elements = []
        while self.peek().kind in (VARIABLE, NAME, NUMERAL, "("):
            elements.append(self.atom())
        if self.peek().kind == "\\":
            elements.append(self.abstraction())
        if not elements:
            raise CommandError(f"column {self.peek().column}: expected term")
        return apply_all(elements[0], elements[1:])

    def atom(self):
        token = self.advance()
        if token.kind == VARIABLE:
            return Var(token.text)
        if token.kind == NAME:
            return Macro(token.text)
        if token.kind == NUMERAL:
            return Numeral(int(token.text[1:]))
        inner = self.term()
        self.expect(")")
        return inner

    def abstraction(self):
        self.advance()
        names = [self.expect(VARIABLE).text]
        while self.peek().kind == VARIABLE:
            names.append(self.advance().text)
        self.expect(".")
        body = self.term()
        for name in reversed(names):
            body = Lam(name, body)
        return body


def parse_term(text):
    return Parser(tokenize(text, 1, len(text) + 1)).term()


def apply_all(head, args):
    return functools.reduce(App, args, head)


def show(term, at_end=True):
    match term:
        case Var(name) | Macro(name) | Const(name):
            return name
        case Numeral(value):
            return f"#{value}"
        case Index(value):
            return str(value)
        case Lam():
            names = []
            while isinstance(term, Lam):
                names.append(term.var)
                term = term.body
            text = f"\\{' '.join(names)}. {show(term)}"
            return text if at_end else f"({text})"
        case DeBruijnLam(body):
            text = "\\" + show(body)
            return text if at_end else f"({text})"
        case App(func, arg):
            left = f"({show(func)})" if isinstance(func, (Lam, DeBruijnLam)) else show(func, False)
            right = f"({show(arg)})" if isinstance(arg, App) else show(arg, at_end)
            return f"{left} {right}"


def free_vars(term):
    match term:
        case Var(name):
            return {name}
        case Lam(var, body):
            return free_vars(body) - {var}
        case DeBruijnLam(body):
            return free_vars(body)
        case App(func, arg):
            return free_vars(func) | free_vars(arg)
    return set()


def macro_references(term):
    match term:
        case Macro(name):
            return [name]
        case Lam(_, body):
            return macro_references(body)
        case App(func, arg):
            return macro_references(func) + macro_references(arg)
    return []


def numeral_term(value):
    body = Var("x")
    for _ in range(value):
        body = App(Var("f"), body)
    return Lam("f", Lam("x", body))


def substitute(term, name, value):
    match term:
        case Var(var):
            return value if var == name else term
        case App(func, arg):
            return App(substitute(func, name, value), substitute(arg, name, value))
        case Lam(var, body):
            body_free = free_vars(body)
            if var == name or name not in body_free:
                return term
            value_free = free_vars(value)
            if var not in value_free:
                return Lam(var, substitute(body, name, value))
            base = var.rstrip("0123456789")
            suffix = 1
            while f"{base}{suffix}" in value_free or f"{base}{suffix}" in body_free:
                suffix += 1
            fresh = f"{base}{suffix}"
            return Lam(fresh, substitute(substitute(body, var, Var(fresh)), name, value))
    return term


def sequence_name(index):
    letter = chr(ord("a") + index % 26)
    return f"{letter}{index // 26}" if index >= 26 else letter


def fresh_names(excluded):
    return (name for name in map(sequence_name, count()) if name not in excluded)


def to_de_bruijn(term, bound=()):
    match term:
        case Var(name):
            return Index(bound.index(name)) if name in bound else term
        case Lam(var, body):
            return DeBruijnLam(to_de_bruijn(body, (var, *bound)))
        case App(func, arg):
            return App(to_de_bruijn(func, bound), to_de_bruijn(arg, bound))
    return term


def from_de_bruijn(term):
    # Names bound variables in printed order with the name sequence, skipping free names.
    names = fresh_names(free_vars(term))

    def rename(node, bound):
        match node:
            case Index(value):
                return Var(bound[value])
            case DeBruijnLam(body):
                name = next(names)
                return Lam(name, rename(body, (name, *bound)))
            case App(func, arg):
                return App(rename(func, bound), rename(arg, bound))
        return node

    return rename(term, ())


def canonical(term):
    return from_de_bruijn(to_de_bruijn(term))


def alpha_equivalent(first, second):
    return to_de_bruijn(first) == to_de_bruijn(second)


def size(term):
    match term:
        case Lam(_, body):
            return 1 + size(body)
        case App(func, arg):
            return 1 + size(func) + size(arg)
    return 1


def depth(term):
    match term:
        case Lam(_, body):
            return 1 + depth(body)
        case App(func, arg):
            return 1 + max(depth(func), depth(arg))
    return 1


def is_eta_redex(term):
    match term:
        case Lam(var, App(func, Var(name))) if name == var:
            return var not in free_vars(func)
    return False


def one_step(term, strategy, eta):
    match term:
        case App(Lam(var, body), arg) if strategy in (NORMAL, CBN):
            return Step(substitute(body, var, arg), "beta")
        case App(func, arg):
            if found := one_step(func, strategy, eta):
                return Step(App(found.term, arg), found.kind)
            if strategy != CBN and (found := one_step(arg, strategy, eta)):
                return Step(App(func, found.term), found.kind)
            # Only APPLICATIVE and CBV get here with an abstraction in the function part.
            if isinstance(func, Lam) and (strategy == APPLICATIVE or isinstance(arg, (Var, Lam))):
                return Step(substitute(func.body, func.var, arg), "beta")
        case Lam(var, body) if strategy in (NORMAL, APPLICATIVE):
            contractible = eta and is_eta_redex(term)
            if contractible and strategy == NORMAL:
                return Step(body.func, "eta")
            if found := one_step(body, strategy, eta):
                return Step(Lam(var, found.term), found.kind)
            if contractible:
                return Step(body.func, "eta")
    return None


def numeral_value(term):
    if not (isinstance(term, Lam) and isinstance(term.body, Lam)):
        return None
    body = term.body.body
    applications = 0
    while isinstance(body, App) and body.func == Var(term.var):
        body = body.arg
        applications += 1
    return applications if body == Var(term.body.var) else None


def read_church(term):
    value = numeral_value(term)
    if value is not None:
        return str(value)
    match term:
        case Lam(outer, Lam(_, Var(name))) if name == outer:
            return "true"
        case Lam(var, App(App(Var(name), first), second)) if (
            name == var and var not in free_vars(first) | free_vars(second)
        ):
            return f"({read_church(first)}, {read_church(second)})"
    return show(canonical(term))


def to_ski(term):
    match term:
        case Lam(var, body):
            return abstract(var, to_ski(body))
        case App(func, arg):
            return App(to_ski(func), to_ski(arg))
    return term


def abstract(var, term):
    if var not in free_vars(term):
        return App(Const("K"), term)
    if term == Var(var):
        return Const("I")
    if term.arg == Var(var) and var not in free_vars(term.func):
        return term.func
    return App(App(Const("S"), abstract(var, term.func)), abstract(var, term.arg))


def unwind(term):
    args = []
    while isinstance(term, App):
        args.append(term.arg)
        term = term.func
    return term, args[::-1]


def ski_step(term):
    head, args = unwind(term)
    match head:
        case Const("I") if len(args) >= 1:
            return Step(apply_all(args[0], args[1:]), "I")
        case Const("K") if len(args) >= 2:
            return Step(apply_all(args[0], args[2:]), "K")
        case Const("S") if len(args) >= 3:
            first, second, third = args[:3]
            return Step(apply_all(App(App(first, third), App(second, third)), args[3:]), "S")
    for position, arg in enumerate(args):
        if found := ski_step(arg):
            args[position] = found.term
            return Step(apply_all(head, args), found.kind)
    return None


def read_back(code, env, binders=0):
    match code:
        case Index(value) if value >= binders:
            return read_back(*env[value - binders])
        case DeBruijnLam(body):
            return DeBruijnLam(read_back(body, env, binders + 1))
        case App(func, arg):
            return App(read_back(func, env, binders), read_back(arg, env, binders))
    return code


class TypeInference:
    def __init__(self):
        self.bindings = {}
        self.variables = 0

    def fresh(self):
        self.variables += 1
        return self.variables

    def resolve(self, type_):
        while isinstance(type_, int) and type_ in self.bindings:
            type_ = self.bindings[type_]
        return type_

    def occurs(self, variable, type_):
        type_ = self.resolve(type_)
        if isinstance(type_, Arrow):
            return self.occurs(variable, type_.domain) or self.occurs(variable, type_.codomain)
        return type_ == variable

    def unify(self, left, right):
        left = self.resolve(left)
        right = self.resolve(right)
        if isinstance(left, int):
            if left != right:
                if self.occurs(left, right):
                    raise NotTypable
                self.bindings[left] = right
        elif isinstance(right, int):
            self.unify(right, left)
        else:
            self.unify(left.domain, right.domain)
            self.unify(left.codomain, right.codomain)

    def infer(self, term, scope):
        match term:
            case Var(name):
                return scope[name]
            case Lam(var, body):
                parameter = self.fresh()
                return Arrow(parameter, self.infer(body, {**scope, var: parameter}))
            case App(func, arg):
                func_type = self.infer(func, scope)
                result = self.fresh()
                self.unify(func_type, Arrow(self.infer(arg, scope), result))
                return result

    def render(self, type_, names):
        type_ = self.resolve(type_)
        if isinstance(type_, int):
            return names.setdefault(type_, sequence_name(len(names)))
        domain = self.render(type_.domain, names)
        if isinstance(self.resolve(type_.domain), Arrow):
            domain = f"({domain})"
        return f"{domain} -> {self.render(type_.codomain, names)}"


def principal_type(term):
    inference = TypeInference()
    scope = {name: inference.fresh() for name in free_vars(term)}
    try:
        type_ = inference.infer(term, scope)
    except NotTypable:
        return "not typable"
    return inference.render(type_, {})


class Workbench:
    def __init__(self):
        self.macros = {name: parse_term(text) for name, text in PREDEFINED.items()}
        self.show_steps = False
        self.eta = False
        self.limit = MAX_LIMIT

    def execute(self, line):
        name, _, argument = line.partition(" ")
        if name in WORD_COMMANDS:
            getattr(self, f"command_{name}")(argument.split())
        elif name in TERM_COMMANDS:
            parser = Parser(tokenize(argument, len(name) + 2, len(line) + 1))
            getattr(self, f"command_{name}")(parser)
        else:
            raise CommandError(f"unknown command {name}")

    def expand(self, term):
        match term:
            case Macro(name):
                if name not in self.macros:
                    raise CommandError(f"unbound macro {name}")
                return self.expand(self.macros[name])
            case Numeral(value):
                return numeral_term(value)
            case Lam(var, body):
                return Lam(var, self.expand(body))
            case App(func, arg):
                return App(self.expand(func), self.expand(arg))
        return term

    def read_term(self, parser):
        term = parser.term()
        parser.finish()
        return self.expand(term)

    def read_pair(self, parser):
        first = parser.term()
        parser.expect(";")
        second = parser.term()
        parser.finish()
        return self.expand(first), self.expand(second)

    def dependencies(self, name):
        found = set()
        pending = [name]
        while pending:
            body = self.macros.get(pending.pop())
            if body is None:
                continue
            for reference in macro_references(body):
                if reference not in found:
                    found.add(reference)
                    pending.append(reference)
        return found

    def run(self, term, step, show_steps):
        for number in count(1):
            found = step(term)
            if found is None:
                return term, number - 1
            if number > self.limit:
                return None
            term = found.term
            if show_steps:
                print(f"step {number} ({found.kind}): {show(term)}")

    def normalize(self, term, strategy, eta, show_steps=False):
        return self.run(term, lambda current: one_step(current, strategy, eta), show_steps)

    def report(self, outcome, render):
        if outcome is None:
            print(f"no normal form within {self.limit} steps")
        else:
            result, steps = outcome
            print(f"result: {render(result)} (steps: {steps})")

    def command_let(self, parser):
        name = parser.expect(NAME).text
        parser.expect("=")
        body = parser.term()
        parser.finish()
        if name in RESERVED:
            raise CommandError(f"reserved name {name}")
        for reference in macro_references(body):
            if reference == name or name in self.dependencies(reference):
                raise CommandError(f"recursive definition of {name}")
            if reference not in self.macros:
                raise CommandError(f"unbound macro {reference}")
        free = free_vars(body)
        if free:
            raise CommandError(f"free variable {min(free)} in definition of {name}")
        print(f"{'redefined' if name in self.macros else 'defined'} {name}")
        self.macros[name] = body

    def command_unlet(self, words):
        if len(words) != 1 or not NAME_PATTERN.fullmatch(words[0]):
            raise CommandError("bad argument")
        name = words[0]
        if name in RESERVED:
            raise CommandError(f"reserved name {name}")
        if name not in self.macros:
            raise CommandError(f"unbound macro {name}")
        user = min(
            (other for other, body in self.macros.items() if name in macro_references(body)),
            default=None,
        )
        if user is not None:
            raise CommandError(f"{name} is used by {user}")
        del self.macros[name]
        print(f"removed {name}")

    def command_macros(self, words):
        if words:
            raise CommandError("bad argument")
        names = sorted(name for name in self.macros if name not in PREDEFINED)
        for name in names:
            print(f"{name} = {show(self.macros[name])}")
        if not names:
            print("(none)")

    def command_steps(self, words):
        self.show_steps = switch_value(words)

    def command_eta(self, words):
        self.eta = switch_value(words)

    def command_limit(self, words):
        if len(words) != 1 or not LIMIT_PATTERN.fullmatch(words[0]):
            raise CommandError("bad argument")
        limit = int(words[0])
        if not 1 <= limit <= MAX_LIMIT:
            raise CommandError("bad argument")
        self.limit = limit

    def command_expand(self, parser):
        print(show(self.read_term(parser)))

    def command_subst(self, parser):
        name = parser.expect(VARIABLE).text
        parser.expect("=")
        value = parser.term()
        parser.expect(";")
        target = parser.term()
        parser.finish()
        value = self.expand(value)
        print(show(substitute(self.expand(target), name, value)))

    def command_reduce(self, parser):
        strategy = NORMAL
        if parser.peek().kind == NAME and parser.peek().text in STRATEGIES:
            strategy = parser.advance().text
        term = self.read_term(parser)
        outcome = self.normalize(term, strategy, self.eta, self.show_steps)
        self.report(outcome, lambda result: show(canonical(result)))

    def command_equal(self, parser):
        first, second = (self.normalize(term, NORMAL, self.eta) for term in self.read_pair(parser))
        if first is None or second is None:
            print("unknown")
        else:
            print("yes" if alpha_equivalent(first[0], second[0]) else "no")

    def command_alpha(self, parser):
        print("yes" if alpha_equivalent(*self.read_pair(parser)) else "no")

    def command_debruijn(self, parser):
        print(show(to_de_bruijn(self.read_term(parser))))

    def command_fv(self, parser):
        names = sorted(free_vars(self.read_term(parser)))
        print(" ".join(names) if names else "(none)")

    def command_size(self, parser):
        print(size(self.read_term(parser)))

    def command_depth(self, parser):
        print(depth(self.read_term(parser)))

    def command_type(self, parser):
        print(principal_type(self.read_term(parser)))

    def command_church(self, parser):
        outcome = self.normalize(self.read_term(parser), NORMAL, False)
        if outcome is None:
            print(f"no normal form within {self.limit} steps")
        else:
            print(read_church(canonical(outcome[0])))

    def command_ski(self, parser):
        print(show(to_ski(self.read_term(parser))))

    def command_skireduce(self, parser):
        combinator = to_ski(self.read_term(parser))
        self.report(self.run(combinator, ski_step, self.show_steps), show)

    def command_kam(self, parser):
        code = to_de_bruijn(self.read_term(parser))
        env = ()
        stack = []
        for number in count(1):
            if isinstance(code, Var) or isinstance(code, DeBruijnLam) and not stack:
                break
            if number > self.limit:
                print(f"no result within {self.limit} transitions")
                return
            match code:
                case App(func, arg):
                    stack.append((arg, env))
                    code = func
                    kind = "push"
                case DeBruijnLam(body):
                    env = (stack.pop(), *env)
                    code = body
                    kind = "grab"
                case Index(value):
                    code, env = env[value]
                    kind = "access"
            if self.show_steps:
                state = f"[env {len(env)}, stack {len(stack)}]"
                print(f"step {number} ({kind}): {show(code)} {state}")
        arguments = [read_back(*closure) for closure in reversed(stack)]
        result = apply_all(read_back(code, env), arguments)
        print(f"result: {show(from_de_bruijn(result))} (transitions: {number - 1})")


def switch_value(words):
    if len(words) != 1 or words[0] not in ("on", "off"):
        raise CommandError("bad argument")
    return words[0] == "on"


def main():
    workbench = Workbench()
    for line in sys.stdin.read().splitlines():
        if line == "quit":
            break
        if not line or line.startswith("--"):
            continue
        try:
            workbench.execute(line)
        except CommandError as error:
            print(f"error: {error}")


if __name__ == "__main__":
    main()
