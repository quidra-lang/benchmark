#include "irc.hpp"
std::string fold(std::string value) {
    for (char &c : value) {
        if (c >= 'A' && c <= 'Z')
            c = char(c - 'A' + 'a');
        else if (c == '[')
            c = '{';
        else if (c == ']')
            c = '}';
        else if (c == '\\')
            c = '|';
        else if (c == '^')
            c = '~';
    }
    return value;
}
bool digits(const std::string &value) {
    return !value.empty() &&
           std::all_of(value.begin(), value.end(), [](char c) { return c >= '0' && c <= '9'; });
}
static bool letter(char c) { return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'); }
static bool special(char c) { return std::string("[]\\`_^{}|").find(c) != std::string::npos; }
bool valid_nickname(const std::string &value) {
    if (value.empty() || (!letter(value[0]) && !special(value[0])))
        return false;
    for (int i = 1; i < int(value.size()); ++i) {
        char c = value[i];
        if (!letter(c) && !special(c) && !(c >= '0' && c <= '9') && c != '-')
            return false;
    }
    return true;
}
bool valid_channel(const std::string &value, int maximum) {
    return value.size() >= 2 && value.size() <= std::size_t(maximum) && value[0] == '#' &&
           value.find(':') == std::string::npos;
}
Parsed parse(const std::string &raw) {
    Parsed out;
    std::size_t position = 0;
    if (!raw.empty() && raw[0] == ':') {
        position = raw.find(' ');
        if (position == std::string::npos)
            return out;
    }
    while (position < raw.size() && raw[position] == ' ')
        ++position;
    std::size_t start = position;
    while (position < raw.size() && raw[position] != ' ')
        ++position;
    out.command = raw.substr(start, position - start);
    for (char &c : out.command)
        if (c >= 'a' && c <= 'z')
            c = char(c - 'a' + 'A');
    if (out.command.empty())
        return out;
    while (position < raw.size()) {
        while (position < raw.size() && raw[position] == ' ')
            ++position;
        if (position == raw.size())
            break;
        if (raw[position] == ':') {
            out.parameters.push_back(raw.substr(position + 1));
            break;
        }
        if (out.parameters.size() == 14) {
            out.parameters.push_back(raw.substr(position));
            break;
        }
        start = position;
        while (position < raw.size() && raw[position] != ' ')
            ++position;
        out.parameters.push_back(raw.substr(start, position - start));
    }
    return out;
}
