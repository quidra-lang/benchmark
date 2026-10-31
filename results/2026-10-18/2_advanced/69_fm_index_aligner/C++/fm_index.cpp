#include "aligner.hpp"
Index::Index(const std::string &text, const std::vector<int> &suffixes, int occurrence_interval,
             int sample_interval)
    : size(int(text.size())), interval(occurrence_interval), samples(size, -1) {
    std::array<int, 6> frequencies{};
    for (char c : text)
        ++frequencies[symbol_number(c)];
    int offset = 0;
    for (int i = 0; i < 6; ++i) {
        C[i] = offset;
        offset += frequencies[i];
    }
    for (int row = 0; row < size; ++row) {
        int position = suffixes[row];
        bwt += text[position ? position - 1 : size - 1];
        if (sample_interval && position % sample_interval == 0) {
            samples[row] = position;
            ++sample_count;
        }
    }
    std::array<int, 6> counts{};
    checkpoints.push_back(counts);
    for (int i = 0; i < size; ++i) {
        ++counts[symbol_number(bwt[i])];
        if ((i + 1) % interval == 0)
            checkpoints.push_back(counts);
    }
}
int Index::occurrence(char symbol, int position) const {
    int checkpoint = position / interval, count = checkpoints[checkpoint][symbol_number(symbol)];
    for (int i = checkpoint * interval; i < position; ++i)
        count += bwt[i] == symbol;
    return count;
}
int Index::lf(int row) const {
    char symbol = bwt[row];
    return C[symbol_number(symbol)] + occurrence(symbol, row);
}
Interval Index::extend(Interval value, char base) const {
    if (base == 'N')
        return {0, 0};
    int start = C[symbol_number(base)];
    return {start + occurrence(base, value.lower), start + occurrence(base, value.upper)};
}
Interval Index::backward_search(const std::string &sequence) const {
    Interval out{0, size};
    for (auto at = sequence.rbegin(); at != sequence.rend(); ++at) {
        out = extend(out, *at);
        if (out.empty())
            break;
    }
    return out;
}
std::pair<int, int> Index::locate(int row) const {
    int steps = 0;
    while (samples[row] < 0) {
        row = lf(row);
        ++steps;
    }
    return {samples[row] + steps, steps};
}
std::string Index::inverse() const {
    std::string out(size, '$');
    int row = 0;
    for (int p = size - 2; p >= 0; --p) {
        out[p] = bwt[row];
        row = lf(row);
    }
    return out;
}
