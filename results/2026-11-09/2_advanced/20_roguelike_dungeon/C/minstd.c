#include "dungeon.h"

long long draw(Minstd *rng) { rng->state = (48271 * rng->state) % 2147483647; return rng->state; }
int rnd(Minstd *rng, int limit) { return (int)(draw(rng) % limit); }

int roll_dice(Minstd *rng, Dice dice) {
    int total = 0;
    for (int i = 0; i < dice.count; ++i) total += 1 + rnd(rng, dice.sides);
    return total;
}

int select_weight(Minstd *rng, const int *weights, int count) {
    int total = 0;
    for (int i = 0; i < count; ++i) total += weights[i];
    int value = rnd(rng, total), cumulative = 0;
    for (int i = 0; i < count; ++i) { cumulative += weights[i]; if (value < cumulative) return i; }
    return count - 1;
}
