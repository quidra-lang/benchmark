#include <iostream>
#include <string>
#include <array>

int main() {
    const std::string alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    for (const std::string &s : std::array<std::string, 5>{"Man", "Hello, World!", "", "<b>bold</b>",
        "a+b=c?"}) {
        std::string encoded;
        for (std::size_t i = 0; i < s.size(); i += 3) {
            std::size_t remain = s.size() - i;
            unsigned bits = static_cast<unsigned char>(s[i]) << 16;
            if (remain > 1)
                bits |= static_cast<unsigned>(static_cast<unsigned char>(s[i + 1])) << 8;
            if (remain > 2)
                bits |= static_cast<unsigned char>(s[i + 2]);
            encoded += alphabet[(bits >> 18) &63];
            encoded += alphabet[(bits >> 12) &63];
            encoded += remain > 1 ? alphabet[(bits >> 6) &63] : '=';
            encoded += remain > 2 ? alphabet[bits &63] : '=';
        }
        std::cout << '"' << s << "\" -> \"" << encoded << "\"\n";
    }
}
