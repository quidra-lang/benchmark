#include <stdio.h>
#include <stdlib.h>

typedef struct {
    char a, b;
    int weight;
} Edge;
int compare(const void *a, const void *b) {
    return ((const Edge *) a)->weight - ((const Edge *) b)->weight;
}

int find(int *parent, int v) {
    if (parent[v] != v)
        parent[v] = find(parent, parent[v]);
    return parent[v];
}

int main(void) {
    Edge edges[] = {{'A', 'B', 7}, {'C', 'A', 4}, {'B', 'C', 9}, {'B', 'D', 14}, {'D', 'C', 6}, {'C',
        'E', 3}, {'E', 'D', 5}, {'F', 'D', 11}, {'E', 'G', 16}, {'G', 'F', 8}, {'H', 'F', 12}, {'G', 'H',
        2}, {'H', 'E', 10}};
    qsort(edges, 13, sizeof(Edge), compare);
    int parent[8];
    for (int i = 0; i < 8; i++)
        parent[i] = i;
    int accepted = 0, total = 0, skipped = 0;
    for (int i = 0; i < 13 && accepted < 7; i++) {
        int a = find(parent, edges[i].a - 'A'), b = find(parent, edges[i].b - 'A');
        if (a == b) {
            skipped++;
            continue;
        }
        parent[a] = b;
        accepted++;
        total += edges[i].weight;
        char u = edges[i].a, v = edges[i].b;
        if (u > v) {
            char t = u;
            u = v;
            v = t;
        }
        printf("%c-%c %d\n", u, v, edges[i].weight);
    }
    printf("total weight: %d\nskipped: %d\n", total, skipped);
    return 0;
}
