"""Conflict-resolution manoeuvres and deterministic aircraft priority."""

from flight_plans import clone_plan, level_list


def priority_order(first, second):
    """Lower priority: later departure after delay, or lexicographically larger."""
    departure_first = first["departure"] + first["delay"]
    departure_second = second["departure"] + second["delay"]
    if (departure_first, first["callsign"]) > (
            departure_second, second["callsign"]):
        return first["callsign"], second["callsign"]
    return second["callsign"], first["callsign"]


def manoeuvres(max_delay):
    yield "level_up", 10
    yield "level_down", -10
    yield "speed_down", None
    for delay in range(60, max_delay + 1, 60):
        yield f"delay_{delay}", delay


def propose(plan, name, amount, aircraft_types, settings):
    """Return a cumulatively changed plan, or None for infeasible proposals."""
    changed = clone_plan(plan)
    if name in ("level_up", "level_down"):
        changed["offset"] += amount
        levels = level_list(changed)
        if any(level < settings["level_min"] or level > settings["level_max"]
               for level in levels):
            return None
    elif name == "speed_down":
        changed["speed"] = changed["speed"] * 9 // 10
        if changed["speed"] < aircraft_types[changed["type"]]["minimum"]:
            return None
    else:
        changed["delay"] += amount
    return changed
