#include <setjmp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { char **items; int count, capacity; } Strings;
typedef struct { int *items, count, capacity; } Indices;
typedef struct { int row, cabin, block, kind; char letter; } Seat;
typedef struct { int from, to, block_count; char blocks[10][5]; } Cabin;
typedef struct {
    char model[9];
    int base, limit, seat_count, lookup[2600], capacity[3];
    Cabin cabins[3];
    Seat seats[990];
    bool blocked[990], exits[100];
} Aircraft;
typedef struct {
    char name[7];
    int model, limit[3], occupants[990];
    bool closed, blocked[990];
    Indices passengers, volunteers;
} Flight;
typedef struct { char pnr[7]; int flight, people[9], count; bool checked; } Booking;
typedef struct {
    char name[13];
    int booking, type, preference, cabin, seat, lap;
    bool active, volunteer;
} Person;
typedef struct { char name[13]; int value; } Tier;
static Aircraft *aircraft[1000], *building;
static Flight *flights[1000];
static Booking bookings[1000];
static Person people[9000];
static Tier tiers[1000];
static int aircraft_count, flight_count, booking_count, people_count, tier_count;
static jmp_buf recovery;
static char error_message[256];
static Strings temporary;
static const char *classes = "FJY";
static const char *type_names[] = {"ADULT", "CHILD", "INFANT"};
static const char *tier_names[] = {"PLATINUM", "GOLD", "SILVER", "NONE"};

