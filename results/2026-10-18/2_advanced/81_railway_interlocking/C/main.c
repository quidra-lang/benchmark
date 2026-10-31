#include "railway.h"
#include <errno.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

const char *const direction_names[2] = {"UP", "DOWN"};
const char *const aspect_names[3] = {"RED", "YELLOW", "GREEN"};
const char *const route_state_names[4] = {"", "LOCKED", "USED", "APPROACH"};
const char *const train_state_names[3] = {"WAITING", "RUNNING", "EXITED"};
void *checked_realloc(void *pointer, size_t size) {
    void *result = realloc(pointer, size ? size : 1);
    if (!result) {
        fputs("allocation failed\n", stderr);
        exit(EXIT_FAILURE);
    }
    return result;
}
char *copy_string(const char *text) {
    char *result = checked_realloc(NULL, strlen(text) + 1);
    strcpy(result, text);
    return result;
}
static char *format_arguments(const char *format, va_list arguments) {
    va_list copy;
    va_copy(copy, arguments);
    int length = vsnprintf(NULL, 0, format, copy);
    va_end(copy);
    if (length < 0)
        exit(EXIT_FAILURE);
    char *text = checked_realloc(NULL, (size_t)length + 1);
    vsnprintf(text, (size_t)length + 1, format, arguments);
    return text;
}
char *format_text(const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    char *text = format_arguments(format, arguments);
    va_end(arguments);
    return text;
}
FILE *open_file(const char *path, const char *mode) {
    FILE *file = fopen(path, mode);
    if (!file) {
        perror(path);
        exit(EXIT_FAILURE);
    }
    return file;
}
char *read_line(FILE *file) {
    size_t count = 0, capacity = 128;
    char *line = checked_realloc(NULL, capacity);
    int c;
    while ((c = fgetc(file)) != EOF && c != '\n') {
        if (count + 1 == capacity) {
            capacity *= 2;
            line = checked_realloc(line, capacity);
        }
        line[count++] = (char)c;
    }
    if (!count && c == EOF) {
        free(line);
        return NULL;
    }
    line[count] = 0;
    return line;
}
Words split_words(char *line) {
    Words result = {0};
    char *part = line;
    for (;;) {
        result.items[result.count++] = part;
        char *next = strchr(part, ' ');
        if (!next)
            break;
        *next = 0;
        part = next + 1;
    }
    return result;
}
void lines_add(TextLines *lines, char *text) {
    if (lines->count == lines->capacity) {
        lines->capacity = lines->capacity ? 2 * lines->capacity : 64;
        lines->items = checked_realloc(lines->items, lines->capacity * sizeof(char *));
    }
    lines->items[lines->count++] = text;
}
void lines_free(TextLines *lines) {
    for (size_t i = 0; i < lines->count; ++i)
        free(lines->items[i]);
    free(lines->items);
}
int bit_count(uint64_t mask) {
    int count = 0;
    while (mask) {
        mask &= mask - 1;
        ++count;
    }
    return count;
}
typedef enum {
    EVENT_REQUEST,
    EVENT_CANCEL,
    EVENT_THROW,
    EVENT_TCFAIL,
    EVENT_TCFIX,
    EVENT_POINTFAIL,
    EVENT_POINTFIX
} EventKind;
typedef struct {
    int time, target;
    EventKind kind;
    char position;
} Event;
typedef struct {
    int number, route, time;
    char reason[64];
} Request;
typedef struct {
    int on_time, late, missing, total_delay, max_delay;
} Punctuality;
typedef struct {
    Layout layout;
    Interlocking interlocking;
    Train trains[26];
    TrainRequest planned[500];
    Event events[200];
    int train_count, planned_count, event_count;
    bool snapshot_times[10001];
    Request queue[700];
    int queue_count;
    Safety safety;
    TextLines log, snapshots;
    int time, end_time, throw_time, overlap_time, total_requests, granted, dropped;
} Simulator;
static void log_event(Simulator *s, const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    char *body = format_arguments(format, arguments);
    va_end(arguments);
    lines_add(&s->log, format_text("%d %s", s->time, body));
    free(body);
}
static void start_throw(Simulator *s, int index, char position) {
    Point *p = &s->layout.points[index];
    p->moving = true;
    p->target = position;
    p->completion = s->time + s->throw_time;
    log_event(s, "MOVE %s %c until %d", p->name, position, p->completion);
}
static void add_request(Simulator *s, int index, const char *requester) {
    Request *q = &s->queue[s->queue_count++];
    *q = (Request){.number = ++s->total_requests, .route = index, .time = s->time};
    strcpy(q->reason, "none");
    Route *r = &s->interlocking.routes[index];
    ++r->requests;
    log_event(s, "REQUEST q%d %s %s", q->number, r->name, requester);
}
static void cancel_route(Simulator *s, int index) {
    Route *r = &s->interlocking.routes[index];
    int remaining = 0;
    bool removed = false;
    for (int i = 0; i < s->queue_count; ++i) {
        Request q = s->queue[i];
        if (q.route == index) {
            log_event(s, "DROP q%d %s", q.number, r->name);
            ++s->dropped;
            removed = true;
        } else
            s->queue[remaining++] = q;
    }
    s->queue_count = remaining;
    if (removed)
        return;
    if (r->state == ROUTE_LOCKED) {
        ++r->cancels;
        Signal *g = &s->layout.signals[r->start];
        if (g->aspect != ASPECT_RED && occupied(&s->layout.sections[g->section])) {
            r->state = ROUTE_APPROACH;
            r->release_time = s->time + r->approach;
            log_event(s, "CANCEL %s approach until %d", r->name, r->release_time);
        } else {
            release_route(&s->interlocking, &s->layout, index);
            log_event(s, "CANCEL %s released", r->name);
        }
    } else
        log_event(s, "CANCEL %s %s", r->name, r->state == ROUTE_NONE ? "none" : "refused");
}
static void execute_event(Simulator *s, const Event *e) {
    if (e->kind == EVENT_REQUEST)
        add_request(s, e->target, "OPERATOR");
    else if (e->kind == EVENT_CANCEL)
        cancel_route(s, e->target);
    else if (e->kind == EVENT_THROW) {
        Point *p = &s->layout.points[e->target];
        const char *reason = (p->normal_locks | p->reverse_locks)       ? "locked"
                             : p->failed                                ? "failed"
                             : p->moving                                ? "moving"
                             : occupied(&s->layout.sections[p->common]) ? "occupied"
                             : p->position == e->position               ? "none"
                                                                        : "start";
        log_event(s, "THROW %s %c %s", p->name, e->position, reason);
        if (strcmp(reason, "start") == 0)
            start_throw(s, e->target, e->position);
    } else if (e->kind == EVENT_TCFAIL || e->kind == EVENT_TCFIX) {
        Section *section = &s->layout.sections[e->target];
        section->failed = e->kind == EVENT_TCFAIL;
        log_event(s, "%s %s", section->failed ? "TCFAIL" : "TCFIX", section->name);
    } else {
        Point *p = &s->layout.points[e->target];
        if (e->kind == EVENT_POINTFAIL) {
            p->failed = true;
            if (p->moving)
                p->completion = -1;
            log_event(s, "POINTFAIL %s", p->name);
        } else {
            p->failed = false;
            log_event(s, "POINTFIX %s", p->name);
            if (p->moving) {
                p->completion = s->time + s->throw_time;
                log_event(s, "MOVE %s %c until %d", p->name, p->target, p->completion);
            }
        }
    }
}
static bool opposite_overlap(const Simulator *s, const Section *section, Direction direction) {
    for (int i = 0; i < s->interlocking.count; ++i)
        if ((section->overlaps & (UINT64_C(1) << i)) &&
            s->interlocking.routes[i].direction != direction)
            return true;
    return false;
}
static void request_reason(const Simulator *s, int index, char out[64]) {
    const Route *r = &s->interlocking.routes[index];
    out[0] = 0;
    if (r->state != ROUTE_NONE) {
        strcpy(out, "busy");
        return;
    }
    for (size_t j = 0; j < r->conflict_count; ++j) {
        const Route *conflict = &s->interlocking.routes[r->conflicts[j]];
        if (conflict->state == ROUTE_LOCKED || conflict->state == ROUTE_APPROACH) {
            snprintf(out, 64, "conflict %s", conflict->name);
            return;
        }
    }
    for (int j = 0; j < r->section_count + r->overlap_count; ++j) {
        bool is_route = j < r->section_count;
        int section_index = is_route ? r->sections[j] : r->overlap[j - r->section_count];
        const Section *section = &s->layout.sections[section_index];
        if (occupied(section)) {
            snprintf(out, 64, "occupied %s", section->name);
            return;
        }
        bool locked =
            section->route >= 0 &&
            (is_route || s->interlocking.routes[section->route].direction != r->direction);
        if (locked || opposite_overlap(s, section, r->direction)) {
            snprintf(out, 64, "locked %s", section->name);
            return;
        }
    }
    for (size_t j = 0; j < requirement_count(r); ++j) {
        Requirement q = requirement_at(r, j);
        const Point *p = &s->layout.points[q.point];
        if (q.position == 'N' ? p->reverse_locks != 0 : p->normal_locks != 0) {
            snprintf(out, 64, "point %s locked", p->name);
            return;
        }
        if ((!p->moving && p->position == q.position) || (p->moving && p->target == q.position))
            continue;
        const char *failure = p->failed                                  ? "failed"
                              : p->moving                                ? "moving"
                              : occupied(&s->layout.sections[p->common]) ? "occupied"
                                                                         : NULL;
        if (failure) {
            snprintf(out, 64, "point %s %s", p->name, failure);
            return;
        }
    }
}
static void judge_requests(Simulator *s) {
    int pending = 0;
    for (int i = 0; i < s->queue_count; ++i) {
        Request q = s->queue[i];
        Route *r = &s->interlocking.routes[q.route];
        char failure[64];
        request_reason(s, q.route, failure);
        if (*failure) {
            if (strcmp(failure, q.reason) != 0) {
                log_event(s, "WAIT q%d %s %s", q.number, r->name, failure);
                strcpy(q.reason, failure);
            }
            s->queue[pending++] = q;
            continue;
        }
        lock_route(&s->interlocking, &s->layout, q.route);
        int wait = s->time - q.time;
        ++s->granted;
        ++r->grants;
        r->wait += wait;
        if (wait > r->maxwait)
            r->maxwait = wait;
        log_event(s, "GRANT q%d %s wait %d", q.number, r->name, wait);
        for (size_t j = 0; j < requirement_count(r); ++j) {
            Requirement requirement = requirement_at(r, j);
            const Point *p = &s->layout.points[requirement.point];
            if (!p->moving && p->position != requirement.position)
                start_throw(s, requirement.point, requirement.position);
        }
    }
    s->queue_count = pending;
}
static int limit_distance(const Simulator *s, const Train *t) {
    if (t->crossed)
        return -1;
    PathSection head = head_section(t);
    int section = head.section,
        distance = head.start + s->layout.sections[section].length - t->head;
    for (;;) {
        int signal = s->layout.signal_at[section][t->direction];
        if (signal >= 0 && s->layout.signals[signal].aspect == ASPECT_RED)
            return distance;
        if (t->next_stop < t->stop_count && t->stops[t->next_stop].section == section)
            return distance;
        Endpoint next = beyond(&s->layout, section, t->direction);
        if (next.kind == END_BOUNDARY)
            return -1;
        if (next.kind != END_SECTION)
            return distance;
        section = next.index;
        distance += s->layout.sections[section].length;
    }
}
static void pass_signal(Simulator *s, Train *t, int index) {
    Signal *g = &s->layout.signals[index];
    Route *route = NULL;
    for (int i = 0; i < s->interlocking.count; ++i) {
        Route *r = &s->interlocking.routes[i];
        if (r->start == index && (r->state == ROUTE_LOCKED || r->state == ROUTE_APPROACH)) {
            route = r;
            break;
        }
    }
    log_event(s, "PASS %s %s %s %s", t->name, g->name, aspect_names[g->aspect],
              route ? route->name : "-");
    ++g->passes;
    ++t->passes;
    if (route) {
        route->state = ROUTE_USED;
        ++route->uses;
    }
    safety_signal_passing(&s->safety, s->time, t, g);
    if (g->aspect == ASPECT_RED) {
        log_event(s, "SPAD %s %s", t->name, g->name);
        t->emergency = true;
    }
}
static void run_train(Simulator *s, Train *t, uint16_t *entered) {
    if (t->state == TRAIN_EXITED)
        return;
    if (t->state == TRAIN_WAITING) {
        Boundary *b = &s->layout.boundaries[t->entry];
        uint16_t bit = (uint16_t)(1u << t->entry);
        if (s->time < t->scheduled_entry || occupied(&s->layout.sections[b->section]) ||
            (*entered & bit))
            return;
        *entered |= bit;
        t->state = TRAIN_RUNNING;
        t->direction = b->end == 'L' ? DIR_UP : DIR_DOWN;
        t->path[0] = (PathSection){b->section, 0};
        t->path_count = 1;
        t->head = 0;
        t->speed = t->entry_speed;
        t->actual_entry = s->time;
        log_event(s, "ENTER %s %s", t->name, b->name);
    }
    if (t->dwelling) {
        Stop *stop = &t->stops[t->next_stop];
        if (s->time < stop->arrival + stop->dwell || s->time < stop->scheduled_departure)
            return;
        t->dwelling = false;
        t->await_departure = t->next_stop++;
        if (stop->turn) {
            PathSection head = head_section(t), parts[40];
            int end = head.start + s->layout.sections[head.section].length,
                count = occupied_sections(t, &s->layout, parts);
            for (int j = 0; j < count; ++j) {
                PathSection part = parts[count - j - 1];
                t->path[j] = (PathSection){
                    part.section, end - (part.start + s->layout.sections[part.section].length)};
            }
            t->path_count = count;
            t->head = end - (t->head - t->length);
            t->direction = t->direction == DIR_UP ? DIR_DOWN : DIR_UP;
            log_event(s, "REVERSE %s %s", t->name, s->layout.sections[stop->section].name);
        }
    }
    int old_speed = t->speed, new_speed = select_speed(t, limit_distance(s, t)),
        remaining = new_speed;
    PathSection current = head_section(t);
    while (remaining > 0) {
        if (t->crossed) {
            t->head += remaining;
            break;
        }
        int end = current.start + s->layout.sections[current.section].length;
        if (t->head + remaining <= end) {
            t->head += remaining;
            break;
        }
        remaining -= end - t->head;
        t->head = end;
        int signal = s->layout.signal_at[current.section][t->direction];
        if (signal >= 0)
            pass_signal(s, t, signal);
        if (t->await_departure >= 0 && t->stops[t->await_departure].section == current.section) {
            t->stops[t->await_departure].departure = s->time;
            t->await_departure = -1;
            log_event(s, "DEPART %s %s", t->name, s->layout.sections[current.section].name);
        }
        Endpoint next = beyond(&s->layout, current.section, t->direction);
        if (next.kind == END_BOUNDARY) {
            t->crossed = true;
            t->boundary_coordinate = end;
        } else {
            if (next.kind != END_SECTION) {
                fputs("impassable movement\n", stderr);
                exit(EXIT_FAILURE);
            }
            current = (PathSection){next.index, end};
            t->path[t->path_count++] = current;
        }
    }
    t->speed = new_speed;
    t->distance += new_speed;
    if (new_speed > t->recorded_max)
        t->recorded_max = new_speed;
    if (new_speed == 0)
        t->emergency = false;
    bool arrived = false;
    if (t->next_stop < t->stop_count && new_speed == 0) {
        Stop *stop = &t->stops[t->next_stop];
        PathSection head = head_section(t);
        if (head.section == stop->section &&
            t->head == head.start + s->layout.sections[head.section].length) {
            t->dwelling = true;
            stop->arrival = s->time;
            arrived = true;
            log_event(s, "ARRIVE %s %s", t->name, s->layout.sections[stop->section].name);
        }
    }
    if (new_speed == 0 && !arrived) {
        ++t->standing;
        if (old_speed > 0)
            log_event(s, "HOLD %s %s", t->name, s->layout.sections[head_section(t).section].name);
    }
    if (t->crossed && t->head - t->length >= t->boundary_coordinate) {
        t->state = TRAIN_EXITED;
        t->actual_exit = s->time;
        log_event(s, "EXIT %s %s", t->name, s->layout.boundaries[t->exit].name);
    }
}
static void update_occupancy(Simulator *s) {
    for (int i = 0; i < s->layout.section_count; ++i)
        s->layout.sections[i].occupants = 0;
    for (int i = 0; i < s->train_count; ++i) {
        Train *t = &s->trains[i];
        if (t->state == TRAIN_RUNNING) {
            PathSection parts[40];
            int count = occupied_sections(t, &s->layout, parts);
            for (int j = 0; j < count; ++j)
                s->layout.sections[parts[j].section].occupants |= UINT32_C(1) << i;
        }
    }
}
static void sectional_release(Simulator *s) {
    for (int i = 0; i < s->interlocking.count; ++i) {
        Route *r = &s->interlocking.routes[i];
        if (r->state != ROUTE_USED)
            continue;
        for (int j = 0; j < r->section_count; ++j) {
            int index = r->sections[j];
            if (s->layout.sections[index].route == i && occupied(&s->layout.sections[index]))
                r->passed[index] = true;
        }
        for (int j = 0; j < r->section_count; ++j) {
            int index = r->sections[j];
            Section *section = &s->layout.sections[index];
            if (section->route != i)
                continue;
            if (!r->passed[index] || occupied(section))
                break;
            unlock_section(&s->interlocking, &s->layout, i, index);
            log_event(s, "RELEASE %s %s", r->name, section->name);
        }
        bool remaining = false;
        for (int j = 0; j < r->section_count; ++j)
            remaining = remaining || s->layout.sections[r->sections[j]].route == i;
        if (!remaining) {
            release_route(&s->interlocking, &s->layout, i);
            log_event(s, "DONE %s", r->name);
        } else if (r->overlap_count && r->overlap_locked) {
            r->overlap_counter = occupied(&s->layout.sections[r->sections[r->section_count - 1]])
                                     ? r->overlap_counter + 1
                                     : 0;
            if (r->overlap_counter >= s->overlap_time) {
                unlock_overlap(&s->interlocking, &s->layout, i);
                log_event(s, "OVERLAP %s", r->name);
            }
        }
    }
}
static void update_statistics(Simulator *s) {
    for (int i = 0; i < s->interlocking.count; ++i)
        if (s->interlocking.routes[i].state != ROUTE_NONE)
            ++s->interlocking.routes[i].locked_ticks;
    for (int i = 0; i < s->layout.point_count; ++i) {
        Point *p = &s->layout.points[i];
        if (p->normal_locks | p->reverse_locks)
            ++p->locked_ticks;
        if (p->moving)
            ++p->moving_ticks;
    }
    for (int i = 0; i < s->layout.section_count; ++i) {
        Section *section = &s->layout.sections[i];
        if (occupied(section))
            ++section->occupied_ticks;
        if (section->route >= 0 || section->overlaps)
            ++section->locked_ticks;
        section->trains |= section->occupants;
    }
    for (int i = 0; i < s->layout.signal_count; ++i) {
        Signal *g = &s->layout.signals[i];
        ++g->ticks[g->aspect];
    }
}
static void snapshot(Simulator *s) {
    Layout *l = &s->layout;
    char grid[21][152];
    for (int row = 0; row < l->height; ++row) {
        memset(grid[row], ' ', (size_t)l->width);
        grid[row][l->width] = 0;
    }
    for (int i = 0; i < l->label_count; ++i) {
        Label *label = &l->labels[i];
        memcpy(grid[label->row] + label->col, label->text, strlen(label->text));
    }
    for (int i = 0; i < l->section_count; ++i) {
        Section *section = &l->sections[i];
        char symbol = section->failed       ? '#'
                      : section->route >= 0 ? '='
                      : section->overlaps   ? '~'
                                            : '-';
        for (int col = section->first; col <= section->last; ++col)
            grid[section->row][col] = symbol;
    }
    for (int i = 0; i < s->train_count; ++i) {
        Train *t = &s->trains[i];
        if (t->state != TRAIN_RUNNING)
            continue;
        PathSection parts[40];
        int count = occupied_sections(t, l, parts);
        for (int j = 0; j < count; ++j) {
            PathSection part = parts[j];
            Section *section = &l->sections[part.section];
            int low = t->head - t->length > part.start ? t->head - t->length : part.start,
                high =
                    t->head < part.start + section->length ? t->head : part.start + section->length,
                p = low - part.start, q = high - part.start;
            if (t->direction == DIR_DOWN) {
                p = section->length - (high - part.start);
                q = section->length - (low - part.start);
            }
            int columns = section->last - section->first + 1;
            for (int col = 0; col < columns; ++col)
                if (p * columns < (col + 1) * section->length &&
                    q * columns > col * section->length) {
                    char *cell = &grid[section->row][section->first + col];
                    *cell = (*cell >= 'a' && *cell <= 'z') || *cell == '*' ? '*' : t->symbol;
                }
        }
    }
    for (int i = 0; i < l->buffer_count; ++i)
        grid[l->buffers[i].row][l->buffers[i].col] = '|';
    for (int i = 0; i < l->point_count; ++i) {
        Point *p = &l->points[i];
        grid[p->row][p->col] = detected(p) ? p->position : '?';
    }
    for (int i = 0; i < l->signal_count; ++i) {
        Signal *g = &l->signals[i];
        grid[g->row][g->col] = g->aspect == ASPECT_RED      ? 'X'
                               : g->aspect == ASPECT_YELLOW ? 'Y'
                                                            : 'G';
    }
    lines_add(&s->snapshots, format_text("SNAPSHOT %d", s->time));
    for (int row = 0; row < l->height; ++row) {
        int end = l->width;
        while (end && grid[row][end - 1] == ' ')
            --end;
        grid[row][end] = 0;
        lines_add(&s->snapshots, copy_string(grid[row]));
    }
    for (int i = 0; i < s->train_count; ++i) {
        Train *t = &s->trains[i];
        if (t->state != TRAIN_RUNNING)
            continue;
        PathSection parts[40];
        int count = occupied_sections(t, l, parts);
        char names[521] = "";
        for (int j = 0; j < count; ++j) {
            if (j)
                strcat(names, ",");
            strcat(names, l->sections[parts[j].section].name);
        }
        lines_add(&s->snapshots,
                  format_text("TRAIN %c %s %s %d%s%s", t->symbol, t->name,
                              direction_names[t->direction], t->speed, count ? " " : "", names));
    }
    char routes[1000] = "";
    for (int i = 0; i < s->interlocking.count; ++i) {
        Route *r = &s->interlocking.routes[i];
        if (r->state == ROUTE_NONE)
            continue;
        if (*routes)
            strcat(routes, " ");
        strcat(routes, r->name);
        strcat(routes, "/");
        strcat(routes, route_state_names[r->state]);
    }
    lines_add(&s->snapshots, format_text("ROUTES %s", *routes ? routes : "-"));
}
static void timetable_row(FILE *file, Punctuality *p, const Train *t, const char *kind,
                          const char *place, int scheduled, int actual) {
    fprintf(file, "%s,%s:%s,%d,", t->name, kind, place, scheduled);
    if (actual < 0) {
        fputs("-,-\n", file);
        ++p->missing;
    } else {
        int delay = actual - scheduled;
        fprintf(file, "%d,%d\n", actual, delay);
        if (delay <= 0)
            ++p->on_time;
        else {
            ++p->late;
            p->total_delay += delay;
        }
        if (delay > p->max_delay)
            p->max_delay = delay;
    }
}
static Punctuality save_timetable(const Simulator *s) {
    Punctuality p = {0};
    FILE *file = open_file("output/train_log.csv", "w");
    fputs("train,location,scheduled,actual,delay\n", file);
    for (int i = 0; i < s->train_count; ++i) {
        const Train *t = &s->trains[i];
        timetable_row(file, &p, t, "enter", s->layout.boundaries[t->entry].name, t->scheduled_entry,
                      t->actual_entry);
        for (int j = 0; j < t->stop_count; ++j) {
            const Stop *stop = &t->stops[j];
            timetable_row(file, &p, t, "arr", s->layout.sections[stop->section].name,
                          stop->scheduled_arrival, stop->arrival);
            timetable_row(file, &p, t, "dep", s->layout.sections[stop->section].name,
                          stop->scheduled_departure, stop->departure);
        }
        timetable_row(file, &p, t, "exit", s->layout.boundaries[t->exit].name, t->scheduled_exit,
                      t->actual_exit);
    }
    fclose(file);
    return p;
}
static void save_summary(const Simulator *s, const Punctuality *p) {
    FILE *file = open_file("output/summary.txt", "w");
    for (int i = 0; i < s->interlocking.count; ++i) {
        const Route *r = &s->interlocking.routes[i];
        fprintf(
            file,
            "ROUTE %s %s-%s requests %d grants %d uses %d cancels %d wait %d maxwait %d locked %d\n",
            r->name, s->layout.signals[r->start].name, r->finish, r->requests, r->grants, r->uses,
            r->cancels, r->wait, r->maxwait, r->locked_ticks);
    }
    for (int i = 0; i < s->layout.point_count; ++i) {
        const Point *point = &s->layout.points[i];
        fprintf(file, "POINT %s throws %d locked %d moving %d final %c\n", point->name,
                point->throws, point->locked_ticks, point->moving_ticks,
                detected(point) ? point->position : '?');
    }
    for (int i = 0; i < s->layout.section_count; ++i) {
        const Section *section = &s->layout.sections[i];
        fprintf(file, "SECTION %s occupied %d locked %d trains %d\n", section->name,
                section->occupied_ticks, section->locked_ticks, bit_count(section->trains));
    }
    for (int i = 0; i < s->layout.signal_count; ++i) {
        const Signal *g = &s->layout.signals[i];
        fprintf(file, "SIGNAL %s red %d yellow %d green %d passes %d\n", g->name, g->ticks[0],
                g->ticks[1], g->ticks[2], g->passes);
    }
    int states[3] = {0};
    for (int i = 0; i < s->train_count; ++i) {
        const Train *t = &s->trains[i];
        ++states[t->state];
        fprintf(file, "TRAIN %s %c %s distance %d maxspeed %d standing %d passes %d\n", t->name,
                t->symbol, train_state_names[t->state], t->distance, t->recorded_max, t->standing,
                t->passes);
    }
    fprintf(file, "TRAINS total %d exited %d running %d waiting %d\n", s->train_count,
            states[TRAIN_EXITED], states[TRAIN_RUNNING], states[TRAIN_WAITING]);
    fprintf(file, "PUNCTUALITY on_time %d late %d missing %d total_delay %d max_delay %d\n",
            p->on_time, p->late, p->missing, p->total_delay, p->max_delay);
    fprintf(file, "REQUESTS total %d granted %d dropped %d pending %d\n", s->total_requests,
            s->granted, s->dropped, s->queue_count);
    fclose(file);
}
static void save_lines(const char *path, const TextLines *lines) {
    FILE *file = open_file(path, "w");
    for (size_t i = 0; i < lines->count; ++i)
        fprintf(file, "%s\n", lines->items[i]);
    fclose(file);
}
static void initialize(Simulator *s) {
    read_layout(&s->layout);
    read_interlocking(&s->interlocking, &s->layout);
    read_trains(&s->layout, &s->interlocking, s->trains, &s->train_count, s->planned,
                &s->planned_count);
    FILE *file = open_file("input/params.txt", "r");
    char *line;
    for (int i = 0; i < 4; ++i) {
        line = read_line(file);
        Words words = split_words(line);
        if (i == 0)
            s->end_time = atoi(words.items[1]);
        else if (i == 1)
            s->throw_time = atoi(words.items[1]);
        else if (i == 2)
            s->overlap_time = atoi(words.items[1]);
        else
            for (int j = 1; j < words.count; ++j)
                s->snapshot_times[atoi(words.items[j])] = true;
        free(line);
    }
    fclose(file);
    file = open_file("input/events.txt", "r");
    while ((line = read_line(file))) {
        Words words = split_words(line);
        char **a = words.items;
        Event *e = &s->events[s->event_count++];
        e->time = atoi(a[0]);
        if (strcmp(a[1], "REQUEST") == 0 || strcmp(a[1], "CANCEL") == 0) {
            e->kind = strcmp(a[1], "REQUEST") == 0 ? EVENT_REQUEST : EVENT_CANCEL;
            e->target = route_index(&s->interlocking, a[2]);
        } else if (strcmp(a[1], "TCFAIL") == 0 || strcmp(a[1], "TCFIX") == 0) {
            e->kind = strcmp(a[1], "TCFAIL") == 0 ? EVENT_TCFAIL : EVENT_TCFIX;
            e->target = section_index(&s->layout, a[2]);
        } else {
            e->kind = strcmp(a[1], "THROW") == 0       ? EVENT_THROW
                      : strcmp(a[1], "POINTFAIL") == 0 ? EVENT_POINTFAIL
                                                       : EVENT_POINTFIX;
            e->target = point_index(&s->layout, a[2]);
            if (e->kind == EVENT_THROW)
                e->position = a[3][0];
        }
        free(line);
    }
    fclose(file);
}
static void simulate(Simulator *s) {
    for (s->time = 0; s->time <= s->end_time; ++s->time) {
        for (int i = 0; i < s->layout.point_count; ++i) {
            Point *p = &s->layout.points[i];
            if (p->moving && p->completion == s->time) {
                p->position = p->target;
                p->moving = false;
                p->completion = -1;
                ++p->throws;
                log_event(s, "POINT %s %c", p->name, p->position);
            }
        }
        for (int i = 0; i < s->interlocking.count; ++i) {
            Route *r = &s->interlocking.routes[i];
            if (r->state == ROUTE_APPROACH && r->release_time == s->time) {
                release_route(&s->interlocking, &s->layout, i);
                log_event(s, "TIMEOUT %s", r->name);
            }
        }
        for (int i = 0; i < s->planned_count; ++i)
            if (s->planned[i].time == s->time)
                add_request(s, s->planned[i].route, s->trains[s->planned[i].train].name);
        for (int i = 0; i < s->event_count; ++i)
            if (s->events[i].time == s->time)
                execute_event(s, &s->events[i]);
        judge_requests(s);
        Aspect aspects[30];
        signal_aspects(&s->layout, &s->interlocking, aspects);
        for (int i = 0; i < s->layout.signal_count; ++i) {
            Signal *g = &s->layout.signals[i];
            if (g->aspect != aspects[i]) {
                g->aspect = aspects[i];
                log_event(s, "SIGNAL %s %s", g->name, aspect_names[g->aspect]);
            }
        }
        uint16_t entered = 0;
        for (int i = 0; i < s->train_count; ++i)
            run_train(s, &s->trains[i], &entered);
        update_occupancy(s);
        sectional_release(s);
        safety_check(&s->safety, s->time, &s->layout, &s->interlocking, s->trains, s->train_count);
        update_statistics(s);
        if (s->snapshot_times[s->time])
            snapshot(s);
    }
}
int main(void) {
    Simulator *s = checked_realloc(NULL, sizeof(*s));
    memset(s, 0, sizeof(*s));
    initialize(s);
    simulate(s);
    if (mkdir("output", 0777) != 0 && errno != EEXIST) {
        perror("output");
        exit(EXIT_FAILURE);
    }
    save_lines("output/events.txt", &s->log);
    save_lines("output/snapshots.txt", &s->snapshots);
    Punctuality p = save_timetable(s);
    FILE *safety = open_file("output/safety.txt", "w");
    safety_write(&s->safety, safety);
    fclose(safety);
    save_summary(s, &p);
    for (int i = 0; i < s->interlocking.count; ++i) {
        Route *r = &s->interlocking.routes[i];
        free(r->points);
        free(r->flank);
        free(r->conflicts);
    }
    lines_free(&s->log);
    lines_free(&s->snapshots);
    lines_free(&s->safety.records);
    free(s);
    return EXIT_SUCCESS;
}
