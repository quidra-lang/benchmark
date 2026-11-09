#include "solver.hpp"
PhaseResult phase(Tableau &tableau, const Values &cost, const std::vector<bool> &candidates,
                  const Lines &columns, const Lines &rows,
                  const std::function<Rational(Rational)> &objective) {
    PhaseResult out;
    for (;;) {
        Values reduced = tableau.reduced(cost).first;
        int entering = -1;
        for (int column = 0; column < static_cast<int>(reduced.size()); ++column)
            if (candidates[column] && reduced[column].numerator < 0) {
                entering = column;
                break;
            }
        if (entering < 0)
            return out;
        int leaving = -1;
        Rational ratio;
        for (int row = 0; row < static_cast<int>(tableau.values.size()); ++row)
            if (tableau.values[row][entering].numerator > 0) {
                Rational value = tableau.beta[row] / tableau.values[row][entering];
                if (leaving < 0 || value.compare(ratio) < 0 ||
                    (value.compare(ratio) == 0 && tableau.basis[row] < tableau.basis[leaving])) {
                    leaving = row;
                    ratio = value;
                }
            }
        if (leaving < 0) {
            out.entering = entering;
            return out;
        }
        int previous = tableau.basis[leaving];
        Rational before = reduced[entering];
        tableau.pivot(leaving, entering);
        ++out.iterations;
        Rational value = tableau.reduced(cost).second;
        out.lines.push_back(text("PIVOT ", out.iterations, " enter ", columns[entering],
                                 " reduced ", before, " leave ", columns[previous], " row ",
                                 rows[leaving], " ratio ", ratio, " objective ", objective(value)));
    }
}
