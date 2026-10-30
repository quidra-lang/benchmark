#include "solver.h"
void tableau_reduced(const Tableau *tableau, const Rational *cost, Rational *reduced,
                     Rational *value) {
    *value = integer(0);
    for (int k = 0; k < tableau->columns; ++k)
        reduced[k] = cost[k];
    for (int row = 0; row < tableau->rows; ++row) {
        Rational basic = cost[tableau->basis[row]];
        *value = rat_add(*value, rat_mul(basic, tableau->beta[row]));
        for (int k = 0; k < tableau->columns; ++k)
            reduced[k] = rat_sub(reduced[k], rat_mul(basic, tableau->values[row][k]));
    }
}
void tableau_pivot(Tableau *tableau, int row, int column) {
    Rational factor = tableau->values[row][column];
    for (int k = 0; k < tableau->columns; ++k)
        tableau->values[row][k] = rat_div(tableau->values[row][k], factor);
    tableau->beta[row] = rat_div(tableau->beta[row], factor);
    for (int other = 0; other < tableau->rows; ++other)
        if (other != row) {
            Rational f = tableau->values[other][column];
            for (int k = 0; k < tableau->columns; ++k)
                tableau->values[other][k] =
                    rat_sub(tableau->values[other][k], rat_mul(f, tableau->values[row][k]));
            tableau->beta[other] = rat_sub(tableau->beta[other], rat_mul(f, tableau->beta[row]));
        }
    tableau->basis[row] = column;
}
TextLines tableau_display(const Tableau *tableau, const char *heading, const Standard *standard,
                          const Rational *cost, Rational constant, int sign) {
    TextLines out = {0}, names = {0};
    lines_push(&out, format_text("TABLEAU %s", heading));
    for (int k = 0; k < tableau->columns; ++k)
        lines_add(&names, standard->columns[k]);
    char *joined = join_texts(&names, " ");
    lines_push(&out, format_text("COLUMNS %s", joined));
    free(joined);
    lines_free(&names);
    for (int row = 0; row < tableau->rows; ++row) {
        TextLines values = {0};
        for (int k = 0; k < tableau->columns; ++k)
            lines_add(&values, rat_text(tableau->values[row][k]).value);
        joined = join_texts(&values, " ");
        lines_push(&out, format_text("ROW %s %s %s | %s", standard->rows[row],
                                     standard->columns[tableau->basis[row]], joined,
                                     rat_text(tableau->beta[row]).value));
        free(joined);
        lines_free(&values);
    }
    Rational reduced[90], value;
    tableau_reduced(tableau, cost, reduced, &value);
    TextLines values = {0};
    for (int k = 0; k < tableau->columns; ++k)
        lines_add(&values, rat_text(reduced[k]).value);
    joined = join_texts(&values, " ");
    lines_push(&out, format_text("COST %s | %s", joined,
                                 rat_text(rat_add(constant, rat_mul(integer(sign), value))).value));
    free(joined);
    lines_free(&values);
    return out;
}
