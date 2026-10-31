"""Mutex planning graphs and the prescribed memoized backward extraction."""

import sys
from collections import namedtuple
from itertools import combinations
from types import SimpleNamespace


Element = namedtuple("Element", "number pre add delete")


def pair(first, second):
    return (first, second) if first < second else (second, first)


def conflict(first, second, mutexes):
    return (bool(first.delete & (second.pre | second.add))
            or bool(second.delete & (first.pre | first.add))
            or any(pair(p, q) in mutexes for p in first.pre for q in second.pre))


class PlanningGraph:
    def __init__(self, actions, initial, goal, limit):
        self.actions, self.goal, self.limit = actions, goal, limit
        self.facts, self.fact_mutexes = [initial], [set()]
        self.elements, self.element_mutexes, self.achievers = [], [], []
        self.memo, self.lines = set(), []
        self.searched, self.memo_hits, self.tried = 0, 0, 0

    def expand(self, level):
        facts, mutexes = self.facts[level], self.fact_mutexes[level]
        elements = [Element(action.number, action.pre, action.add, action.delete) for action in self.actions
                    if action.pre <= facts and not any(pair(p, q) in mutexes for p, q in combinations(action.pre, 2))]
        action_count = len(elements)
        elements.extend(Element(None, frozenset([fact]), frozenset([fact]), frozenset()) for fact in sorted(facts))
        exclusive = {(first, second) for first, second in combinations(range(len(elements)), 2)
                     if conflict(elements[first], elements[second], mutexes)}
        self.lines.append(f"action level {level}: actions={action_count} noops={len(facts)} mutexes={len(exclusive)}")
        achievers = {}
        for index, element in enumerate(elements):
            for fact in element.add:
                achievers.setdefault(fact, []).append(index)
        for producers in achievers.values():
            producers.sort(key=lambda index: (-1 if elements[index].number is None else elements[index].number))
        following = frozenset(achievers)
        following_mutexes = set()
        for first, second in combinations(sorted(following), 2):
            if all(x != y and pair(x, y) in exclusive for x in achievers[first] for y in achievers[second]):
                following_mutexes.add((first, second))
        self.elements.append(elements)
        self.element_mutexes.append(exclusive)
        self.achievers.append(achievers)
        self.facts.append(following)
        self.fact_mutexes.append(following_mutexes)

    def extract(self, level, goals):
        if level == 0:
            return ()
        key = (level, goals)
        if key in self.memo:
            self.memo_hits += 1
            return None
        self.searched += 1
        layers = self.assign(level, goals, 0, ())
        if layers is None:
            self.memo.add(key)
        return layers

    def assign(self, level, goals, position, chosen):
        elements = self.elements[level - 1]
        while position < len(goals) and any(goals[position] in elements[index].add for index in chosen):
            position += 1
        if position == len(goals):
            previous = tuple(sorted({fact for index in chosen for fact in elements[index].pre}))
            layers = self.extract(level - 1, previous)
            if layers is None:
                return None
            layer = tuple(sorted(elements[index].number for index in chosen if elements[index].number is not None))
            return layers + (layer,)
        for index in self.achievers[level - 1][goals[position]]:
            if any(pair(index, other) in self.element_mutexes[level - 1] for other in chosen):
                continue
            self.tried += 1
            layers = self.assign(level, goals, position + 1, chosen + (index,))
            if layers is not None:
                return layers
        return None

    def finish(self, status, layers=()):
        return SimpleNamespace(status=status, plan=tuple(number for layer in layers for number in layer),
                               layers=layers, lines=self.lines, expanded=self.searched,
                               generated=self.tried, memo_hits=self.memo_hits)

    def run(self):
        universe = set(self.facts[0])
        for action in self.actions:
            universe.update(action.pre | action.add | action.delete)
        depth_bound = (self.limit + 1) * (len(universe) + 3) + 100
        sys.setrecursionlimit(max(sys.getrecursionlimit(), depth_bound))
        for level in range(self.limit + 1):
            facts, mutexes = self.facts[level], self.fact_mutexes[level]
            self.lines.append(f"fact level {level}: facts={len(facts)} mutexes={len(mutexes)}")
            possible = self.goal <= facts and not any(pair(p, q) in mutexes for p, q in combinations(self.goal, 2))
            if possible:
                before_search, before_hits = self.searched, self.memo_hits
                layers = self.extract(level, tuple(sorted(self.goal)))
                outcome = "success" if layers is not None else "fail"
                self.lines.append(f"extract level {level}: {outcome} searched={self.searched - before_search} "
                                  f"memo_hits={self.memo_hits - before_hits}")
                if layers is not None:
                    return self.finish("solved", layers)
            elif level and len(facts) == len(self.facts[level - 1]) and len(mutexes) == len(self.fact_mutexes[level - 1]):
                return self.finish("unreachable")
            if level == self.limit:
                return self.finish("level limit")
            self.expand(level)
