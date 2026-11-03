#include "codec.hpp"
const std::array<Key, 4> table_keys{{{0, 0}, {1, 0}, {0, 1}, {1, 1}}};
const std::array<std::string, 4> table_names{"dc_luma", "ac_luma", "dc_chroma", "ac_chroma"};
int category(I value) {
    I magnitude = std::llabs(value);
    int out = 0;
    while (magnitude) {
        ++out;
        magnitude >>= 1;
    }
    return out;
}
Key extra_bits(I value) {
    int size = category(value);
    return {int(value >= 0 ? value : value + (I(1) << size) - 1), size};
}
I amplitude(int bits, int size) {
    if (!size)
        return 0;
    return bits >= (1 << (size - 1)) ? bits : bits - (1 << size) + 1;
}
Huffman::Huffman(std::array<int, 16> counts, Bytes symbols)
    : counts(counts), symbols(std::move(symbols)) {
    int code = 0, offset = 0;
    for (int length = 1; length <= 16; ++length) {
        for (int i = 0; i < counts[length - 1]; ++i) {
            int symbol = this->symbols[offset++];
            lengths[symbol] = length;
            codes[symbol] = code++;
        }
        code *= 2;
    }
}
Huffman optimized_table(const std::array<I, 256> &frequencies) {
    std::array<I, 257> freq{};
    std::copy(frequencies.begin(), frequencies.end(), freq.begin());
    freq[256] = 1;
    std::array<int, 257> sizes{}, others{};
    others.fill(-1);
    while (true) {
        std::vector<int> available;
        for (int symbol = 0; symbol <= 256; ++symbol)
            if (freq[symbol] > 0)
                available.push_back(symbol);
        if (available.size() < 2)
            break;
        std::sort(available.begin(), available.end(),
                  [&](int a, int b) { return freq[a] != freq[b] ? freq[a] < freq[b] : a > b; });
        int first = available[0], second = available[1];
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
    std::array<int, 257> counts{};
    int longest = 0;
    for (int size : sizes)
        if (size) {
            ++counts[size];
            longest = std::max(longest, size);
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
    Bytes symbols;
    for (int symbol = 0; symbol < 256; ++symbol)
        if (sizes[symbol] > 0)
            symbols.push_back(symbol);
    std::sort(symbols.begin(), symbols.end(),
              [&](int a, int b) { return sizes[a] != sizes[b] ? sizes[a] < sizes[b] : a < b; });
    std::array<int, 16> result{};
    for (int length = 1; length <= 16; ++length)
        result[length - 1] = counts[length];
    return Huffman(result, symbols);
}
