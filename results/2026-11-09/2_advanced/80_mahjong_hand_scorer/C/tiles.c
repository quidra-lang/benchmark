#include "mahjong.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void *checked_realloc(void *memory, size_t size) {
    void *result = realloc(memory, size);
    if (!result && size) {
        fputs("allocation failed\n", stderr);
        exit(EXIT_FAILURE);
    }
    return result;
}
bool parse_tiles(const char *text, bool allow_empty, Tiles *out) {
    *out = (Tiles){0};
    if (allow_empty && strcmp(text, "-") == 0)
        return true;
    if (!*text || strcmp(text, "-") == 0)
        return false;
    for (size_t i = 0; text[i];) {
        size_t start = i;
        while (text[i] >= '0' && text[i] <= '9')
            ++i;
        if (i == start || !text[i])
            return false;
        static const char suits[] = "mpsz";
        const char *found = strchr(suits, text[i]);
        if (!found)
            return false;
        int suit = (int)(found - suits);
        for (size_t j = start; j < i; ++j) {
            int rank = text[j] - '0';
            bool red = rank == 0;
            if (suit == 3) {
                if (rank < 1 || rank > 7)
                    return false;
            } else if (red)
                rank = 5;
            ++out->counts.values[9 * suit + rank - 1];
            ++out->size;
            if (red)
                ++out->reds[suit];
        }
        ++i;
    }
    return true;
}
Tiles combine_tiles(Tiles a, Tiles b) {
    for (int i = 0; i < 34; ++i)
        a.counts.values[i] += b.counts.values[i];
    for (int i = 0; i < 3; ++i)
        a.reds[i] += b.reds[i];
    a.size += b.size;
    return a;
}
Tiles add_kind(Tiles tiles, int kind) {
    ++tiles.counts.values[kind];
    ++tiles.size;
    return tiles;
}
void tile_name(int kind, char out[3]) {
    out[0] = (char)('1' + kind % 9);
    out[1] = "mpsz"[kind / 9];
    out[2] = 0;
}
void block_notation(int kind, int size, bool sequence, char out[6]) {
    for (int i = 0; i < size; ++i)
        out[i] = (char)('1' + kind % 9 + (sequence ? i : 0));
    out[size] = "mpsz"[kind / 9];
    out[size + 1] = 0;
}
void block_name(Block block, char out[6]) {
    block_notation(block.kind, block.kan ? 4 : 3, block.sequence, out);
}
bool honor(int kind) { return kind >= 27; }
bool terminal(int kind) { return kind < 27 && (kind % 9 == 0 || kind % 9 == 8); }
bool yaochuu(int kind) { return honor(kind) || terminal(kind); }
int next_dora(int kind) {
    if (kind < 27)
        return kind / 9 * 9 + (kind % 9 + 1) % 9;
    if (kind < 31)
        return 27 + (kind - 27 + 1) % 4;
    return 31 + (kind - 31 + 1) % 3;
}
