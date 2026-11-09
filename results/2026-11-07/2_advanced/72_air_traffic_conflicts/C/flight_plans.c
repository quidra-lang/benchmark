#include "airspace.h"
static char *read_line(FILE *file) {
    size_t count = 0, capacity = 128;
    char *line = malloc(capacity);
    int ch;
    while ((ch = fgetc(file)) != EOF && ch != '\n') {
        if (count + 1 == capacity) {
            capacity *= 2;
            line = realloc(line, capacity);
        }
        line[count++] = (char)ch;
    }
    if (ch == EOF && count == 0) {
        free(line);
        return NULL;
    }
    line[count] = 0;
    return line;
}
static int split(char *text, const char *separator, char **out) {
    int count = 0;
    for (char *field = strtok(text, separator); field; field = strtok(NULL, separator))
        out[count++] = field;
    return count;
}
static int plan_compare(const void *a, const void *b) {
    return strcmp(((const Plan *)a)->callsign, ((const Plan *)b)->callsign);
}
void read_inputs(Input *out) {
    memset(out, 0, sizeof *out);
    FILE *file = fopen("input/aircraft.txt", "r");
    char *text, *p[32];
    while ((text = read_line(file))) {
        split(text, " ", p);
        AircraftType *v = &out->types[out->type_count++];
        strcpy(v->name, p[0]);
        v->climb = atoi(p[1]);
        v->descent = atoi(p[2]);
        v->minimum = atoi(p[3]);
        free(text);
    }
    fclose(file);
    file = fopen("input/sectors.txt", "r");
    while ((text = read_line(file))) {
        split(text, " ", p);
        Sector *v = &out->sectors[out->sector_count++];
        strcpy(v->name, p[0]);
        v->x1 = atoi(p[1]);
        v->y1 = atoi(p[2]);
        v->x2 = atoi(p[3]);
        v->y2 = atoi(p[4]);
        v->lower = strtoll(p[5], NULL, 10);
        v->upper = strtoll(p[6], NULL, 10);
        v->capacity = strtoll(p[7], NULL, 10);
        free(text);
    }
    fclose(file);
    file = fopen("input/flights.csv", "r");
    free(read_line(file));
    while ((text = read_line(file))) {
        split(text, ",", p);
        Plan *v = &out->plans[out->plan_count++];
        strcpy(v->callsign, p[0]);
        for (int i = 0; i < out->type_count; ++i)
            if (!strcmp(out->types[i].name, p[1]))
                v->type = i;
        v->departure = strtoll(p[2], NULL, 10);
        v->level = strtoll(p[3], NULL, 10);
        v->speed_initial = v->speed = atoi(p[4]);
        char *waypoints[8];
        int count = split(p[5], " ", waypoints);
        for (int i = 0; i < count; ++i) {
            char *values[3];
            int n = split(waypoints[i], ":", values);
            v->waypoints[v->waypoint_count++] =
                (Waypoint){atoi(values[0]), atoi(values[1]), n == 3,
                           n == 3 ? strtoll(values[2], NULL, 10) : 0};
        }
        free(text);
    }
    fclose(file);
    file = fopen("input/params.txt", "r");
    Params *s = &out->params;
    int row = 0;
    while ((text = read_line(file))) {
        char *token = strtok(text, " ");
        Integer values[6];
        int count = 0;
        while ((token = strtok(NULL, " "))) {
            Integer value = strtoll(token, NULL, 10);
            if (row == 6)
                Integers_append(&s->snapshots, value);
            else
                values[count++] = value;
        }
        switch (row) {
        case 0:
            s->horizontal = values[0];
            s->vertical = values[1];
            break;
        case 1:
            s->lookahead = values[0];
            break;
        case 2:
            s->max_delay = values[0];
            break;
        case 3:
            s->level_min = values[0];
            s->level_max = values[1];
            break;
        case 4:
            s->sample_start = values[0];
            s->sample_end = values[1];
            break;
        case 5:
            memcpy(s->radar, values, sizeof values);
            break;
        case 7:
            s->leader = values[0];
            break;
        case 8:
            s->alert = values[0];
            break;
        }
        ++row;
        free(text);
    }
    fclose(file);
    qsort(out->plans, (size_t)out->plan_count, sizeof *out->plans, plan_compare);
}
int flight_levels(const Plan *plan, Integer out[8]) {
    int count = 0;
    out[count++] = plan->level + plan->offset;
    for (int i = 1; i < plan->waypoint_count; ++i)
        if (plan->waypoints[i].has_level)
            out[count++] = plan->waypoints[i].level + plan->offset;
    return count;
}
