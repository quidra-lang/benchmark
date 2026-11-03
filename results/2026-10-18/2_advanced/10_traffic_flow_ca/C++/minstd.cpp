#include "traffic.hpp"
#include <numeric>

Integer Minstd::draw() { state = 48271 * state % 2147483647; return state; }
int select(const std::vector<Integer>& weights, Integer value) {
    Integer q = value % std::accumulate(weights.begin(),weights.end(),Integer{}), total = 0;
    for (int j = 0; j < static_cast<int>(weights.size()); ++j) { total += weights[j]; if (q < total) return j; } return -1;
}
