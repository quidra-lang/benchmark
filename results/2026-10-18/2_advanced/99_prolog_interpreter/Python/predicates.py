"""Exact integer arithmetic and deterministic built-in predicates."""

from terms import (Compound, Fault, Variable, copy_term, dereference, domain_error,
                   indicator, indicator_term, list_parts, make_list, type_error)
from unify import identical


DETERMINISTIC = {
    ("true", 0), ("fail", 0), ("false", 0), ("=", 2), ("\\=", 2), ("==", 2), ("\\==", 2),
    ("var", 1), ("nonvar", 1), ("atom", 1), ("number", 1), ("integer", 1), ("atomic", 1),
    ("compound", 1), ("callable", 1), ("is_list", 1), ("is", 2), ("=:=", 2), ("=\\=", 2),
    ("<", 2), (">", 2), ("=<", 2), (">=", 2), ("functor", 3), ("arg", 3), ("=..", 2),
    ("copy_term", 2), ("atom_length", 2), ("atom_chars", 2), ("write", 1), ("writeq", 1), ("nl", 0),
}


def checked_integer(value):
    if not -2147483648 <= value <= 2147483647:
        raise Fault(Compound("evaluation_error", "int_overflow"))
    return value


def quotient(left, right):
    value = abs(left) // abs(right)
    return -value if (left < 0) != (right < 0) else value


def evaluate(term):
    term = dereference(term)
    if isinstance(term, Variable):
        raise Fault("instantiation_error")
    if isinstance(term, int):
        return term
    if isinstance(term, str):
        raise Fault(type_error("evaluable", indicator_term((term, 0))))
    key = indicator(term)
    supported = {("+", 2), ("-", 2), ("*", 2), ("//", 2), ("mod", 2), ("rem", 2),
                 ("-", 1), ("abs", 1), ("min", 2), ("max", 2)}
    if key not in supported:
        raise Fault(type_error("evaluable", indicator_term(key)))
    values = [evaluate(argument) for argument in term.args]
    name = term.name
    if len(values) == 1:
        result = -values[0] if name == "-" else abs(values[0])
    else:
        left, right = values
        if name in {"//", "mod", "rem"} and right == 0:
            raise Fault(Compound("evaluation_error", "zero_divisor"))
        if name == "+":
            result = left + right
        elif name == "-":
            result = left - right
        elif name == "*":
            result = left * right
        elif name == "//":
            result = quotient(left, right)
        elif name == "mod":
            result = left % right
        elif name == "rem":
            result = left - right * quotient(left, right)
        elif name == "min":
            result = min(left, right)
        else:
            result = max(left, right)
    return checked_integer(result)


def require_integer(term):
    term = dereference(term)
    if isinstance(term, Variable):
        raise Fault("instantiation_error")
    if not isinstance(term, int):
        raise Fault(type_error("integer", term))
    return term


def require_atom(term):
    term = dereference(term)
    if isinstance(term, Variable):
        raise Fault("instantiation_error")
    if not isinstance(term, str):
        raise Fault(type_error("atom", term))
    return term


def require_list(term):
    elements, tail = list_parts(term)
    if isinstance(tail, Variable):
        raise Fault("instantiation_error")
    if tail != "[]":
        raise Fault(type_error("list", term))
    return elements


