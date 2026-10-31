"""BNF tokenizer, line validation and grammar parsing with diagnostic columns."""

from pathlib import Path
import re


NT_RE = re.compile(r"<[A-Za-z][A-Za-z0-9_]*>")
WORD_RE = re.compile(r"[A-Za-z][A-Za-z0-9_]*")


def is_nonterminal(symbol):
    return symbol.startswith("<") and symbol.endswith(">")


def lex_line(line):
    tokens = []
    i = 0
    while i < len(line):
        if line[i] == " ":
            i += 1
            continue
        if line[i] == "#":
            break
        start = i
        suffix = line[i:]
        if line[i] == "<":
            match = NT_RE.match(line, i)
            if match is not None:
                kind, value, i = "nonterminal", match.group(), match.end()
            else:
                kind, value, i = "invalid", line[i], i + 1
        elif line[i] == '"':
            j = i + 1
            while j < len(line) and line[j] not in ('"', " "):
                j += 1
            if j > i + 1 and j < len(line) and line[j] == '"':
                kind, value, i = "terminal", line[i + 1:j], j + 1
            else:
                kind, value, i = "invalid", line[i], i + 1
        elif line[i].isalpha():
            match = WORD_RE.match(line, i)
            kind, value, i = "word", match.group(), match.end()
        elif suffix.startswith("::="):
            kind, value, i = "definition", "::=", i + 3
        elif line[i] == "|":
            kind, value, i = "separator", "|", i + 1
        elif line[i] == "%":
            directive = next(
                (name for name in ("empty", "start", "token")
                 if suffix.startswith("%" + name)), None
            )
            if directive is not None:
                kind, value, i = "directive", "%" + directive, i + len(directive) + 1
            else:
                kind, value, i = "invalid", line[i], i + 1
        else:
            kind, value, i = "invalid", line[i], i + 1
        tokens.append({
            "kind": kind, "value": value,
            "start": start + 1, "end": i,
        })
        if kind == "invalid":
            break
    return tokens


def _error(tokens, cursor):
    """First token violating a grammar prefix, or EOF after an incomplete one."""
    if cursor < len(tokens):
        return tokens[cursor]["start"]
    return tokens[-1]["end"] + 1


def _alternative_list(tokens, cursor):
    """Parse symbol alternatives and return (alternatives, bad column)."""
    alternatives = []
    while True:
        if cursor >= len(tokens):
            return None, _error(tokens, cursor)
        first = tokens[cursor]
        if first["value"] == "%empty" and first["kind"] == "directive":
            alternative = ()
            cursor += 1
            if cursor < len(tokens) and tokens[cursor]["kind"] != "separator":
                return None, _error(tokens, cursor)
        elif first["kind"] in ("nonterminal", "terminal", "word"):
            values = []
            while cursor < len(tokens) and tokens[cursor]["kind"] in (
                    "nonterminal", "terminal", "word"):
                values.append(tokens[cursor]["value"])
                cursor += 1
            alternative = tuple(values)
        else:
            return None, _error(tokens, cursor)
        alternatives.append(alternative)
        if cursor >= len(tokens):
            return alternatives, None
        if tokens[cursor]["kind"] != "separator":
            return None, _error(tokens, cursor)
        cursor += 1


def parse_line(tokens):
    """Return (kind, left-hand-side, alternatives-or-words, error column)."""
    if not tokens:
        return "blank", None, None, None
    first = tokens[0]
    if first["kind"] == "nonterminal":
        if len(tokens) < 2:
            return None, None, None, _error(tokens, len(tokens))
        if tokens[1]["kind"] != "definition":
            return None, None, None, _error(tokens, 1)
        alternatives, error = _alternative_list(tokens, 2)
        return "rule", first["value"], alternatives, error
    if first["kind"] == "separator":
        alternatives, error = _alternative_list(tokens, 1)
        return "continuation", None, alternatives, error
    if first["value"] == "%start" and first["kind"] == "directive":
        if len(tokens) < 2:
            return None, None, None, _error(tokens, len(tokens))
        if tokens[1]["kind"] != "nonterminal":
            return None, None, None, _error(tokens, 1)
        if len(tokens) > 2:
            return None, None, None, _error(tokens, 2)
        return "start", tokens[1]["value"], None, None
    if first["value"] == "%token" and first["kind"] == "directive":
        if len(tokens) < 2:
            return None, None, None, _error(tokens, len(tokens))
        for i in range(1, len(tokens)):
            if tokens[i]["kind"] != "word":
                return None, None, None, _error(tokens, i)
        return "declaration", None, [t["value"] for t in tokens[1:]], None
    return None, None, None, _error(tokens, 0)


def format_alternative(symbols):
    return " ".join(symbols) if symbols else "%empty"


def format_production(symbol, alternative):
    return symbol + " -> " + format_alternative(alternative)


def parse_grammar(path="input/grammar.bnf"):
    """Parse rules in source order; blank lines preserve continuation attachment."""
    grammar = {
        "order": [], "rules": {}, "start": None,
        "declared": set(), "has_declaration": False,
        "words": {}, "diagnostics": [],
    }
    attachment = None
    for line_number, raw in enumerate(
        Path(path).read_text(encoding="ascii").splitlines(), 1
    ):
        tokens = lex_line(raw)
        kind, symbol, alternatives, error = parse_line(tokens)
        if error is not None:
            grammar["diagnostics"].append(
                f"line {line_number}: syntax error at column {error}"
            )
            attachment = None
            continue
        if kind == "blank":
            continue
        if kind == "rule":
            attachment = symbol
            if symbol not in grammar["rules"]:
                grammar["order"].append(symbol)
                grammar["rules"][symbol] = []
        elif kind == "continuation":
            if attachment is None:
                grammar["diagnostics"].append(
                    f"line {line_number}: continuation without a rule"
                )
                continue
            symbol = attachment
        elif kind == "start":
            attachment = None
            if grammar["start"] is None:
                grammar["start"] = symbol
            else:
                grammar["diagnostics"].append(
                    f"line {line_number}: duplicate %start"
                )
        elif kind == "declaration":
            attachment = None
            grammar["has_declaration"] = True
            grammar["declared"].update(alternatives)

        if kind in ("rule", "continuation"):
            for token in tokens:
                if token["kind"] == "word" and token["value"] not in grammar["words"]:
                    grammar["words"][token["value"]] = line_number
            for alternative in alternatives:
                if alternative in grammar["rules"][symbol]:
                    grammar["diagnostics"].append(
                        f"line {line_number}: duplicate alternative "
                        f"{format_production(symbol, alternative)}"
                    )
                else:
                    grammar["rules"][symbol].append(alternative)
    if grammar["start"] is None:
        grammar["start"] = grammar["order"][0]
    return grammar
