#include "irc.hpp"
bool matches(std::string mask, std::string value) {
    mask = fold(mask);
    value = fold(value);
    std::size_t pattern = 0, position = 0, restart = 0;
    std::optional<std::size_t> star;
    while (position < value.size()) {
        if (pattern < mask.size() && mask[pattern] == '*') {
            star = pattern++;
            restart = position;
        } else if (pattern < mask.size() &&
                   (mask[pattern] == '?' || mask[pattern] == value[position])) {
            ++pattern;
            ++position;
        } else if (star) {
            position = ++restart;
            pattern = *star + 1;
        } else
            return false;
    }
    while (pattern < mask.size() && mask[pattern] == '*')
        ++pattern;
    return pattern == mask.size();
}
std::string normalize(const std::string &argument) {
    bool bang = argument.find('!') != std::string::npos,
         at = argument.find('@') != std::string::npos;
    if (bang && at)
        return argument;
    if (at)
        return "*!" + argument;
    if (bang)
        return argument + "@*";
    if (argument.find('.') != std::string::npos)
        return "*!*@" + argument;
    return argument + "!*@*";
}
