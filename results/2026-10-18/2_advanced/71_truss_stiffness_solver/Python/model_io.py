"""Read the seven input files while preserving their defined orders."""

import csv
from collections import namedtuple
from pathlib import Path


Node = namedtuple("Node", "identifier x y")
Member = namedtuple("Member", "identifier start end section material group")
Section = namedtuple("Section", "name area inertia")
Material = namedtuple("Material", "name young yield_stress density expansion")
Support = namedtuple("Support", "node fixed prescribed")
LoadCase = namedtuple("LoadCase", "name lines")
Combination = namedtuple("Combination", "name terms")
Model = namedtuple("Model", "nodes members sections materials supports cases combinations settings")


def csv_rows(name):
    with open("input/" + name + ".csv", encoding="ascii", newline="") as source:
        rows = csv.reader(source)
        next(rows)
        return list(rows)


def read_loads(node_index, member_index):
    cases, combinations = [], []
    for line in Path("input/loads.txt").read_text(encoding="ascii").splitlines():
        kind, *values = line.split()
        if kind == "LOADCASE":
            name, loads = values[0], []
        elif kind == "END":
            cases.append(LoadCase(name, loads))
        elif kind == "COMBINATION":
            terms = [(values[index], float(values[index + 1])) for index in range(1, len(values), 2)]
            combinations.append(Combination(values[0], terms))
        elif kind == "FORCE":
            loads.append((kind, node_index[int(values[0])], float(values[1]), float(values[2])))
        elif kind == "TEMPERATURE":
            loads.append((kind, member_index[int(values[0])], float(values[1])))
        else:
            loads.append((kind,))
    return cases, combinations


def read_settings(node_index, member_index):
    settings = {"influence": [], "drawing": []}
    for line in Path("input/params.txt").read_text(encoding="ascii").splitlines():
        kind, *values = line.split()
        if kind == "deck":
            settings[kind] = [node_index[int(value)] for value in values]
        elif kind == "influence":
            settings[kind].append(member_index[int(values[0])])
        elif kind == "vehicle":
            axles = [(int(values[index]), float(values[index + 1])) for index in range(1, len(values), 2)]
            settings[kind] = int(values[0]), axles
        elif kind == "rating":
            settings[kind] = values[0], float(values[1]), float(values[2])
        elif kind == "slenderness":
            settings[kind] = tuple(map(float, values))
        elif kind == "deflection":
            settings[kind] = values[0], int(values[1])
        elif kind == "vibration":
            settings[kind] = values[0], int(values[1]), int(values[2])
        elif kind == "removal":
            settings[kind] = values[0]
        elif kind == "drawing":
            settings[kind].append((values[0], *map(int, values[1:])))
        else:
            settings[kind] = tuple(map(int, values))
    return settings


def read_model():
    nodes = [Node(*map(int, row)) for row in csv_rows("nodes")]
    sections = [Section(row[0], float(row[1]), float(row[2])) for row in csv_rows("sections")]
    materials = [Material(row[0], *map(float, row[1:])) for row in csv_rows("materials")]
    node_index = {node.identifier: index for index, node in enumerate(nodes)}
    section_index = {section.name: index for index, section in enumerate(sections)}
    material_index = {material.name: index for index, material in enumerate(materials)}
    members = [Member(int(row[0]), node_index[int(row[1])], node_index[int(row[2])],
                      section_index[row[3]], material_index[row[4]], row[5]) for row in csv_rows("members")]
    member_index = {member.identifier: index for index, member in enumerate(members)}
    supports = [Support(node_index[int(row[0])], (int(row[1]), int(row[2])),
                        (float(row[3]), float(row[4]))) for row in csv_rows("supports")]
    cases, combinations = read_loads(node_index, member_index)
    settings = read_settings(node_index, member_index)
    return Model(nodes, members, sections, materials, supports, cases, combinations, settings)
