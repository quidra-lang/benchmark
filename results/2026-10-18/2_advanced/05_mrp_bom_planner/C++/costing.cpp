#include "mrp.hpp"
#include <algorithm>

std::map<std::string, StandardCost> standardCosts(const Items& items, const Bom& bom, const Lines& planningOrder) {
    std::map<std::string, StandardCost> costs;
    for (auto iterator = planningOrder.rbegin(); iterator != planningOrder.rend(); ++iterator) {
        const Item& item = items.at(*iterator); StandardCost cost{item.material, item.labor};
        for (const Edge& edge : bom.children.at(*iterator)) { const StandardCost& child = costs.at(edge.child); cost.material += (edge.quantity * (100 + edge.scrap) * child.material + 50) / 100; cost.labor += (edge.quantity * (100 + edge.scrap) * child.labor + 50) / 100; }
        costs.emplace(*iterator, cost);
    }
    return costs;
}
std::map<std::string, std::string> abcClasses(const std::map<std::string, Integer>& values) {
    Lines order; Integer total = 0; for (const auto& [id, value] : values) { order.push_back(id); total += value; }
    std::sort(order.begin(), order.end(), [&](const std::string& a, const std::string& b) { return values.at(a) != values.at(b) ? values.at(a) > values.at(b) : a < b; });
    std::map<std::string, std::string> classes; Integer before = 0;
    for (const std::string& id : order) { Integer value = values.at(id); classes[id] = value == 0 ? "C" : 100 * before < 80 * total ? "A" : 100 * before < 95 * total ? "B" : "C"; before += value; }
    return classes;
}
