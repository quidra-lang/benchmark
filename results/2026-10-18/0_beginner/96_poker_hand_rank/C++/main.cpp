#include <iostream>
#include <string>
#include <vector>
#include <array>
#include <algorithm>

struct Hand {
    std::string text;
    int category;
    std::vector<int> key;
};
Hand evaluate(const std::string &text) {
    const std::string ranks = "23456789TJQKA";
    std::array<int, 15> counts {};
    bool flush = true;
    for (int i = 0; i < 5; i++) {
        int rank = static_cast<int>(ranks.find(text[i * 3])) + 2;
        ++counts[rank];
        if (text[i * 3 + 1] != text[1])
            flush = false;
    }
    Hand h {
        text, 0, {}
    };
    int maximum = 0, pairs = 0;
    for (int r = 14; r >= 2; r--)
        if (counts[r]) {
            h.key.push_back(r);
            maximum = std::max(maximum, counts[r]);
            if (counts[r] == 2)
                ++pairs;
        }
    bool wheel = h.key.size() == 5 && counts[14] && counts[2] && counts[3] && counts[4] && counts[5];
    bool straight = h.key.size() == 5 && (h.key[0] - h.key[4] == 4 || wheel);
    h.category = straight && flush ? 8
               : maximum == 4 ? 7
               : maximum == 3 && pairs == 1 ? 6
               : flush ? 5
               : straight ? 4
               : maximum == 3 ? 3
               : pairs == 2 ? 2
               : pairs == 1 ? 1 : 0;
    std::sort(h.key.begin(), h.key.end(), [&counts](int a, int b) {
        return counts[a] != counts[b] ? counts[a] > counts[b] : a > b;
    });
    if (wheel && straight)
        for (int i = 0; i < 5; i++)
            h.key[i] = 5 - i;
    return h;
}

int main() {
    std::vector<Hand> hands;
    for (const std::string &text : std::array<std::string, 8>{"9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S",
        "7H 7D KC 7S KD", "3H 6C 4S 2D 5C", "JD TC 4H 8C AS", "QC 6D QS 3S 6H", "9H KH 9S 8H 3D"})
        hands.push_back(evaluate(text));
    std::sort(hands.begin(), hands.end(), [](const Hand &a, const Hand &b) {
        return a.category != b.category ? a.category > b.category : a.key > b.key;
    });
    const std::array<std::string, 9> categories = {"high card", "one pair", "two pair", "three of a kind",
        "straight", "flush", "full house", "four of a kind", "straight flush"};
    for (std::size_t i = 0; i < hands.size(); i++)
        std::cout << i + 1 << ". " << hands[i].text << ": " << categories[hands[i].category] << '\n';
}
