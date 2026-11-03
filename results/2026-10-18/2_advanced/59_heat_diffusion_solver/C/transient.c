#include "heat.h"
double heat_flow(const System *system, const double *field, int point, int first, int last) {
    double out = 0;
    for (int direction = first; direction < last; ++direction) {
        Face face = system->faces[point][direction];
        if (face.neighbor >= 0)
            out += face.g * (field[face.neighbor] - field[point]);
        else if (face.boundary)
            out += face.g * (face.theta - field[point]);
    }
    return out;
}
void thomas(const double *lower, const double *diagonal, const double *upper, const double *rhs,
            int count, double *out) {
    double u[40], r[40];
    u[0] = upper[0] / diagonal[0];
    r[0] = rhs[0] / diagonal[0];
    for (int i = 1; i < count; ++i) {
        double pivot = diagonal[i] - lower[i] * u[i - 1];
        u[i] = upper[i] / pivot;
        r[i] = (rhs[i] - lower[i] * r[i - 1]) / pivot;
    }
    out[count - 1] = r[count - 1];
    for (int i = count - 2; i >= 0; --i)
        out[i] = r[i] - u[i] * out[i + 1];
}
void sweep(const System *system, double tau, const double *rhs, bool horizontal, double *out) {
    const Mesh *mesh = &system->mesh;
    int count = horizontal ? mesh->height : mesh->width,
        length = horizontal ? mesh->width : mesh->height, first = horizontal ? 0 : 2;
    double lower[40], diagonal[40], upper[40], r[40], solved[40];
    for (int line = 0; line < count; ++line) {
        for (int i = 0; i < length; ++i) {
            int p = horizontal ? cell(mesh, line, i) : cell(mesh, i, line);
            Face a = system->faces[p][first], b = system->faces[p][first + 1];
            lower[i] = a.neighbor >= 0 ? -a.g : 0;
            diagonal[i] = system->capacity[p] / tau + a.g + b.g;
            upper[i] = b.neighbor >= 0 ? -b.g : 0;
            r[i] = rhs[p];
            if (a.boundary)
                r[i] += a.g * a.theta;
            if (b.boundary)
                r[i] += b.g * b.theta;
        }
        thomas(lower, diagonal, upper, r, length, solved);
        for (int i = 0; i < length; ++i)
            out[horizontal ? cell(mesh, line, i) : cell(mesh, i, line)] = solved[i];
    }
}
void advance(const System *system, const double *field, const double *source, double dt,
             const char *method, double *out, double *intermediate) {
    int n = system->mesh.count;
    if (strcmp(method, "ftcs") == 0) {
        for (int p = 0; p < n; ++p)
            out[p] = field[p] +
                     dt * (heat_flow(system, field, p, 0, 4) + source[p]) / system->capacity[p];
        return;
    }
    bool backward = strcmp(method, "backward_euler") == 0;
    double tau = backward ? dt : dt / 2, vertical[1000], rhs[1000];
    for (int p = 0; p < n; ++p) {
        vertical[p] = heat_flow(system, field, p, 2, 4);
        rhs[p] = system->capacity[p] / tau * field[p] + vertical[p] + source[p];
    }
    sweep(system, tau, rhs, true, intermediate);
    for (int p = 0; p < n; ++p)
        rhs[p] = backward ? system->capacity[p] / tau * intermediate[p] - vertical[p]
                          : system->capacity[p] / tau * intermediate[p] +
                                heat_flow(system, intermediate, p, 0, 2) + source[p];
    sweep(system, tau, rhs, false, out);
}
