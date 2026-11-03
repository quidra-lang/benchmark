#include "regex.hpp"
bool letter(unsigned char c) { return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'); }
bool digit(unsigned char c) { return c >= '0' && c <= '9'; }
unsigned char swapped(unsigned char c) {
    if (c >= 'A' && c <= 'Z')
        return static_cast<unsigned char>(c + 32);
    if (c >= 'a' && c <= 'z')
        return static_cast<unsigned char>(c - 32);
    return c;
}
CharSet standard_set(unsigned char kind) {
    unsigned char lower = static_cast<unsigned char>(kind | 32);
    CharSet result;
    for (int c = 0; c < 128; ++c) {
        bool present = lower == 'd' ? digit(static_cast<unsigned char>(c))
                       : lower == 'w'
                           ? (letter(static_cast<unsigned char>(c)) ||
                              digit(static_cast<unsigned char>(c)) || c == '_')
                           : (c == 9 || c == 10 || c == 11 || c == 12 || c == 13 || c == 32);
        if (present)
            result.set(static_cast<size_t>(c));
    }
    if (kind >= 'A' && kind <= 'Z')
        result.flip();
    return result;
}
bool char_matches(unsigned char a, unsigned char b, const std::string &flags) {
    return a == b || (flags.find('i') != std::string::npos && letter(a) && swapped(a) == b);
}
bool class_matches(const CharSet &set, bool negated, unsigned char c, const std::string &flags) {
    bool present = set[c] || (flags.find('i') != std::string::npos && letter(c) && set[swapped(c)]);
    return present != negated;
}
bool assertion(const std::string &kind, const std::string &text, int position,
               const std::string &flags) {
    bool multiline = flags.find('m') != std::string::npos;
    int length = static_cast<int>(text.size());
    if (kind == "BOL")
        return position == 0 || (multiline && text[static_cast<size_t>(position - 1)] == '\n');
    if (kind == "EOL")
        return position == length || (multiline && text[static_cast<size_t>(position)] == '\n');
    auto word = [&](int index) {
        if (index < 0 || index >= length)
            return false;
        unsigned char c = static_cast<unsigned char>(text[static_cast<size_t>(index)]);
        return letter(c) || digit(c) || c == '_';
    };
    bool boundary = word(position - 1) != word(position);
    return kind == "WORD" ? boundary : !boundary;
}
bool consumes(const Instruction &instruction, const std::string &text, int position,
              const std::string &flags) {
    if (position >= static_cast<int>(text.size()))
        return false;
    unsigned char c = static_cast<unsigned char>(text[static_cast<size_t>(position)]);
    if (instruction.op == "CHAR")
        return char_matches(c, instruction.character, flags);
    if (instruction.op == "ANY")
        return flags.find('s') != std::string::npos || c != '\n';
    if (instruction.op == "CLASS")
        return class_matches(instruction.set, instruction.negated, c, flags);
    return false;
}
