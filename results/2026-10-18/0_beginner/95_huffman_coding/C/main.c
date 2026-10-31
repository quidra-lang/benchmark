#include <stdio.h>
#include <string.h>

typedef struct {
    int weight, minimum, left, right, symbol;
} Node;

int pop(int *roots, int *length, const Node *nodes) {
    int best = 0;
    for (int i = 1; i < *length; i++) {
        Node a = nodes[roots[i]], b = nodes[roots[best]];
        if (a.weight < b.weight || (a.weight == b.weight && a.minimum < b.minimum))
            best = i;
    }
    int result = roots[best];
    roots[best] = roots[--*length];
    return result;
}

void assign(const Node *nodes, int root, char *prefix, int depth, char codes[128][128]) {
    if (nodes[root].symbol >= 0) {
        prefix[depth] = 0;
        strcpy(codes[nodes[root].symbol], prefix);
        return;
    }
    prefix[depth] = '0';
    assign(nodes, nodes[root].left, prefix, depth + 1, codes);
    prefix[depth] = '1';
    assign(nodes, nodes[root].right, prefix, depth + 1, codes);
}

int main(void) {
    const char *text = "she sells sea shells by the sea shore";
    int freq[128] = {0};
    for (int i = 0; text[i]; i++)
        freq[(unsigned char)text[i]]++;
    Node nodes[256];
    int roots[128], length = 0, used = 0;
    for (int c = 0; c < 128; c++)
        if (freq[c]) {
            nodes[used] = (Node){freq[c], c, -1, -1, c};
            roots[length++] = used++;
        }
    while (length > 1) {
        int left = pop(roots, &length, nodes), right = pop(roots, &length, nodes);
        int minimum = nodes[left].minimum < nodes[right].minimum ? nodes[left].minimum : nodes[right].minimum;
        nodes[used] = (Node){nodes[left].weight + nodes[right].weight, minimum, left, right, -1};
        roots[length++] = used++;
    }
    char codes[128][128], prefix[128];
    assign(nodes, roots[0], prefix, 0, codes);
    int bits = 0;
    for (int c = 0; c < 128; c++)
        if (freq[c]) {
            printf("'%c' freq=%d code=%s\n", c, freq[c], codes[c]);
            bits += freq[c] * (int)strlen(codes[c]);
        }
    printf("encoded bits: %d\nfixed 8-bit: %zu\n", bits, strlen(text) * 8);
    return 0;
}
