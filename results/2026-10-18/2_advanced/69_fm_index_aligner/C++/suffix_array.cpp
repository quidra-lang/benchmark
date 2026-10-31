#include "aligner.hpp"
int symbol_number(char symbol) { return int(std::string("$#ACGT").find(symbol)); }
std::vector<int> counting_sort(const std::vector<int> &positions, const std::vector<int> &keys,
                               int key_count) {
    std::vector<int> counts(key_count), out(positions.size());
    for (int position : positions)
        ++counts[keys[position]];
    int offset = 0;
    for (int &count : counts) {
        int size = count;
        count = offset;
        offset += size;
    }
    for (int position : positions)
        out[counts[keys[position]]++] = position;
    return out;
}
SuffixArray suffix_array(const std::string &text) {
    int size = int(text.size());
    std::vector<int> positions(size), codes(size);
    std::iota(positions.begin(), positions.end(), 0);
    for (int i = 0; i < size; ++i)
        codes[i] = symbol_number(text[i]);
    SuffixArray out;
    out.order = counting_sort(positions, codes, 6);
    std::vector<int> ranks(size);
    int count = 0, previous = -1;
    for (int position : out.order) {
        if (codes[position] != previous) {
            ++count;
            previous = codes[position];
        }
        ranks[position] = count - 1;
    }
    out.classes.push_back(count);
    for (int width = 1; count < size; width *= 2) {
        std::vector<int> second(size);
        for (int i = 0; i < size; ++i)
            second[i] = i + width < size ? ranks[i + width] + 1 : 0;
        out.order = counting_sort(counting_sort(positions, second, count + 1), ranks, count);
        std::vector<int> updated(size);
        count = 0;
        std::pair<int, int> previous_key = {-1, -1};
        for (int position : out.order) {
            std::pair<int, int> key = {ranks[position], second[position]};
            if (key != previous_key) {
                ++count;
                previous_key = key;
            }
            updated[position] = count - 1;
        }
        ranks = std::move(updated);
        out.classes.push_back(count);
    }
    return out;
}
std::vector<int> direct_sort(const std::string &text) {
    std::vector<int> out(text.size());
    std::iota(out.begin(), out.end(), 0);
    std::sort(out.begin(), out.end(), [&](int a, int b) {
        return text.compare(a, std::string::npos, text, b, std::string::npos) < 0;
    });
    return out;
}
Check adjacent_check(const std::string &text, const std::vector<int> &suffixes) {
    Check out;
    for (int row = 1; row < int(suffixes.size()); ++row) {
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
