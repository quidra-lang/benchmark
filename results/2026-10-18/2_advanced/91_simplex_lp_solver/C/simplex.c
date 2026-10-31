#include "solver.h"
PhaseResult phase(Tableau *tableau, const Rational *cost, const bool *candidates,
                  const Standard *standard, Rational constant, int sign) {
    PhaseResult out = {0};
    out.entering = -1;
    for (;;) {
        Rational reduced[90], value;
        tableau_reduced(tableau, cost, reduced, &value);
        int entering = -1;
        for (int k = 0; k < tableau->columns; ++k)
            if (candidates[k] && reduced[k].numerator < 0) {
                entering = k;
                break;
            }
        if (entering < 0)
            return out;
        int leaving = -1;
        Rational ratio = integer(0);
        for (int row = 0; row < tableau->rows; ++row)
            if (tableau->values[row][entering].numerator > 0) {
                Rational candidate = rat_div(tableau->beta[row], tableau->values[row][entering]);
                int comparison = rat_compare(candidate, ratio);
                if (leaving < 0 || comparison < 0 ||
                    (!comparison && tableau->basis[row] < tableau->basis[leaving])) {
                    leaving = row;
                    ratio = candidate;
                }
            }
        if (leaving < 0) {
            out.entering = entering;
            return out;
        }
        int previous = tableau->basis[leaving];
        Rational before = reduced[entering];
        tableau_pivot(tableau, leaving, entering);
        ++out.iterations;
        tableau_reduced(tableau, cost, reduced, &value);
        lines_push(&out.lines,
                   format_text("PIVOT %d enter %s reduced %s leave %s row %s ratio %s objective %s",
                               out.iterations, standard->columns[entering], rat_text(before).value,
                               standard->columns[previous], standard->rows[leaving],
                               rat_text(ratio).value,
                               rat_text(rat_add(constant, rat_mul(integer(sign), value))).value));
    }
}
