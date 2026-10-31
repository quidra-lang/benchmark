"""Ordered indirect/direct left-recursion elimination and prefix factoring."""

from grammar_parser import format_alternative, format_production, is_nonterminal


def clone_grammar(grammar):
    return {
        "order": list(grammar["order"]),
        "rules": {name: list(alternatives)
                  for name, alternatives in grammar["rules"].items()},
        "start": grammar["start"],
    }


def fresh_name(symbol, rules):
    proposed = symbol[:-1] + "'" + ">"
    while proposed in rules:
        proposed = proposed[:-1] + "'" + ">"
    return proposed


def leading_reaches(rules, source, target):
    stack = [source]
    discovered = {source}
    while stack:
        current = stack.pop(0)
        for symbols in rules.get(current, []):
            if not symbols or not is_nonterminal(symbols[0]):
                continue
            neighbor = symbols[0]
            if neighbor == target:
                return True
            if neighbor not in discovered:
                discovered.add(neighbor)
                stack.append(neighbor)
    return False


def deduplicate(alternatives):
    seen = set()
    result = []
    for alternative in alternatives:
        if alternative not in seen:
            seen.add(alternative)
            result.append(alternative)
    return result


def eliminate_left_recursion(grammar):
    """Process only original nonterminals in original relative order."""
    g = clone_grammar(grammar)
    initial = list(g["order"])
    log = []
    for i, lhs in enumerate(initial):
        for earlier in initial[:i]:
            current = g["rules"][lhs]
            if (not any(row and row[0] == earlier for row in current)
                    or not leading_reaches(g["rules"], earlier, lhs)):
                continue
            replacements = []
            for row in current:
                if row and row[0] == earlier:
                    for source in g["rules"][earlier]:
                        replacements.append(source + row[1:])
                else:
                    replacements.append(row)
            g["rules"][lhs] = deduplicate(replacements)
            log.append(f"substitute {earlier} into {lhs}")
        source = g["rules"][lhs]
        direct_cycle = (lhs,)
        without_cycle = []
        for row in source:
            if row == direct_cycle:
                log.append(
                    "remove cycle " + format_production(lhs, row)
                )
            else:
                without_cycle.append(row)
        recursive = [row[1:] for row in without_cycle
                     if row and row[0] == lhs]
        if not recursive:
            g["rules"][lhs] = without_cycle
            continue
        nonrecursive = [row for row in without_cycle
                        if not row or row[0] != lhs]
        created = fresh_name(lhs, g["rules"])
        g["rules"][lhs] = [row + (created,) for row in nonrecursive]
        g["rules"][created] = [
            row + (created,) for row in recursive
        ] + [()]
        g["order"].insert(g["order"].index(lhs) + 1, created)
        log.append(
            f"eliminate left recursion in {lhs} with {created}"
        )
    return g, log


def longest_common_prefix(rows):
    if not rows:
        return ()
    limit = min(len(row) for row in rows)
    position = 0
    while position < limit and all(
            row[position] == rows[0][position] for row in rows):
        position += 1
    return rows[0][:position]


def left_factor(grammar):
    """Keep the earliest member at the original position of each prefix group."""
    g = clone_grammar(grammar)
    log = []
    position = 0
    while position < len(g["order"]):
        lhs = g["order"][position]
        current = g["rules"][lhs]
        insertions = []
        index = 0
        while index < len(current):
            row = current[index]
            if not row:
                index += 1
                continue
            group = [
                i for i, other in enumerate(current)
                if other and other[0] == row[0]
            ]
            if len(group) == 1:
                index += 1
                continue
            prefix = longest_common_prefix([current[i] for i in group])
            created = fresh_name(lhs, g["rules"])
            suffixes = [current[i][len(prefix):] for i in group]
            g["rules"][created] = suffixes
            new_alternatives = []
            for i, alternative in enumerate(current):
                if i == group[0]:
                    new_alternatives.append(prefix + (created,))
                elif i not in group:
                    new_alternatives.append(alternative)
            g["rules"][lhs] = current = new_alternatives
            insertions.append(created)
            log.append(
                f"left factor {lhs} on {format_alternative(prefix)} "
                f"with {created}"
            )
            index = group[0] + 1
        g["order"][position + 1:position + 1] = insertions
        position += 1
    return g, log
