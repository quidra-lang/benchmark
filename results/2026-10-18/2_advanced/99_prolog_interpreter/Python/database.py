"""Ordered clause storage and first-argument candidate selection."""

from dataclasses import dataclass

from terms import copy_terms, indicator, same_kind


@dataclass
class Clause:
    head: object
    body: object
    file: str
    line: int

    def copy(self):
        return copy_terms(self.head, self.body)


class Database:
    def __init__(self):
        self.predicates = {}

    def add(self, clause):
        self.predicates.setdefault(indicator(clause.head), []).append(clause)

    def candidates(self, goal):
        key = indicator(goal)
        clauses = self.predicates[key]
        if key[1] == 0:
            return clauses.copy()
        return [clause for clause in clauses if same_kind(goal.args[0], clause.head.args[0])]
