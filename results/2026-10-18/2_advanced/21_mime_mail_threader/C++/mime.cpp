#include "mail.hpp"

int hexValue(char character) {
    if (character >= '0' && character <= '9') return character - '0';
    if (character >= 'a' && character <= 'f') return character - 'a' + 10;
    if (character >= 'A' && character <= 'F') return character - 'A' + 10;
    return -1;
}
std::optional<std::string> strictBase64(const std::string& value) {
    if (value.size() % 4) return std::nullopt;
    std::size_t length = value.size();
    while (length && value[length - 1] == '=') --length;
    if (value.size() - length >= 3) return std::nullopt;
    const std::string alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    int buffer = 0, bits = 0;
    std::string result;
    for (std::size_t i = 0; i < length; ++i) {
        std::size_t position = alphabet.find(value[i]);
        if (position == std::string::npos) return std::nullopt;
        buffer = (buffer << 6) | static_cast<int>(position); bits += 6;
        if (bits >= 8) { bits -= 8; result += static_cast<char>(buffer >> bits); buffer &= (1 << bits) - 1; }
    }
    return result;
}
std::optional<std::string> decodeBase64Body(const std::string& value) {
    std::string compact;
    for (char character : value) if (!whitespace(character) && character != '\n') compact += character;
    std::optional<std::string> decoded = strictBase64(compact);
    if (!decoded) return std::nullopt;
    std::string result;
    for (std::size_t i = 0; i < decoded->size(); ++i) {
        unsigned char character = static_cast<unsigned char>((*decoded)[i]);
        if (character == 13 && i + 1 < decoded->size() && (*decoded)[i + 1] == '\n') { character = 10; ++i; }
        if (character != 9 && character != 10 && (character < 32 || character > 126)) return std::nullopt;
        result += static_cast<char>(character);
    }
    return result;
}
std::pair<std::string, bool> decodeQuotedPrintable(const std::string& value) {
    Lines lines = split(value, '\n'); std::string result; bool error = false;
    for (std::size_t i = 0; i < lines.size(); ++i) {
        std::string line = stripTrailing(lines[i]); bool soft = !line.empty() && line.back() == '=';
        if (soft) line.pop_back();
        for (std::size_t position = 0; position < line.size();) {
            if (line[position] == '=' && position + 2 < line.size()) {
                int first = hexValue(line[position + 1]), second = hexValue(line[position + 2]);
                int decoded = 16 * first + second;
                if (first >= 0 && second >= 0 && (decoded == 9 || (decoded >= 32 && decoded <= 126))) { result += static_cast<char>(decoded); position += 3; continue; }
            }
            error = error || line[position] == '='; result += line[position++];
        }
        if (!soft && i + 1 < lines.size()) result += '\n';
    }
    return {result, error};
}
