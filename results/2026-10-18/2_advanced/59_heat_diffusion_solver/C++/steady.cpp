#include "heat.hpp"
double g_value(const System &system, const Field &field, int point) {
    double value = 0;
    for (const Face &face : system.faces[point]) {
        if (face.neighbor >= 0)
            value += face.g * field[face.neighbor];
        else if (face.theta)
            value += face.g * *face.theta;
    }
    return value + system.source_all[point];
}
Iteration iterate(const System &system, const Params &params, const std::string &method,
                  double omega) {
    Iteration out{method, Field(system.mesh.count, params.initial), {}, omega, false};
    for (int iteration = 1; iteration <= params.max_iterations; ++iteration) {
        const Field previous = out.field;
        for (int p = 0; p < system.mesh.count; ++p) {
            const double value =
                g_value(system, method == "jacobi" ? previous : out.field, p) / system.diagonal[p];
            if (method == "jacobi" || method == "gauss_seidel")
                out.field[p] = value;
            else
                out.field[p] = out.field[p] + omega * (value - out.field[p]);
        }
        double change = 0;
        for (int p = 0; p < system.mesh.count; ++p)
            change = std::max(change, std::abs(out.field[p] - previous[p]));
        out.changes.push_back(change);
        if (change < params.tolerance) {
            out.converged = true;
            break;
        }
    }
    return out;
}
std::vector<Field> direct(const System &system, std::vector<Field> rhs) {
    const int n = system.mesh.count, w = system.mesh.width;
    std::vector<Field> matrix(n, Field(2 * w + 1));
    auto at = [&](int row, int column) -> double & { return matrix[row][column - row + w]; };
    for (int p = 0; p < n; ++p) {
        at(p, p) = system.diagonal[p];
        for (const Face &face : system.faces[p])
            if (face.neighbor >= 0)
                at(p, face.neighbor) = -face.g;
    }
    for (int k = 0; k < n; ++k) {
        const int stop = std::min(n, k + w + 1);
        for (int i = k + 1; i < stop; ++i) {
            const double factor = at(i, k) / at(k, k);
            at(i, k) = 0;
            for (int j = k + 1; j < stop; ++j)
                at(i, j) = at(i, j) - factor * at(k, j);
            for (Field &values : rhs)
                values[i] = values[i] - factor * values[k];
        }
    }
    std::vector<Field> solutions;
    for (const Field &values : rhs) {
        Field solution(n);
        for (int i = n - 1; i >= 0; --i) {
            double value = values[i];
            for (int j = i + 1; j < std::min(n, i + w + 1); ++j)
                value = value - at(i, j) * solution[j];
            solution[i] = value / at(i, i);
        }
        solutions.push_back(std::move(solution));
    }
    return solutions;
}
double residual(const System &system, const Field &field, const Field &rhs) {
    double maximum = 0;
    for (int p = 0; p < system.mesh.count; ++p) {
        double value = rhs[p];
        for (const Face &face : system.faces[p])
            if (face.neighbor >= 0)
                value += face.g * field[face.neighbor];
        value -= system.diagonal[p] * field[p];
        maximum = std::max(maximum, std::abs(value));
    }
    return maximum;
}
