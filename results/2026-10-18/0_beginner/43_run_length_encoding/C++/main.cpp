#include <iostream>
#include <string>
#include <array>

int main() {
    for (const std::string &s : std::array<std::string, 5>{"AAABBBCCCD", "WWWWWWWWWWWWBWWWWWWWWWWWWBBB",
        "ALGORITHM", "MISSISSIPPI", "XXXXXXXXXXYYYYYYYYYYYYYYYYYYYYYZ"}) {
        std::string encoded, decoded;
        for (std::size_t i = 0; i < s.size();) {
            std::size_t j = i + 1;
            while (j < s.size() && s[j] == s[i])
                j++;
            encoded += std::to_string(j - i) + s[i];
            i = j;
        }
        for (std::size_t i = 0; i < encoded.size();) {
            int count = 0;
            while (encoded[i] >= '0' && encoded[i] <= '9')
                count = count * 10 + encoded[i++] - '0';
            char c = encoded[i++];
            decoded.append(count, c);
        }
        std::cout << s << " -> " << encoded << " -> " << decoded << '\n';
    }
}
