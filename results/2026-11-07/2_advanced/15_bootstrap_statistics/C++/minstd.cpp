#include "statistics.hpp"

Integer Minstd::draw() { state = 48271 * state % 2147483647; return state; }
std::size_t Minstd::below(std::size_t limit) { return static_cast<std::size_t>(draw() % static_cast<Integer>(limit)); }
void Minstd::shuffle(Indices& values) {
    for (std::size_t i = values.size(); i > 1; --i) std::swap(values[i - 1], values[below(i)]);
}
