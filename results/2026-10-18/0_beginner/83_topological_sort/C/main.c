#include <stdio.h>
#include <string.h>

void solve(const char * * names, int n, const char *edges[][2], int e, int show_cycle) {
    int graph[8][8] = {{0}}, indegree[8] = {0}, taken[8] = {0};
    for (int i = 0; i < e; i++) {
        int a = 0, b = 0;
        while (strcmp(names[a], edges[i][0]))
            a++;
        while (strcmp(names[b], edges[i][1]))
            b++;
        graph[a][b] = 1;
        indegree[b]++;
    }
    printf("order: ");
    int count = 0;
    while (1) {
        int best = -1;
        for (int v = 0; v < n; v++)
            if (!taken[v] && !indegree[v] && (best < 0 || strcmp(names[v], names[best]) < 0))
                best = v;
        if (best < 0)
            break;
        if (count++)
            printf(" -> ");
        printf("%s", names[best]);
        taken[best] = 1;
        for (int v = 0; v < n; v++)
            if (graph[best][v])
                indegree[v]--;
    }
    putchar('\n');
    if (show_cycle) {
        printf("cycle:");
        while (1) {
            int best = -1;
            for (int v = 0; v < n; v++)
                if (!taken[v] && (best < 0 || strcmp(names[v], names[best]) < 0))
                    best = v;
            if (best < 0)
                break;
            printf(" %s", names[best]);
            taken[best] = 1;
        }
        putchar('\n');
    }
}

int main(void) {
    const char *names1[] = {"physics", "algebra", "graphics", "programming", "statistics", "calculus",
        "databases", "algorithms"}, *names2[] = {"music", "ecology", "art", "geology", "biology", "chemistry"}, *edges1[][2] = {{"calculus",
        "physics"}, {"algebra", "calculus"}, {"programming", "algorithms"}, {"algebra", "statistics"}, {"algorithms",
        "databases"}, {"statistics", "databases"}, {"calculus", "graphics"}, {"algorithms", "graphics"},
        {"physics", "graphics"}}, *edges2[][2] = {{"music", "art"}, {"art", "ecology"}, {"biology", "chemistry"},
        {"chemistry", "ecology"}, {"ecology", "geology"}, {"geology", "chemistry"}};
    solve(names1, 8, edges1, 9, 0);
    solve(names2, 6, edges2, 6, 1);
    return 0;
}
