#include "railway.h"
#include <stdlib.h>
#include <string.h>

int section_index(const Layout *l, const char *name) {
    for (int i = 0; i < l->section_count; ++i)
        if (strcmp(l->sections[i].name, name) == 0)
            return i;
    return -1;
}
int point_index(const Layout *l, const char *name) {
    for (int i = 0; i < l->point_count; ++i)
        if (strcmp(l->points[i].name, name) == 0)
            return i;
    return -1;
}
int signal_index(const Layout *l, const char *name) {
    for (int i = 0; i < l->signal_count; ++i)
        if (strcmp(l->signals[i].name, name) == 0)
            return i;
    return -1;
}
int buffer_index(const Layout *l, const char *name) {
    for (int i = 0; i < l->buffer_count; ++i)
        if (strcmp(l->buffers[i].name, name) == 0)
            return i;
    return -1;
}
int boundary_index(const Layout *l, const char *name) {
    for (int i = 0; i < l->boundary_count; ++i)
        if (strcmp(l->boundaries[i].name, name) == 0)
            return i;
    return -1;
}
bool occupied(const Section *s) { return s->failed || s->occupants != 0; }
bool detected(const Point *p) { return !p->moving && !p->failed; }
static void position(Layout *l, int row, int col) {
    if (row + 1 > l->height)
        l->height = row + 1;
    if (col + 1 > l->width)
        l->width = col + 1;
}
void read_layout(Layout *l) {
    *l = (Layout){0};
    for (int i = 0; i < 40; ++i)
        for (int d = 0; d < 2; ++d)
            l->signal_at[i][d] = -1;
    FILE *file = open_file("input/layout.txt", "r");
    char *line;
    while ((line = read_line(file))) {
        Words words = split_words(line);
        char **a = words.items;
        if (strcmp(a[0], "SECTION") == 0) {
            Section *s = &l->sections[l->section_count++];
            strcpy(s->name, a[1]);
            s->length = atoi(a[2]);
            s->row = atoi(a[3]);
            s->first = atoi(a[4]);
            s->last = atoi(a[5]);
            s->route = -1;
            position(l, s->row, s->last);
        } else if (strcmp(a[0], "JOINT") == 0) {
            int x = section_index(l, a[1]), y = section_index(l, a[2]);
            l->ends[x][1] = (Endpoint){END_SECTION, y, false};
            l->ends[y][0] = (Endpoint){END_SECTION, x, false};
        } else if (strcmp(a[0], "POINT") == 0) {
            int index = l->point_count++;
            Point *p = &l->points[index];
            strcpy(p->name, a[1]);
            p->side = a[2][0];
            p->common = section_index(l, a[3]);
            p->normal = section_index(l, a[4]);
            p->reverse = section_index(l, a[5]);
            p->row = atoi(a[6]);
            p->col = atoi(a[7]);
            p->position = p->target = 'N';
            p->completion = -1;
            int side = p->side == 'R', branch = !side;
            l->ends[p->common][side] = (Endpoint){END_POINT, index, true};
            l->ends[p->normal][branch] = l->ends[p->reverse][branch] =
                (Endpoint){END_POINT, index, false};
            position(l, p->row, p->col);
        } else if (strcmp(a[0], "SIGNAL") == 0) {
            int index = l->signal_count++;
            Signal *g = &l->signals[index];
            strcpy(g->name, a[1]);
            g->section = section_index(l, a[2]);
            g->direction = strcmp(a[3], "UP") == 0 ? DIR_UP : DIR_DOWN;
            g->row = atoi(a[4]);
            g->col = atoi(a[5]);
            l->signal_at[g->section][g->direction] = index;
            position(l, g->row, g->col);
        } else if (strcmp(a[0], "BUFFER") == 0) {
            int index = l->buffer_count++;
            Buffer *b = &l->buffers[index];
            strcpy(b->name, a[1]);
            b->section = section_index(l, a[2]);
            b->end = a[3][0];
            b->row = atoi(a[4]);
            b->col = atoi(a[5]);
            l->ends[b->section][b->end == 'R'] = (Endpoint){END_BUFFER, index, false};
            position(l, b->row, b->col);
        } else if (strcmp(a[0], "BOUNDARY") == 0) {
            int index = l->boundary_count++;
            Boundary *b = &l->boundaries[index];
            strcpy(b->name, a[1]);
            b->section = section_index(l, a[2]);
            b->end = a[3][0];
            l->ends[b->section][b->end == 'R'] = (Endpoint){END_BOUNDARY, index, false};
        } else {
            Label *label = &l->labels[l->label_count++];
            label->row = atoi(a[1]);
            label->col = atoi(a[2]);
            strcpy(label->text, a[3]);
            position(l, label->row, label->col + (int)strlen(label->text) - 1);
        }
        free(line);
    }
    fclose(file);
}
Endpoint beyond(const Layout *l, int section, Direction direction) {
    Endpoint endpoint = l->ends[section][direction == DIR_UP];
    if (endpoint.kind != END_POINT)
        return endpoint;
    const Point *p = &l->points[endpoint.index];
    if (p->moving)
        return (Endpoint){END_IMPASSABLE, 0, false};
    int selected = p->position == 'N' ? p->normal : p->reverse;
    if (endpoint.common)
        return (Endpoint){END_SECTION, selected, false};
    if (selected != section)
        return (Endpoint){END_IMPASSABLE, 0, false};
    return (Endpoint){END_SECTION, p->common, false};
}
