"""DIMACS CNF validation and ten-literal-wide model output."""

import re
from pathlib import Path


NUMBER_RE = re.compile(r"(?:0|[1-9][0-9]*)\Z")
LITERAL_RE = re.compile(r"(?:0|-?[1-9][0-9]*)\Z")


def valid_number(token):
    return len(token) <= 6 and NUMBER_RE.fullmatch(token) is not None


def valid_literal(token):
    digits = token[1:] if token.startswith("-") else token
    return len(digits) <= 6 and LITERAL_RE.fullmatch(token) is not None


def read_dimacs(filename):
    header = None
    clauses = []
    partial = []
    lines = (Path("input") / filename).read_text(encoding="ascii").splitlines()
    for lineno, line in enumerate(lines, 1):
        if line.startswith("c") or not line.split():
            continue
        tokens = line.split()
        if tokens[0] == "p":
            if header is not None:
                raise ValueError(f"duplicate header at line {lineno}")
            if (len(tokens) != 4 or tokens[1] != "cnf"
                    or not valid_number(tokens[2])
                    or not valid_number(tokens[3])):
                raise ValueError(f"bad header at line {lineno}")
            header = int(tokens[2]), int(tokens[3])
            continue
        if header is None:
            raise ValueError("missing header")
        for token in tokens:
            if not valid_literal(token):
                raise ValueError(f"bad token {token} at line {lineno}")
            literal = int(token)
            if abs(literal) > header[0]:
                raise ValueError(f"literal out of range {token} at line {lineno}")
            if literal:
                partial.append(literal)
            else:
                clauses.append(partial)
                partial = []
    if header is None:
        raise ValueError("missing header")
    if partial:
        raise ValueError("unterminated clause")
    if len(clauses) != header[1]:
        raise ValueError(
            f"clause count mismatch header={header[1]} found={len(clauses)}"
        )
    return header[0], clauses


def model_lines(assignment):
    tokens = [
        str(variable if assignment[variable] else -variable)
        for variable in range(1, len(assignment))
    ]
    tokens.append("0")
    return [
        "v " + " ".join(tokens[start:start + 10])
        for start in range(0, len(tokens), 10)
    ]
