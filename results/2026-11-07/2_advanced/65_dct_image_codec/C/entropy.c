#include "codec.h"
const Pair table_keys[4] = {{0, 0}, {1, 0}, {0, 1}, {1, 1}};
const char *table_names[4] = {"dc_luma", "ac_luma", "dc_chroma", "ac_chroma"};
int category(I value) {
    I magnitude = llabs(value);
    int out = 0;
    while (magnitude) {
        ++out;
        magnitude >>= 1;
    }
    return out;
}
Pair extra_bits(I value) {
    int size = category(value);
    return (Pair){(int)(value >= 0 ? value : value + ((I)1 << size) - 1), size};
}
I amplitude(int bits, int size) {
    if (!size)
        return 0;
    return bits >= (1 << (size - 1)) ? bits : bits - (1 << size) + 1;
}
Huffman huffman(const int counts[16], const int *symbols, int count) {
    Huffman out = {0};
    out.defined = true;
    out.symbol_count = count;
    memcpy(out.counts, counts, sizeof(out.counts));
    memcpy(out.symbols, symbols, (size_t)count * sizeof(int));
    int code = 0, offset = 0;
    for (int length = 1; length <= 16; ++length) {
        for (int i = 0; i < counts[length - 1]; ++i) {
            int symbol = symbols[offset++];
            out.lengths[symbol] = length;
            out.codes[symbol] = code++;
        }
        code *= 2;
    }
    return out;
}
Huffman optimized_table(const I frequencies[256]) {
    I freq[257] = {0};
    memcpy(freq, frequencies, 256 * sizeof(I));
    freq[256] = 1;
    int sizes[257] = {0}, others[257];
    for (int i = 0; i <= 256; ++i)
        others[i] = -1;
    while (true) {
        int first = -1, second = -1;
        for (int i = 0; i <= 256; ++i)
            if (freq[i] > 0 &&
                (first < 0 || freq[i] < freq[first] || (freq[i] == freq[first] && i > first)))
                first = i;
        for (int i = 0; i <= 256; ++i)
            if (i != first && freq[i] > 0 &&
                (second < 0 || freq[i] < freq[second] || (freq[i] == freq[second] && i > second)))
                second = i;
        if (second < 0)
            break;
        freq[first] += freq[second];
        freq[second] = 0;
        ++sizes[first];
        while (others[first] != -1) {
            first = others[first];
            ++sizes[first];
        }
        others[first] = second;
        ++sizes[second];
        while (others[second] != -1) {
            second = others[second];
            ++sizes[second];
        }
    }
    int counts[257] = {0}, longest = 0;
    for (int i = 0; i <= 256; ++i)
        if (sizes[i]) {
            ++counts[sizes[i]];
            if (sizes[i] > longest)
                longest = sizes[i];
        }
    for (int length = longest; length >= 17; --length)
        while (counts[length] > 0) {
            int shorter = length - 2;
            while (counts[shorter] == 0)
                --shorter;
            counts[length] -= 2;
            ++counts[length - 1];
            counts[shorter + 1] += 2;
            --counts[shorter];
        }
    longest = 16;
    while (counts[longest] == 0)
        --longest;
    --counts[longest];
    int symbols[256], symbol_count = 0, result[16];
    for (int size = 1; size <= 256; ++size)
        for (int symbol = 0; symbol < 256; ++symbol)
            if (sizes[symbol] == size)
                symbols[symbol_count++] = symbol;
    for (int length = 1; length <= 16; ++length)
        result[length - 1] = counts[length];
    return huffman(result, symbols, symbol_count);
}
