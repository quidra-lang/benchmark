#include "heat.h"
double g_value(const System *system, const double *field, int point) {
    double out = 0;
    for (int direction = 0; direction < 4; ++direction) {
        Face face = system->faces[point][direction];
        if (face.neighbor >= 0)
            out += face.g * field[face.neighbor];
        else if (face.boundary)
            out += face.g * face.theta;
    }
    return out + system->source_all[point];
}
Iteration iterate(const System *system, const Params *params, const char *method, double omega) {
    Iteration out = {0};
    strcpy(out.method, method);
    out.omega = omega;
    int n = system->mesh.count;
    out.field = allocate((size_t)n, sizeof(double));
    out.changes = allocate((size_t)params->max_iterations, sizeof(double));
    for (int p = 0; p < n; ++p)
        out.field[p] = params->initial;
    double previous[1000];
    for (int iteration = 1; iteration <= params->max_iterations; ++iteration) {
        memcpy(previous, out.field, (size_t)n * sizeof(double));
        bool jacobi = strcmp(method, "jacobi") == 0, seidel = strcmp(method, "gauss_seidel") == 0;
        for (int p = 0; p < n; ++p) {
            double value = g_value(system, jacobi ? previous : out.field, p) / system->diagonal[p];
            out.field[p] = jacobi || seidel ? value : out.field[p] + omega * (value - out.field[p]);
        }
        double change = 0;
        for (int p = 0; p < n; ++p)
            if (fabs(out.field[p] - previous[p]) > change)
                change = fabs(out.field[p] - previous[p]);
        out.changes[out.count++] = change;
        if (change < params->tolerance) {
            out.converged = true;
            break;
        }
    }
    return out;
}
static double *entry(double *matrix, int width, int row, int column) {
    return matrix + (size_t)row * (2 * width + 1) + column - row + width;
}
double **direct(const System *system, double **rhs, int rhs_count) {
    int n = system->mesh.count, w = system->mesh.width;
    double *matrix = allocate((size_t)n * (2 * w + 1), sizeof(double));
    double **vectors = allocate((size_t)rhs_count, sizeof(double *)),
           **solutions = allocate((size_t)rhs_count, sizeof(double *));
    for (int r = 0; r < rhs_count; ++r) {
        vectors[r] = allocate((size_t)n, sizeof(double));
        memcpy(vectors[r], rhs[r], (size_t)n * sizeof(double));
    }
    for (int p = 0; p < n; ++p) {
        *entry(matrix, w, p, p) = system->diagonal[p];
        for (int direction = 0; direction < 4; ++direction) {
            Face face = system->faces[p][direction];
            if (face.neighbor >= 0)
                *entry(matrix, w, p, face.neighbor) = -face.g;
        }
    }
    for (int k = 0; k < n; ++k) {
        int stop = k + w + 1 < n ? k + w + 1 : n;
        for (int i = k + 1; i < stop; ++i) {
            double factor = *entry(matrix, w, i, k) / *entry(matrix, w, k, k);
            *entry(matrix, w, i, k) = 0;
            for (int j = k + 1; j < stop; ++j)
                *entry(matrix, w, i, j) =
                    *entry(matrix, w, i, j) - factor * *entry(matrix, w, k, j);
            for (int r = 0; r < rhs_count; ++r)
                vectors[r][i] = vectors[r][i] - factor * vectors[r][k];
        }
    }
    for (int r = 0; r < rhs_count; ++r) {
        solutions[r] = allocate((size_t)n, sizeof(double));
        for (int i = n - 1; i >= 0; --i) {
            double value = vectors[r][i];
            int stop = i + w + 1 < n ? i + w + 1 : n;
            for (int j = i + 1; j < stop; ++j)
                value = value - *entry(matrix, w, i, j) * solutions[r][j];
            solutions[r][i] = value / *entry(matrix, w, i, i);
        }
    }
    return solutions;
}
double residual(const System *system, const double *field, const double *rhs) {
    double maximum = 0;
    for (int p = 0; p < system->mesh.count; ++p) {
        double value = rhs[p];
        for (int direction = 0; direction < 4; ++direction) {
            Face face = system->faces[p][direction];
            if (face.neighbor >= 0)
                value += face.g * field[face.neighbor];
        }
        value -= system->diagonal[p] * field[p];
        if (fabs(value) > maximum)
            maximum = fabs(value);
    }
    return maximum;
}
