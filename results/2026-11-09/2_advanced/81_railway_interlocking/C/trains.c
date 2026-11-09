#include "railway.h"
#include <stdlib.h>
#include <string.h>

static int train_index(const Train trains[26], int count, const char *name) {
    for (int i = 0; i < count; ++i)
        if (strcmp(trains[i].name, name) == 0)
            return i;
    return -1;
}
void read_trains(Layout *l, Interlocking *i, Train trains[26], int *count,
                 TrainRequest requests[500], int *request_count) {
    *count = *request_count = 0;
    FILE *file = open_file("input/trains.txt", "r");
    char *line;
    while ((line = read_line(file))) {
        Words words = split_words(line);
        char **a = words.items;
        if (strcmp(a[0], "TRAIN") == 0) {
            Train *t = &trains[*count];
            *t = (Train){.symbol = (char)('a' + *count),
                         .length = atoi(a[2]),
                         .acceleration = atoi(a[3]),
                         .deceleration = atoi(a[4]),
                         .max_speed = atoi(a[5]),
                         .entry = boundary_index(l, a[6]),
                         .scheduled_entry = atoi(a[7]),
                         .entry_speed = atoi(a[8]),
                         .actual_entry = -1,
                         .actual_exit = -1,
                         .await_departure = -1};
            strcpy(t->name, a[1]);
            ++*count;
        } else {
            int index = train_index(trains, *count, a[1]);
            Train *t = &trains[index];
            if (strcmp(a[0], "REQUEST") == 0)
                requests[(*request_count)++] =
                    (TrainRequest){index, route_index(i, a[2]), atoi(a[3])};
            else if (strcmp(a[0], "EXIT") == 0) {
                t->exit = boundary_index(l, a[2]);
                t->scheduled_exit = atoi(a[3]);
            } else {
                t->stops[t->stop_count++] = (Stop){.turn = strcmp(a[0], "TURN") == 0,
                                                   .section = section_index(l, a[2]),
                                                   .dwell = atoi(a[3]),
                                                   .scheduled_arrival = atoi(a[4]),
                                                   .scheduled_departure = atoi(a[5]),
                                                   .arrival = -1,
                                                   .departure = -1};
            }
        }
        free(line);
    }
    fclose(file);
}
int braking_distance(int speed, int deceleration) {
    int n = speed / deceleration;
    return n * speed - deceleration * n * (n + 1) / 2;
}
int select_speed(const Train *t, int distance) {
    int low = t->speed > t->deceleration ? t->speed - t->deceleration : 0;
    if (t->emergency)
        return low;
    int high = t->speed + t->acceleration;
    if (high > t->max_speed)
        high = t->max_speed;
    for (int speed = high; speed >= low; --speed)
        if (distance < 0 || speed + braking_distance(speed, t->deceleration) <= distance)
            return speed;
    return low;
}
PathSection head_section(const Train *t) {
    PathSection result = t->path[0];
    for (int i = 0; i < t->path_count; ++i)
        if (t->path[i].start < t->head)
            result = t->path[i];
    return result;
}
int occupied_sections(const Train *t, const Layout *l, PathSection out[40]) {
    int count = 0;
    for (int i = 0; i < t->path_count; ++i) {
        PathSection part = t->path[i];
        if (part.start < t->head &&
            part.start + l->sections[part.section].length > t->head - t->length)
            out[count++] = part;
    }
    return count;
}
