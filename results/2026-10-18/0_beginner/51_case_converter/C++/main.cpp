#include <cctype>
#include <iostream>
#include <string>
#include <vector>
#include <array>

int main() {
    for (const std::string &id : std::array<std::string, 6>{"user_name", "maxRetryCount", "ShoppingCartItem",
        "background-color", "get_last_login_time", "isEmailAddressValid"}) {
        std::vector<std::string> words;
        std::string word;
        for (char c : id) {
            if (c == '_' || c == '-' || std::isupper(static_cast<unsigned char>(c))) {
                if (!word.empty()) {
                    words.push_back(word);
                    word.clear();
                }
                if (c == '_' || c == '-')
                    continue;
            }
            word += static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
        }
        if (!word.empty())
            words.push_back(word);
        std::string snake, camel, pascal, kebab;
        for (std::size_t i = 0; i < words.size(); i++) {
            if (i) {
                snake += '_';
                kebab += '-';
            }
            snake += words[i];
            kebab += words[i];
            std::string cap = words[i];
            cap[0] = static_cast<char>(std::toupper(static_cast<unsigned char>(cap[0])));
            pascal += cap;
            camel += i ? cap : words[i];
        }
        std::cout << id << ": snake=" << snake << ", camel=" << camel << ", pascal=" << pascal << ", kebab="
            << kebab << '\n';
    }
}
