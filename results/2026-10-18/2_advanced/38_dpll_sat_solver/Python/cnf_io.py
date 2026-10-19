"""DIMACS CNF parsing and fixed-width model v-line rendering."""

from pathlib import Path
import re


NUMBER = re.compile(r"(?:0|[1-9][0-9]*)\Z")
LITERAL = re.compile(r"(?:0|-?[1-9][0-9]*)\Z")


def valid_number(text):
    return len(text) <= 6 and NUMBER.fullmatch(text) is not None


def valid_literal(text):
    number = text[1:] if text.startswith("-") else text
    return len(number) <= 6 and LITERAL.fullmatch(text) is not None


def read_dimacs(name):
    """Return (variable count, ordered clauses) or raise ValueError(reason)."""
    lines = Path("input", name).read_text(encoding="ascii").splitlines()
    header = None
    clauses = []
    partial = []
    for lineno, raw in enumerate(lines, 1):
        if raw.startswith("c") or not raw.split():
            continue
        words = raw.split()
        if words[0] == "p":
            if header is not None:
                raise ValueError(f"duplicate header at line {lineno}")
            if (len(words) != 4 or words[1] != "cnf"
                    or not valid_number(words[2]) or not valid_number(words[3])):
                raise ValueError(f"bad header at line {lineno}")
            header = (int(words[2]), int(words[3]))
            continue
        if header is None:
            raise ValueError("missing header")
        for word in words:
            if not valid_literal(word):
                raise ValueError(f"bad token {word} at line {lineno}")
            value = int(word)
            if abs(value) > header[0]:
                raise ValueError(f"literal out of range {word} at line {lineno}")
            if value:
                partial.append(value)
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
    """Groups of ten signed literals, including a final zero terminator."""
    tokens = [
        str(variable if assignment[variable] else -variable)
        for variable in range(1, len(assignment))
    ] + ["0"]
    return [
        "v " + " ".join(tokens[i:i + 10])
        for i in range(0, len(tokens), 10)
    ]
