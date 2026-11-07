#include "sat.h"
static void pair_clause(Formula *formula, int a, int b) {
    Clause clause = {0};
    int_push(&clause, a);
    int_push(&clause, b);
    formula_push(formula, clause);
}
Formula queens_formula(int n) {
    Formula out = {.variables = n * n};
    for (int r = 0; r < n; ++r) {
        Clause clause = {0};
        for (int c = 1; c <= n; ++c)
            int_push(&clause, r * n + c);
        formula_push(&out, clause);
    }
    for (int a = 1; a <= out.variables; ++a)
        for (int b = a + 1; b <= out.variables; ++b) {
            int ar = (a - 1) / n, ac = (a - 1) % n, br = (b - 1) / n, bc = (b - 1) % n;
            if (ar == br || ac == bc || abs(ar - br) == abs(ac - bc))
                pair_clause(&out, -a, -b);
        }
    return out;
}
Formula pigeon_formula(int pigeons, int holes) {
    Formula out = {.variables = pigeons * holes};
    for (int p = 0; p < pigeons; ++p) {
        Clause clause = {0};
        for (int h = 1; h <= holes; ++h)
            int_push(&clause, p * holes + h);
        formula_push(&out, clause);
    }
    for (int p = 0; p < pigeons; ++p)
        for (int a = 1; a <= holes; ++a)
            for (int b = a + 1; b <= holes; ++b)
                pair_clause(&out, -(p * holes + a), -(p * holes + b));
    for (int h = 1; h <= holes; ++h)
        for (int a = 0; a < pigeons; ++a)
            for (int b = a + 1; b < pigeons; ++b)
                pair_clause(&out, -(a * holes + h), -(b * holes + h));
    return out;
}
Formula color_formula(const Graph *graph, int colors) {
    Formula out = {.variables = graph->vertices * colors};
    for (int x = 0; x < graph->vertices; ++x) {
        Clause clause = {0};
        for (int c = 1; c <= colors; ++c)
            int_push(&clause, x * colors + c);
        formula_push(&out, clause);
    }
    for (int x = 0; x < graph->vertices; ++x)
        for (int a = 1; a <= colors; ++a)
            for (int b = a + 1; b <= colors; ++b)
                pair_clause(&out, -(x * colors + a), -(x * colors + b));
    for (int e = 0; e < graph->edge_count; ++e)
        for (int c = 1; c <= colors; ++c)
            pair_clause(&out, -((graph->edges[e].a - 1) * colors + c),
                        -((graph->edges[e].b - 1) * colors + c));
    return out;
}
IntList decode(const Model *model, int rows, int columns) {
    IntList positions = {0};
    for (int r = 0; r < rows; ++r) {
        int position = 0;
        for (int c = 1; c <= columns; ++c)
            if (model->values[r * columns + c])
                position = c;
        int_push(&positions, position);
    }
    return positions;
}
