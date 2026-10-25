#include "market.hpp"
#include <algorithm>
#include <fstream>
#include <sstream>

bool Transaction::add(const std::string& product) { bool duplicate = counts.count(product) != 0; ++counts[product]; return duplicate; }
Items Transaction::products() const { Items result; for (const auto& entry : counts) result.push_back(entry.first); return result; }
Integer Transaction::units() const { Integer total = 0; for (const auto& entry : counts) total += entry.second; return total; }
std::vector<Items> readRecords(const std::string& name) {
    std::ifstream file("input/" + name);
    std::string line, value;
    std::vector<Items> result;
    std::getline(file,line);
    while (std::getline(file,line)) {
        Items fields; std::istringstream row(line);
        while (std::getline(row,value,',')) fields.push_back(value);
        result.push_back(fields);
    }
    return result;
}
bool contains(const Items& items, const Items& subset) { return std::includes(items.begin(),items.end(),subset.begin(),subset.end()); }
Items extendedBasket(const Items& items, const Taxonomy& taxonomy) {
    Items result = items;
    for (const std::string& item : items) result.push_back(taxonomy.at(item));
    std::sort(result.begin(),result.end()); result.erase(std::unique(result.begin(),result.end()),result.end());
    return result;
}
Items united(Items first, const Items& second) {
    first.insert(first.end(),second.begin(),second.end()); std::sort(first.begin(),first.end());
    first.erase(std::unique(first.begin(),first.end()),first.end()); return first;
}
