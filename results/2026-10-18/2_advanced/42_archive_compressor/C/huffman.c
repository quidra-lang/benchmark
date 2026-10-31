#include "archive.h"
typedef struct {
    int weight, minimum, left, right, symbol;
} Node;
static bool node_less(const Node *nodes, int a, int b) {
    return nodes[a].weight != nodes[b].weight ? nodes[a].weight < nodes[b].weight
                                              : nodes[a].minimum < nodes[b].minimum;
}
static void tree_lengths(const int *frequencies, int count, int *lengths) {
    Node nodes[576];
    int queue[288], node_count = 0, queue_count = 0;
    memset(lengths, 0, (size_t)count * sizeof(int));
    for (int s = 0; s < count; ++s)
        if (frequencies[s] > 0) {
            queue[queue_count++] = node_count;
            nodes[node_count++] = (Node){frequencies[s], s, -1, -1, s};
        }
    if (!queue_count)
        return;
    if (queue_count == 1) {
        lengths[nodes[queue[0]].symbol] = 1;
        return;
    }
    while (queue_count > 1) {
        for (int i = 1; i < queue_count; ++i) {
            int selected = queue[i], j = i;
            while (j > 0 && node_less(nodes, selected, queue[j - 1])) {
                queue[j] = queue[j - 1];
                --j;
            }
            queue[j] = selected;
        }
        int a = queue[0], b = queue[1];
        memmove(queue, queue + 2, (size_t)(queue_count - 2) * sizeof(int));
        queue_count -= 2;
        queue[queue_count++] = node_count;
        nodes[node_count++] =
            (Node){nodes[a].weight + nodes[b].weight,
                   nodes[a].minimum < nodes[b].minimum ? nodes[a].minimum : nodes[b].minimum, a, b, -1};
    }
    int stack_node[576], stack_depth[576], stack_count = 0;
    stack_node[stack_count] = queue[0];
    stack_depth[stack_count++] = 0;
    while (stack_count) {
        --stack_count;
        int index = stack_node[stack_count], depth = stack_depth[stack_count];
        Node node = nodes[index];
        if (node.symbol >= 0)
            lengths[node.symbol] = depth;
        else {
            stack_node[stack_count] = node.right;
            stack_depth[stack_count++] = depth + 1;
            stack_node[stack_count] = node.left;
            stack_depth[stack_count++] = depth + 1;
        }
    }
}
Huffman huffman_lengths(const int *frequencies, int count, int maximum) {
    Huffman out = {.count = count};
    out.lengths = resize(NULL, (size_t)count * sizeof(int));
    int *current = resize(NULL, (size_t)count * sizeof(int));
    memcpy(current, frequencies, (size_t)count * sizeof(int));
    while (true) {
        tree_lengths(current, count, out.lengths);
        int longest = 0;
        for (int i = 0; i < count; ++i)
            if (out.lengths[i] > longest)
                longest = out.lengths[i];
        if (longest <= maximum) {
            free(current);
            return out;
        }
        for (int i = 0; i < count; ++i)
            current[i] = (current[i] + 1) / 2;
        ++out.halvings;
    }
}
int *canonical_codes(const int *lengths, int count) {
    int *codes = calloc((size_t)count, sizeof(int)), *order = resize(NULL, (size_t)count * sizeof(int));
    int used = 0;
    for (int s = 0; s < count; ++s)
        if (lengths[s] > 0) {
            int j = used;
            while (j > 0 && (lengths[s] < lengths[order[j - 1]] ||
                             (lengths[s] == lengths[order[j - 1]] && s < order[j - 1]))) {
                order[j] = order[j - 1];
                --j;
            }
            order[j] = s;
            ++used;
        }
    int code = 0, previous = 0;
    for (int i = 0; i < used; ++i) {
        int symbol = order[i];
        if (previous)
            code = (code + 1) << (lengths[symbol] - previous);
        codes[symbol] = code;
        previous = lengths[symbol];
    }
    free(order);
    return codes;
}
