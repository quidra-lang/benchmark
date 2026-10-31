#include "solver.hpp"
std::pair<Values, Rational> Tableau::reduced(const Values &cost) const {
    Values reduced = cost;
    Rational value;
    for (std::size_t row = 0; row < basis.size(); ++row) {
        Rational basic = cost[basis[row]];
        value = value + basic * beta[row];
        for (std::size_t column = 0; column < cost.size(); ++column)
            reduced[column] = reduced[column] - basic * values[row][column];
    }
    return {reduced, value};
}
void Tableau::pivot(int row, int column) {
    Rational factor = values[row][column];
    for (Rational &value : values[row])
        value = value / factor;
    beta[row] = beta[row] / factor;
    for (int other = 0; other < static_cast<int>(values.size()); ++other)
        if (other != row) {
            Rational f = values[other][column];
            for (std::size_t k = 0; k < values[other].size(); ++k)
                values[other][k] = values[other][k] - f * values[row][k];
            beta[other] = beta[other] - f * beta[row];
        }
    basis[row] = column;
}
Lines Tableau::display(const std::string &heading, const Lines &columns, const Lines &rows,
                       const Values &cost, Rational constant, int sign) const {
    Lines out{"TABLEAU " + heading, "COLUMNS " + join(columns)};
    for (std::size_t i = 0; i < values.size(); ++i) {
        Lines parts;
        for (Rational value : values[i])
            parts.push_back(value.str());
        out.push_back(
            text("ROW ", rows[i], " ", columns[basis[i]], " ", join(parts), " | ", beta[i]));
    }
    auto [reduced, value] = this->reduced(cost);
    Lines parts;
    for (Rational entry : reduced)
        parts.push_back(entry.str());
    out.push_back(text("COST ", join(parts), " | ", constant + Rational(sign) * value));
    return out;
}
