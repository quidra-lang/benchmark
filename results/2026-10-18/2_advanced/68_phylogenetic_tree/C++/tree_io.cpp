#include "phylogeny.hpp"
std::string real(double value, int digits) {
    std::ostringstream out;
    out << std::fixed << std::setprecision(digits) << value;
    std::string text = out.str();
    if (text[0] == '-' && text.find_first_not_of("-0.") == std::string::npos)
        text.erase(0, 1);
    return text;
}
std::string symbols(Mask mask, int size) {
    std::string out;
    for (int t = 0; t < size; ++t)
        out += mask & (1u << t) ? '*' : '.';
    return out;
}
static std::array<std::vector<int>, 32> child_order(const Tree &tree, const Rooted &rooted,
                                                    const Names &names) {
    std::array<std::vector<int>, 32> children = rooted.children;
    std::array<std::string, 32> minimum;
    for (auto at = rooted.order.rbegin(); at != rooted.order.rend(); ++at) {
        int node = *at;
        if (node < tree.size)
            minimum[node] = names[node];
        else {
            std::sort(children[node].begin(), children[node].end(),
                      [&](int a, int b) { return minimum[a] < minimum[b]; });
            minimum[node] = minimum[children[node][0]];
        }
    }
    return children;
}
std::string newick(const Tree &tree, const Names &names, int outgroup, bool lengths,
                   const std::map<Mask, int> *support) {
    Rooted rooted(tree, outgroup);
    auto children = child_order(tree, rooted, names);
    std::function<std::string(int)> render = [&](int node) {
        std::string text;
        if (node < tree.size)
            text = names[node];
        else {
            text = "(";
            for (int i = 0; i < int(children[node].size()); ++i) {
                if (i)
                    text += ",";
                text += render(children[node][i]);
            }
            text += ")";
            if (support && node != rooted.root) {
                auto entry = support->find(rooted.masks[node]);
                text += std::to_string(entry == support->end() ? 0 : entry->second);
            }
        }
        if (lengths && node != rooted.root)
            text += ":" + real(tree.length[node][rooted.parents[node]], 5);
        return text;
    };
    return render(rooted.root) + ";";
}
Lines cladogram(const Tree &tree, const Names &names, int outgroup,
                const std::map<Mask, int> &support) {
    Rooted rooted(tree, outgroup);
    auto children = child_order(tree, rooted, names);
    Lines out = {"*"};
    std::function<void(int, const std::string &)> descend = [&](int node,
                                                                const std::string &prefix) {
        for (int i = 0; i < int(children[node].size()); ++i) {
            int child = children[node][i];
            bool last = i + 1 == int(children[node].size());
            std::string label;
            if (child < tree.size)
                label = names[child];
            else {
                auto entry = support.find(rooted.masks[child]);
                label = "[" + std::to_string(entry == support.end() ? 0 : entry->second) + "]";
            }
            out.push_back(prefix + (last ? "`-- " : "|-- ") + label);
            descend(child, prefix + (last ? "    " : "|   "));
        }
    };
    descend(rooted.root, "");
    return out;
}
void save(const std::string &name, const Lines &lines) {
    std::ofstream out("output/" + name);
    for (const std::string &line : lines)
        out << line << '\n';
}
