#include <iostream>
#include <string>
#include <array>

int main() {
    const std::string sentence = "Peter Piper picked a peck of pickled peppers!";
    std::array<int, 26> counts {
    };
    for (char c : sentence) {
        if (c >= 'A' && c <= 'Z')
            c = static_cast<char>(c - 'A' + 'a');
        if (c >= 'a' && c <= 'z')
            ++counts[c - 'a'];
    }
    for (int i = 0; i < 26; i++)
        if (counts[i])
            std::cout << static_cast<char>('a' + i) << ": " << counts[i] << '\n';
}
