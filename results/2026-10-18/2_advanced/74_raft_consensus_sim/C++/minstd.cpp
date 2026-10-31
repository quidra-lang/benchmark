#include "raft.hpp"
int Minstd::draw() {
    state = 48271 * state % 2147483647;
    ++draws;
    return int(state);
}
int Minstd::between(int minimum, int maximum) { return minimum + draw() % (maximum - minimum + 1); }
