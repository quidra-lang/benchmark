#include <cctype>
#include <iostream>
#include <string>
#include <array>
#include <algorithm>

int main() {
    const std::array<std::string, 6> phrases = {
        "Never odd or even", "Race a car", "Was it a car or a cat I saw?", "Hello, World!",
        "Step on no pets.", "No lemon, no melon"};
    for (const std::string &phrase : phrases) {
        std::string clean;
        for (unsigned char c : phrase) {
            if (std::isalpha(c)) clean += static_cast<char>(std::tolower(c));
        }
        bool yes = std::equal(clean.begin(), clean.end(), clean.rbegin());
        std::cout << phrase << " -> " << (yes ? "yes" : "no") << '\n';
    }
}
