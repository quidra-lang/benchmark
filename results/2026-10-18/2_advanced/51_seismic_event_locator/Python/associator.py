"""Candidate association by earliest available pick of each station."""


def associate(picks, window, minimum):
    """Retain pick order and let groups claim their own participating picks."""
    candidates = []
    for index, first in enumerate(picks):
        if first["assigned"]:
            continue
        chosen = []
        seen_stations = set()
        for pick in picks[index:]:
            if pick["sample"] > first["sample"] + window:
                break
            if pick["assigned"] or pick["station"] in seen_stations:
                continue
            chosen.append(pick)
            seen_stations.add(pick["station"])
        if len(chosen) < minimum:
            continue
        for pick in chosen:
            pick["assigned"] = True
        candidates.append({
            "number": len(candidates) + 1,
            "first": first, "picks": chosen, "passes": [],
            "event": None, "rejected": False, "dropped": [],
        })
    return candidates
