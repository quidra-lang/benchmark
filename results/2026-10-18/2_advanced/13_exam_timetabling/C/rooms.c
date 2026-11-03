#include "timetable.h"

static int room_compare(const void *first, const void *second) {
    const Room *a = first, *b = second;
    return a->capacity != b->capacity ? a->capacity - b->capacity : strcmp(a->id, b->id);
}
void load_rooms(Scheduler *scheduler) {
    Lines lines = read_lines("input/rooms.csv");
    for (int i = 1; i < lines.count; ++i) {
        char *id = lines.items[i], *text = strchr(id, ',');
        *text++ = '\0';
        bool duplicate = false;
        for (int j = 0; j < scheduler->room_count; ++j)
            if (!strcmp(scheduler->rooms[j].id, id)) duplicate = true;
        int capacity = atoi(text);
        if (duplicate) add_line(&scheduler->errors, "rooms.csv line %d: duplicate room %s", i + 1, id);
        else if (capacity < 1) add_line(&scheduler->errors, "rooms.csv line %d: bad capacity %s", i + 1, text);
        else {
            Room *room = &scheduler->rooms[scheduler->room_count++];
            strcpy(room->id, id); room->capacity = capacity;
        }
    }
    qsort(scheduler->rooms, (size_t)scheduler->room_count, sizeof(Room), room_compare);
    scheduler->largest_room = scheduler->rooms[scheduler->room_count - 1].capacity;
}
bool pack(const Scheduler *scheduler, Courses courses, Placement *placements) {
    int remaining[MAX_ROOMS], durations[MAX_ROOMS] = {0};
    for (int r = 0; r < scheduler->room_count; ++r) remaining[r] = scheduler->rooms[r].capacity;
    sort_courses(scheduler, &courses, NULL);
    for (int i = 0; i < courses.count; ++i) {
        int c = courses.items[i], r;
        const Course *course = &scheduler->courses[c];
        for (r = 0; r < scheduler->room_count; ++r)
            if (remaining[r] >= course->size && (!durations[r] || durations[r] == course->duration)) break;
        if (r == scheduler->room_count) return false;
        int first = scheduler->rooms[r].capacity - remaining[r] + 1;
        if (placements) placements[i] = (Placement){c, r, first, first + course->size - 1};
        remaining[r] -= course->size; durations[r] = course->duration;
    }
    return true;
}
