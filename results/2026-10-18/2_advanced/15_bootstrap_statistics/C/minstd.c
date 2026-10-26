#include "statistics.h"

Integer draw(Minstd *generator) {
    generator->state = 48271 * generator->state % 2147483647;
    return generator->state;
}
int below(Minstd *generator, int limit) { return (int)(draw(generator) % limit); }
void shuffle(Minstd *generator, int *values, int count) {
    for (int i = count; i > 1; --i) {
        int j = below(generator, i), saved = values[i - 1];
        values[i - 1] = values[j];
        values[j] = saved;
    }
}
