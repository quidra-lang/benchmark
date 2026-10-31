#include "tracker.hpp"
std::vector<Pair> minimum_matching(const Matrix &costs) {
    if (costs.empty() || costs[0].empty())
        return {};
    bool flipped = costs.size() > costs[0].size();
    Matrix matrix = flipped ? transpose(costs) : costs;
    int rows = int(matrix.size()), columns = int(matrix[0].size());
    Vector u(rows + 1), v(columns + 1);
    std::vector<int> matched(columns + 1), previous(columns + 1);
    for (int row = 1; row <= rows; ++row) {
        matched[0] = row;
        int column = 0;
        Vector distances(columns + 1, std::numeric_limits<double>::infinity());
        std::vector<bool> used(columns + 1);
        do {
            used[column] = true;
            int current = matched[column], following = 0;
            double delta = std::numeric_limits<double>::infinity();
            for (int candidate = 1; candidate <= columns; ++candidate)
                if (!used[candidate]) {
                    double reduced = matrix[current - 1][candidate - 1] - u[current] - v[candidate];
                    if (reduced < distances[candidate]) {
                        distances[candidate] = reduced;
                        previous[candidate] = column;
                    }
                    if (distances[candidate] < delta) {
                        delta = distances[candidate];
                        following = candidate;
                    }
                }
            for (int candidate = 0; candidate <= columns; ++candidate) {
                if (used[candidate]) {
                    u[matched[candidate]] += delta;
                    v[candidate] -= delta;
                } else
                    distances[candidate] -= delta;
            }
            column = following;
        } while (matched[column] != 0);
        while (column) {
            int following = previous[column];
            matched[column] = matched[following];
            column = following;
        }
    }
    std::vector<Pair> out;
    for (int column = 1; column <= columns; ++column)
        if (matched[column])
            out.push_back(flipped ? Pair{column - 1, matched[column] - 1}
                                  : Pair{matched[column] - 1, column - 1});
    std::sort(out.begin(), out.end());
    return out;
}
std::vector<Pair> optimal_assignment(const Matrix &costs,
                                     const std::vector<std::vector<bool>> &usable) {
    if (costs.empty() || costs[0].empty())
        return {};
    double largest = 0;
    for (int i = 0; i < int(costs.size()); ++i)
        for (int j = 0; j < int(costs[0].size()); ++j)
            if (usable[i][j])
                largest = std::max(largest, costs[i][j]);
    double penalty = (std::min(costs.size(), costs[0].size()) + 1) * (std::max(1.0, largest) + 1);
    Matrix matrix = costs;
    for (int i = 0; i < int(matrix.size()); ++i)
        for (int j = 0; j < int(matrix[i].size()); ++j)
            if (!usable[i][j])
                matrix[i][j] = penalty;
    std::vector<Pair> out;
    for (Pair pair : minimum_matching(matrix))
        if (usable[pair.first][pair.second])
            out.push_back(pair);
    return out;
}
