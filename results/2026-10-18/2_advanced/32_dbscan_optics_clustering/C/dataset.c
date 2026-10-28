#include "clustering.h"
static int point_compare(const void *a, const void *b) {
    int x = ((const Point *)a)->id, y = ((const Point *)b)->id;
    return (x > y) - (x < y);
}
Input read_input(void) {
    Input input = {0};
    FILE *file = fopen("input/points.csv", "r");
    free(read_line(file));
    char *line;
    int capacity = 0;
    while ((line = read_line(file))) {
        if (input.count == capacity) {
            capacity = capacity ? capacity * 2 : 64;
            input.points = realloc(input.points, (size_t)capacity * sizeof *input.points);
        }
        Point *point = input.points + input.count++;
        sscanf(line, "%d,%d,%d", &point->id, &point->x, &point->y);
        free(line);
    }
    fclose(file);
    qsort(input.points, (size_t)input.count, sizeof *input.points, point_compare);
    file = fopen("input/params.txt", "r");
    Params *p = &input.params;
    int row = 0;
    while ((line = read_line(file))) {
        char *key = strtok(line, " "), *value = strtok(NULL, " ");
        (void)key;
        switch (row++) {
        case 0:
            do {
                push(&p->eps, atoi(value));
            } while ((value = strtok(NULL, " ")));
            break;
        case 1:
            p->min_points = atoi(value);
            break;
        case 2:
            p->max_eps = atoi(value);
            break;
        case 3:
            do {
                push(&p->extract, atoi(value));
            } while ((value = strtok(NULL, " ")));
            break;
        case 4:
            sscanf(value, "%d/%d", &p->xi_u, &p->xi_v);
            break;
        case 5:
            p->xi_size = atoi(value);
            break;
        case 6:
            p->width = atoi(value);
            p->height = atoi(strtok(NULL, " "));
            break;
        case 7:
            p->kwidth = atoi(value);
            p->kheight = atoi(strtok(NULL, " "));
            break;
        case 8:
            p->rwidth = atoi(value);
            break;
        }
        free(line);
    }
    fclose(file);
    return input;
}
Integer distance(Point a, Point b) {
    Integer x = (Integer)a.x - b.x, y = (Integer)a.y - b.y;
    return x * x + y * y;
}
