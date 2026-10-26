#include "image.h"

static int root(int *parents, int value) {
    while (parents[value] != value) {
        parents[value] = parents[parents[value]];
        value = parents[value];
    }
    return value;
}

Labeling label_components(Mask mask, int connectivity) {
    Labeling result = {allocate((size_t)mask.width * mask.height * sizeof(int)), 0, 0};
    int parents[3073] = {0}, numbers[3073] = {0};
    const Point previous4[] = {{-1,0},{0,-1}};
    const Point previous8[] = {{-1,0},{-1,-1},{0,-1},{1,-1}};
    const Point *previous = connectivity == 4 ? previous4 : previous8;
    int neighbor_count = connectivity == 4 ? 2 : 4;
    for (int y = 0; y < mask.height; ++y) {
        for (int x = 0; x < mask.width; ++x) {
            int index = y * mask.width + x;
            if (!mask.pixels[index]) continue;
            int label = 0;
            for (int i = 0; i < neighbor_count; ++i) {
                int nx = x + previous[i].x, ny = y + previous[i].y;
                if (!occupied(mask, nx, ny)) continue;
                int other = result.pixels[ny * mask.width + nx];
                if (!label) label = other;
                else {
                    int first = root(parents, label), second = root(parents, other);
                    if (first > second) parents[first] = second;
                    else parents[second] = first;
                }
            }
            if (!label) { label = ++result.provisional; parents[label] = label; }
            result.pixels[index] = label;
        }
    }
    for (int i = 0; i < mask.width * mask.height; ++i) {
        if (!result.pixels[i]) continue;
        int representative = root(parents, result.pixels[i]);
        if (!numbers[representative]) numbers[representative] = ++result.count;
        result.pixels[i] = numbers[representative];
    }
    return result;
}

int bit_quad_euler(Mask mask, int connectivity) {
    int singles = 0, triples = 0, diagonals = 0;
    for (int y = -1; y < mask.height; ++y) {
        for (int x = -1; x < mask.width; ++x) {
            bool a = occupied(mask, x, y), b = occupied(mask, x + 1, y);
            bool c = occupied(mask, x, y + 1), d = occupied(mask, x + 1, y + 1);
            int count = a + b + c + d;
            if (count == 1) ++singles;
            else if (count == 3) ++triples;
            else if (count == 2 && ((a && d) || (b && c))) ++diagonals;
        }
    }
    return (singles - triples + (connectivity == 8 ? -2 : 2) * diagonals) / 4;
}
