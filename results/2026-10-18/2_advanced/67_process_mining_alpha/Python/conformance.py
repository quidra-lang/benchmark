from collections import Counter
from fractions import Fraction
from pathlib import Path


class PetriNet:
    def __init__(self, places, transitions, arcs, initial, final):
        self.places = tuple(places)
        self.transitions = tuple(sorted(transitions))
        self.arcs = set(arcs)
        self.initial = self.places.index(initial)
        self.final = self.places.index(final)
        self.inputs = {}
        self.outputs = {}
        for transition in self.transitions:
            self.inputs[transition] = tuple(index for index, place in enumerate(self.places)
                                            if (place, transition) in self.arcs)
            self.outputs[transition] = tuple(index for index, place in enumerate(self.places)
                                             if (transition, place) in self.arcs)
        self.routes = [tuple(transition for transition in self.transitions
                             if (place, transition) in self.arcs) for place in self.places]
        self.initial_marking = tuple(int(index == self.initial) for index in range(len(self.places)))
        self.final_marking = tuple(int(index == self.final) for index in range(len(self.places)))

    def enabled(self, marking, transition):
        return all(marking[index] >= 1 for index in self.inputs[transition])

    def enabled_transitions(self, marking):
        return tuple(transition for transition in self.transitions if self.enabled(marking, transition))

    def fire(self, marking, transition):
        result = list(marking)
        for index in self.inputs[transition]:
            result[index] -= 1
        for index in self.outputs[transition]:
            result[index] += 1
        return tuple(result)


def read_model():
    places = []
    transitions = []
    arcs = []
    for line in Path("input/model.txt").read_text(encoding="ascii").splitlines():
        kind, *values = line.split(" ")
        if kind == "PLACE":
            places.append(values[0])
        elif kind == "TRANSITION":
            transitions.append(values[0])
        elif kind == "ARC":
            arcs.append(tuple(values))
        elif kind == "INITIAL":
            initial = values[0]
        else:
            final = values[0]
    return PetriNet(places, transitions, arcs, initial, final)


class ReplayTotals:
    def __init__(self, place_count):
        self.missing = 0
        self.remaining = 0
        self.consumed = 0
        self.produced = 0
        self.skipped = 0
        self.place_missing = [0] * place_count
        self.place_remaining = [0] * place_count
        self.deviating = [0] * place_count
        self.waiting = [[] for _ in range(place_count)]
        self.routes = [Counter() for _ in range(place_count)]

    def fitness(self):
        return (Fraction(1, 2) * (1 - Fraction(self.missing, self.consumed))
                + Fraction(1, 2) * (1 - Fraction(self.remaining, self.produced)))
