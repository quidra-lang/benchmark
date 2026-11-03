#include <cctype>
#include <iostream>
#include <string>
#include <array>

int main() {
    std::string sentence = "Peter Piper picked a peck of pickled peppers!";
    std::array<int, 26> counts{};
    for (unsigned char c : sentence) {
        if (std::isalpha(c)) ++counts[std::tolower(c) - 'a'];
    }
    for (int i = 0; i < 26; i++)
        if (counts[i])
            std::cout << static_cast<char>('a' + i) << ": " << counts[i] << '\n';
}