def execute(goal, trail, output):
    name, arity = indicator(goal)
    args = [dereference(argument) for argument in goal.args] if isinstance(goal, Compound) else []
    if name == "true":
        return True
    if name in {"fail", "false"}:
        return False
    if name == "=":
        return trail.unify(*args)
    if name == "\\=":
        mark = trail.mark()
        result = trail.unify(*args)
        trail.undo(mark)
        return not result
    if name in {"==", "\\=="}:
        result = identical(*args)
        return result if name == "==" else not result
    if name in {"var", "nonvar", "atom", "number", "integer", "atomic", "compound", "callable", "is_list"}:
        term = args[0]
        if name == "var":
            return isinstance(term, Variable)
        if name == "nonvar":
            return not isinstance(term, Variable)
        if name == "atom":
            return isinstance(term, str)
        if name in {"number", "integer"}:
            return isinstance(term, int)
        if name == "atomic":
            return isinstance(term, (str, int))
        if name == "compound":
            return isinstance(term, Compound)
        if name == "callable":
            return isinstance(term, (str, Compound))
        return list_parts(term)[1] == "[]"
    if name == "is":
        return trail.unify(args[0], evaluate(args[1]))
    if name in {"=:=", "=\\=", "<", ">", "=<", ">="}:
        left = evaluate(args[0])
        right = evaluate(args[1])
        return {"=:=": left == right, "=\\=": left != right, "<": left < right,
                ">": left > right, "=<": left <= right, ">=": left >= right}[name]
    if name == "functor":
        term, functor, count = args
        if not isinstance(term, Variable):
            if isinstance(term, Compound):
                return trail.unify(functor, term.name) and trail.unify(count, len(term.args))
            return trail.unify(functor, term) and trail.unify(count, 0)
        if isinstance(functor, Variable) or isinstance(count, Variable):
            raise Fault("instantiation_error")
        if isinstance(functor, Compound):
            raise Fault(type_error("atomic", functor))
        if not isinstance(count, int):
            raise Fault(type_error("integer", count))
        if count < 0:
            raise Fault(domain_error("not_less_than_zero", count))
        if count > 255:
            raise Fault(Compound("representation_error", "max_arity"))
        if count == 0:
            return trail.unify(term, functor)
        if isinstance(functor, int):
            raise Fault(type_error("atom", functor))
        return trail.unify(term, Compound(functor, *(Variable() for _ in range(count))))
    if name == "arg":
        number, term, value = args
        if isinstance(number, Variable) or isinstance(term, Variable):
            raise Fault("instantiation_error")
        if not isinstance(number, int):
            raise Fault(type_error("integer", number))
        if not isinstance(term, Compound):
            raise Fault(type_error("compound", term))
        return 1 <= number <= len(term.args) and trail.unify(term.args[number - 1], value)
    if name == "=..":
        term, sequence = args
        if isinstance(term, Compound):
            return trail.unify(make_list([term.name, *term.args]), sequence)
        if not isinstance(term, Variable):
            return trail.unify(make_list([term]), sequence)
        elements = require_list(sequence)
        if not elements:
            raise Fault(domain_error("non_empty_list", "[]"))
        head = dereference(elements[0])
        if isinstance(head, Variable):
            raise Fault("instantiation_error")
        if len(elements) == 1:
            if isinstance(head, Compound):
                raise Fault(type_error("atomic", head))
            return trail.unify(term, head)
        if not isinstance(head, str):
            raise Fault(type_error("atom", head))
        if len(elements) > 256:
            raise Fault(Compound("representation_error", "max_arity"))
        return trail.unify(term, Compound(head, *elements[1:]))
    if name == "copy_term":
        return trail.unify(copy_term(args[0]), args[1])
    if name == "atom_length":
        atom = require_atom(args[0])
        if not isinstance(args[1], (Variable, int)):
            raise Fault(type_error("integer", args[1]))
        return trail.unify(len(atom), args[1])
    if name == "atom_chars":
        atom, sequence = args
        if not isinstance(atom, Variable):
            atom = require_atom(atom)
            return trail.unify(sequence, make_list(list(atom)))
        elements = require_list(sequence)
        characters = []
        for element in elements:
            character = dereference(element)
            if isinstance(character, Variable):
                raise Fault("instantiation_error")
            if not isinstance(character, str) or len(character) != 1:
                raise Fault(type_error("character", character))
            characters.append(character)
        return trail.unify(atom, "".join(characters))
    if name in {"write", "writeq"}:
        output(args[0], name == "writeq")
        return True
    if name == "nl":
        output(None, False)
        return True
