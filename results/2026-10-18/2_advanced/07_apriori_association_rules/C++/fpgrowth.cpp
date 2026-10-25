#include "market.hpp"
#include <algorithm>
#include <memory>
#include <utility>

struct Pattern { Items items; Integer weight; };
struct FPNode { std::string item; int parent; Integer count = 0; std::map<std::string, int> children; };
class FPTree {
public:
    Items header;
    std::vector<FPNode> nodes{{"",-1}};
    std::map<std::string, std::vector<int>> links;
    FPTree(const std::vector<Pattern>& base, Integer minimum) {
        Counts counts;
        for (const Pattern& pattern : base) for (const std::string& item : pattern.items) counts[item] += pattern.weight;
        for (const auto& entry : counts) if (entry.second >= minimum) header.push_back(entry.first);
        std::sort(header.begin(),header.end(),[&](const std::string& a, const std::string& b) { return counts[a] != counts[b] ? counts[a] > counts[b] : a < b; });
        std::map<std::string, int> order;
        for (int j = 0; j < static_cast<int>(header.size()); ++j) order[header[j]] = j;
        for (const Pattern& pattern : base) {
            Items path;
            for (const std::string& item : pattern.items) if (order.count(item)) path.push_back(item);
            std::sort(path.begin(),path.end(),[&](const std::string& a, const std::string& b) { return order[a] < order[b]; });
            int node = 0;
            for (const std::string& item : path) {
                auto found = nodes[node].children.find(item);
                int child;
                if (found == nodes[node].children.end()) {
                    child = static_cast<int>(nodes.size()); nodes[node].children[item] = child;
                    nodes.push_back({item,node}); links[item].push_back(child);
                } else child = found->second;
                nodes[child].count += pattern.weight; node = child;
            }
        }
    }
    Integer support(const std::string& item) const {
        Integer count = 0; for (int node : links.at(item)) count += nodes[node].count; return count;
    }
    std::vector<Pattern> conditional(const std::string& item) const {
        std::vector<Pattern> base;
        for (int node : links.at(item)) {
            Items path;
            for (int parent = nodes[node].parent; parent != 0; parent = nodes[parent].parent) path.push_back(nodes[parent].item);
            std::reverse(path.begin(),path.end()); base.push_back({path,nodes[node].count});
        }
        return base;
    }
};
GrowthResult fpGrowth(const Baskets& baskets, Integer minimum, int maximum) {
    std::vector<Pattern> base;
    for (const Items& items : baskets) base.push_back({items,1});
    auto whole = std::make_shared<FPTree>(base,minimum);
    GrowthResult result; result.headers = static_cast<int>(whole->header.size()); result.nodes = static_cast<int>(whole->nodes.size()) - 1;
    std::vector<std::pair<std::shared_ptr<FPTree>, Items>> stack{{whole,{}}};
    while (!stack.empty()) {
        auto current = std::move(stack.back()); stack.pop_back();
        for (auto item = current.first->header.rbegin(); item != current.first->header.rend(); ++item) {
            Items suffix = united(current.second,{*item}); result.itemsets[suffix] = current.first->support(*item);
            if (static_cast<int>(suffix.size()) < maximum) {
                auto tree = std::make_shared<FPTree>(current.first->conditional(*item),minimum);
                if (tree->nodes.size() > 1) { ++result.conditionalTrees; result.conditionalNodes += static_cast<int>(tree->nodes.size()) - 1; stack.push_back({tree,suffix}); }
            }
        }
    }
    return result;
}
