"""In-place nullable/FIRST/FOLLOW fixpoints and sequence FIRST sets."""

from grammar_parser import is_nonterminal


def terminal_order(terms):
    return sorted(x for x in terms if x != "$") + (
        ["$"] if "$" in terms else []
    )


def terminals_of(grammar):
    return set(
        symbol for lhs in grammar["order"]
        for rhs in grammar["rules"][lhs]
        for symbol in rhs if not is_nonterminal(symbol)
    )


def first_sequence(rhs, nullable, first):
    found = set()
    for symbol in rhs:
        if not is_nonterminal(symbol):
            found.add(symbol)
            return found, False
        found.update(first[symbol])
        if not nullable[symbol]:
            return found, False
    return found, True


def analyze_sets(grammar):
    order = grammar["order"]
    rules = grammar["rules"]
    nullable = {name: False for name in order}
    first = {name: set() for name in order}
    follow = {name: set() for name in order}
    follow[grammar["start"]].add("$")
    passes = {}

    count = 0
    while True:
        count += 1
        changed = False
        for lhs in order:
            if nullable[lhs]:
                continue
            for rhs in rules[lhs]:
                if all(is_nonterminal(s) and nullable[s] for s in rhs):
                    nullable[lhs] = True
                    changed = True
                    break
        if not changed:
            break
    passes["nullable"] = count

    count = 0
    while True:
        count += 1
        changed = False
        for lhs in order:
            for rhs in rules[lhs]:
                more, _ = first_sequence(rhs, nullable, first)
                if not more <= first[lhs]:
                    first[lhs].update(more)
                    changed = True
        if not changed:
            break
    passes["first"] = count

    count = 0
    while True:
        count += 1
        changed = False
        for lhs in order:
            for rhs in rules[lhs]:
                for i, symbol in enumerate(rhs):
                    if not is_nonterminal(symbol):
                        continue
                    more, empty = first_sequence(rhs[i + 1:], nullable, first)
                    if empty:
                        more.update(follow[lhs])
                    if not more <= follow[symbol]:
                        follow[symbol].update(more)
                        changed = True
        if not changed:
            break
    passes["follow"] = count
    return {
        "nullable": nullable,
        "first": first,
        "follow": follow,
        "passes": passes,
        "terminals": terminal_order(terminals_of(grammar)),
    }
