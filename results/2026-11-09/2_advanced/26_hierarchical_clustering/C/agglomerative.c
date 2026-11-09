#include "clustering.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

static void coefficients(const char *method, int a, int b, int k, double result[4]) {
    double merged = a + b;
    result[0] = result[1] = 0.5;
    result[2] = result[3] = 0;
    if (!strcmp(method, "single")) result[3] = -0.5;
    else if (!strcmp(method, "complete")) result[3] = 0.5;
    else if (!strcmp(method, "average") || !strcmp(method, "centroid")) {
        result[0] = a / merged;
        result[1] = b / merged;
        if (!strcmp(method, "centroid")) result[2] = -(a * b) / (merged * merged);
    } else if (!strcmp(method, "median")) result[2] = -0.25;
    else if (!strcmp(method, "ward")) {
        double total = a + b + k;
        result[0] = (a + k) / total;
        result[1] = (b + k) / total;
        result[2] = -k / total;
    }
}
void agglomerate(const Matrix delta, int count, const char *method, Merge *merges) {
    double (*values)[MAX_NODES] = calloc(MAX_NODES, sizeof *values);
    if (!values) exit(1);
    bool squared = !strcmp(method, "centroid") || !strcmp(method, "median") || !strcmp(method, "ward");
    bool active[MAX_NODES] = {0};
    int sizes[MAX_NODES] = {0};
    for (int i = 0; i < count; ++i) {
        active[i] = true;
        sizes[i] = 1;
        for (int j = 0; j < count; ++j) values[i][j] = squared ? delta[i][j] * delta[i][j] : delta[i][j];
    }
    for (int step = 0; step < count - 1; ++step) {
        int a = -1, b = -1, node = count + step;
        double best = 0;
        for (int i = 0; i < node; ++i) if (active[i]) for (int j = i + 1; j < node; ++j) if (active[j]) {
            if (a < 0 || values[i][j] < best) { a = i; b = j; best = values[i][j]; }
        }
        sizes[node] = sizes[a] + sizes[b];
        merges[step] = (Merge){a, b, sizes[node], squared ? sqrt(best) : best};
        for (int k = 0; k < node; ++k) if (active[k] && k != a && k != b) {
            double c[4];
            coefficients(method, sizes[a], sizes[b], sizes[k], c);
            double value = c[0] * values[a][k] + c[1] * values[b][k] + c[2] * values[a][b] + c[3] * fabs(values[a][k] - values[b][k]);
            values[node][k] = values[k][node] = value;
        }
        active[a] = active[b] = false;
        active[node] = true;
    }
    free(values);
}
void minimum_spanning_tree(const Matrix delta, int count, Edge *edges) {
    bool included[MAX_OBSERVATIONS] = {true};
    double keys[MAX_OBSERVATIONS];
    int parents[MAX_OBSERVATIONS] = {0};
    for (int i = 0; i < count; ++i) keys[i] = delta[0][i];
    for (int step = 0; step < count - 1; ++step) {
        int chosen = -1;
        for (int i = 0; i < count; ++i) if (!included[i] && (chosen < 0 || keys[i] < keys[chosen])) chosen = i;
        included[chosen] = true;
        edges[step] = (Edge){parents[chosen], chosen, keys[chosen]};
        for (int i = 0; i < count; ++i) if (!included[i] && delta[chosen][i] < keys[i]) { keys[i] = delta[chosen][i]; parents[i] = chosen; }
    }
}
