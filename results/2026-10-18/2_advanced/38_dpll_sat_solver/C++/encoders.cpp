#include "sat.hpp"
Formula queens_formula(int n) {
    Formula out;
    out.variables = n * n;
    for (int r = 0; r < n; ++r) {
        Clause clause;
        for (int c = 1; c <= n; ++c)
            clause.push_back(r * n + c);
        out.clauses.push_back(clause);
    }
    for (int a = 1; a <= out.variables; ++a)
        for (int b = a + 1; b <= out.variables; ++b) {
            const int ar = (a - 1) / n, ac = (a - 1) % n, br = (b - 1) / n, bc = (b - 1) % n;
            if (ar == br || ac == bc || std::abs(ar - br) == std::abs(ac - bc))
                out.clauses.push_back({-a, -b});
        }
    return out;
}
Formula pigeon_formula(int pigeons, int holes) {
    Formula out;
    out.variables = pigeons * holes;
    for (int p = 0; p < pigeons; ++p) {
        Clause clause;
        for (int h = 1; h <= holes; ++h)
            clause.push_back(p * holes + h);
        out.clauses.push_back(clause);
    }
    for (int p = 0; p < pigeons; ++p)
        for (int a = 1; a <= holes; ++a)
            for (int b = a + 1; b <= holes; ++b)
                out.clauses.push_back({-(p * holes + a), -(p * holes + b)});
    for (int h = 1; h <= holes; ++h)
        for (int a = 0; a < pigeons; ++a)
            for (int b = a + 1; b < pigeons; ++b)
                out.clauses.push_back({-(a * holes + h), -(b * holes + h)});
    return out;
}
Formula color_formula(const Graph &graph, int colors) {
    Formula out;
    out.variables = graph.vertices * colors;
    for (int x = 0; x < graph.vertices; ++x) {
        Clause clause;
        for (int c = 1; c <= colors; ++c)
            clause.push_back(x * colors + c);
        out.clauses.push_back(clause);
    }
    for (int x = 0; x < graph.vertices; ++x)
        for (int a = 1; a <= colors; ++a)
            for (int b = a + 1; b <= colors; ++b)
                out.clauses.push_back({-(x * colors + a), -(x * colors + b)});
    for (const auto &edge : graph.edges)
        for (int c = 1; c <= colors; ++c)
            out.clauses.push_back({-((edge.first - 1) * colors + c), -((edge.second - 1) * colors + c)});
    return out;
}
std::vector<int> decode(const Model &model, int rows, int columns) {
    std::vector<int> out(rows);
    for (int r = 0; r < rows; ++r)
        for (int c = 1; c <= columns; ++c)
            if (model[r * columns + c])
                out[r] = c;
    return out;
}
