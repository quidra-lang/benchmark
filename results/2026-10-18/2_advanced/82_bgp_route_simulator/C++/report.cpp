#include "bgp.hpp"
#include <fstream>
#include <sstream>
#include <stdexcept>
std::vector<std::string> readLines(const std::string &name) {
    std::ifstream file(name);
    if (!file)
        throw std::runtime_error("cannot read " + name);
    std::vector<std::string> result;
    std::string line;
    while (std::getline(file, line))
        result.push_back(line);
    return result;
}
std::vector<std::string> words(const std::string &text) {
    std::istringstream input(text);
    std::vector<std::string> result;
    std::string word;
    while (input >> word)
        result.push_back(word);
    return result;
}
std::string join(const std::vector<std::string> &parts, const std::string &separator) {
    std::string result;
    for (std::size_t i = 0; i < parts.size(); ++i) {
        if (i)
            result += separator;
        result += parts[i];
    }
    return result;
}
std::string pathText(const std::vector<int> &path) {
    std::vector<std::string> parts;
    for (int number : path)
        parts.push_back(std::to_string(number));
    return join(parts, ",");
}
std::string attributeText(const Attribute &attribute) {
    return "path " + pathText(attribute.path) + " origin " + originName(attribute.origin) +
           " med " + std::to_string(attribute.med) + " comm " +
           communitiesText(attribute.communities);
}
std::string routeText(const std::optional<Route> &route) {
    if (!route)
        return "NONE";
    const Attribute &a = route->attribute;
    if (route->local)
        return "LOCAL origin " + std::string(originName(a.origin)) + " comm " +
               communitiesText(a.communities);
    return "next " + std::to_string(a.path.front()) + " path " + pathText(a.path) + " link " +
           route->link->name + " lp " + std::to_string(route->preference) + " med " +
           std::to_string(a.med) + " origin " + originName(a.origin) + " comm " +
           communitiesText(a.communities);
}
void writeLines(const std::string &name, const std::vector<std::string> &lines) {
    std::ofstream file("output/" + name);
    if (!file)
        throw std::runtime_error("cannot write " + name);
    for (const std::string &line : lines)
        file << line << '\n';
}
