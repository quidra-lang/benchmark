#include "phylogeny.hpp"
int base_index(char character) {
    std::string bases = "ACGT";
    std::size_t at = bases.find(character);
    return at == std::string::npos ? -1 : int(at);
}
unsigned base_set(char character) {
    switch (character) {
    case 'A':
        return 1;
    case 'C':
        return 2;
    case 'G':
        return 4;
    case 'T':
        return 8;
    case 'R':
        return 5;
    case 'Y':
        return 10;
    case 'S':
        return 6;
    case 'W':
        return 9;
    case 'K':
        return 12;
    case 'M':
        return 3;
    case 'B':
        return 14;
    case 'D':
        return 13;
    case 'H':
        return 11;
    case 'V':
        return 7;
    case 'N':
    case '-':
        return 15;
    default:
        return 0;
    }
}
std::vector<Record> read_fasta() {
    std::ifstream input("input/alignment.fasta");
    std::vector<Record> out;
    std::string text;
    int number = 0;
    while (std::getline(input, text)) {
        ++number;
        if (text[0] == '>') {
            std::size_t space = text.find(' ');
            out.push_back(
                {number, text.substr(1, space == std::string::npos ? space : space - 1), ""});
        } else
            for (unsigned char c : text)
                out.back().sequence += char(std::toupper(c));
    }
    return out;
}
Patterns::Patterns(const Names &sequences) {
    std::map<std::string, int> lookup;
    for (int c = 0; c < int(sequences[0].size()); ++c) {
        std::string pattern;
        for (const std::string &sequence : sequences)
            pattern += sequence[c];
        auto found = lookup.emplace(pattern, int(text.size()));
        int index = found.first->second;
        if (found.second) {
            text.push_back(pattern);
            weights.push_back(0);
            std::array<unsigned, 16> values{};
            for (int t = 0; t < int(pattern.size()); ++t)
                values[t] = base_set(pattern[t]);
            encoded.push_back(values);
        }
        columns.push_back(index);
        ++weights[index];
    }
}
Classes classify(const Names &sequences) {
    Classes out;
    for (int c = 0; c < int(sequences[0].size()); ++c) {
        int counts[4] = {}, kinds = 0, multiple = 0;
        bool gapped = false;
        for (const std::string &sequence : sequences) {
            int index = base_index(sequence[c]);
            if (index >= 0)
                ++counts[index];
            gapped |= sequence[c] == '-';
        }
        for (int count : counts) {
            kinds += count > 0;
            multiple += count >= 2;
        }
        out.empty += kinds == 0;
        out.constant += kinds == 1;
        out.variable += kinds >= 2;
        out.informative += multiple >= 2;
        out.gapped += gapped;
    }
    return out;
}
