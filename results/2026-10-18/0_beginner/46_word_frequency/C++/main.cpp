#include <iostream>
#include <string>
#include <vector>
#include <algorithm>
#include <map>
#include <sstream>

int main() {
    std::string text = "The cat sat on the mat. The dog sat on the rug, and the cat watched the dog. A bird sang on the fence, and the Dog barked at the bird. The cat slept in the sun, the bird flew away, and the dog sat by the door.";
    for (char &c : text) {
        if (c >= 'A' && c <= 'Z')
            c = static_cast<char>(c - 'A' + 'a');
        else if (c < 'a' || c > 'z')
            c = ' ';
    }
    std::map<std::string, int> counts;
    std::istringstream input(text);
    for (std::string w; input >> w;)
        ++counts[w];
    std::vector<std::pair<std::string, int>> entries(counts.begin(), counts.end());
    std::sort(entries.begin(), entries.end(), [](const std::pair<std::string, int> &a, const std::pair<std::string,
        int> &b) {
        return a.second != b.second ? a.second > b.second : a.first < b.first;
    });
    for (int i = 0; i < 5; i++)
        std::cout << entries[i].first << ": " << entries[i].second << '\n';
    std::cout << "distinct words: " << counts.size() << '\n';
}
