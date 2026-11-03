"""Integer relaxed costs, FF plans, and verified fact landmarks; None is infinity."""

from collections import deque
from functools import cache

from search import applicable


NAMES = ("goalcount", "hmax", "hadd", "ff", "lmcount")


class Heuristics:
    def __init__(self, problem):
        self.actions, self.goal, self.fact_count = problem.actions, problem.goal, len(problem.facts)
        self.achievers = [[] for _ in problem.facts]
        self.consumers = [[] for _ in problem.facts]
        for action in self.actions:
            for fact in action.add:
                self.achievers[fact].append(action.number)
            for fact in action.pre:
                self.consumers[fact].append(action.number)

    @cache
    def relaxed_costs(self, state, maximum):
        costs = [0 if fact in state else None for fact in range(self.fact_count)]
        changed = True
        while changed:
            changed = False
            for action in self.actions:
                values = [costs[fact] for fact in action.pre]
                if any(value is None for value in values):
                    continue
                aggregate = max(values, default=0) if maximum else sum(values)
                value = action.cost + aggregate
                for fact in action.add:
                    if costs[fact] is None or value < costs[fact]:
                        costs[fact] = value
                        changed = True
        return tuple(costs)

    @cache
    def relaxed_plan(self, state):
        costs = self.relaxed_costs(state, False)
        if any(costs[fact] is None for fact in self.goal):
            return None
        chosen, pending = set(), list(self.goal - state)
        while pending:
            fact = pending.pop()
            winner, lowest = None, None
            for number in self.achievers[fact]:
                action = self.actions[number]
                values = [costs[pre] for pre in action.pre]
                if any(value is None for value in values):
                    continue
                cost = action.cost + sum(values)
                if lowest is None or cost < lowest:
                    winner, lowest = number, cost
            if winner not in chosen:
                chosen.add(winner)
                pending.extend(self.actions[winner].pre - state)
        return tuple(sorted(chosen))

    @cache
    def helpful(self, state):
        plan = self.relaxed_plan(state)
        return () if plan is None else tuple(number for number in plan if applicable(self.actions[number], state))

    @cache
    def levels(self, state):
        facts = [0 if fact in state else None for fact in range(self.fact_count)]
        actions = [None] * len(self.actions)
        level = 0
        while True:
            changed = False
            for action in self.actions:
                if actions[action.number] is not None:
                    continue
                if any(facts[fact] is None or facts[fact] > level for fact in action.pre):
                    continue
                actions[action.number] = level
                for fact in action.add:
                    if facts[fact] is None:
                        facts[fact] = level + 1
                        changed = True
            if not changed:
                return tuple(facts), tuple(actions)
            level += 1

    def verified(self, state, excluded_fact):
        remaining = [len(action.pre) for action in self.actions]
        excluded = set(self.achievers[excluded_fact])
        reachable, queue = set(state), deque(state)
        for action in self.actions:
            if not action.pre and action.number not in excluded:
                for fact in action.add - reachable:
                    reachable.add(fact)
                    queue.append(fact)
        while queue:
            fact = queue.popleft()
            for number in self.consumers[fact]:
                if number in excluded:
                    continue
                remaining[number] -= 1
                if remaining[number] == 0:
                    for added in self.actions[number].add - reachable:
                        reachable.add(added)
                        queue.append(added)
        return not self.goal <= reachable

    @cache
    def landmarks(self, state):
        fact_levels, action_levels = self.levels(state)
        if any(fact_levels[fact] is None for fact in self.goal):
            return None
        landmarks, pending, verification = set(self.goal - state), deque(sorted(self.goal - state)), {}
        while pending:
            fact = pending.popleft()
            earliest = [self.actions[number].pre for number in self.achievers[fact]
                        if action_levels[number] == fact_levels[fact] - 1]
            candidates = set(earliest[0])
            for preconditions in earliest[1:]:
                candidates.intersection_update(preconditions)
            for candidate in sorted(candidates - state - landmarks):
                if candidate not in verification:
                    verification[candidate] = self.verified(state, candidate)
                if verification[candidate]:
                    landmarks.add(candidate)
                    pending.append(candidate)
        return frozenset(landmarks)

    @cache
    def value(self, name, state):
        if name == "none":
            return 0
        if name == "goalcount":
            return len(self.goal - state)
        if name in ("hmax", "hadd"):
            costs = self.relaxed_costs(state, name == "hmax")
            values = [costs[fact] for fact in self.goal]
            if any(value is None for value in values):
                return None
            return max(values, default=0) if name == "hmax" else sum(values)
        if name == "ff":
            plan = self.relaxed_plan(state)
            return None if plan is None else sum(self.actions[number].cost for number in plan)
        landmarks = self.landmarks(state)
        return None if landmarks is None else len(landmarks)

    def values(self, state):
        return {name: self.value(name, state) for name in NAMES}
