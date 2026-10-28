#include "scheduler.h"
Integer draw(Minstd *random) {
    random->state = 48271 * random->state % 2147483647;
    return random->state;
}
int below(Minstd *random, int limit) {
    return (int)(draw(random) % limit);
}
bool chance(Minstd *random, int numerator, int denominator) {
    return below(random, denominator) < numerator;
}
void shuffle(Minstd *random, Chromosome *genes) {
    for (int length = genes->count; length > 1; --length) {
        int index = below(random, length), value = genes->ids[length - 1];
        genes->ids[length - 1] = genes->ids[index];
        genes->ids[index] = value;
    }
}
