#include "truss.h"
void axial_forces(const Geometry *geometry, const Properties *properties, int members,
                  const double *displacement, const double *temperature, int removed, double *out) {
    for (int i = 0; i < members; ++i) {
        out[i] = 0;
        if (i == removed)
            continue;
        const Geometry *g = &geometry[i];
        double extension = (displacement[g->dofs[2]] - displacement[g->dofs[0]]) * g->cosine +
                           (displacement[g->dofs[3]] - displacement[g->dofs[1]]) * g->sine;
        out[i] = properties[i].stiffness * extension - temperature[i];
    }
}
void reactions(const Matrix *matrix, const double *displacement, const double *force,
               const int *restrained, int nr, double *out) {
    memset(out, 0, (size_t)matrix->n * sizeof *out);
    for (int i = 0; i < nr; ++i) {
        int r = restrained[i];
        double value = 0;
        for (int d = 0; d < matrix->n; ++d)
            value += matrix->v[r][d] * displacement[d];
        out[r] = value - force[r];
    }
}
void superpose(const Combination *combination, const Result *cases, int members, int degrees,
               Result *out) {
    memset(out, 0, sizeof *out);
    strcpy(out->name, combination->name);
    for (int component = 0; component < 4; ++component) {
        double *target = component == 0   ? out->displacement
                         : component == 1 ? out->forces
                         : component == 2 ? out->reactions
                                          : out->external;
        int n = component == 1 ? members : degrees;
        for (int term = 0; term < combination->count; ++term) {
            const Term *t = &combination->terms[term];
            const Result *source = &cases[t->index];
            const double *values = component == 0   ? source->displacement
                                   : component == 1 ? source->forces
                                   : component == 2 ? source->reactions
                                                    : source->external;
            for (int j = 0; j < n; ++j) {
                if (term == 0)
                    target[j] = t->factor * values[j];
                else
                    target[j] += t->factor * values[j];
            }
        }
    }
}
double equilibrium_residual(const Result *result, const Geometry *geometry, int members,
                            int degrees) {
    double residual[80];
    for (int i = 0; i < degrees; ++i)
        residual[i] = result->external[i] + result->reactions[i];
    for (int i = 0; i < members; ++i) {
        const Geometry *g = &geometry[i];
        double direction[4] = {g->cosine, g->sine, -g->cosine, -g->sine};
        for (int j = 0; j < 4; ++j)
            residual[g->dofs[j]] += result->forces[i] * direction[j];
    }
    double maximum = 0;
    for (int i = 0; i < degrees; ++i)
        maximum = fmax(maximum, fabs(residual[i]));
    return maximum;
}
