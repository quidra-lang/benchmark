#include "heat.hpp"
double heat_flow(const System &system, const Field &field, int point, int first, int last) {
    double out = 0;
    for (int direction = first; direction < last; ++direction) {
        const Face &face = system.faces[point][direction];
        if (face.neighbor >= 0)
            out += face.g * (field[face.neighbor] - field[point]);
        else if (face.theta)
            out += face.g * (*face.theta - field[point]);
    }
    return out;
}
Field thomas(const Field &lower, const Field &diagonal, const Field &upper, const Field &rhs) {
    const int n = int(rhs.size());
    Field u(n), r(n), out(n);
    u[0] = upper[0] / diagonal[0];
    r[0] = rhs[0] / diagonal[0];
    for (int i = 1; i < n; ++i) {
        const double pivot = diagonal[i] - lower[i] * u[i - 1];
        u[i] = upper[i] / pivot;
        r[i] = (rhs[i] - lower[i] * r[i - 1]) / pivot;
    }
    out[n - 1] = r[n - 1];
    for (int i = n - 2; i >= 0; --i)
        out[i] = r[i] - u[i] * out[i + 1];
    return out;
}
Field sweep(const System &system, double tau, const Field &rhs, bool horizontal) {
    const Mesh &mesh = system.mesh;
    const int count = horizontal ? mesh.height : mesh.width,
              length = horizontal ? mesh.width : mesh.height, first = horizontal ? 0 : 2;
    Field out(mesh.count), lower(length), diagonal(length), upper(length), r(length);
    for (int line = 0; line < count; ++line) {
        for (int i = 0; i < length; ++i) {
            const int p = horizontal ? mesh.cell(line, i) : mesh.cell(i, line);
            const Face &a = system.faces[p][first], &b = system.faces[p][first + 1];
            lower[i] = a.neighbor >= 0 ? -a.g : 0;
            diagonal[i] = system.capacity[p] / tau + a.g + b.g;
            upper[i] = b.neighbor >= 0 ? -b.g : 0;
            r[i] = rhs[p];
            if (a.theta)
                r[i] += a.g * *a.theta;
            if (b.theta)
                r[i] += b.g * *b.theta;
        }
        const Field solved = thomas(lower, diagonal, upper, r);
        for (int i = 0; i < length; ++i)
            out[horizontal ? mesh.cell(line, i) : mesh.cell(i, line)] = solved[i];
    }
    return out;
}
Step advance(const System &system, const Field &field, const Field &source, double dt,
             const std::string &method) {
    const int n = system.mesh.count;
    Step out;
    out.field.resize(n);
    if (method == "ftcs") {
        for (int p = 0; p < n; ++p)
            out.field[p] = field[p] + dt * (heat_flow(system, field, p, 0, 4) + source[p]) /
                                          system.capacity[p];
        return out;
    }
    const bool backward = method == "backward_euler";
    const double tau = backward ? dt : dt / 2;
    Field vertical(n), rhs(n);
    for (int p = 0; p < n; ++p) {
        vertical[p] = heat_flow(system, field, p, 2, 4);
        rhs[p] = system.capacity[p] / tau * field[p] + vertical[p] + source[p];
    }
    out.intermediate = sweep(system, tau, rhs, true);
    for (int p = 0; p < n; ++p)
        rhs[p] = backward ? system.capacity[p] / tau * out.intermediate[p] - vertical[p]
                          : system.capacity[p] / tau * out.intermediate[p] +
                                heat_flow(system, out.intermediate, p, 0, 2) + source[p];
    out.field = sweep(system, tau, rhs, false);
    return out;
}
