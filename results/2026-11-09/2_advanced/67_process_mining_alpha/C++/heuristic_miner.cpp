#include "mining.hpp"
Fraction dependency(const Counts &counts, const std::string &a, const std::string &b) {
    I forward = count(counts, a, b), backward = count(counts, b, a);
    return {forward - backward, forward + backward + 1};
}
Fraction loop_measure(I value) { return {value, value + 1}; }
Fraction split_measure(const Counts &counts, const std::string &a, const std::string &b,
                       const std::string &c) {
    return {count(counts, b, c) + count(counts, c, b),
            count(counts, a, b) + count(counts, a, c) + 1};
}
Fraction join_measure(const Counts &counts, const std::string &a, const std::string &b,
                      const std::string &c) {
    return {count(counts, b, c) + count(counts, c, b),
            count(counts, b, a) + count(counts, c, a) + 1};
}
