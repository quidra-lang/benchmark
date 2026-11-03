"""Script blocks, expanded time actions, process state and cut balances."""

from pathlib import Path


def parse_action(words):
    return (words[0], *(
        int(value) if words[0] == "TRANSFER" and index == 2 else value
        for index, value in enumerate(words[1:], 1)
    ))


def read_scripts(path="input/programs.txt"):
    blocks = {}
    current = None
    for line in Path(path).read_text(encoding="ascii").splitlines():
        items = line.split()
        if items[0] == "PROCESS":
            current = {"name": items[1], "balance": int(items[3]),
                       "at": [], "on": []}
        elif items[0] == "END":
            blocks[current["name"]] = current
            current = None
        elif items[0] == "AT":
            first = int(items[1])
            if items[2] == "EVERY":
                current["at"].append((first, int(items[3]),
                                      parse_action(items[4:])))
            else:
                current["at"].append((first, None, parse_action(items[2:])))
        elif items[0] == "ON":
            current["on"].append((items[1], parse_action(items[2:])))
    return blocks


def initialize(names, blocks):
    size = len(names)
    processes = {}
    for name in names:
        block = blocks[name]
        processes[name] = {
            "name": name, "initial": block["balance"],
            "balance": block["balance"], "lamport": 0,
            "vector": [0] * size, "broadcast": [0] * size,
            "at": block["at"], "on": block["on"],
            "events": [], "next_sequence": {
                source: 1 for source in names if source != name
            },
            "reorder": {source: {} for source in names if source != name},
            "holdback": [], "delivered": [], "max_held": 0,
            "in": 0, "out": 0, "refused": 0,
            "min_balance": block["balance"], "types": {},
        }
    return processes


def schedule_actions(names, processes, limit, enqueue):
    """Create items in process order, then AT-line order and increasing time."""
    for name in names:
        for start, period, action in processes[name]["at"]:
            if period is None:
                if start <= limit:
                    enqueue(start, name, "action", action)
            else:
                for time in range(start, limit + 1, period):
                    enqueue(time, name, "action", action)


def reaction_actions(process, tag):
    return [action for expected, action in process["on"] if expected == tag]


def balance_at_cut(process, count):
    if count == 0:
        return process["initial"]
    return process["events"][count - 1]["balance"]


def held_count(process):
    return (sum(len(buffer) for buffer in process["reorder"].values())
            + len(process["holdback"]))
