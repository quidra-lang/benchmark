#include "mapf.h"
#include <stdlib.h>
#include <string.h>
bool free_cell(const Grid *g, int cell) {
    return cell >= 0 && cell < g->width * g->height &&
           g->rows[cell / g->width][cell % g->width] == '.';
}
Destinations destinations(const Grid *g, int cell) {
    Destinations result = {.items = {cell}, .count = 1};
    static const int dx[] = {0, 1, 0, -1}, dy[] = {-1, 0, 1, 0};
    int x = cell % g->width, y = cell / g->width;
    for (int i = 0; i < 4; ++i) {
        int nx = x + dx[i], ny = y + dy[i];
        if (nx >= 0 && nx < g->width && ny >= 0 && ny < g->height &&
            free_cell(g, ny * g->width + nx))
            result.items[result.count++] = ny * g->width + nx;
    }
    return result;
}
void distances(const Grid *g, int goal, int out[1024]) {
    int count = g->width * g->height, queue[1024], tail = 1;
    for (int i = 0; i < count; ++i)
        out[i] = -1;
    out[goal] = 0;
    queue[0] = goal;
    for (int head = 0; head < tail; ++head) {
        int c = queue[head];
        Destinations next = destinations(g, c);
        for (int i = 1; i < next.count; ++i) {
            int v = next.items[i];
            if (out[v] < 0) {
                out[v] = out[c] + 1;
                queue[tail++] = v;
            }
        }
    }
}
void read_grid(Grid *g) {
    memset(g, 0, sizeof(*g));
    FILE *file = open_file("input/map.txt", "r");
    char *line = read_line(file);
    sscanf(line, "%d %d", &g->width, &g->height);
    free(line);
    for (int y = 0; y < g->height; ++y) {
        line = read_line(file);
        strcpy(g->rows[y], line);
        free(line);
    }
    fclose(file);
    file = open_file("input/agents.csv", "r");
    free(read_line(file));
    while ((line = read_line(file))) {
        int id, sx, sy, gx, gy;
        sscanf(line, "%d,%d,%d,%d,%d", &id, &sx, &sy, &gx, &gy);
        g->agents[g->agent_count++] = (Agent){sy * g->width + sx, gy * g->width + gx};
        free(line);
    }
    fclose(file);
    for (int i = 0; i < g->agent_count; ++i)
        distances(g, g->agents[i].goal, g->distance[i]);
}
