"""Member forces, reactions, ordered superposition and nodal equilibrium."""

from collections import namedtuple


Result = namedtuple("Result", "name displacement forces reactions external")


def axial_forces(geometry, properties, displacement, temperature, removed=None):
    forces = [0.0] * len(geometry)
    for number, (shape, member) in enumerate(zip(geometry, properties)):
        if number == removed:
            continue
        ix, iy, jx, jy = shape.dofs
        extension = ((displacement[jx] - displacement[ix]) * shape.cosine
                     + (displacement[jy] - displacement[iy]) * shape.sine)
        forces[number] = member.stiffness * extension - temperature[number]
    return forces


def reactions(matrix, displacement, force, restrained):
    result = [0.0] * len(force)
    for row in restrained:
        value = 0.0
        for column in range(len(force)):
            value += matrix[row][column] * displacement[column]
        result[row] = value - force[row]
    return result


def superpose(combination, results):
    first_name, first_factor = combination.terms[0]
    vectors = [[first_factor * value for value in vector] for vector in results[first_name][1:]]
    for name, factor in combination.terms[1:]:
        for target, source in zip(vectors, results[name][1:]):
            for index, value in enumerate(source):
                target[index] += factor * value
    return Result(combination.name, *vectors)


def equilibrium_residual(result, geometry):
    residual = [external + reaction for external, reaction in zip(result.external, result.reactions)]
    for shape, force in zip(geometry, result.forces):
        direction = (shape.cosine, shape.sine, -shape.cosine, -shape.sine)
        for degree, coefficient in zip(shape.dofs, direction):
            residual[degree] += force * coefficient
    return max(abs(value) for value in residual)
