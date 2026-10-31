#include "clustering.h"
#include <math.h>
#include <string.h>

void ordered_children(Tree *tree) {
    int minimum[MAX_NODES];
    for (int i = 0; i < tree->count; ++i) minimum[i] = i;
    for (int step = 0; step < tree->count - 1; ++step) {
        Merge merge = tree->merges[step];
        bool forward = minimum[merge.a] < minimum[merge.b];
        tree->children[step][0] = forward ? merge.a : merge.b;
        tree->children[step][1] = forward ? merge.b : merge.a;
        minimum[tree->count + step] = forward ? minimum[merge.a] : minimum[merge.b];
    }
}
void leaf_order(Tree *tree) {
    int pending[MAX_NODES], size = 1, position = 0;
    pending[0] = 2 * tree->count - 2;
    while (size) {
        int node = pending[--size];
        if (node < tree->count) tree->order[position++] = node;
        else {
            pending[size++] = tree->children[node - tree->count][1];
            pending[size++] = tree->children[node - tree->count][0];
        }
    }
}
int column_position(double height, double maximum, int width) {
    double position = floor(height / maximum * width);
    return position > width ? width + 1 : (int)position;
}
static void mark(int *cell, int value) { if (*cell < value) *cell = value; }
Lines dendrogram_rows(const Tree *tree, const Dataset *data, double maximum, const int *cuts, size_t cut_count, int width) {
    int grid[MAX_OBSERVATIONS][101] = {{0}}, anchor[MAX_NODES] = {0}, columns[MAX_OBSERVATIONS];
    for (int row = 0; row < tree->count; ++row) anchor[tree->order[row]] = row;
    for (size_t cut = 0; cut < cut_count; ++cut) if (cuts[cut] <= width) for (int row = 0; row < tree->count; ++row) mark(&grid[row][cuts[cut]], 1);
    for (int step = 0; step < tree->count - 1; ++step) columns[step] = column_position(tree->heights[step], maximum, width);
    for (int step = 0; step < tree->count - 1; ++step) {
        int upper = tree->children[step][0], lower = tree->children[step][1], x = columns[step];
        mark(&grid[anchor[upper]][x], 4);
        mark(&grid[anchor[lower]][x], 4);
        for (int row = anchor[upper] + 1; row < anchor[lower]; ++row) mark(&grid[row][x], 3);
        for (int which = 0; which < 2; ++which) {
            int child = tree->children[step][which], start = child < tree->count ? 0 : columns[child - tree->count] + 1;
            for (int column = start; column < x; ++column) mark(&grid[anchor[child]][column], 2);
        }
        anchor[tree->count + step] = (anchor[upper] + anchor[lower]) / 2;
    }
    int id_width = 0, label_width = 0;
    for (int i = 0; i < tree->count; ++i) {
        if ((int)strlen(data->ids[i]) > id_width) id_width = (int)strlen(data->ids[i]);
        if ((int)strlen(data->labels[i]) > label_width) label_width = (int)strlen(data->labels[i]);
    }
    Lines rows = {0};
    for (int row = 0; row < tree->count; ++row) {
        int leaf = tree->order[row];
        Text line = {0};
        text_add(&line, "%-*s %-*s ", id_width, data->ids[leaf], label_width, data->labels[leaf]);
        for (int x = 0; x <= width; ++x) text_add(&line, "%c", " :-|+"[grid[row][x]]);
        while (line.length && line.data[line.length - 1] == ' ') line.data[--line.length] = '\0';
        add_line(&rows, "%s", line.data);
    }
    Text scale = {0};
    text_add(&scale, "%*s", id_width + label_width + 2, "");
    for (int x = 0; x <= width; ++x) text_add(&scale, "%c", x % 10 ? '-' : '+');
    add_line(&rows, "%s", scale.data);
    return rows;
}
