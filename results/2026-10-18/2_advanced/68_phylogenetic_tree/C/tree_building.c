#include "phylogeny.h"
Tree tree_create(int size) {
    Tree out = {0};
    out.size = out.next = size;
    return out;
}
int tree_internal(Tree *tree) {
    tree->present[tree->next] = 1;
    return tree->next++;
}
void connect(Tree *tree, int a, int b, double length) {
    tree->present[a] = tree->present[b] = 1;
    tree->adjacent[a][b] = tree->adjacent[b][a] = 1;
    tree->length[a][b] = tree->length[b][a] = length;
}
double disconnect(Tree *tree, int a, int b) {
    double length = tree->length[a][b];
    tree->adjacent[a][b] = tree->adjacent[b][a] = 0;
    return length;
}
static void root_visit(const Tree *tree, Rooted *root, int node, int parent) {
    root->parent[node] = parent;
    root->order[root->count++] = node;
    if (node < tree->size)
        root->masks[node] = 1u << node;
    for (int child = 0; child < tree->next; ++child)
        if (tree->adjacent[node][child] && child != parent) {
            root->children[node][root->child_count[node]++] = child;
            root_visit(tree, root, child, node);
            root->masks[node] |= root->masks[child];
        }
}
Rooted rooted(const Tree *tree, int outgroup) {
    Rooted out = {0};
    out.outgroup = outgroup;
    while (!tree->adjacent[outgroup][out.root])
        ++out.root;
    root_visit(tree, &out, out.root, -1);
    out.ingroup = out.masks[out.root] ^ (1u << outgroup);
    return out;
}
Masks split_set(const Tree *tree, const Rooted *root) {
    Masks out = {0};
    for (int node = tree->size; node < tree->next; ++node)
        if (tree->present[node] && node != root->root)
            out.values[out.count++] = root->masks[node];
    return out;
}
Tree star(int size, const int *taxa, int count) {
    Tree out = tree_create(size);
    int root = tree_internal(&out);
    for (int i = 0; i < count; ++i)
        connect(&out, root, taxa[i], 0);
    return out;
}
Tree neighbor_joining(const Matrix *matrix, int size, const int *taxa, int length) {
    Tree tree = tree_create(size);
    double distances[32][32] = {{0}};
    int active[32], count = length;
    memcpy(active, taxa, (size_t)length * sizeof(int));
    for (int i = 0; i < length; ++i)
        for (int j = 0; j < length; ++j)
            distances[taxa[i]][taxa[j]] = matrix->values[taxa[i]][taxa[j]];
    while (count >= 4) {
        double totals[32] = {0}, best = INFINITY;
        int first = 0, second = 0;
        for (int i = 0; i < count; ++i)
            for (int j = 0; j < count; ++j)
                if (i != j)
                    totals[active[i]] += distances[active[i]][active[j]];
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
        int node = tree_internal(&tree);
        double distance = distances[first][second],
               left = distance / 2 + (totals[first] - totals[second]) / (2 * (count - 2));
        connect(&tree, first, node, left);
        connect(&tree, second, node, distance - left);
        int remaining[32], n = 0;
        for (int i = 0; i < count; ++i) {
            int other = active[i];
            if (other != first && other != second) {
                remaining[n++] = other;
                distances[node][other] = distances[other][node] =
                    (distances[first][other] + distances[second][other] - distance) / 2;
            }
        }
        remaining[n++] = node;
        memcpy(active, remaining, (size_t)n * sizeof(int));
        count = n;
    }
    int a = active[0], b = active[1], c = active[2], node = tree_internal(&tree);
    double ab = distances[a][b], ac = distances[a][c], bc = distances[b][c];
    connect(&tree, a, node, (ab + ac - bc) / 2);
    connect(&tree, b, node, (ab + bc - ac) / 2);
    connect(&tree, c, node, (ac + bc - ab) / 2);
    for (int i = 0; i < tree.next; ++i)
        for (int j = i + 1; j < tree.next; ++j)
            if (tree.adjacent[i][j] && tree.length[i][j] < 0) {
                connect(&tree, i, j, 0);
                ++tree.negative;
            }
    return tree;
}
static void path_visit(const Tree *tree, int node, int parent, int unit, double output[32]) {
    for (int child = 0; child < tree->next; ++child)
        if (tree->adjacent[node][child] && child != parent) {
            output[child] = output[node] + (unit ? 1 : tree->length[node][child]);
            path_visit(tree, child, node, unit, output);
        }
}
void paths(const Tree *tree, int start, int unit, double output[32]) {
    memset(output, 0, 32 * sizeof(double));
    path_visit(tree, start, -1, unit, output);
}
Matrix patristic(const Tree *tree) {
    Matrix out = {0};
    for (int a = 0; a < tree->size; ++a)
        if (tree->present[a]) {
            double distances[32];
            paths(tree, a, 0, distances);
            for (int b = 0; b < tree->size; ++b)
                if (tree->present[b])
                    out.values[a][b] = distances[b];
        }
    return out;
}
