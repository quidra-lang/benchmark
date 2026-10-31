#include <iostream>
#include <string>
#include <array>
#include <algorithm>

int main() {
    std::array<std::string, 12> words = {"listen", "stone", "night", "silent", "notes", "apple",
        "thing", "enlist", "earth", "onset", "heart", "tones"};
    std::array<std::string, 12> keys = words;
    std::array<bool, 12> used{};
    for (std::string &key : keys)
        std::sort(key.begin(), key.end());
    for (int i = 0; i < 12; i++)
        if (!used[i]) {
            bool first = true;
            for (int j = i; j < 12; j++)
                if (!used[j] && keys[j] == keys[i]) {
                    if (!first)
                        std::cout << ' ';
                    std::cout << words[j];
                    first = false;
                    used[j] = true;
                }
            std::cout << '\n';
        }
}
