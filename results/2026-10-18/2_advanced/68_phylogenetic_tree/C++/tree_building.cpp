#include "phylogeny.hpp"
int Tree::internal() {
    present[next] = true;
    return next++;
}
void Tree::connect(int a, int b, double distance) {
    present[a] = present[b] = true;
    adjacent[a][b] = adjacent[b][a] = true;
    length[a][b] = length[b][a] = distance;
}
double Tree::disconnect(int a, int b) {
    double distance = length[a][b];
    adjacent[a][b] = adjacent[b][a] = false;
    return distance;
}
std::vector<int> Tree::taxa() const {
    std::vector<int> out;
    for (int i = 0; i < size; ++i)
        if (present[i])
            out.push_back(i);
    return out;
}
std::vector<int> Tree::internal_nodes() const {
    std::vector<int> out;
    for (int i = size; i < next; ++i)
        if (present[i])
            out.push_back(i);
    return out;
}
Rooted::Rooted(const Tree &tree, int group) : outgroup(group) {
    root = 0;
    while (!tree.adjacent[outgroup][root])
        ++root;
    std::function<void(int, int)> visit = [&](int node, int parent) {
        parents[node] = parent;
        order.push_back(node);
        if (node < tree.size)
            masks[node] = 1u << node;
        for (int child = 0; child < tree.next; ++child)
            if (tree.adjacent[node][child] && child != parent) {
                children[node].push_back(child);
                visit(child, node);
                masks[node] |= masks[child];
            }
    };
    visit(root, -1);
    ingroup = masks[root] ^ (1u << outgroup);
}
std::set<Mask> Rooted::splits(const Tree &tree) const {
    std::set<Mask> out;
    for (int node : tree.internal_nodes())
        if (node != root)
            out.insert(masks[node]);
    return out;
}
std::map<Mask, double> Rooted::branch_lengths(const Tree &tree) const {
    std::map<Mask, double> out;
    for (int node : order)
        if (node != root)
            out[node == outgroup ? ingroup : masks[node]] = tree.length[node][parents[node]];
    return out;
}
Tree star(int size, const std::vector<int> &taxa) {
    Tree out(size);
    int node = out.internal();
    for (int taxon : taxa)
        out.connect(node, taxon);
    return out;
}
Tree neighbor_joining(const Matrix &matrix, int size, const std::vector<int> &taxa) {
    Tree tree(size);
    std::vector<int> active = taxa;
    std::array<std::array<double, 32>, 32> distances{};
    for (int a : taxa)
        for (int b : taxa)
            distances[a][b] = matrix[a][b];
    while (active.size() >= 4) {
        int count = int(active.size());
        std::array<double, 32> totals{};
        for (int a : active)
            for (int b : active)
                if (a != b)
                    totals[a] += distances[a][b];
        double best = std::numeric_limits<double>::infinity();
        int first = 0, second = 0;
        for (int i = 0; i < count; ++i)
            for (int j = i + 1; j < count; ++j) {
                int a = active[i], b = active[j];
                double value = (count - 2) * distances[a][b] - totals[a] - totals[b];
                if (value < best) {
                    best = value;
                    first = a;
                    second = b;
                }
            }
        int node = tree.internal();
        double distance = distances[first][second],
               left = distance / 2 + (totals[first] - totals[second]) / (2 * (count - 2));
        tree.connect(first, node, left);
        tree.connect(second, node, distance - left);
        std::vector<int> remaining;
        for (int other : active)
            if (other != first && other != second) {
                remaining.push_back(other);
                distances[node][other] = distances[other][node] =
                    (distances[first][other] + distances[second][other] - distance) / 2;
            }
        remaining.push_back(node);
        active = remaining;
    }
    int a = active[0], b = active[1], c = active[2], node = tree.internal();
    double ab = distances[a][b], ac = distances[a][c], bc = distances[b][c];
    tree.connect(a, node, (ab + ac - bc) / 2);
    tree.connect(b, node, (ab + bc - ac) / 2);
    tree.connect(c, node, (ac + bc - ab) / 2);
    for (int i = 0; i < tree.next; ++i)
        for (int j = i + 1; j < tree.next; ++j)
            if (tree.adjacent[i][j] && tree.length[i][j] < 0) {
                tree.connect(i, j, 0);
                ++tree.negative;
            }
    return tree;
}
std::array<double, 32> paths(const Tree &tree, int start, bool unit) {
    std::array<double, 32> out{};
    std::function<void(int, int)> visit = [&](int node, int parent) {
        for (int child = 0; child < tree.next; ++child)
            if (tree.adjacent[node][child] && child != parent) {
                out[child] = out[node] + (unit ? 1 : tree.length[node][child]);
                visit(child, node);
            }
    };
    visit(start, -1);
    return out;
}
Matrix patristic(const Tree &tree) {
    Matrix out{};
    std::vector<int> taxa = tree.taxa();
    for (int a : taxa) {
        std::array<double, 32> distances = paths(tree, a);
        for (int b : taxa)
            out[a][b] = distances[b];
    }
    return out;
}
