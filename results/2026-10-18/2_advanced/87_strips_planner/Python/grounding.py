"""Ground typed schemas, filter static conditions, and close relaxed reachability."""

from collections import namedtuple
from itertools import product
from types import SimpleNamespace

from pddl_parser import Atom


Action = namedtuple("Action", "number source arguments cost pre neg add delete")


def subtype(parents, actual, expected):
    while actual is not None:
        if actual == expected:
            return True
        actual = parents[actual]
    return False


def predicate_classes(domain):
    fluent = {atom.predicate for action in domain.actions for _, atom in action.effects}
    return fluent, set(domain.predicates) - fluent


def substitute(atom, assignment):
    return Atom(atom.predicate, tuple(assignment[term] for term in atom.terms))


def ground(domain, problem):
    objects_by_type = {kind: tuple(name for name, actual in problem.objects.items()
                                   if subtype(domain.parents, actual, kind)) for kind in domain.type_order}
    initial_atoms = set(problem.initial)
    candidates, statistics = [], {}
    for schema in domain.actions:
        choices = [objects_by_type[kind] for _, kind in schema.parameters]
        assignments = 1
        for choice in choices:
            assignments *= len(choice)
        statistics[schema.name] = [assignments, 0, 0]
        for arguments in product(*choices):
            binding = dict(zip((name for name, _ in schema.parameters), arguments))
            positive, negative = set(), set()
            for sign, atom in schema.condition:
                bound = substitute(atom, binding)
                if bound.predicate == "=":
                    truth = bound.terms[0] == bound.terms[1]
                elif bound.predicate in domain.static:
                    truth = bound in initial_atoms
                else:
                    (positive if sign else negative).add(bound)
                    continue
                if truth != sign:
                    break
            else:
                adds = {substitute(atom, binding) for sign, atom in schema.effects if sign}
                deletes = {substitute(atom, binding) for sign, atom in schema.effects if not sign} - adds
                candidates.append(SimpleNamespace(source=schema, arguments=arguments, cost=schema.cost,
                                                  pre=positive, neg=negative, add=adds, delete=deletes))
                statistics[schema.name][1] += 1
    reachable = {atom for atom in problem.initial if atom.predicate in domain.fluent}
    accepted = set()
    while True:
        changed = False
        for number, candidate in enumerate(candidates):
            if number not in accepted and candidate.pre <= reachable:
                accepted.add(number)
                reachable.update(candidate.add)
                statistics[candidate.source.name][2] += 1
                changed = True
        if not changed:
            break
    predicate_order = {name: index for index, name in enumerate(domain.predicates)}
    object_order = {name: index for index, name in enumerate(problem.objects)}
    facts = sorted(reachable, key=lambda atom: (predicate_order[atom.predicate],
                                               tuple(object_order[name] for name in atom.terms)))
    fact_numbers = {atom: number for number, atom in enumerate(facts)}
    actions = []
    for number, candidate in enumerate(candidates):
        if number in accepted:
            mapped = [frozenset(fact_numbers[atom] for atom in values if atom in fact_numbers)
                      for values in (candidate.pre, candidate.neg, candidate.add, candidate.delete)]
            actions.append(Action(len(actions), candidate.source, candidate.arguments, candidate.cost, *mapped))
    initial = frozenset(fact_numbers[atom] for atom in problem.initial if atom.predicate in domain.fluent)
    goal, unreachable = set(), []
    for atom in problem.goals:
        if atom in fact_numbers:
            goal.add(fact_numbers[atom])
        elif atom.predicate not in domain.static or atom not in initial_atoms:
            unreachable.append(atom)
    return SimpleNamespace(name=problem.name, source=problem, objects_by_type=objects_by_type,
                           statistics=statistics, candidate_count=len(candidates), facts=facts, actions=actions,
                           initial=initial, goal=frozenset(goal), unreachable=unreachable,
                           static_count=sum(atom.predicate in domain.static for atom in problem.initial),
                           action_numbers={(action.source.name, action.arguments): action.number for action in actions})
