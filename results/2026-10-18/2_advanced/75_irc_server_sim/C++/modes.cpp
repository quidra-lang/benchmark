#include "irc.hpp"
std::vector<Change> channel_items(const std::string &mode, const Names &arguments) {
    std::vector<Change> out;
    char sign = '+';
    std::size_t position = 0;
    for (char c : mode) {
        if (c == '+' || c == '-') {
            sign = c;
            continue;
        }
        std::optional<std::string> argument;
        if (c == 'o' || c == 'v' || c == 'b' || c == 'k' || (c == 'l' && sign == '+'))
            if (position < arguments.size())
                argument = arguments[position++];
        if (c == 'k' && sign == '-')
            argument = "*";
        else if (c == 'l' && sign == '+')
            if (!argument || !digits(*argument) || argument->size() > 4 || std::stoi(*argument) < 1)
                argument.reset();
        out.push_back({sign, c, argument});
    }
    return out;
}
std::string change_string(const std::vector<Change> &changes) {
    std::string mode, arguments;
    char previous = 0;
    for (const Change &change : changes) {
        if (change.sign != previous) {
            mode += change.sign;
            previous = change.sign;
        }
        mode += change.character;
        if (change.argument)
            arguments += ' ' + *change.argument;
    }
    return mode + arguments;
}
