#include <iostream>
#include <string>

void cipher(std::string &s, int shift) {
    for (char &c : s) {
        if (c >= 'a' && c <= 'z')
            c = static_cast<char>('a' + (c - 'a' + shift) % 26);
        else if (c >= 'A' && c <= 'Z')
            c = static_cast<char>('A' + (c - 'A' + shift) % 26);
    }
}

int main() {
    std::string message = "Zoe, meet Max by the Old Bridge at six!";
    cipher(message, 3);
    std::cout << message << '\n';
    cipher(message, 23);
    std::cout << message << '\n';
}
