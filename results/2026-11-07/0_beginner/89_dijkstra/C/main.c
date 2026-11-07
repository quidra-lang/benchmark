#include <stdio.h>

int main(void) {
    int graph[7][7] = {{0}};
    int edges[][3] = {{0, 1, 7}, {0, 2, 3}, {0, 3, 9}, {1, 2, 2}, {2, 4, 6}, {1, 3, 3},
        {3, 4, 4}, {3, 5, 5}, {4, 5, 3}, {4, 6, 8}, {5, 6, 4}};
    for (int i = 0; i < 11; i++)
        graph[edges[i][0]][edges[i][1]] = graph[edges[i][1]][edges[i][0]] = edges[i][2];
    int distance[7], parent[7], done[7] = {0};
    for (int i = 0; i < 7; i++) {
        distance[i] = 1000000;
        parent[i] = -1;
    }
    distance[0] = 0;
    for (int step = 0; step < 7; step++) {
        int u = -1;
        for (int v = 0; v < 7; v++)
            if (!done[v] && (u < 0 || distance[v] < distance[u]))
                u = v;
        done[u] = 1;
        for (int v = 0; v < 7; v++)
            if (graph[u][v] && distance[u] + graph[u][v] < distance[v]) {
                distance[v] = distance[u] + graph[u][v];
                parent[v] = u;
            }
    }
    for (int v = 0; v < 7; v++) {
        int path[7], length = 0;
        for (int u = v; u >= 0; u = parent[u])
            path[length++] = u;
        printf("%c: distance=%d path=", 'A' + v, distance[v]);
        for (int i = length - 1; i >= 0; i--)
            printf("%s%c", i == length - 1 ? "" : "-", 'A' + path[i]);
        putchar('\n');
    }
    return 0;
}
