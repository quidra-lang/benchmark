#include <iostream>
#include <string>
#include <array>
#include <algorithm>

int main() {
    for (const std::string &phrase : std::array<std::string, 6>{"Never odd or even", "Race a car", "Was it a car or a cat I saw?",
        "Hello, World!", "Step on no pets.", "No lemon, no melon"}) {
        std::string clean;
        for (char c : phrase) {
            if (c >= 'A' && c <= 'Z')
                c = static_cast<char>(c - 'A' + 'a');
            if (c >= 'a' && c <= 'z')
                clean += c;
        }
        bool yes = std::equal(clean.begin(), clean.end(), clean.rbegin());
        std::cout << phrase << " -> " << (yes ? "yes" : "no") << '\n';
    }
}
