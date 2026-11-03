#include "railway.h"
#include <stdlib.h>
#include <string.h>

int route_index(const Interlocking *i, const char *name) {
    for (int n = 0; n < i->count; ++n)
        if (strcmp(i->routes[n].name, name) == 0)
            return n;
    return -1;
}
static Requirement *read_requirements(Layout *l, char *text, size_t *count) {
    *count = 0;
    if (strcmp(text, "-") == 0)
        return NULL;
    size_t capacity = 1;
    for (char *p = text; *p; ++p)
        if (*p == ',')
            ++capacity;
    Requirement *result = checked_realloc(NULL, capacity * sizeof(Requirement));
    char *part = text;
    for (;;) {
        char *next = strchr(part, ',');
        if (next)
            *next++ = 0;
        char *colon = strchr(part, ':');
        *colon++ = 0;
        result[(*count)++] = (Requirement){point_index(l, part), colon[0]};
        if (!next)
            break;
        part = next;
    }
    return result;
}
static int read_sections(Layout *l, char *text, int *out) {
    if (strcmp(text, "-") == 0)
        return 0;
    int count = 0;
    char *part = text;
    for (;;) {
        char *next = strchr(part, ',');
        if (next)
            *next++ = 0;
        out[count++] = section_index(l, part);
        if (!next)
            return count;
        part = next;
    }
}
void read_interlocking(Interlocking *interlocking, Layout *l) {
    *interlocking = (Interlocking){0};
    FILE *file = open_file("input/routes.txt", "r");
    char *line;
    while ((line = read_line(file))) {
        Words words = split_words(line);
        char **a = words.items;
        Route *r = &interlocking->routes[interlocking->count++];
        strcpy(r->name, a[1]);
        r->start = signal_index(l, a[2]);
        strcpy(r->finish, a[3]);
        r->direction = l->signals[r->start].direction;
        r->points = read_requirements(l, a[4], &r->point_count);
        r->flank = read_requirements(l, a[7], &r->flank_count);
        r->section_count = read_sections(l, a[5], r->sections);
        r->overlap_count = read_sections(l, a[6], r->overlap);
        r->conflict_text = copy_string(a[8]);
        r->approach = atoi(a[9]);
        r->release_time = -1;
        free(line);
    }
    fclose(file);
    for (int n = 0; n < interlocking->count; ++n) {
        Route *r = &interlocking->routes[n];
        char *part = r->conflict_text;
        if (strcmp(part, "-") != 0) {
            size_t capacity = 1;
            for (char *p = part; *p; ++p)
                if (*p == ',')
                    ++capacity;
            r->conflicts = checked_realloc(NULL, capacity * sizeof(int));
            for (;;) {
                char *next = strchr(part, ',');
                if (next)
                    *next++ = 0;
                r->conflicts[r->conflict_count++] = route_index(interlocking, part);
                if (!next)
                    break;
                part = next;
            }
        }
        free(r->conflict_text);
        r->conflict_text = NULL;
    }
}
size_t requirement_count(const Route *r) { return r->point_count + r->flank_count; }
Requirement requirement_at(const Route *r, size_t index) {
    return index < r->point_count ? r->points[index] : r->flank[index - r->point_count];
}
static void remove_point_locks(Point *point, int route) {
    uint64_t bit = UINT64_C(1) << route;
    point->normal_locks &= ~bit;
    point->reverse_locks &= ~bit;
}
void lock_route(Interlocking *i, Layout *l, int index) {
    Route *r = &i->routes[index];
    uint64_t bit = UINT64_C(1) << index;
    r->state = ROUTE_LOCKED;
    memset(r->passed, 0, sizeof(r->passed));
    for (int j = 0; j < r->section_count; ++j)
        l->sections[r->sections[j]].route = index;
    for (int j = 0; j < r->overlap_count; ++j)
        l->sections[r->overlap[j]].overlaps |= bit;
    for (size_t j = 0; j < requirement_count(r); ++j) {
        Requirement q = requirement_at(r, j);
        Point *p = &l->points[q.point];
        if (q.position == 'N')
            p->normal_locks |= bit;
        else
            p->reverse_locks |= bit;
    }
    r->overlap_locked = true;
    r->overlap_counter = 0;
    r->release_time = -1;
}
void unlock_section(Interlocking *i, Layout *l, int route, int section) {
    (void)i;
    if (l->sections[section].route == route)
        l->sections[section].route = -1;
    for (int j = 0; j < l->point_count; ++j)
        if (l->points[j].common == section)
            remove_point_locks(&l->points[j], route);
}
void unlock_overlap(Interlocking *i, Layout *l, int route) {
    Route *r = &i->routes[route];
    uint64_t bit = UINT64_C(1) << route;
    for (int j = 0; j < r->overlap_count; ++j) {
        int section = r->overlap[j];
        l->sections[section].overlaps &= ~bit;
        for (int p = 0; p < l->point_count; ++p)
            if (l->points[p].common == section)
                remove_point_locks(&l->points[p], route);
    }
    r->overlap_locked = false;
}
void release_route(Interlocking *i, Layout *l, int route) {
    Route *r = &i->routes[route];
    for (int j = 0; j < r->section_count; ++j)
        if (l->sections[r->sections[j]].route == route)
            l->sections[r->sections[j]].route = -1;
    if (r->overlap_locked)
        unlock_overlap(i, l, route);
    for (int p = 0; p < l->point_count; ++p)
        remove_point_locks(&l->points[p], route);
    r->state = ROUTE_NONE;
}
