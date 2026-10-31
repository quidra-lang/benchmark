#include "raft.h"
int random_draw(Minstd *random) {
    random->state = 48271 * random->state % 2147483647;
    ++random->draws;
    return (int)random->state;
}
int random_between(Minstd *random, int minimum, int maximum) {
    return minimum + random_draw(random) % (maximum - minimum + 1);
}
