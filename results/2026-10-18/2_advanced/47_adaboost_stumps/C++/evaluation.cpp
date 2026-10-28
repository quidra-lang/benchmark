#include "boosting.hpp"
std::string real(double value, int precision) {
    if (std::abs(value) < 0.5 * std::pow(10.0, -precision))
        value = 0;
    std::ostringstream out;
    out << std::fixed << std::setprecision(precision) << value;
    return out.str();
}
std::string ratio(std::int64_t a, std::int64_t b) {
    return b ? real(double(a) / double(b)) : "-";
}
int prediction(double score) {
    return score > 0 ? 1 : -1;
}
std::pair<std::int64_t, std::int64_t> auc(const Rows &rows, const Vector &scores) {
    std::int64_t positives = 0, negatives = 0, wins = 0, ties = 0;
    for (std::size_t i = 0; i < rows.size(); ++i)
        if (rows[i].label == 1) {
            ++positives;
            for (std::size_t j = 0; j < rows.size(); ++j)
                if (rows[j].label == -1) {
                    wins += scores[i] > scores[j];
                    ties += scores[i] == scores[j];
                }
        } else
            ++negatives;
    return {2 * wins + ties, 2 * positives * negatives};
}
std::vector<Ints> confusion(const Rows &rows, const Ints &predictions, int classes) {
    std::vector<Ints> out(classes, Ints(classes));
    for (std::size_t i = 0; i < rows.size(); ++i)
        ++out[rows[i].label - 1][predictions[i] - 1];
    return out;
}
int margin_count(const Vector &margins, double threshold) {
    int out = 0;
    for (double value : margins)
        out += value <= threshold;
    return out;
}
void write_lines(const std::string &name, const Lines &lines) {
    std::ofstream file("output/" + name, std::ios::binary);
    for (const std::string &line : lines)
        file << line << '\n';
}
