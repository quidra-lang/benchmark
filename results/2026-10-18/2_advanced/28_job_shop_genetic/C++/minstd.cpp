#include "scheduler.hpp"
Integer Minstd::draw() {
    state = 48271 * state % 2147483647;
    return state;
}
int Minstd::below(int limit) {
    return int(draw() % limit);
}
bool Minstd::chance(std::pair<int, int> probability) {
    return below(probability.second) < probability.first;
}
void Minstd::shuffle(Chromosome &genes) {
    for (std::size_t length = genes.size(); length > 1; --length)
        std::swap(genes[length - 1], genes[below(int(length))]);
}
