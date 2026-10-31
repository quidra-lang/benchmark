#include "auction.hpp"
#include <fstream>
#include <stdexcept>
std::vector<std::string> readLines(const std::string &name) {
    std::ifstream file(name);
    if (!file)
        throw std::runtime_error("cannot read " + name);
    std::vector<std::string> result;
    std::string value;
    while (std::getline(file, value))
        result.push_back(value);
    return result;
}
std::vector<std::string> words(const std::string &text) {
    std::istringstream input(text);
    std::vector<std::string> result;
    std::string value;
    while (input >> value)
        result.push_back(value);
    return result;
}
Input readInput() {
    Input input;
    for (const std::string &value : readLines("input/items.txt")) {
        std::vector<std::string> a = words(value);
        input.items.push_back({a[0], std::stoll(a[1])});
    }
    RawAuction *auction = nullptr;
    for (const std::string &value : readLines("input/bids.txt")) {
        std::vector<std::string> a = words(value);
        if (a[0] == "auction") {
            RawAuction raw;
            raw.name = a[1];
            raw.offered.assign(a.begin() + 2, a.end());
            auction = &input.auctions.emplace(raw.name, std::move(raw)).first->second;
        } else
            auction->lines.push_back(
                {a[1], a[2], std::vector<std::string>(a.begin() + 3, a.end())});
    }
    for (const std::string &value : readLines("input/single_item.txt")) {
        std::vector<std::string> a = words(value);
        if (a[0] == "lot" || a[0] == "slots")
            input.groups.push_back(
                {a[0], a[1], std::vector<std::string>(a.begin() + 2, a.end()), {}});
        else
            input.groups.back().participants.push_back({a[1], std::stoll(a[2]), std::stoll(a[3])});
    }
    for (const std::string &value : readLines("input/params.txt")) {
        std::vector<std::string> a = words(value);
        if (a[0] == "run")
            input.runs.assign(a.begin() + 1, a.end());
        else
            input.parameters[a[0]] = std::stoll(a[1]);
    }
    return input;
}
