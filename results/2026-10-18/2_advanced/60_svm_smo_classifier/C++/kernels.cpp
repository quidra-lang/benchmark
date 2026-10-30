#include "classifier.hpp"
double kernel_value(const Kernel &kernel, Point a, Point b) {
    if (kernel.kind == "linear")
        return a[0] * b[0] + a[1] * b[1];
    if (kernel.kind == "poly") {
        const double s = kernel.gamma * (a[0] * b[0] + a[1] * b[1]) + kernel.coef0;
        double value = 1;
        for (int i = 0; i < kernel.degree; ++i)
            value *= s;
        return value;
    }
    const double e1 = a[0] - b[0], e2 = a[1] - b[1];
    return std::exp(-kernel.gamma * (e1 * e1 + e2 * e2));
}
Matrix kernel_matrix(const Kernel &kernel, const std::vector<Example> &data) {
    Matrix out(data.size(), Field(data.size()));
    for (int i = 0; i < int(data.size()); ++i)
        for (int j = 0; j < int(data.size()); ++j)
            out[i][j] = kernel_value(kernel, data[i].point, data[j].point);
    return out;
}
std::string kernel_description(const Kernel &kernel) {
    if (kernel.kind == "linear")
        return "linear";
    if (kernel.kind == "rbf")
        return "rbf gamma " + real(kernel.gamma, 4);
    return "poly degree " + std::to_string(kernel.degree) + " gamma " + real(kernel.gamma, 4) +
           " coef0 " + real(kernel.coef0, 4);
}
