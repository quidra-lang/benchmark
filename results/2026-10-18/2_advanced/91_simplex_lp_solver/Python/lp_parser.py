"""Read physical LF records and perform the complete syntax pass."""

import re
from pathlib import Path
from types import SimpleNamespace

from rational import Fraction, read_number


def is_name(word):
    return (re.fullmatch(r"[a-z][a-z0-9_]*", word) is not None
            and word not in {"bounds", "integer", "binary", "free", "inf"})


def expression(words):
    terms = []
    position = 0
    sign = 1
    if words and words[0] == "-":
        sign = -1
        position = 1
    while position < len(words):
        coefficient = read_number(words[position])
        if coefficient is not None:
            if position + 1 == len(words) or not is_name(words[position + 1]):
                return None
            name = words[position + 1]
            position += 2
        elif is_name(words[position]):
            coefficient = Fraction(1)
            name = words[position]
            position += 1
        else:
            return None
        terms.append((name, sign * coefficient))
        if position == len(words):
            return terms
        if words[position] not in {"+", "-"}:
            return None
        sign = 1 if words[position] == "+" else -1
        position += 1
    return None


def named_expression(words):
    if len(words) < 2 or not words[0].endswith(":"):
        return None
    name = words[0][:-1]
    terms = expression(words[1:])
    return (name, terms) if is_name(name) and terms is not None else None


def constraint(words, line):
    if len(words) < 4 or words[-2] not in {"<=", ">=", "="}:
        return None
    rhs = read_number(words[-1], True)
    named = named_expression(words[:-2])
    if rhs is None or named is None:
        return None
    return SimpleNamespace(line=line, name=named[0], terms=named[1],
                           comparison=words[-2], rhs=rhs)


def bound(words, line):
    if len(words) == 2 and is_name(words[0]) and words[1] == "free":
        return (line, words[0], "both", None, None)
    if len(words) == 3 and is_name(words[0]):
        name, operator, word = words
        value = read_number(word, True)
        if operator == ">=" and (value is not None or word == "-inf"):
            return (line, name, "lower", value, None)
        if operator == "<=" and (value is not None or word == "inf"):
            return (line, name, "upper", None, value)
        if operator == "=" and value is not None:
            return (line, name, "both", value, value)
    if len(words) == 5 and words[1] == words[3] == "<=" and is_name(words[2]):
        lower = read_number(words[0], True)
        upper = read_number(words[4], True)
        if ((lower is not None or words[0] == "-inf")
                and (upper is not None or words[4] == "inf")):
            return (line, words[2], "both", lower, upper)
    return None


def parse_block(name, body, end_line):
    result = SimpleNamespace(name=name, error=None, direction=None, objective=None,
                             constraints=[], bounds=[], integers=[], binaries=[])
    state = "A"
    for line, text in body:
        words = text.split(" ")
        accepted = False
        if state == "A" and text in {"maximize", "minimize"}:
            result.direction = text
            state, accepted = "B", True
        elif state == "B":
            named = named_expression(words)
            if named is not None:
                result.objective = named[1]
                state, accepted = "C", True
        elif state == "C" and text == "subject to":
            state, accepted = "D", True
        elif state in {"D", "E"}:
            if state == "E" and text in {"bounds", "integer", "binary"}:
                state = {"bounds": "F", "integer": "G", "binary": "H"}[text]
                accepted = True
            else:
                item = constraint(words, line)
                if item is not None:
                    result.constraints.append(item)
                    state, accepted = "E", True
        elif state == "F":
            if text in {"integer", "binary"}:
                state = "G" if text == "integer" else "H"
                accepted = True
            else:
                item = bound(words, line)
                if item is not None:
                    result.bounds.append(item)
                    accepted = True
        elif state in {"G", "H"}:
            if state == "G" and text == "binary":
                state, accepted = "H", True
            elif all(is_name(word) for word in words):
                declarations = result.integers if state == "G" else result.binaries
                declarations.append((line, words))
                accepted = True
        if not accepted:
            result.error = (line, "syntax error")
            return result
    if state in {"A", "B", "C", "D"}:
        result.error = (end_line, "syntax error")
    return result


def read_models():
    records = Path("input/models.lp").read_bytes().decode("ascii").split("\n")
    models = []
    name = None
    body = []
    for line, text in enumerate(records, 1):
        if not text or text.startswith("#"):
            continue
        if name is None:
            name = text.split(" ")[1]
            body = []
        elif text == "end":
            models.append(parse_block(name, body, line))
            name = None
        else:
            body.append((line, text))
    return models


def read_settings():
    lines = Path("input/params.txt").read_bytes().decode("ascii").split("\n")
    level = int(lines[0].split(" ")[1])
    limit = int(lines[1].split(" ")[1])
    logs, limits = {}, {}
    for text in lines[2:]:
        if text:
            kind, name, value = text.split(" ")
            (logs if kind == "log" else limits)[name] = int(value)
    return SimpleNamespace(level=level, limit=limit, logs=logs, limits=limits)
