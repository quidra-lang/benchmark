#include "image.h"

static const Point neighborhood[8] = {{0,-1},{1,-1},{1,0},{1,1},{0,1},{-1,1},{-1,0},{-1,-1}};

Mask new_mask(int width, int height) { return (Mask){width, height, allocate((size_t)width * height * sizeof(bool))}; }
bool occupied(Mask mask, int x, int y) { return x >= 0 && x < mask.width && y >= 0 && y < mask.height && mask.pixels[y * mask.width + x]; }

Mask erode(Mask mask, const Point *offsets, int count) {
    Mask result = new_mask(mask.width, mask.height);
    for (int y = 0; y < mask.height; ++y) {
        for (int x = 0; x < mask.width; ++x) {
            bool value = true;
            for (int i = 0; i < count; ++i) if (!occupied(mask, x + offsets[i].x, y + offsets[i].y)) { value = false; break; }
            result.pixels[y * mask.width + x] = value;
        }
    }
    return result;
}

Mask dilate(Mask mask, const Point *offsets, int count) {
    Mask result = new_mask(mask.width, mask.height);
    for (int y = 0; y < mask.height; ++y) {
        for (int x = 0; x < mask.width; ++x) {
            bool value = false;
            for (int i = 0; i < count; ++i) if (occupied(mask, x - offsets[i].x, y - offsets[i].y)) { value = true; break; }
            result.pixels[y * mask.width + x] = value;
        }
    }
    return result;
}

Mask opening(Mask mask, const Point *offsets, int count) { return dilate(erode(mask, offsets, count), offsets, count); }
Mask closing(Mask mask, const Point *offsets, int count) { return erode(dilate(mask, offsets, count), offsets, count); }

static int bits_at(Mask mask, int x, int y, bool *bits) {
    int count = 0;
    for (int i = 0; i < 8; ++i) { bits[i] = occupied(mask, x + neighborhood[i].x, y + neighborhood[i].y); count += bits[i]; }
    return count;
}

static int transitions(const bool *bits) {
    int count = 0;
    for (int i = 0; i < 8; ++i) if (!bits[i] && bits[(i + 1) % 8]) ++count;
    return count;
}

int crossing_number(Mask mask, int x, int y) {
    bool bits[8];
    bits_at(mask, x, y, bits);
    return transitions(bits);
}

static bool thinning_step(Mask mask, bool first) {
    bool removed[3072] = {false}, changed = false;
    for (int y = 0; y < mask.height; ++y) {
        for (int x = 0; x < mask.width; ++x) {
            int index = y * mask.width + x;
            if (!mask.pixels[index]) continue;
            bool bits[8];
            int count = bits_at(mask, x, y, bits);
            if (count < 2 || count > 6 || transitions(bits) != 1) continue;
            bool p2 = bits[0], p4 = bits[2], p6 = bits[4], p8 = bits[6];
            bool blocked = first ? (p2 && p4 && p6) || (p4 && p6 && p8) : (p2 && p4 && p8) || (p2 && p6 && p8);
            if (!blocked) { removed[index] = true; changed = true; }
        }
    }
    for (int i = 0; i < mask.width * mask.height; ++i) if (removed[i]) mask.pixels[i] = false;
    return changed;
}

Mask thin(Mask mask) {
    Mask result = new_mask(mask.width, mask.height);
    memcpy(result.pixels, mask.pixels, (size_t)mask.width * mask.height * sizeof(bool));
    while (true) {
        bool first = thinning_step(result, true);
        bool second = thinning_step(result, false);
        if (!first && !second) return result;
    }
}
