#include "classifier.h"
double kernel_value(Kernel kernel, const double *first, const double *second) {
    if (strcmp(kernel.kind, "linear") == 0)
        return first[0] * second[0] + first[1] * second[1];
    if (strcmp(kernel.kind, "poly") == 0) {
        double s = kernel.gamma * (first[0] * second[0] + first[1] * second[1]) + kernel.coef0,
               value = 1;
        for (int i = 0; i < kernel.degree; ++i)
            value *= s;
        return value;
    }
    double e1 = first[0] - second[0], e2 = first[1] - second[1];
    return exp(-kernel.gamma * (e1 * e1 + e2 * e2));
}
double *kernel_matrix(Kernel kernel, const Example *data, int count) {
    double *out = allocate((size_t)count * count, sizeof(double));
    for (int i = 0; i < count; ++i)
        for (int j = 0; j < count; ++j)
            out[i * count + j] = kernel_value(kernel, data[i].point, data[j].point);
    return out;
}
char *kernel_description(Kernel kernel) {
    if (strcmp(kernel.kind, "linear") == 0)
        return "linear";
    if (strcmp(kernel.kind, "rbf") == 0)
        return format("rbf gamma %s", real(kernel.gamma, 4));
    return format("poly degree %d gamma %s coef0 %s", kernel.degree, real(kernel.gamma, 4),
                  real(kernel.coef0, 4));
}
