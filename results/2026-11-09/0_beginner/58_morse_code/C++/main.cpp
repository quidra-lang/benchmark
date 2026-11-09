#include <iostream>
#include <string>
#include <array>
#include <algorithm>
#include <sstream>

int main() {
    const std::string symbols = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", message = "MEET ME AT PIER 9 AT 1745";
    const std::array<std::string, 36> codes = {".-", "-...", "-.-.", "-..", ".", "..-.", "--.", "....",
        "..", ".---", "-.-", ".-..", "--", "-.", "---", ".--.", "--.-", ".-.", "...", "-", "..-", "...-",
        ".--", "-..-", "-.--", "--..", "-----", ".----", "..---", "...--", "....-", ".....", "-....", "--...",
        "---..", "----."};
    std::string encoded;
    for (std::size_t i = 0; i < message.size(); i++) {
        if (message[i] == ' ') {
            encoded += " / ";
            continue;
        }
        if (i && message[i - 1] != ' ')
            encoded += ' ';
        encoded += codes[symbols.find(message[i])];
    }
    std::cout << encoded << '\n';
    std::istringstream input(encoded);
    std::string decoded;
    for (std::string token; input >> token;) {
        if (token == "/")
            decoded += ' ';
        else
            decoded += symbols[std::find(codes.begin(), codes.end(), token) - codes.begin()];
    }
    std::cout << decoded << '\n';
}
