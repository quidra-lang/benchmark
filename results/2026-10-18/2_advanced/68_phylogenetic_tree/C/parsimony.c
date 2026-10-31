#include "phylogeny.h"
unsigned merge(unsigned a, unsigned b, int *changes) {
    if (a & b)
        return a & b;
    ++*changes;
    return a | b;
}
Provisional provisional(const Tree *tree, const Rooted *root, const unsigned pattern[16]) {
    Provisional out = {0};
    for (int i = root->count - 1; i >= 0; --i) {
        int node = root->order[i];
        if (node < tree->size)
            out.sets[node] = pattern[node];
        else {
            int children[2], count = 0;
            for (int j = 0; j < root->child_count[node]; ++j) {
                int child = root->children[node][j];
                if (child != root->outgroup)
                    children[count++] = child;
            }
            out.sets[node] = merge(out.sets[children[0]], out.sets[children[1]], &out.changes);
            if (node == root->root)
                merge(out.sets[node], out.sets[root->outgroup], &out.changes);
        }
    }
    return out;
}
void pattern_scores(const Tree *tree, const Patterns *patterns, int outgroup, int *scores) {
    Rooted root = rooted(tree, outgroup);
    for (int i = 0; i < patterns->count; ++i)
        scores[i] = provisional(tree, &root, patterns->encoded[i]).changes;
}
int score(const Tree *tree, const Patterns *patterns, int outgroup) {
    int values[300], out = 0;
    pattern_scores(tree, patterns, outgroup, values);
    for (int i = 0; i < patterns->count; ++i)
        out += values[i] * patterns->weights[i];
    return out;
}
Reconstruction *reconstruct(const Tree *tree, const Patterns *patterns, int outgroup) {
    Reconstruction *out = calloc(1, sizeof(Reconstruction));
    Rooted root = rooted(tree, outgroup);
    for (int c = 0; c < patterns->length; ++c) {
        Provisional p = provisional(tree, &root, patterns->encoded[patterns->columns[c]]);
        out->sites[c] = p.changes;
        int ignored = 0;
        unsigned combined = merge(p.sets[root.root], p.sets[outgroup], &ignored),
                 first = combined & (~combined + 1u), states[32] = {0};
        states[root.root] =
            p.sets[root.root] & first ? first : p.sets[root.root] & (~p.sets[root.root] + 1u);
        states[outgroup] =
            p.sets[outgroup] & first ? first : p.sets[outgroup] & (~p.sets[outgroup] + 1u);
        for (int i = 1; i < root.count; ++i) {
            int node = root.order[i];
            if (node != outgroup) {
                unsigned parent = states[root.parent[node]];
                states[node] = p.sets[node] & parent ? parent : p.sets[node] & (~p.sets[node] + 1u);
            }
        }
        for (int node = tree->size; node < tree->next; ++node) {
            int base = 0;
            while ((1u << base) != states[node])
                ++base;
            out->ancestors[node][c] = "ACGT"[base];
        }
        for (int a = 0; a < tree->next; ++a)
            for (int b = a + 1; b < tree->next; ++b)
                if (tree->adjacent[a][b])
                    out->changes[a][b] += states[a] != states[b];
    }
    return out;
}
static int branch_order(const void *left, const void *right) {
    Mask a = ((const Branch *)left)->mask, b = ((const Branch *)right)->mask;
    return (a > b) - (a < b);
}
Branches branches(const Tree *tree, int outgroup) {
    Branches out = {0};
    Rooted root = rooted(tree, outgroup);
    for (int i = 1; i < root.count; ++i) {
        int child = root.order[i];
        out.values[out.count++] = (Branch){child == outgroup ? root.ingroup : root.masks[child],
                                           root.parent[child], child};
    }
    qsort(out.values, (size_t)out.count, sizeof(Branch), branch_order);
    return out;
}
Tree insert(const Tree *tree, int first, int second, int taxon) {
    Tree out = *tree;
    disconnect(&out, first, second);
    int node = tree_internal(&out);
    connect(&out, first, node, 0);
    connect(&out, second, node, 0);
    connect(&out, taxon, node, 0);
    return out;
}
Swaps nni_candidates(const Tree *tree, int outgroup) {
    Swaps out = {0};
    out.values = malloc(26 * sizeof(Swap));
    Rooted root = rooted(tree, outgroup);
    Branches edges = branches(tree, outgroup);
    for (int i = 0; i < edges.count; ++i) {
        Branch branch = edges.values[i];
        int u = branch.first, v = branch.second;
        if (u < tree->size || v < tree->size)
            continue;
        int sibling = -1;
        for (int j = 0; j < root.child_count[u]; ++j) {
            int child = root.children[u][j];
            if (child != v && child != outgroup)
                sibling = child;
        }
        int children[2] = {root.children[v][0], root.children[v][1]};
        if (root.masks[children[0]] > root.masks[children[1]]) {
            int temp = children[0];
            children[0] = children[1];
            children[1] = temp;
        }
        for (int swap = 0; swap < 2; ++swap) {
            int child = children[swap];
            Swap *next = &out.values[out.count++];
            next->mask = branch.mask;
            next->number = swap + 1;
            next->tree = *tree;
            double sibling_length = disconnect(&next->tree, u, sibling),
                   child_length = disconnect(&next->tree, v, child);
            connect(&next->tree, u, child, child_length);
            connect(&next->tree, v, sibling, sibling_length);
        }
    }
    return out;
}
