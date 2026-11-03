"""Term values, fresh copies, lists, and error terms."""


class Variable:
    __slots__ = ("binding",)

    def __init__(self):
        self.binding = None


class Compound:
    __slots__ = ("name", "args")

    def __init__(self, name, *args):
        self.name = name
        self.args = tuple(args)


class Fault(Exception):
    def __init__(self, term):
        self.term = term


class Ball(Exception):
    def __init__(self, term):
        self.term = term


def dereference(term):
    while isinstance(term, Variable) and term.binding is not None:
        term = term.binding
    return term


def indicator(term):
    term = dereference(term)
    return (term.name, len(term.args)) if isinstance(term, Compound) else (term, 0)


def indicator_term(key):
    return Compound("/", key[0], key[1])


def make_list(elements, tail="[]"):
    for element in reversed(elements):
        tail = Compound(".", element, tail)
    return tail


def list_parts(term):
    elements = []
    term = dereference(term)
    while isinstance(term, Compound) and term.name == "." and len(term.args) == 2:
        elements.append(term.args[0])
        term = dereference(term.args[1])
    return elements, term


def copy_terms(*terms):
    variables = {}

    def copy(term):
        term = dereference(term)
        if isinstance(term, Variable):
            if term not in variables:
                variables[term] = Variable()
            return variables[term]
        if isinstance(term, Compound):
            return Compound(term.name, *(copy(argument) for argument in term.args))
        return term

    return tuple(copy(term) for term in terms)


def copy_term(term):
    return copy_terms(term)[0]


def variables_in(*terms):
    result = []
    stack = list(reversed(terms))
    while stack:
        term = dereference(stack.pop())
        if isinstance(term, Variable):
            result.append(term)
        elif isinstance(term, Compound):
            stack.extend(reversed(term.args))
    return result


def same_kind(left, right):
    left, right = dereference(left), dereference(right)
    if isinstance(left, Variable) or isinstance(right, Variable):
        return True
    if isinstance(left, Compound) and isinstance(right, Compound):
        return left.name == right.name and len(left.args) == len(right.args)
    return type(left) is type(right) and left == right


def type_error(kind, term):
    return Compound("type_error", kind, term)


def domain_error(kind, term):
    return Compound("domain_error", kind, term)
