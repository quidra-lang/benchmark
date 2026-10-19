"""Member geometry, stiffness assembly, weights and ordered load vectors."""

from collections import namedtuple
from math import sqrt


Geometry = namedtuple("Geometry", "length cosine sine dofs")
Properties = namedtuple("Properties", "area inertia young yield_stress density expansion stiffness")
Loading = namedtuple("Loading", "external total temperature settlement")


def member_geometry(nodes, members, node_dofs):
    geometry = []
    for member in members:
        start, end = nodes[member.start], nodes[member.end]
        dx, dy = end.x - start.x, end.y - start.y
        length = sqrt(dx * dx + dy * dy)
        geometry.append(Geometry(length, dx / length, dy / length,
                                 node_dofs[member.start] + node_dofs[member.end]))
    return geometry


def member_properties(model, choices, geometry):
    result = []
    for member, choice, shape in zip(model.members, choices, geometry):
        section, material = model.sections[choice], model.materials[member.material]
        result.append(Properties(section.area, section.inertia, material.young, material.yield_stress,
                                 material.density, material.expansion, material.young * section.area / shape.length))
    return result


def member_weight(properties, geometry):
    return properties.density * 9.81 * properties.area * geometry.length / 1000000000


def member_stiffness(properties, geometry):
    stiffness, c, s = properties.stiffness, geometry.cosine, geometry.sine
    xx, xy, yy = stiffness * (c * c), stiffness * (c * s), stiffness * (s * s)
    return ((xx, xy, -xx, -xy), (xy, yy, -xy, -yy),
            (-xx, -xy, xx, xy), (-xy, -yy, xy, yy))


def assemble(geometry, properties, degrees, removed=None):
    matrix = [[0.0] * degrees for _ in range(degrees)]
    for number, (shape, member) in enumerate(zip(geometry, properties)):
        if number == removed:
            continue
        local = member_stiffness(member, shape)
        for row, global_row in enumerate(shape.dofs):
            for column, global_column in enumerate(shape.dofs):
                matrix[global_row][global_column] += local[row][column]
    return matrix


def load_vectors(case, geometry, properties, node_dofs, degrees, removed=None):
    external, thermal = [0.0] * degrees, [0.0] * degrees
    temperature, settlement = [0.0] * len(geometry), False
    for line in case.lines:
        if line[0] == "FORCE":
            _, node, horizontal, vertical = line
            x, y = node_dofs[node]
            external[x] += horizontal * 1000
            external[y] += vertical * 1000
        elif line[0] == "TEMPERATURE":
            _, number, change = line
            if number == removed:
                continue
            member, shape = properties[number], geometry[number]
            force = member.young * member.area * member.expansion * change
            temperature[number] = force
            direction = (-shape.cosine, -shape.sine, shape.cosine, shape.sine)
            for degree, coefficient in zip(shape.dofs, direction):
                thermal[degree] += force * coefficient
        elif line[0] == "SELFWEIGHT":
            for number, (member, shape) in enumerate(zip(properties, geometry)):
                if number != removed:
                    weight = member_weight(member, shape)
                    external[shape.dofs[1]] -= weight / 2
                    external[shape.dofs[3]] -= weight / 2
        else:
            settlement = True
    total = [first + second for first, second in zip(external, thermal)]
    return Loading(external, total, temperature, settlement)
