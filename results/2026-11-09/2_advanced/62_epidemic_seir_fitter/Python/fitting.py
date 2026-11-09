PHI = 0.6180339887498949


def golden(function, a, b, iterations):
    c = b - PHI * (b - a)
    d = a + PHI * (b - a)
    fc = function(c)
    fd = function(d)
    records = [(a, b, c, d, fc, fd)]
    for _ in range(iterations):
        if fc < fd:
            b, d, fd = d, c, fc
            c = b - PHI * (b - a)
            fc = function(c)
        else:
            a, c, fc = c, d, fd
            d = a + PHI * (b - a)
            fd = function(d)
        records.append((a, b, c, d, fc, fd))
    point, value = (c, fc) if fc < fd else (d, fd)
    return point, value, records


def nelder_mead(function, beta, gamma, delta_beta, delta_gamma,
                alpha, chi, psi, omega, iterations):
    vertices = []
    for number, point in enumerate(((beta, gamma), (beta + delta_beta, gamma),
                                    (beta, gamma + delta_gamma))):
        vertices.append((number, *point, function(*point)))
    initial = vertices.copy()
    serial = 3
    records = []

    def order(vertex):
        return vertex[3], vertex[0]

    def toward(origin, target, factor):
        return tuple(origin[axis] + factor * (target[axis] - origin[axis]) for axis in range(2))

    for _ in range(iterations):
        vertices.sort(key=order)
        first, second, third = vertices
        centroid = ((first[1] + second[1]) / 2.0, (first[2] + second[2]) / 2.0)
        reflected = tuple(centroid[axis] + alpha * (centroid[axis] - third[axis + 1])
                          for axis in range(2))
        fr = function(*reflected)
        accepted = None
        if fr < first[3]:
            expanded = toward(centroid, reflected, chi)
            fe = function(*expanded)
            if fe < fr:
                accepted, value, operation = expanded, fe, "expand"
            else:
                accepted, value, operation = reflected, fr, "reflect"
        elif fr < second[3]:
            accepted, value, operation = reflected, fr, "reflect"
        elif fr < third[3]:
            contracted = toward(centroid, reflected, psi)
            fc = function(*contracted)
            if fc <= fr:
                accepted, value, operation = contracted, fc, "contract_out"
        else:
            contracted = toward(centroid, third[1:3], psi)
            fc = function(*contracted)
            if fc < third[3]:
                accepted, value, operation = contracted, fc, "contract_in"
        if accepted is None:
            operation = "shrink"
            vertices = [first]
            for vertex in (second, third):
                point = toward(first[1:3], vertex[1:3], omega)
                vertices.append((serial, *point, function(*point)))
                serial += 1
        else:
            vertices = [first, second, (serial, *accepted, value)]
            serial += 1
        vertices.sort(key=order)
        records.append((operation, vertices[0]))
    return initial, records, vertices
