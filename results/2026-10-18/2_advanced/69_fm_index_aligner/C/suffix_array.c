#include "aligner.h"
int symbol_number(char symbol) {
    static const char symbols[] = "$#ACGT";
    return (int)(strchr(symbols, symbol) - symbols);
}
int *counting_sort(const int *positions, int length, const int *keys, int key_count) {
    int *counts = calloc((size_t)key_count, sizeof(int)),
        *out = malloc((size_t)length * sizeof(int));
    for (int i = 0; i < length; ++i)
        ++counts[keys[positions[i]]];
    int offset = 0;
    for (int key = 0; key < key_count; ++key) {
        int count = counts[key];
        counts[key] = offset;
        offset += count;
    }
    for (int i = 0; i < length; ++i) {
        int position = positions[i];
        out[counts[keys[position]]++] = position;
    }
    free(counts);
    return out;
}
SuffixArray suffix_array(const char *text) {
    SuffixArray out = {0};
    int size = out.size = (int)strlen(text);
    int *positions = malloc((size_t)size * sizeof(int)),
        *codes = malloc((size_t)size * sizeof(int)), *ranks = malloc((size_t)size * sizeof(int));
    for (int i = 0; i < size; ++i) {
        positions[i] = i;
        codes[i] = symbol_number(text[i]);
    }
    out.order = counting_sort(positions, size, codes, 6);
    int count = 0, previous = -1;
    for (int i = 0; i < size; ++i) {
        int position = out.order[i];
        if (codes[position] != previous) {
            ++count;
            previous = codes[position];
        }
        ranks[position] = count - 1;
    }
    out.classes[out.class_count++] = count;
    for (int width = 1; count < size; width *= 2) {
        int *second = malloc((size_t)size * sizeof(int));
        for (int i = 0; i < size; ++i)
            second[i] = i + width < size ? ranks[i + width] + 1 : 0;
        int *sorted = counting_sort(positions, size, second, count + 1);
        free(out.order);
        out.order = counting_sort(sorted, size, ranks, count);
        free(sorted);
        int *updated = malloc((size_t)size * sizeof(int));
        count = 0;
        int first = -1, last = -1;
        for (int i = 0; i < size; ++i) {
            int position = out.order[i];
            if (ranks[position] != first || second[position] != last) {
                ++count;
                first = ranks[position];
                last = second[position];
            }
            updated[position] = count - 1;
        }
        free(ranks);
        ranks = updated;
        free(second);
        out.classes[out.class_count++] = count;
    }
    free(positions);
    free(codes);
    free(ranks);
    return out;
}
static const char *sorting_text;
static int suffix_order(const void *left, const void *right) {
    return strcmp(sorting_text + *(const int *)left, sorting_text + *(const int *)right);
}
int *direct_sort(const char *text) {
    int size = (int)strlen(text), *out = malloc((size_t)size * sizeof(int));
    for (int i = 0; i < size; ++i)
        out[i] = i;
    sorting_text = text;
    qsort(out, (size_t)size, sizeof(int), suffix_order);
    return out;
}
Check adjacent_check(const char *text, const int *suffixes, int length) {
    Check out = {0};
    out.maximum = -1;
    out.row = 1;
    for (int row = 1; row < length; ++row) {
        int left = suffixes[row - 1], right = suffixes[row], common = 0;
        while (text[left + common] == text[right + common])
            ++common;
        out.ordered += symbol_number(text[left + common]) < symbol_number(text[right + common]);
        out.lcp_sum += common;
        if (common > out.maximum) {
            out.maximum = common;
            out.row = row;
        }
    }
    return out;
}
