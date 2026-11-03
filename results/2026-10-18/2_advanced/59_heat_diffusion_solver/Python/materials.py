"""Material input and the specified heat-capacity and conductance formulas."""

from pathlib import Path


class Material:
    def __init__(self, code, name, conductivity, density, specific_heat):
        self.code = code
        self.name = name
        self.k = conductivity
        self.rho = density
        self.cp = specific_heat


def read_materials(path="input/materials.txt"):
    result = []
    with Path(path).open(encoding="ascii") as source:
        for line in source:
            code, name, conductivity, density, specific_heat = line.split()
            result.append(Material(
                code, name, float(conductivity), float(density), float(specific_heat)
            ))
    return result


def heat_capacity(material, dx, thickness):
    return material.rho * material.cp * dx * dx * thickness


def interior_conductance(first, second, thickness):
    return 2 * first * second / (first + second) * thickness


def fixed_conductance(conductivity, thickness):
    return 2 * conductivity * thickness


def convective_conductance(conductivity, coefficient, dx, thickness):
    return 1 / (1 / (coefficient * dx * thickness) + 1 / (2 * conductivity * thickness))
