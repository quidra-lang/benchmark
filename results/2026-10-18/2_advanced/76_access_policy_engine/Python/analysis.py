"""Canonical domain points, day ranges, blockers and conflict winners."""

from itertools import product


def points(domains):
    for values in product(*(values for _, values in domains)):
        yield dict(zip((name for name, _ in domains), values))


def day_notation(days):
    ordered = sorted(days)
    first = last = ordered[0]
    runs = []
    for day in ordered[1:]:
        if day != last + 1:
            runs.append(f"{first}-{last}")
            first = day
        last = day
    runs.append(f"{first}-{last}")
    return ",".join(runs)


def blocker(rule, standalone):
    for earlier in rule.parent.children:
        if earlier is rule:
            break
        if standalone[earlier.identifier] != "NOT_APPLICABLE":
            return earlier.identifier
    return None


def conflict_winner(policy, earlier, later):
    if policy.behavior == "first-applicable":
        return earlier.identifier
    effect = "DENY" if policy.behavior in ("deny-overrides", "permit-unless-deny") else "PERMIT"
    return earlier.identifier if earlier.behavior == effect else later.identifier
