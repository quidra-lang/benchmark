#include "typesetting.hpp"
void register_word(Dictionary &dictionary, const std::string &word) {
    std::string key;
    std::vector<int> positions;
    for (char c : word) {
        if (c == '-')
            positions.push_back(key.size());
        else
            key += c;
    }
    dictionary[key] = positions;
}
std::vector<SplitPoint> split_points(const Dictionary &dictionary, const std::string &word,
                                     const Params &params) {
    std::vector<SplitPoint> out;
    std::size_t first = 0, last = word.size();
    while (first < last && !letter(word[first]))
        ++first;
    while (last > first && !letter(word[last - 1]))
        --last;
    const std::string core = word.substr(first, last - first);
    if (!core.empty() && std::all_of(core.begin(), core.end(), letter)) {
        const auto found = dictionary.find(lower(core));
        if (found != dictionary.end())
            for (int position : found->second)
                if (position >= params.at("left_min") &&
                    Integer(core.size()) - position >= params.at("right_min"))
                    out.push_back({int(first) + position, true});
    }
    for (std::size_t i = 1; i + 1 < word.size(); ++i)
        if (word[i] == '-' && letter(word[i - 1]) && letter(word[i + 1]))
            out.push_back({int(i + 1), false});
    std::sort(out.begin(), out.end(), [](SplitPoint a, SplitPoint b) { return a.position < b.position; });
    return out;
}
