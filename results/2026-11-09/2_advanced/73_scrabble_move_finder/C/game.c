#include "scrabble.h"
int64_t random_next(Minstd *random) {
    random->state = 48271 * random->state % 2147483647;
    return random->state;
}
void shuffle(Bag *bag, Minstd *random) {
    for (int i = bag->count - 1; i >= 1; --i) {
        int j = (int)(random_next(random) % (i + 1));
        char tile = bag->tiles[i];
        bag->tiles[i] = bag->tiles[j];
        bag->tiles[j] = tile;
    }
}
Bag make_bag(const Counts counts, Minstd *random) {
    Bag out = {0};
    for (int tile = 0; tile < 27; ++tile)
        for (int i = 0; i < counts[tile]; ++i)
            out.tiles[out.count++] = tile_order[tile];
    shuffle(&out, random);
    return out;
}
void draw(Bag *bag, int count, char *out) {
    int n = 0;
    while (count-- > 0 && bag->count > 0)
        out[n++] = bag->tiles[--bag->count];
    out[n] = 0;
}
void exchange(Bag *bag, const char *returned, Minstd *random, char *drawn) {
    int counts[128] = {0}, n = (int)strlen(returned);
    draw(bag, n, drawn);
    for (int i = 0; i < n; ++i)
        ++counts[(unsigned char)returned[i]];
    for (int tile = 0; tile < 128; ++tile)
        for (int i = 0; i < counts[tile]; ++i)
            bag->tiles[bag->count++] = (char)tile;
    shuffle(bag, random);
}
int points(const char *collection, const Counts values) {
    int out = 0;
    while (*collection)
        out += values[tile_index(*collection++)];
    return out;
}
