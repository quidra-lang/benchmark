"""Clause normalization, deterministic unit simplification and pure literals."""


def _fresh_stats():
    return {
        "tautologies": 0, "duplicate_literals": 0,
        "unit_fixed": 0, "unit_removed": 0,
        "subsumed": 0, "pure_fixed": 0, "pure_removed": 0,
        "removed": {"tautology": [], "unit": [], "subsumed": [], "pure": []},
    }


def preprocess(variable_count, original, use_pure):
    """Preserve the original clause numbering and surviving literal order."""
    stats = _fresh_stats()
    clauses = []
    for number, source in enumerate(original, 1):
        literals = set(source)
        if any(-value in literals for value in literals):
            stats["tautologies"] += 1
            stats["removed"]["tautology"].append(number)
            continue
        unique = []
        seen = set()
        for literal in source:
            if literal in seen:
                stats["duplicate_literals"] += 1
            else:
                unique.append(literal)
                seen.add(literal)
        clauses.append((number, unique))
    fixed = {}
    empty = None
    while True:
        if any(not literals for _, literals in clauses):
            empty = next(number for number, literals in clauses if not literals)
            return {
                "clauses": None, "fixed": fixed,
                "stats": stats, "empty": empty,
                "active": [x for x in range(1, variable_count + 1)
                           if x not in fixed],
                "pure": use_pure,
            }
        unit = next((literals[0] for _, literals in clauses
                     if len(literals) == 1), None)
        if unit is None:
            break
        fixed[abs(unit)] = unit > 0
        stats["unit_fixed"] += 1
        rest = []
        for number, literals in clauses:
            if unit in literals:
                stats["unit_removed"] += 1
                stats["removed"]["unit"].append(number)
            else:
                rest.append((number, [value for value in literals
                                      if value != -unit]))
        clauses = rest

    all_sets = [set(literals) for _, literals in clauses]
    subsumed = set()
    for i, (_, larger) in enumerate(clauses):
        for j, (_, smaller) in enumerate(clauses):
            if i == j:
                continue
            if all_sets[j] <= all_sets[i] and (
                    len(smaller) < len(larger) or j < i):
                subsumed.add(i)
                break
    if subsumed:
        stats["removed"]["subsumed"] = [
            clauses[i][0] for i in sorted(subsumed)
        ]
        stats["subsumed"] = len(subsumed)
        clauses = [item for i, item in enumerate(clauses) if i not in subsumed]

    if use_pure:
        while clauses:
            appearances = {literal for _, row in clauses for literal in row}
            pure_literals = {literal for literal in appearances
                             if -literal not in appearances}
            if not pure_literals:
                break
            for literal in pure_literals:
                fixed[abs(literal)] = literal > 0
            stats["pure_fixed"] += len(pure_literals)
            rest = []
            for number, row in clauses:
                if any(value in pure_literals for value in row):
                    stats["pure_removed"] += 1
                    stats["removed"]["pure"].append(number)
                else:
                    rest.append((number, row))
            clauses = rest

    return {
        "clauses": [literals for _, literals in clauses],
        "fixed": fixed, "stats": stats, "empty": empty,
        "active": [x for x in range(1, variable_count + 1)
                   if x not in fixed],
        "pure": use_pure,
    }


def removed_count(data):
    counts = data["stats"]
    return (counts["tautologies"] + counts["unit_removed"]
            + counts["subsumed"] + counts["pure_removed"])
