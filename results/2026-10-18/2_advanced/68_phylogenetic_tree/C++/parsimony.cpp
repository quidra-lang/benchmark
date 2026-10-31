#include "phylogeny.hpp"
std::pair<unsigned, int> merge(unsigned a, unsigned b) {
    return a & b ? std::make_pair(a & b, 0) : std::make_pair(a | b, 1);
}
Provisional provisional(const Tree &tree, const Rooted &rooted,
                        const std::array<unsigned, 16> &pattern) {
    Provisional out;
    for (auto at = rooted.order.rbegin(); at != rooted.order.rend(); ++at) {
        int node = *at;
        if (node < tree.size)
            out.sets[node] = pattern[node];
        else {
            std::vector<int> children;
            for (int child : rooted.children[node])
                if (child != rooted.outgroup)
                    children.push_back(child);
            auto value = merge(out.sets[children[0]], out.sets[children[1]]);
            out.sets[node] = value.first;
            out.changes += value.second;
            if (node == rooted.root)
                out.changes += merge(out.sets[node], out.sets[rooted.outgroup]).second;
        }
    }
    return out;
}
std::vector<int> pattern_scores(const Tree &tree, const Patterns &patterns, int outgroup) {
    Rooted rooted(tree, outgroup);
    std::vector<int> out;
    for (const auto &pattern : patterns.encoded)
        out.push_back(provisional(tree, rooted, pattern).changes);
    return out;
}
int score(const Tree &tree, const Patterns &patterns, int outgroup) {
    std::vector<int> values = pattern_scores(tree, patterns, outgroup);
    int out = 0;
    for (int i = 0; i < int(values.size()); ++i)
        out += values[i] * patterns.weights[i];
    return out;
}
Reconstruction reconstruct(const Tree &tree, const Patterns &patterns, int outgroup) {
    Reconstruction out;
    Rooted rooted(tree, outgroup);
    for (int node : tree.internal_nodes())
        out.ancestors[node] = "";
    for (int a = 0; a < tree.next; ++a)
        for (int b = a + 1; b < tree.next; ++b)
            if (tree.adjacent[a][b])
                out.changes[{a, b}] = 0;
    for (int index : patterns.columns) {
        Provisional p = provisional(tree, rooted, patterns.encoded[index]);
        out.sites.push_back(p.changes);
        unsigned combined = merge(p.sets[rooted.root], p.sets[outgroup]).first,
                 first = combined & (~combined + 1u);
        std::array<unsigned, 32> states{};
        for (int node : {rooted.root, outgroup})
            states[node] = p.sets[node] & first ? first : p.sets[node] & (~p.sets[node] + 1u);
        for (int node : rooted.order)
            if (node != rooted.root && node != outgroup) {
                unsigned parent = states[rooted.parents[node]];
                states[node] = p.sets[node] & parent ? parent : p.sets[node] & (~p.sets[node] + 1u);
            }
        for (auto &entry : out.ancestors) {
            int index_base = 0;
            while ((1u << index_base) != states[entry.first])
                ++index_base;
            entry.second += "ACGT"[index_base];
        }
        for (auto &entry : out.changes)
            entry.second += states[entry.first.first] != states[entry.first.second];
    }
    return out;
}
std::vector<Branch> branches(const Tree &tree, int outgroup) {
    Rooted rooted(tree, outgroup);
    std::vector<Branch> out;
    for (int child : rooted.order)
        if (child != rooted.root)
            out.push_back({child == outgroup ? rooted.ingroup : rooted.masks[child],
                           rooted.parents[child], child});
    std::sort(out.begin(), out.end(),
              [](const Branch &a, const Branch &b) { return a.mask < b.mask; });
    return out;
}
Tree insert(const Tree &tree, int first, int second, int taxon) {
    Tree out = tree;
    out.disconnect(first, second);
    int node = out.internal();
    out.connect(first, node);
    out.connect(second, node);
    out.connect(taxon, node);
    return out;
}
std::vector<Swap> nni_candidates(const Tree &tree, int outgroup) {
    Rooted rooted(tree, outgroup);
    std::vector<Swap> out;
    for (const Branch &branch : branches(tree, outgroup)) {
        int u = branch.first, v = branch.second;
        if (u < tree.size || v < tree.size)
            continue;
        int sibling = -1;
        for (int child : rooted.children[u])
            if (child != v && child != outgroup)
                sibling = child;
        std::vector<int> children = rooted.children[v];
        std::sort(children.begin(), children.end(),
                  [&](int a, int b) { return rooted.masks[a] < rooted.masks[b]; });
        for (int i = 0; i < 2; ++i) {
            int child = children[i];
            Tree candidate = tree;
            double sibling_length = candidate.disconnect(u, sibling),
                   child_length = candidate.disconnect(v, child);
            candidate.connect(u, child, child_length);
            candidate.connect(v, sibling, sibling_length);
            out.push_back({branch.mask, i + 1, candidate});
        }
    }
    return out;
}
