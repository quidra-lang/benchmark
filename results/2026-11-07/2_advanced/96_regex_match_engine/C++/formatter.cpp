#include "regex.hpp"
std::string character_display(unsigned char c) {
    if (c >= 33 && c <= 126 && c != '\\' && c != ']' && c != '^' && c != '-')
        return std::string(1, static_cast<char>(c));
    const char *digits = "0123456789ABCDEF";
    std::string result = "\\x";
    result += digits[c / 16];
    result += digits[c % 16];
    return result;
}
std::string set_notation(const CharSet &set, bool negated) {
    std::string result = negated ? "[^" : "[";
    for (int i = 0; i < 128;) {
        if (!set[static_cast<size_t>(i)]) {
            ++i;
            continue;
        }
        int end = i;
        while (end + 1 < 128 && set[static_cast<size_t>(end + 1)])
            ++end;
        result += character_display(static_cast<unsigned char>(i));
        if (end == i + 1)
            result += character_display(static_cast<unsigned char>(end));
        else if (end >= i + 2)
            result += "-" + character_display(static_cast<unsigned char>(end));
        i = end + 1;
    }
    return result + "]";
}
std::string instruction_notation(const Instruction &instruction) {
    if (instruction.op == "CHAR")
        return "CHAR " + character_display(instruction.character);
    if (instruction.op == "CLASS")
        return "CLASS " + set_notation(instruction.set, instruction.negated);
    if (instruction.op == "SPLIT")
        return "SPLIT " + std::to_string(instruction.x) + ", " + std::to_string(instruction.y);
    if (instruction.op == "JMP")
        return "JMP " + std::to_string(instruction.x);
    if (instruction.op == "SAVE" || instruction.op == "BACKREF")
        return instruction.op + " " + std::to_string(instruction.number);
    if (instruction.op == "ASSERT")
        return "ASSERT " + instruction.kind;
    if (instruction.op == "LOOK")
        return "LOOK " + instruction.kind + " " + std::to_string(instruction.x);
    return instruction.op;
}
std::string quote(const std::string &text) {
    std::string result = "\"";
    for (char c : text) {
        if (c == '\\')
            result += "\\\\";
        else if (c == '"')
            result += "\\\"";
        else if (c == '\n')
            result += "\\n";
        else if (c == '\t')
            result += "\\t";
        else
            result += c;
    }
    return result + "\"";
}
