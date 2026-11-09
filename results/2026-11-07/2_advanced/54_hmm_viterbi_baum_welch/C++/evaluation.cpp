#include "hmm.hpp"
std::string fraction(I numerator, I denominator) {
    if (!denominator)
        return "-";
    if (denominator < 0) {
        numerator = -numerator;
        denominator = -denominator;
    }
    const I divisor = std::gcd(std::abs(numerator), denominator);
    return std::to_string(numerator / divisor) + "/" + std::to_string(denominator / divisor);
}
void accumulate(Confusion &matrix, const Path &truth, const Path &predicted) {
    for (int i = 0; i < int(truth.size()); ++i)
        ++matrix[truth[i]][predicted[i]];
}
I correct(const Path &truth, const Path &prediction) {
    I out = 0;
    for (int i = 0; i < int(truth.size()); ++i)
        out += truth[i] == prediction[i];
    return out;
}
Lines matrix_lines(const Model &model, const Confusion &matrix) {
    int width = 1;
    for (int i = 0; i < model.k(); ++i)
        for (int j = 0; j < model.k(); ++j)
            width = std::max<int>(width, std::to_string(matrix[i][j]).size());
    Lines out;
    std::ostringstream header;
    header << ' ';
    for (char state : model.states)
        header << ' ' << std::setw(width) << state;
    out.push_back(header.str());
    for (int i = 0; i < model.k(); ++i) {
        std::ostringstream row;
        row << model.states[i];
        for (int j = 0; j < model.k(); ++j)
            row << ' ' << std::setw(width) << matrix[i][j];
        out.push_back(row.str());
    }
    return out;
}
Lines metric_lines(const Model &model, const Confusion &matrix) {
    std::array<I, 4> rows{}, columns{};
    I total = 0, correct_count = 0, expected = 0;
    for (int i = 0; i < model.k(); ++i)
        for (int j = 0; j < model.k(); ++j) {
            rows[i] += matrix[i][j];
            columns[j] += matrix[i][j];
        }
    for (int i = 0; i < model.k(); ++i) {
        total += rows[i];
        correct_count += matrix[i][i];
        expected += rows[i] * columns[i];
    }
    Lines out{"ACCURACY " + fraction(correct_count, total),
              "KAPPA " + fraction(total * correct_count - expected, total * total - expected)};
    for (int i = 0; i < model.k(); ++i)
        out.push_back("STATE " + std::string(1, model.states[i]) + " precision " +
                      fraction(matrix[i][i], columns[i]) + " recall " + fraction(matrix[i][i], rows[i]) +
                      " f1 " + fraction(2 * matrix[i][i], columns[i] + rows[i]));
    return out;
}
std::vector<Run> runs(const Path &path) {
    std::vector<Run> out;
    if (path.empty())
        return out;
    int start = 1, state = path[0];
    for (int t = 1; t < int(path.size()); ++t)
        if (path[t] != state) {
            out.push_back({state, start, t});
            start = t + 1;
            state = path[t];
        }
    out.push_back({state, start, int(path.size())});
    return out;
}
MatchCounts region_counts(const std::vector<Region> &predicted, const std::vector<Region> &truth) {
    MatchCounts out;
    out.predicted = predicted.size();
    out.truth = truth.size();
    for (const Region &first : predicted)
        for (const Region &second : truth)
            if (first.start <= second.end && second.start <= first.end) {
                ++out.matched_predicted;
                break;
            }
    for (const Region &first : truth)
        for (const Region &second : predicted)
            if (first.start <= second.end && second.start <= first.end) {
                ++out.matched_truth;
                break;
            }
    return out;
}
MatchCounts boundary_counts(const Path &predicted, const Path &truth, int tolerance) {
    Path a, b;
    for (int i = 1; i < int(predicted.size()); ++i)
        if (predicted[i] != predicted[i - 1])
            a.push_back(i + 1);
    for (int i = 1; i < int(truth.size()); ++i)
        if (truth[i] != truth[i - 1])
            b.push_back(i + 1);
    MatchCounts out;
    out.predicted = a.size();
    out.truth = b.size();
    for (int first : a)
        for (int second : b)
            if (std::abs(first - second) <= tolerance) {
                ++out.matched_predicted;
                break;
            }
    for (int first : b)
        for (int second : a)
            if (std::abs(first - second) <= tolerance) {
                ++out.matched_truth;
                break;
            }
    return out;
}