static void *allocate(size_t size) {
    void *p = malloc(size ? size : 1);
    if (!p) exit(EXIT_FAILURE);
    return p;
}
static char *slice(const char *s, size_t length) {
    char *result = allocate(length + 1);
    memcpy(result, s, length);
    result[length] = '\0';
    return result;
}
static char *format(const char *pattern, ...) {
    va_list args, copy;
    va_start(args, pattern);
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *result = allocate((size_t)length + 1);
    vsnprintf(result, (size_t)length + 1, pattern, args);
    va_end(args);
    return result;
}
static void appendf(char **s, const char *pattern, ...) {
    va_list args, copy;
    va_start(args, pattern);
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    size_t old = strlen(*s);
    *s = realloc(*s, old + (size_t)length + 1);
    if (!*s) exit(EXIT_FAILURE);
    vsnprintf(*s + old, (size_t)length + 1, pattern, args);
    va_end(args);
}
static void push_owned(Strings *s, char *item) {
    if (s->count == s->capacity) {
        s->capacity = s->capacity ? s->capacity * 2 : 8;
        s->items = realloc(s->items, (size_t)s->capacity * sizeof *s->items);
        if (!s->items) exit(EXIT_FAILURE);
    }
    s->items[s->count++] = item;
}
static void free_strings(Strings *s) {
    for (int i = 0; i < s->count; ++i) free(s->items[i]);
    free(s->items);
    *s = (Strings){0};
}
static Strings split(const char *s, char delimiter) {
    Strings result = {0};
    const char *start = s;
    for (const char *p = s;; ++p) {
        if (!*p || *p == delimiter) {
            push_owned(&result, slice(start, (size_t)(p - start)));
            start = p + 1;
            if (!*p) break;
        }
    }
    return result;
}
static const char *keep(char *s) {
    push_owned(&temporary, s);
    return s;
}
static void failf(const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    vsnprintf(error_message, sizeof error_message, pattern, args);
    va_end(args);
    longjmp(recovery, 1);
}
static void add_index(Indices *values, int value) {
    if (values->count == values->capacity) {
        values->capacity = values->capacity ? values->capacity * 2 : 8;
        values->items = realloc(values->items, (size_t)values->capacity * sizeof *values->items);
        if (!values->items) exit(EXIT_FAILURE);
    }
    values->items[values->count++] = value;
}
static bool contains(const int *values, int count, int value) {
    for (int i = 0; i < count; ++i) if (values[i] == value) return true;
    return false;
}
static int cabin_id(const char *s) { return (int)(strchr(classes, s[0]) - classes); }
static int seat_key(const char *s) { return atoi(s) * 26 + s[strlen(s) - 1] - 'A'; }
static const char *seat_name(const Aircraft *a, int index) { return index < 0 ? "UNASSIGNED" : keep(format("%d%c", a->seats[index].row, a->seats[index].letter)); }
static int tier(int id) {
    for (int i = 0; i < tier_count; ++i) if (!strcmp(tiers[i].name, people[id].name)) return tiers[i].value;
    return 3;
}
static int find_flight(const char *name, bool open) {
    for (int i = 0; i < flight_count; ++i) {
        if (!strcmp(flights[i]->name, name)) {
            if (open && flights[i]->closed) failf("flight %s is closed", name);
            return i;
        }
    }
    failf("unknown flight %s", name);
    return -1;
}
static int active_count(int b) {
    int count = 0;
    for (int i = 0; i < bookings[b].count; ++i) count += people[bookings[b].people[i]].active;
    return count;
}
static int find_booking(const char *pnr, bool open) {
    for (int i = 0; i < booking_count; ++i) {
        if (!strcmp(bookings[i].pnr, pnr) && active_count(i)) {
            if (open && flights[bookings[i].flight]->closed) failf("flight %s is closed", flights[bookings[i].flight]->name);
            return i;
        }
    }
    failf("unknown PNR %s", pnr);
    return -1;
}
static int find_passenger(int b, const char *name) {
    for (int i = 0; i < bookings[b].count; ++i) {
        int id = bookings[b].people[i];
        if (people[id].active && !strcmp(people[id].name, name)) return id;
    }
    failf("no passenger %s in %s", name, bookings[b].pnr);
    return -1;
}
static int resolve(const char *pnr, const char *name) { return find_passenger(find_booking(pnr, true), name); }
static bool has_infant(int id) { return people[id].type == 0 && people[id].lap >= 0 && people[people[id].lap].active; }
static bool booking_infants(int b) {
    for (int i = 0; i < bookings[b].count; ++i) {
        int id = bookings[b].people[i];
        if (people[id].active && people[id].type == 2) return true;
    }
    return false;
}
static int booked_count(int f, int c) {
    int count = 0;
    for (int i = 0; i < flights[f]->passengers.count; ++i) {
        const Person *p = &people[flights[f]->passengers.items[i]];
        if (p->active && p->type != 2 && p->cabin == c) ++count;
    }
    return count;
}
static bool exit_allowed(int id, const Aircraft *a, int target) { return !a->exits[a->seats[target].row] || (people[id].type == 0 && !has_infant(id)); }
static bool infant_allowed(int f, int id, int target, const int *moving, int count, const int *assigned, int extra) {
    if (!has_infant(id)) return true;
    const Flight *flight = flights[f];
    const Aircraft *a = aircraft[flight->model];
    Seat s = a->seats[target];
    const char *letters = a->cabins[s.cabin].blocks[s.block];
    for (int i = 0; letters[i]; ++i) {
        int peer = a->lookup[s.row * 26 + letters[i] - 'A'], owner = flight->occupants[peer];
        if (owner >= 0 && owner != id && owner != extra && !contains(moving, count, owner) && has_infant(owner)) return false;
    }
    for (int i = 0; i < count; ++i) {
        int other = moving[i];
        Seat t = a->seats[assigned[i]];
        if (other != id && has_infant(other) && t.row == s.row && t.block == s.block) return false;
    }
    return true;
}
static bool fits(int f, const int *ids, const int *assigned, int count, int extra) {
    const Flight *flight = flights[f];
    const Aircraft *a = aircraft[flight->model];
    for (int i = 0; i < count; ++i) {
        int target = assigned[i], owner = flight->occupants[target];
        if (flight->blocked[target] || (owner >= 0 && owner != extra && !contains(ids, count, owner)) || !exit_allowed(ids[i], a, target) || !infant_allowed(f, ids[i], target, ids, count, assigned, extra)) return false;
    }
    return true;
}
static int choose_seat(int f, int id, int c) {
    const Flight *flight = flights[f];
    const Aircraft *a = aircraft[flight->model];
    int first = -1;
    for (int target = 0; target < a->seat_count; ++target) {
        Seat s = a->seats[target];
        if (s.cabin != c || flight->blocked[target] || flight->occupants[target] >= 0 || !exit_allowed(id, a, target) || !infant_allowed(f, id, target, NULL, 0, NULL, -1)) continue;
        if (first < 0) first = target;
        if (people[id].preference < 0 || people[id].preference == s.kind) return target;
    }
    return first;
}
static void seat_person(int f, int id, int target) {
    if (people[id].seat >= 0) flights[f]->occupants[people[id].seat] = -1;
    people[id].seat = target;
    if (target >= 0) flights[f]->occupants[target] = id;
}
static void reassign(int f, Strings *out) {
    for (int i = 0; i < flights[f]->passengers.count; ++i) {
        int id = flights[f]->passengers.items[i];
        Person *p = &people[id];
        if (!p->active || p->type == 2 || p->seat >= 0) continue;
        int target = choose_seat(f, id, p->cabin);
        if (target < 0) continue;
        seat_person(f, id, target);
        push_owned(out, format("REASSIGNED %s %s %s", bookings[p->booking].pnr, p->name, seat_name(aircraft[flights[f]->model], target)));
    }
}
static void remove_person(int id) {
    Person *p = &people[id];
    if (!p->active) return;
    int lap = p->lap;
    if (p->type == 0 && lap >= 0) remove_person(lap);
    if (p->type == 2 && lap >= 0) people[lap].lap = -1;
    seat_person(bookings[p->booking].flight, id, -1);
    p->active = p->volunteer = false;
    p->lap = -1;
}
static const char *passenger_result(int id) {
    const Person *p = &people[id];
    return p->type == 2 ? "LAP" : seat_name(aircraft[flights[bookings[p->booking].flight]->model], p->seat);
}
static const char *assign_booking(int f, int c, const int *ids, int count) {
    if (count == 1) {
        seat_person(f, ids[0], choose_seat(f, ids[0], c));
        return "SINGLE";
    }
    const Aircraft *a = aircraft[flights[f]->model];
    const Cabin *cabin = &a->cabins[c];
    for (int stage = 0; stage < 3; ++stage) {
        int first_height = stage == 2 ? 2 : 1, last_height = stage == 2 ? count : 1;
        for (int height = first_height; height <= last_height; ++height) {
            int width = stage == 2 ? (count + height - 1) / height : count;
            int rows = (count + width - 1) / width;
            for (int row = cabin->from; row + rows - 1 <= cabin->to; ++row) {
                int blocks = stage == 1 ? 1 : cabin->block_count;
                for (int b = 0; b < blocks; ++b) {
                    char letters[11] = "";
                    if (stage == 1) {
                        for (int j = 0; j < cabin->block_count; ++j) strcat(letters, cabin->blocks[j]);
                    } else strcpy(letters, cabin->blocks[b]);
                    for (int x = 0; x + width <= (int)strlen(letters); ++x) {
                        int candidate[9];
                        for (int j = 0; j < count; ++j) candidate[j] = a->lookup[(row + j / width) * 26 + letters[x + j % width] - 'A'];
                        if (!fits(f, ids, candidate, count, -1)) continue;
                        for (int j = 0; j < count; ++j) seat_person(f, ids[j], candidate[j]);
                        const char *methods[] = {"BLOCK", "ROW", "STACK"};
                        return methods[stage];
                    }
                }
            }
        }
    }
    for (int i = 0; i < count; ++i) seat_person(f, ids[i], choose_seat(f, ids[i], c));
    return "SPLIT";
}
typedef struct { int tier, id; } Target;
static int compare_targets(const void *left, const void *right) {
    const Target *a = left, *b = right;
    if (a->tier != b->tier) return a->tier < b->tier ? -1 : 1;
    return a->id < b->id ? -1 : a->id > b->id;
}
typedef struct { int id, group, zone, kind, row; char letter; } BoardingItem;
static int compare_boarding(const void *left, const void *right) {
    const BoardingItem *a = left, *b = right;
    if (a->group != b->group) return a->group < b->group ? -1 : 1;
    if (a->group == 3) {
        if (a->zone != b->zone) return a->zone > b->zone ? -1 : 1;
        if (a->kind != b->kind) return a->kind < b->kind ? -1 : 1;
        if (a->row != b->row) return a->row > b->row ? -1 : 1;
    } else if (a->row != b->row) return a->row < b->row ? -1 : 1;
    return a->letter < b->letter ? -1 : a->letter > b->letter;
}
static void flight_command(int f, const Strings *v, Strings *out) {
    const char *command = v->items[0];
    Flight *flight = flights[f];
    const Aircraft *a = aircraft[flight->model];
    if (!strcmp(command, "BLOCK") || !strcmp(command, "UNBLOCK")) {
        int target = a->lookup[seat_key(v->items[2])];
        if (target < 0) failf("no seat %s on %s", v->items[2], flight->name);
        bool block = !strcmp(command, "BLOCK");
        if (block && flight->blocked[target]) failf("seat %s is blocked", v->items[2]);
        if (!block && !flight->blocked[target]) failf("seat %s is not blocked", v->items[2]);
        flight->blocked[target] = block;
        push_owned(out, format("%s %s %s", command, flight->name, v->items[2]));
        int id = flight->occupants[target];
        if (block && id >= 0) {
            seat_person(f, id, -1);
            seat_person(f, id, choose_seat(f, id, people[id].cabin));
            push_owned(out, format("DISPLACED %s %s %s -> %s", bookings[people[id].booking].pnr, people[id].name, v->items[2], passenger_result(id)));
        }
        reassign(f, out);
    } else if (!strcmp(command, "UPGRADE")) {
        int cabins[3], cabin_count = 0, upgraded = 0;
        for (int c = 0; c < 3; ++c) if (a->cabins[c].from) cabins[cabin_count++] = c;
        for (int pair = 0; pair + 1 < cabin_count; ++pair) {
            int higher = cabins[pair], lower = cabins[pair + 1], booked = booked_count(f, higher);
            Target targets[9000];
            int count = 0;
            for (int i = 0; i < flight->passengers.count; ++i) {
                int id = flight->passengers.items[i];
                const Person *p = &people[id];
                if (p->active && p->cabin == lower && p->type == 0 && !has_infant(id) && tier(id) < 3) targets[count++] = (Target){tier(id), id};
            }
            if (count > 1) qsort(targets, count, sizeof *targets, compare_targets);
            for (int i = 0; i < count; ++i) {
                if (booked >= flight->limit[higher]) break;
                int id = targets[i].id, target = choose_seat(f, id, higher);
                if (target < 0) break;
                const char *old = passenger_result(id);
                people[id].cabin = higher;
                seat_person(f, id, target);
                ++booked;
                ++upgraded;
                push_owned(out, format("UPGRADED %s %s %c %s -> %c %s", bookings[people[id].booking].pnr, people[id].name, classes[lower], old, classes[higher], seat_name(a, target)));
            }
        }
        reassign(f, out);
        push_owned(out, format("UPGRADE %s %d", flight->name, upgraded));
    } else if (!strcmp(command, "CLOSE")) {
        for (int b = 0; b < booking_count; ++b) {
            if (bookings[b].flight != f || bookings[b].checked || !active_count(b)) continue;
            push_owned(out, format("NOSHOW %s %d", bookings[b].pnr, active_count(b)));
            for (int i = 0; i < bookings[b].count; ++i) remove_person(bookings[b].people[i]);
        }
        reassign(f, out);
        int denied = 0, compensation = 0;
        const int voluntary[] = {500, 300, 150}, involuntary[] = {1000, 600, 300};
        for (int c = 0; c < 3; ++c) {
            int targets[9000], count = 0;
            for (int i = 0; i < flight->volunteers.count; ++i) {
                int id = flight->volunteers.items[i];
                const Person *p = &people[id];
                if (p->active && p->volunteer && p->seat >= 0 && p->cabin == c) targets[count++] = id;
            }
            for (int i = 0; i < count; ++i) {
                int id = targets[i], target = people[id].seat;
                bool useful = false;
                for (int j = 0; j < flight->passengers.count; ++j) {
                    int other = flight->passengers.items[j];
                    const Person *p = &people[other];
                    if (p->active && p->type != 2 && p->cabin == c && p->seat < 0 && fits(f, &other, &target, 1, id)) {
                        useful = true;
                        break;
                    }
                }
                if (!useful) continue;
                push_owned(out, format("DENIED VOLUNTARY %s %s %c %d", bookings[people[id].booking].pnr, people[id].name, classes[c], voluntary[c]));
                ++denied;
                compensation += voluntary[c];
                remove_person(id);
                reassign(f, out);
            }
        }
        for (int i = 0; i < flight->passengers.count; ++i) {
            int id = flight->passengers.items[i];
            const Person *p = &people[id];
            if (!p->active || p->type == 2 || p->seat >= 0) continue;
            int value = involuntary[p->cabin] / (p->type == 1 ? 2 : 1);
            push_owned(out, format("DENIED INVOLUNTARY %s %s %c %d", bookings[p->booking].pnr, p->name, classes[p->cabin], value));
            ++denied;
            compensation += value;
            remove_person(id);
        }
        flight->closed = true;
        push_owned(out, format("CLOSED %s denied %d compensation %d", flight->name, denied, compensation));
    } else if (!strcmp(command, "MAP")) {
        push_owned(out, format("MAP %s", flight->name));
        for (int c = 0; c < 3; ++c) {
            const Cabin *cabin = &a->cabins[c];
            if (!cabin->from) continue;
            push_owned(out, format("CABIN %c", classes[c]));
            char *header = format("   ");
            for (int b = 0; b < cabin->block_count; ++b) appendf(&header, "%s%s", b ? " " : "", cabin->blocks[b]);
            push_owned(out, header);
            for (int row = cabin->from; row <= cabin->to; ++row) {
                char *line = format("%2d ", row);
                for (int b = 0; b < cabin->block_count; ++b) {
                    if (b) appendf(&line, " ");
                    for (int i = 0; cabin->blocks[b][i]; ++i) {
                        int target = a->lookup[row * 26 + cabin->blocks[b][i] - 'A'];
                        char mark = flight->blocked[target] ? '#' : flight->occupants[target] >= 0 ? 'X' : a->exits[row] ? 'E' : '.';
                        appendf(&line, "%c", mark);
                    }
                }
                push_owned(out, line);
            }
        }
    } else if (!strcmp(command, "MANIFEST")) {
        int order[9000], count = 0, seated, unassigned = 0, infants = 0;
        for (int i = 0; i < a->seat_count; ++i) if (flight->occupants[i] >= 0) order[count++] = flight->occupants[i];
        seated = count;
        for (int i = 0; i < flight->passengers.count; ++i) {
            int id = flight->passengers.items[i];
            const Person *p = &people[id];
            if (!p->active) continue;
            if (p->type == 2) ++infants;
            else if (p->seat < 0) {
                ++unassigned;
                order[count++] = id;
            }
        }
        push_owned(out, format("MANIFEST %s seated %d unassigned %d infants %d", flight->name, seated, unassigned, infants));
        for (int i = 0; i < count; ++i) {
            int id = order[i];
            const Person *p = &people[id];
            const Booking *b = &bookings[p->booking];
            char *line = format("%s %c %s %s %s", p->seat < 0 ? "---" : seat_name(a, p->seat), classes[p->cabin], b->pnr, p->name, type_names[p->type]);
            if (has_infant(id)) appendf(&line, " +%s", people[p->lap].name);
            if (tier(id) < 3) appendf(&line, " %s", tier_names[tier(id)]);
            if (b->checked) appendf(&line, " CHECKED");
            if (p->volunteer) appendf(&line, " VOL");
            push_owned(out, line);
        }
    } else if (!strcmp(command, "LOADFACTOR")) {
        push_owned(out, format("LOADFACTOR %s", flight->name));
        int all_seated = 0, all_seats = 0;
        for (int c = 0; c < 3; ++c) {
            if (!a->cabins[c].from) continue;
            int seats = 0, seated = 0;
            for (int i = 0; i < a->seat_count; ++i) {
                if (a->seats[i].cabin != c) continue;
                seats += !flight->blocked[i];
                seated += flight->occupants[i] >= 0;
            }
            int factor = seated * 1000 / seats;
            push_owned(out, format("%c %d/%d %d.%d%% booked %d/%d", classes[c], seated, seats, factor / 10, factor % 10, booked_count(f, c), flight->limit[c]));
            all_seated += seated;
            all_seats += seats;
        }
        int factor = all_seated * 1000 / all_seats;
        push_owned(out, format("ALL %d/%d %d.%d%%", all_seated, all_seats, factor / 10, factor % 10));
    } else if (!strcmp(command, "BALANCE")) {
        int weight = 0, moment = 0;
        for (int i = 0; i < a->seat_count; ++i) {
            int id = flight->occupants[i];
            if (id < 0) continue;
            int value = (people[id].type == 0 ? 80 : 40) + (has_infant(id) ? 10 : 0);
            weight += value;
            moment += value * (a->seats[people[id].seat].row - a->base);
        }
        const char *verdict = moment < -a->limit ? "NOSE-HEAVY" : moment > a->limit ? "TAIL-HEAVY" : "OK";
        push_owned(out, format("BALANCE %s weight %d moment %d limit %d %s", flight->name, weight, moment, a->limit, verdict));
    } else if (!strcmp(command, "BOARDING")) {
        BoardingItem order[990];
        int count = 0;
        for (int i = 0; i < a->seat_count; ++i) {
            int id = flight->occupants[i];
            if (id < 0) continue;
            const Person *p = &people[id];
            Seat s = a->seats[p->seat];
            int group = booking_infants(p->booking) ? 0 : p->cabin < 2 ? 1 : tier(id) < 2 ? 2 : 3;
            int zone = group == 3 ? (s.row - a->cabins[2].from) / 5 + 1 : 0;
            order[count++] = (BoardingItem){id, group, zone, s.kind, s.row, s.letter};
        }
        if (count > 1) qsort(order, count, sizeof *order, compare_boarding);
        push_owned(out, format("BOARDING %s %d", flight->name, count));
        for (int i = 0; i < count; ++i) {
            const BoardingItem *item = &order[i];
            const Person *p = &people[item->id];
            const char *groups[] = {"PRE", "CABIN", "TIER"};
            const char *group = item->group == 3 ? keep(format("ZONE%d", item->zone)) : groups[item->group];
            push_owned(out, format("%d %s %s %s %s", i + 1, group, seat_name(a, p->seat), bookings[p->booking].pnr, p->name));
        }
    } else if (!strcmp(command, "AVAIL")) {
        int c = cabin_id(v->items[2]);
        if (!a->cabins[c].from) failf("no cabin %s on %s", v->items[2], flight->name);
        int free_count = 0, exits = 0, kinds[3] = {0};
        for (int i = 0; i < a->seat_count; ++i) {
            Seat s = a->seats[i];
            if (s.cabin != c || flight->blocked[i] || flight->occupants[i] >= 0) continue;
            ++free_count;
            ++kinds[s.kind];
            exits += a->exits[s.row];
        }
        push_owned(out, format("AVAIL %s %c free %d W %d M %d A %d EXIT %d", flight->name, classes[c], free_count, kinds[0], kinds[1], kinds[2], exits));
    }
}
static void execute(const Strings *v, Strings *out) {
    const char *command = v->items[0];
    if (!strcmp(command, "AIRCRAFT")) {
        building = allocate(sizeof *building);
        memset(building, 0, sizeof *building);
        for (int i = 0; i < 2600; ++i) building->lookup[i] = -1;
        strcpy(building->model, v->items[1]);
        building->base = atoi(v->items[2]);
        building->limit = atoi(v->items[3]);
    } else if (!strcmp(command, "CABIN")) {
        int c = cabin_id(v->items[1]);
        Cabin *cabin = &building->cabins[c];
        cabin->from = atoi(v->items[2]);
        cabin->to = atoi(v->items[3]);
        cabin->block_count = v->count - 4;
        for (int b = 0; b < cabin->block_count; ++b) strcpy(cabin->blocks[b], v->items[b + 4]);
        for (int row = cabin->from; row <= cabin->to; ++row) {
            for (int b = 0; b < cabin->block_count; ++b) {
                const char *letters = cabin->blocks[b];
                for (int position = 0; letters[position]; ++position) {
                    char letter = letters[position];
                    int kind = (b == 0 && position == 0) || (b + 1 == cabin->block_count && position + 1 == (int)strlen(letters)) ? 0 : position == 0 || position + 1 == (int)strlen(letters) ? 2 : 1;
                    building->lookup[row * 26 + letter - 'A'] = building->seat_count;
                    building->seats[building->seat_count++] = (Seat){row, c, b, kind, letter};
                }
            }
        }
    } else if (!strcmp(command, "EXIT")) {
        for (int i = 1; i < v->count; ++i) building->exits[atoi(v->items[i])] = true;
    } else if (!strcmp(command, "BLOCKED")) {
        for (int i = 1; i < v->count; ++i) building->blocked[building->lookup[seat_key(v->items[i])]] = true;
    } else if (!strcmp(command, "END")) {
        for (int i = 0; i < building->seat_count; ++i) if (!building->blocked[i]) ++building->capacity[building->seats[i].cabin];
        char *line = format("AIRCRAFT %s", building->model);
        for (int c = 0; c < 3; ++c) if (building->cabins[c].from) appendf(&line, " %c %d", classes[c], building->capacity[c]);
        aircraft[aircraft_count++] = building;
        building = NULL;
        push_owned(out, line);
    } else if (!strcmp(command, "FLIGHT")) {
        for (int i = 0; i < flight_count; ++i) if (!strcmp(flights[i]->name, v->items[1])) failf("duplicate flight %s", v->items[1]);
        int model = -1;
        for (int i = 0; i < aircraft_count; ++i) if (!strcmp(aircraft[i]->model, v->items[2])) model = i;
        if (model < 0) failf("unknown aircraft %s", v->items[2]);
        Flight *f = allocate(sizeof *f);
        memset(f, 0, sizeof *f);
        strcpy(f->name, v->items[1]);
        f->model = model;
        const Aircraft *a = aircraft[model];
        memcpy(f->blocked, a->blocked, sizeof f->blocked);
        for (int i = 0; i < 990; ++i) f->occupants[i] = -1;
        char *line = format("FLIGHT %s %s", f->name, a->model);
        for (int c = 0; c < 3; ++c) {
            f->limit[c] = a->capacity[c] * (100 + atoi(v->items[3])) / 100;
            if (a->cabins[c].from) appendf(&line, " %c %d/%d", classes[c], a->capacity[c], f->limit[c]);
        }
        flights[flight_count++] = f;
        push_owned(out, line);
    } else if (!strcmp(command, "BOOK")) {
        for (int i = 0; i < booking_count; ++i) if (!strcmp(bookings[i].pnr, v->items[1])) failf("duplicate PNR %s", v->items[1]);
        int f = find_flight(v->items[2], true), c = cabin_id(v->items[3]);
        if (!aircraft[flights[f]->model]->cabins[c].from) failf("no cabin %s on %s", v->items[3], v->items[2]);
        Person draft[9] = {0};
        int adults[9], infants[9], adult_count = 0, infant_count = 0, count = v->count - 4;
        for (int i = 0; i < count; ++i) {
            Strings fields = split(v->items[i + 4], ':');
            Person *p = &draft[i];
            strcpy(p->name, fields.items[0]);
            for (int j = 0; j < 3; ++j) if (!strcmp(type_names[j], fields.items[1])) p->type = j;
            p->booking = booking_count;
            p->cabin = c;
            p->preference = fields.count == 3 ? (fields.items[2][0] == 'W' ? 0 : fields.items[2][0] == 'M' ? 1 : 2) : -1;
            p->seat = p->lap = -1;
            p->active = true;
            if (p->type == 0) adults[adult_count++] = i;
            if (p->type == 2) infants[infant_count++] = i;
            free_strings(&fields);
        }
        for (int i = 0; i < count; ++i) {
            for (int j = 0; j < i; ++j) if (!strcmp(draft[i].name, draft[j].name)) failf("duplicate name %s in %s", draft[i].name, v->items[1]);
        }
        for (int i = 0; i < count; ++i) {
            for (int j = 0; j < flights[f]->passengers.count; ++j) {
                const Person *p = &people[flights[f]->passengers.items[j]];
                if (p->active && !strcmp(p->name, draft[i].name)) failf("%s already on %s", draft[i].name, v->items[2]);
            }
        }
        if (!adult_count) failf("no adult in %s", v->items[1]);
        if (infant_count > adult_count) failf("too many infants in %s", v->items[1]);
        if (booked_count(f, c) + count - infant_count > flights[f]->limit[c]) failf("limit exceeded for %s %s", v->items[2], v->items[3]);
        for (int i = 0; i < infant_count; ++i) {
            draft[adults[i]].lap = people_count + infants[i];
            draft[infants[i]].lap = people_count + adults[i];
        }
        Booking *b = &bookings[booking_count++];
        strcpy(b->pnr, v->items[1]);
        b->flight = f;
        int needs[9], need_count = 0;
        for (int i = 0; i < count; ++i) {
            int id = people_count++;
            people[id] = draft[i];
            b->people[b->count++] = id;
            add_index(&flights[f]->passengers, id);
            if (people[id].type != 2) needs[need_count++] = id;
        }
        const char *method = assign_booking(f, c, needs, need_count);
        char *line = format("BOOKED %s %s %s %s", b->pnr, v->items[2], v->items[3], method);
        for (int i = 0; i < b->count; ++i) appendf(&line, " %s:%s", people[b->people[i]].name, passenger_result(b->people[i]));
        push_owned(out, line);
    } else if (!strcmp(command, "STATUS")) {
        int id = -1, value = 3;
        for (int i = 0; i < tier_count; ++i) if (!strcmp(tiers[i].name, v->items[1])) id = i;
        for (int i = 0; i < 4; ++i) if (!strcmp(tier_names[i], v->items[2])) value = i;
        if (id < 0) {
            id = tier_count++;
            strcpy(tiers[id].name, v->items[1]);
        }
        tiers[id].value = value;
        push_owned(out, format("STATUS %s %s", v->items[1], v->items[2]));
    } else if (!strcmp(command, "FIND")) {
        int membership = 3;
        for (int i = 0; i < tier_count; ++i) if (!strcmp(tiers[i].name, v->items[1])) membership = tiers[i].value;
        Strings found = {0};
        for (int f = 0; f < flight_count; ++f) {
            for (int i = 0; i < flights[f]->passengers.count; ++i) {
                int id = flights[f]->passengers.items[i];
                const Person *p = &people[id];
                if (p->active && !strcmp(p->name, v->items[1])) push_owned(&found, format("%s %s %c %s %s", flights[f]->name, bookings[p->booking].pnr, classes[p->cabin], passenger_result(id), flights[f]->closed ? "CLOSED" : "OPEN"));
            }
        }
        push_owned(out, format("FIND %s %s %d", v->items[1], tier_names[membership], found.count));
        for (int i = 0; i < found.count; ++i) push_owned(out, found.items[i]);
        free(found.items);
    } else if (!strcmp(command, "SEAT")) {
        int id = resolve(v->items[1], v->items[2]);
        Person *p = &people[id];
        int f = bookings[p->booking].flight;
        const Aircraft *a = aircraft[flights[f]->model];
        if (p->type == 2) failf("infant %s has no seat", p->name);
        int target = a->lookup[seat_key(v->items[3])];
        if (target < 0 || a->seats[target].cabin != p->cabin) failf("no seat %s in cabin %c", v->items[3], classes[p->cabin]);
        if (flights[f]->blocked[target]) failf("seat %s is blocked", v->items[3]);
        if (flights[f]->occupants[target] >= 0) failf("seat %s is occupied", v->items[3]);
        if (!exit_allowed(id, a, target)) failf("exit row %d not allowed for %s", a->seats[target].row, p->name);
        if (!infant_allowed(f, id, target, NULL, 0, NULL, -1)) failf("infant limit reached at %s", v->items[3]);
        const char *old = seat_name(a, p->seat);
        seat_person(f, id, target);
        push_owned(out, format("MOVED %s %s %s -> %s", v->items[1], v->items[2], old, v->items[3]));
        reassign(f, out);
    } else if (!strcmp(command, "SWAP")) {
        int ids[2];
        ids[0] = resolve(v->items[1], v->items[2]);
        ids[1] = resolve(v->items[3], v->items[4]);
        if (ids[0] == ids[1]) failf("cannot swap %s with itself", v->items[2]);
        for (int i = 0; i < 2; ++i) if (people[ids[i]].type == 2) failf("infant %s has no seat", people[ids[i]].name);
        int f = bookings[people[ids[0]].booking].flight;
        if (f != bookings[people[ids[1]].booking].flight) failf("%s and %s are on different flights", v->items[1], v->items[3]);
        if (people[ids[0]].cabin != people[ids[1]].cabin) failf("%s and %s are in different cabins", v->items[2], v->items[4]);
        for (int i = 0; i < 2; ++i) if (people[ids[i]].seat < 0) failf("%s has no seat", people[ids[i]].name);
        int assigned[] = {people[ids[1]].seat, people[ids[0]].seat};
        if (!fits(f, ids, assigned, 2, -1)) failf("swap of %s and %s breaks seating rules", v->items[2], v->items[4]);
        flights[f]->occupants[assigned[0]] = flights[f]->occupants[assigned[1]] = -1;
        people[ids[0]].seat = people[ids[1]].seat = -1;
        seat_person(f, ids[0], assigned[0]);
        seat_person(f, ids[1], assigned[1]);
        const Aircraft *a = aircraft[flights[f]->model];
        push_owned(out, format("SWAPPED %s %s %s %s %s %s", v->items[1], v->items[2], seat_name(a, assigned[0]), v->items[3], v->items[4], seat_name(a, assigned[1])));
        reassign(f, out);
    } else if (!strcmp(command, "CANCEL")) {
        int b = find_booking(v->items[1], true), target = v->count == 3 ? find_passenger(b, v->items[2]) : -1;
        int removed[9], count = 0, remaining = 0, adults = 0;
        for (int i = 0; i < bookings[b].count; ++i) {
            int id = bookings[b].people[i];
            if (people[id].active && (target < 0 || id == target || (people[target].type == 0 && people[target].lap == id))) removed[count++] = id;
        }
        for (int i = 0; i < bookings[b].count; ++i) {
            int id = bookings[b].people[i];
            if (people[id].active && !contains(removed, count, id)) {
                ++remaining;
                adults += people[id].type == 0;
            }
        }
        if (target >= 0 && remaining && !adults) failf("%s would have no adult", v->items[1]);
        char *line = format("CANCELLED %s", v->items[1]);
        for (int i = 0; i < count; ++i) appendf(&line, " %s", people[removed[i]].name);
        for (int i = 0; i < count; ++i) remove_person(removed[i]);
        push_owned(out, line);
        reassign(bookings[b].flight, out);
    } else if (!strcmp(command, "CHECKIN") || !strcmp(command, "VOLUNTEER") || !strcmp(command, "INFO")) {
        int b = find_booking(v->items[1], strcmp(command, "INFO") != 0);
        Booking *book = &bookings[b];
        if (!strcmp(command, "CHECKIN")) {
            if (book->checked) failf("%s already checked in", v->items[1]);
            book->checked = true;
            push_owned(out, format("CHECKIN %s %d", book->pnr, active_count(b)));
        } else if (!strcmp(command, "INFO")) {
            push_owned(out, format("INFO %s %s %d %s", book->pnr, flights[book->flight]->name, active_count(b), book->checked ? "CHECKED" : "NOT-CHECKED"));
            for (int i = 0; i < book->count; ++i) {
                int id = book->people[i];
                const Person *p = &people[id];
                if (p->active) push_owned(out, format("%s %s %c %s", p->name, type_names[p->type], classes[p->cabin], passenger_result(id)));
            }
        } else {
            int id = find_passenger(b, v->items[2]);
            Person *p = &people[id];
            if (p->type != 0 || has_infant(id)) failf("%s cannot volunteer", p->name);
            if (p->seat < 0) failf("%s has no seat", p->name);
            if (p->volunteer) failf("%s already volunteered", p->name);
            p->volunteer = true;
            add_index(&flights[book->flight]->volunteers, id);
            push_owned(out, format("VOLUNTEER %s %s %s", book->pnr, p->name, passenger_result(id)));
        }
    } else {
        bool modifying = !strcmp(command, "UPGRADE") || !strcmp(command, "CLOSE") || !strcmp(command, "BLOCK") || !strcmp(command, "UNBLOCK");
        int f = find_flight(v->items[1], modifying);
        flight_command(f, v, out);
    }
}
int main(void) {
    char line[8192];
    if (!fgets(line, sizeof line, stdin)) return 0;
    int count = atoi(line);
    for (int i = 0; i < count; ++i) {
        if (!fgets(line, sizeof line, stdin)) break;
        line[strcspn(line, "\n")] = '\0';
        Strings values = split(line, ' ');
        if (setjmp(recovery) == 0) {
            Strings out = {0};
            execute(&values, &out);
            for (int j = 0; j < out.count; ++j) puts(out.items[j]);
            free_strings(&out);
        } else printf("ERROR %s\n", error_message);
        free_strings(&values);
        free_strings(&temporary);
    }
    for (int i = 0; i < aircraft_count; ++i) free(aircraft[i]);
    for (int i = 0; i < flight_count; ++i) {
        free(flights[i]->passengers.items);
        free(flights[i]->volunteers.items);
        free(flights[i]);
    }
    free(building);
    return 0;
}
