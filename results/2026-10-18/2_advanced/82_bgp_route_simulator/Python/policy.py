"""Ordered policy matching, prefix lists, and community editing."""

from pathlib import Path

import topology


NO_EXPORT = (65535, 65281)


def parse_community(text):
    return NO_EXPORT if text == "NO_EXPORT" else tuple(map(int, text.split(":")))


def parse_communities(values):
    return tuple(sorted({parse_community(value) for value in values}))


def community_text(community):
    return "NO_EXPORT" if community == NO_EXPORT else f"{community[0]}:{community[1]}"


def communities_text(communities):
    return ",".join(community_text(value) for value in sorted(communities)) or "-"


def edit_communities(communities, rule):
    edited = set(communities)
    for action, value in rule.actions:
        if action == "ADD":
            edited.add(value)
        elif action == "REMOVE":
            edited.discard(value)
    return tuple(sorted(edited))


class Rule:
    def __init__(self, name, state, owner, direction, target, conditions, actions):
        self.name = name
        self.active = state == "ON"
        self.owner = owner
        self.direction = direction
        self.target = target
        self.conditions = conditions
        self.actions = actions
        self.settings = {action: value for action, value in actions}
        self.hits = 0

    def has(self, action):
        return action in self.settings

    def value(self, action, default):
        return self.settings.get(action, default)


class Policies:
    def __init__(self, lists, rules):
        self.lists = lists
        self.rules = rules
        self.by_name = {rule.name: rule for rule in rules}
        self.by_owner_direction = {}
        for rule in rules:
            self.by_owner_direction.setdefault((rule.owner, rule.direction), []).append(rule)

    def permitted(self, name, prefix):
        for permit, base, low, high in self.lists[name]:
            if low <= prefix[1] <= high and topology.contains(base, prefix[0]):
                return permit
        return False

    def matches(self, rule, owner, link, prefix, path, communities):
        if not rule.active or rule.owner != owner:
            return False
        if rule.target not in ("*", str(link.other(owner)), link.name):
            return False
        for condition, value in rule.conditions:
            if condition == "PREFIX" and not self.permitted(value, prefix):
                return False
            if condition == "CONTAINS" and value not in path:
                return False
            if condition == "ORIGINAS" and (path[-1] if path else owner) != value:
                return False
            if condition == "LENGTH" and not value[0] <= len(path) <= value[1]:
                return False
            if condition == "COMMUNITY" and value not in communities:
                return False
        return True

    def applied(self, direction, owner, link, prefix, path, communities):
        for rule in self.by_owner_direction.get((owner, direction), []):
            if self.matches(rule, owner, link, prefix, path, communities):
                return rule
        return None


def read_policies():
    lists, rules = {}, []
    for line in Path("input/policies.txt").read_text(encoding="ascii").splitlines():
        fields = line.split(" ")
        if fields[0] == "PLIST":
            name, action = fields[1:3]
            prefix = topology.parse_prefix(fields[3])
            bounds = {fields[index]: int(fields[index + 1]) for index in range(4, len(fields), 2)}
            low = bounds.get("GE", prefix[1])
            high = bounds.get("LE", 32 if "GE" in bounds else prefix[1])
            lists.setdefault(name, []).append((action == "PERMIT", prefix, low, high))
            continue
        name, state, owner, direction, target = fields[1:6]
        separator = fields.index("THEN")
        conditions = []
        for index in range(6, separator, 2):
            condition, value = fields[index:index + 2]
            if condition in ("CONTAINS", "ORIGINAS"):
                value = int(value)
            elif condition == "LENGTH":
                value = tuple(map(int, value.split("-")))
            elif condition == "COMMUNITY":
                value = parse_community(value)
            conditions.append((condition, value))
        actions = []
        index = separator + 1
        while index < len(fields):
            action = fields[index]
            index += 1
            value = None
            if action not in ("DENY", "ALLOW"):
                value = fields[index]
                index += 1
                value = parse_community(value) if action in ("ADD", "REMOVE") else int(value)
            actions.append((action, value))
        rules.append(Rule(name, state, int(owner), direction, target, conditions, actions))
    return Policies(lists, rules)
