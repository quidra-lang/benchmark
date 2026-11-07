#include "spatial.h"
void points_push(Points *values, Point value) {
    if (values->n == values->capacity) {
        values->capacity = values->capacity ? values->capacity * 2 : 8;
        values->v = realloc(values->v, (size_t)values->capacity * sizeof *values->v);
    }
    values->v[values->n++] = value;
}
void points_insert(Points *values, Point value) {
    points_push(values, value);
    int position = values->n - 1;
    while (position > 0 && value.id < values->v[position - 1].id) {
        values->v[position] = values->v[position - 1];
        --position;
    }
    values->v[position] = value;
}
void points_remove(Points *values, int id) {
    for (int i = 0; i < values->n; ++i)
        if (values->v[i].id == id) {
            memmove(values->v + i, values->v + i + 1, (size_t)(values->n - i - 1) * sizeof *values->v);
            --values->n;
            return;
        }
}
void objects_push(Objects *values, Object value) {
    if (values->n == values->capacity) {
        values->capacity = values->capacity ? values->capacity * 2 : 8;
        values->v = realloc(values->v, (size_t)values->capacity * sizeof *values->v);
    }
    values->v[values->n++] = value;
}
Box point_box(Point point) {
    return (Box){point.x, point.y, point.x, point.y};
}
Input read_input(void) {
    Input out = {0};
    FILE *file = fopen("input/points.csv", "r");
    char text[256];
    fgets(text, sizeof text, file);
    while (fgets(text, sizeof text, file)) {
        Point point;
        long long x, y;
        sscanf(text, "%d,%lld,%lld", &point.id, &x, &y);
        point.x = x;
        point.y = y;
        points_push(&out.points, point);
    }
    fclose(file);
    file = fopen("input/rects.csv", "r");
    fgets(text, sizeof text, file);
    while (fgets(text, sizeof text, file)) {
        Object object;
        long long x1, y1, x2, y2;
        sscanf(text, "%d,%lld,%lld,%lld,%lld", &object.id, &x1, &y1, &x2, &y2);
        object.box = (Box){x1, y1, x2, y2};
        objects_push(&out.rectangles, object);
    }
    fclose(file);
    file = fopen("input/params.txt", "r");
    char key[32];
    Params *p = &out.params;
    fscanf(file, "%31s %d", key, &p->world);
    fscanf(file, "%31s %d", key, &p->bucket);
    fscanf(file, "%31s %d %d", key, &p->maximum, &p->minimum);
    fscanf(file, "%31s %d", key, &p->grid);
    fclose(file);
    file = fopen("input/queries.txt", "r");
    while (fgets(text, sizeof text, file)) {
        Command command = {0};
        char *word = strtok(text, " \n");
        strcpy(command.name, word);
        while ((word = strtok(NULL, " \n")))
            command.values[command.n++] = strtoll(word, NULL, 10);
        out.commands = realloc(out.commands, (size_t)(out.ncommands + 1) * sizeof *out.commands);
        out.commands[out.ncommands++] = command;
    }
    fclose(file);
    return out;
}
