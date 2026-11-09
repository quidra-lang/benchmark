#include <iostream>
#include <string>
#include <array>
#include <algorithm>
#include <vector>

int main() {
    std::array<std::string, 12> words = {"listen", "stone", "night", "silent", "notes", "apple",
        "thing", "enlist", "earth", "onset", "heart", "tones"};
    std::array<std::string, 12> keys = words;
    for (std::string &key : keys)
        std::sort(key.begin(), key.end());
    std::vector<std::vector<int>> groups;
    for (int i = 0; i < 12; ++i) {
        std::size_t g = 0;
        while (g < groups.size() && keys[groups[g][0]] != keys[i]) ++g;
        if (g == groups.size()) groups.emplace_back();
        groups[g].push_back(i);
    }
    for (const std::vector<int> &group : groups) {
        for (std::size_t j = 0; j < group.size(); ++j) {
            if (j) std::cout << ' ';
            std::cout << words[group[j]];
        }
        std::cout << '\n';
    }
}
