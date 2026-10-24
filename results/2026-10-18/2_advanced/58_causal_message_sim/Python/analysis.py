"""Causal graph and BFS, races, consistent cut enumeration and predicates."""

from collections import Counter, defaultdict, deque
from itertools import product

from clocks import relation
from snapshot import cut_details


def graph_edges(events, copies):
    outgoing = {event["number"]: [] for event in events}
    by_sender = defaultdict(list)
    for copy in copies:
        if copy.get("recv_event") is not None:
            by_sender[copy["send_event"]["number"]].append(copy)
    for event in events:
        neighbors = []
        if event["local_number"] < len(event["process_events"]):
            neighbors.append(event["process_events"][event["local_number"]]["number"])
        for copy in by_sender[event["number"]]:
            neighbors.append(copy["recv_event"]["number"])
        outgoing[event["number"]] = neighbors
    return outgoing


def graph_path(source, target, edges):
    queue = deque([source["number"]])
    parent = {source["number"]: None}
    goal = target["number"]
    while queue and goal not in parent:
        current = queue.popleft()
        for next_number in edges[current]:
            if next_number not in parent:
                parent[next_number] = current
                queue.append(next_number)
    if goal not in parent:
        return None
    result = []
    cursor = goal
    while cursor is not None:
        result.append(cursor)
        cursor = parent[cursor]
    return list(reversed(result))


def range_notation(path):
    if not path:
        return "-"
    segments = []
    first = last = path[0]
    for event in path[1:]:
        if (event["process"] == last["process"]
                and event["local_number"] == last["local_number"] + 1):
            last = event
            continue
        segments.append((first, last))
        first = last = event
    segments.append((first, last))
    result = []
    for a, b in segments:
        if a is b:
            result.append(a["name"])
        else:
            result.append(
                f"{a['process']}.{a['local_number']}-{b['local_number']}"
            )
    return " ".join(result)


def concurrency_statistics(events, names):
    count = len(events)
    ordered = 0
    concurrent = 0
    same_lamport = 0
    inversions = 0
    by_pair = Counter()
    index = {name: i for i, name in enumerate(names)}
    for a_index in range(count):
        a = events[a_index]
        for b in events[a_index + 1:]:
            rel = relation(a["vector"], b["vector"])
            if rel == "||":
                concurrent += 1
                if a["lamport"] == b["lamport"]:
                    same_lamport += 1
                if a["process"] != b["process"]:
                    key = tuple(sorted((a["process"], b["process"]),
                                       key=lambda name: index[name]))
                    by_pair[key] += 1
            else:
                ordered += 1
            if (a["time"] != b["time"] and a["lamport"] != b["lamport"]
                    and (a["time"] - b["time"]) * (a["lamport"] - b["lamport"]) < 0):
                inversions += 1
    return {
        "pairs": count * (count - 1) // 2,
        "ordered": ordered, "concurrent": concurrent,
        "same_lamport": same_lamport, "inversions": inversions,
        "by_pair": by_pair,
    }


def races_and_violations(processes, names):
    races = []
    violations = []
    for name in names:
        delivered = processes[name]["delivered"]
        for a, b in zip(delivered, delivered[1:]):
            if relation(a["send_event"]["vector"],
                        b["send_event"]["vector"]) == "||":
                races.append((name, a, b))
        for index, a in enumerate(delivered):
            for b in delivered[index + 1:]:
                if relation(b["send_event"]["vector"],
                            a["send_event"]["vector"]) == "->":
                    violations.append((name, a, b))
    return races, violations


def consistent_cut(cut, events_by_process, names):
    for i, name in enumerate(names):
        if not cut[i]:
            continue
        event = events_by_process[name][cut[i] - 1]
        if any(event["vector"][j] > cut[j] for j in range(len(names))):
            return False
    return True


def enumerate_cuts(names, processes, time_limit, thresholds):
    """Enumerate every cut in the requested rectangle, then test reachability."""
    limits = [
        sum(event["time"] <= time_limit for event in processes[name]["events"])
        for name in names
    ]
    levels = Counter()
    consistent = set()
    predicate_count = {threshold: 0 for threshold in thresholds}
    initial_total = sum(processes[name]["initial"] for name in names)
    for cut in product(*(range(limit + 1) for limit in limits)):
        if not consistent_cut(cut, {
                name: processes[name]["events"] for name in names
        }, names):
            continue
        consistent.add(cut)
        levels[sum(cut)] += 1
        in_transit = initial_total - sum(
            processes[name]["initial"] if count == 0
            else processes[name]["events"][count - 1]["balance"]
            for name, count in zip(names, cut)
        )
        for threshold in thresholds:
            if in_transit >= threshold:
                predicate_count[threshold] += 1

    # A monotone path avoiding a predicate disproves inevitability.
    zero = (0,) * len(names)
    target = tuple(limits)
    def avoids(threshold):
        frontier = deque([zero])
        visited = {zero}
        while frontier:
            cut = frontier.popleft()
            transit = initial_total - sum(
                processes[name]["initial"] if count == 0
                else processes[name]["events"][count - 1]["balance"]
                for name, count in zip(names, cut)
            )
            if transit >= threshold:
                continue
            if cut == target:
                return True
            for i in range(len(names)):
                if cut[i] == limits[i]:
                    continue
                proposed = list(cut)
                proposed[i] += 1
                following = tuple(proposed)
                if following in consistent and following not in visited:
                    visited.add(following)
                    frontier.append(following)
        return False

    product_size = 1
    for limit in limits:
        product_size *= limit + 1
    return {
        "limits": limits, "product": product_size, "consistent": len(consistent),
        "levels": levels,
        "predicates": {
            threshold: {
                "cuts": predicate_count[threshold],
                "possibly": predicate_count[threshold] > 0,
                "definitely": not avoids(threshold),
            } for threshold in thresholds
        },
    }
