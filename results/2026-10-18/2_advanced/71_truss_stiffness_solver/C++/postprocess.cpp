#include "truss.hpp"
Vector axial_forces(const std::vector<Geometry> &geometry,
                    const std::vector<Properties> &properties, const Vector &displacement,
                    const Vector &temperature, int removed) {
    Vector out(geometry.size());
    for (int i = 0; i < int(geometry.size()); ++i)
        if (i != removed) {
            const Geometry &g = geometry[i];
            double extension = (displacement[g.dofs[2]] - displacement[g.dofs[0]]) * g.cosine +
                               (displacement[g.dofs[3]] - displacement[g.dofs[1]]) * g.sine;
            out[i] = properties[i].stiffness * extension - temperature[i];
        }
    return out;
}
Vector reactions(const Matrix &matrix, const Vector &displacement, const Vector &force,
                 const Indices &restrained) {
    Vector out(force.size());
    for (int row : restrained) {
        double value = 0;
        for (int column = 0; column < int(force.size()); ++column)
            value += matrix[row][column] * displacement[column];
        out[row] = value - force[row];
    }
    return out;
}
static Vector combined_vector(const Combination &combination, const std::vector<Result> &cases,
                              Vector Result::*field) {
    const auto &first = combination.terms[0];
    Vector out = cases[first.first].*field;
    for (double &value : out)
        value = first.second * value;
    for (int i = 1; i < int(combination.terms.size()); ++i) {
        const auto &term = combination.terms[i];
        const Vector &source = cases[term.first].*field;
        for (int j = 0; j < int(out.size()); ++j)
            out[j] += term.second * source[j];
    }
    return out;
}
Result superpose(const Combination &combination, const std::vector<Result> &cases) {
    return {combination.name, combined_vector(combination, cases, &Result::displacement),
            combined_vector(combination, cases, &Result::forces),
            combined_vector(combination, cases, &Result::reactions),
            combined_vector(combination, cases, &Result::external)};
}
double equilibrium_residual(const Result &result, const std::vector<Geometry> &geometry) {
    Vector residual(result.external.size());
    for (int i = 0; i < int(residual.size()); ++i)
        residual[i] = result.external[i] + result.reactions[i];
    for (int i = 0; i < int(geometry.size()); ++i) {
        const Geometry &g = geometry[i];
        std::array<double, 4> direction = {g.cosine, g.sine, -g.cosine, -g.sine};
        for (int j = 0; j < 4; ++j)
            residual[g.dofs[j]] += result.forces[i] * direction[j];
    }
    double maximum = 0;
    for (double value : residual)
        maximum = std::max(maximum, std::abs(value));
    return maximum;
}
