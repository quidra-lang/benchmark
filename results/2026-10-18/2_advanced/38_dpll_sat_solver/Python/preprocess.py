"""Exact ordered normalization, units, subsumption, and pure-literal elimination."""

from collections import Counter


def preprocess(variables, original, use_pure):
    working = []
    records = {kind: [] for kind in ("tautology", "unit", "subsumed", "pure")}
    counts = {
        "tautologies": 0, "duplicate_literals": 0, "unit_fixed": 0,
        "unit_removed": 0, "subsumed": 0, "pure_fixed": 0, "pure_removed": 0,
    }
    fixed = {}

    for number, original_clause in enumerate(original, 1):
        seen = set(original_clause)
        if any(-literal in seen for literal in original_clause):
            counts["tautologies"] += 1
            records["tautology"].append(number)
            continue
        reduced = []
        seen.clear()
        for literal in original_clause:
            if literal in seen:
                counts["duplicate_literals"] += 1
            else:
                seen.add(literal)
                reduced.append(literal)
        working.append((number, reduced))

    empty_clause = None
    while True:
        empty = next((number for number, clause in working if not clause), None)
        if empty is not None:
            empty_clause = empty
            break
        unit = next((clause[0] for _, clause in working if len(clause) == 1), None)
        if unit is None:
            break
        fixed[abs(unit)] = unit > 0
        counts["unit_fixed"] += 1
        surviving = []
        for number, clause in working:
            if unit in clause:
                records["unit"].append(number)
                counts["unit_removed"] += 1
            else:
                surviving.append((number, [lit for lit in clause if lit != -unit]))
        working = surviving

    if empty_clause is None:
        before = working
        removed = set()
        for index_b, (_, b) in enumerate(before):
            b_set = set(b)
            for index_a, (_, a) in enumerate(before):
                if index_a == index_b:
                    continue
                if set(a).issubset(b_set) and (
                    len(a) < len(b) or index_a < index_b
                ):
                    removed.add(index_b)
                    break
        working = [pair for i, pair in enumerate(before) if i not in removed]
        records["subsumed"] = [before[i][0] for i in sorted(removed)]
        counts["subsumed"] = len(removed)

        if use_pure:
            while True:
                present = {lit for _, clause in working for lit in clause}
                pure_literals = {lit for lit in present if -lit not in present}
                if not pure_literals:
                    break
                for literal in pure_literals:
                    fixed[abs(literal)] = literal > 0
                counts["pure_fixed"] += len(pure_literals)
                remaining = []
                for number, clause in working:
                    if any(literal in pure_literals for literal in clause):
                        records["pure"].append(number)
                        counts["pure_removed"] += 1
                    else:
                        remaining.append((number, clause))
                working = remaining

    counts["removed"] = sum(
        counts[key] for key in (
            "tautologies", "unit_removed", "subsumed", "pure_removed"
        )
    )
    for entries in records.values():
        entries.sort()
    return {
        "clauses": [clause for _, clause in working],
        "numbered_clauses": working,
        "fixed": fixed,
        "active": [v for v in range(1, variables + 1) if v not in fixed],
        "counts": counts,
        "records": records,
        "empty_clause": empty_clause,
        "pure": use_pure,
    }
