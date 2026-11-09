#include "dungeon.hpp"

Integer Minstd::draw() { state = 48271 * state % 2147483647; return state; }
int Minstd::rnd(int limit) { return static_cast<int>(draw() % limit); }
int Minstd::roll(Dice dice) { int total = 0; for (int i = 0; i < dice.count; ++i) total += 1 + rnd(dice.sides); return total; }
int Minstd::select(const std::vector<int>& weights) {
    int sum = 0; for (int weight : weights) sum += weight;
    int selected = static_cast<int>(draw() % sum), cumulative = 0;
    for (int i = 0; i < static_cast<int>(weights.size()); ++i) { cumulative += weights[i]; if (selected < cumulative) return i; }
    return static_cast<int>(weights.size() - 1);
}
