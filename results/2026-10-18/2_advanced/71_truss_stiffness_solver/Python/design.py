"""Stress, Euler buckling and slenderness checks for catalogue selection."""

from math import sqrt


PI = 3.141592653589793


def buckling(properties, geometry, inertia=None):
    inertia = properties.inertia if inertia is None else inertia
    return PI * PI * properties.young * inertia / (geometry.length * geometry.length)


def utilization(force, properties, geometry, section=None):
    area = properties.area if section is None else section.area
    inertia = properties.inertia if section is None else section.inertia
    return max(abs(force / area) / properties.yield_stress,
               max(0, -force) / buckling(properties, geometry, inertia))


def slenderness(properties, geometry, section=None):
    area = properties.area if section is None else section.area
    inertia = properties.inertia if section is None else section.inertia
    return geometry.length / sqrt(inertia / area)


def slenderness_limit(number, combinations, limits):
    return limits[0] if any(result.forces[number] < 0 for result in combinations) else limits[1]


def select_section(members, sections, properties, geometry, combinations, limits):
    for number, section in enumerate(sections):
        acceptable = True
        for member in members:
            if slenderness(properties[member], geometry[member], section) > limits[member]:
                acceptable = False
                break
            for result in combinations:
                if utilization(result.forces[member], properties[member], geometry[member], section) > 1:
                    acceptable = False
                    break
            if not acceptable:
                break
        if acceptable:
            return number
    return len(sections) - 1
