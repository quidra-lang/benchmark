#include "mrp.hpp"
#include <algorithm>

std::string Item::lotLabel() const {
    if (rule == "MIN") return rule + " " + std::to_string(first) + "/" + std::to_string(second);
    return rule == "LFL" ? rule : rule + " " + std::to_string(first);
}
Items readItems(Lines& errors) {
    Items items; const std::set<std::string> rules{"LFL", "FOQ", "POQ", "MIN"};
    for (const Row& row : readRows("items.csv")) {
        const Lines& f = row.fields; std::string error; Lines parts = split(f[3], '/');
        Values lot; for (const std::string& part : parts) lot.push_back(std::stoll(part));
        bool fits = f[2] == "LFL" ? lot.size() == 1 && lot[0] == 0 : f[2] == "MIN" ? lot.size() == 2 && lot[0] >= 1 && lot[1] >= 1 : lot.size() == 1 && lot[0] >= 1;
        if (items.count(f[0])) error = "duplicate item " + f[0];
        else if (!rules.count(f[2])) error = "unknown lot rule " + f[2];
        else if (!fits) error = "bad lot parameter " + f[3] + " for " + f[2];
        if (!error.empty()) inputError(errors, "items.csv", row.line, error);
        else items.emplace(f[0], Item{f[0], std::stoi(f[1]), f[2], lot[0], lot.size() > 1 ? lot[1] : 0, std::stoll(f[4]), std::stoll(f[5]), std::stoll(f[6]), std::stoll(f[7]), f[8]});
    }
    return items;
}
