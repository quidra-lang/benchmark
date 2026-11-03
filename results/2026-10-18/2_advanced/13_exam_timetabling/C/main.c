#include "timetable.h"

static int minimum(int a, int b) { return a < b ? a : b; }
static int ceil_div(int a, int b) { return (a + b - 1) / b; }
static int day_of(const Scheduler *s, int slot) { return (slot - 1) / s->periods + 1; }
static int slot_length(const Scheduler *s, int slot) { return s->lengths[(slot - 1) % s->periods]; }
static char *slot_name(const Scheduler *s, int slot) { return format("D%dP%d", day_of(s, slot), (slot - 1) % s->periods + 1); }
static int slot_at(const Scheduler *s, const char *day_text, const char *period_text) {
    int day = atoi(day_text), period = atoi(period_text);
    return day >= 1 && day <= s->days && period >= 1 && period <= s->periods ? (day - 1) * s->periods + period : 0;
}
static bool schedulable(const Scheduler *s, int c) { return s->courses[c].size > 0 && s->courses[c].size <= s->largest_room; }
static Courses courses_at(const Scheduler *s, const int *assignment, int slot) {
    Courses result = {0};
    for (int c = 0; c < s->course_count; ++c) if (assignment[c] == slot) result.items[result.count++] = c;
    return result;
}
static int blocked_student(const Scheduler *s, int c, int slot) {
    const Course *course = &s->courses[c];
    for (int i = 0; i < course->size; ++i) {
        int student = course->students[i];
        if (s->students[student].unavailable[slot]) return student;
    }
    return -1;
}
static bool suitable(const Scheduler *s, int c, int slot) {
    return slot_length(s, slot) >= s->courses[c].duration && blocked_student(s, c, slot) < 0;
}
static int order_conflict(const Scheduler *s, int c, int slot, const int *assignment) {
    int result = -1;
    for (int i = 0; i < s->order_count; ++i) {
        Order order = s->orders[i]; int other = -1;
        if (order.later == c && assignment[order.earlier] && slot <= assignment[order.earlier]) other = order.earlier;
        if (order.earlier == c && assignment[order.later] && slot >= assignment[order.later]) other = order.later;
        if (other >= 0 && (result < 0 || other < result)) result = other;
    }
    return result;
}
static bool orders_satisfied(const Scheduler *s, const int *assignment) {
    for (int i = 0; i < s->order_count; ++i) {
        Order order = s->orders[i];
        if (assignment[order.later] && assignment[order.earlier] && assignment[order.later] <= assignment[order.earlier]) return false;
    }
    return true;
}
Courses candidate_slots(const Scheduler *s, int c, const int *assignment) {
    Courses result = {0};
    for (int slot = 1; slot <= s->slots; ++slot) {
        if (s->closed[slot] || !suitable(s, c, slot) || order_conflict(s, c, slot, assignment) >= 0) continue;
        bool conflict = false;
        for (int n = 0; n < s->course_count; ++n) if (s->shared[c][n] && assignment[n] == slot) conflict = true;
        if (conflict) continue;
        Courses group = courses_at(s, assignment, slot); group.items[group.count++] = c;
        if (pack(s, group, NULL)) result.items[result.count++] = slot;
    }
    return result;
}
static void classify(Scheduler *s) {
    for (int c = 0; c < s->course_count; ++c) {
        if (!s->courses[c].size) s->empty.items[s->empty.count++] = c;
        else {
            s->vertices.items[s->vertices.count++] = c;
            if (s->courses[c].size > s->largest_room) s->oversized.items[s->oversized.count++] = c;
            else s->schedulable.items[s->schedulable.count++] = c;
        }
    }
    build_graph(s);
    s->front_load = s->schedulable; sort_courses(s, &s->front_load, NULL);
    s->front_load.count = minimum(s->front_load.count, s->front_count);
}
static void read_settings(Scheduler *s, const Lines *lines) {
    int settings[6][5] = {{0}}, counts[6] = {0};
    for (int i = 0; i < 6; ++i) {
        char *text = format("%s", lines->items[i]);
        strtok(text, " "); char *word;
        while ((word = strtok(NULL, " "))) settings[i][counts[i]++] = atoi(word);
    }
    s->days = settings[0][0]; s->periods = counts[1]; s->slots = s->days * s->periods;
    memcpy(s->lengths, settings[1], sizeof s->lengths); s->limit = settings[2][0];
    memcpy(s->weights, settings[3], sizeof s->weights);
    s->front_count = settings[4][0]; s->deadline = settings[4][1]; s->ratio = settings[5][0];
}
static char *accept_closed(Scheduler *s, const char *day, const char *period) {
    int slot = slot_at(s, day, period);
    if (!slot) return format("slot %s %s outside calendar", day, period);
    if (s->closed[slot]) return format("duplicate closed %s", slot_name(s, slot));
    s->closed[slot] = true; return NULL;
}
static char *accept_unavailable(Scheduler *s, const char *id, const char *day, const char *period) {
    int student = find_student(s, id);
    if (student < 0) return format("unknown student %s", id);
    int slot = slot_at(s, day, period);
    if (!slot) return format("slot %s %s outside calendar", day, period);
    if (s->students[student].unavailable[slot]) return format("duplicate unavailable %s %s", id, slot_name(s, slot));
    s->students[student].unavailable[slot] = true; return NULL;
}
static char *accept_fixed(Scheduler *s, const char *id, const char *day, const char *period) {
    int c = find_course(s, id);
    if (c < 0) return format("unknown course %s", id);
    if (!schedulable(s, c)) return format("course %s not schedulable", id);
    int slot = slot_at(s, day, period);
    if (!slot) return format("slot %s %s outside calendar", day, period);
    if (s->closed[slot]) return format("slot %s closed", slot_name(s, slot));
    if (!suitable(s, c, slot)) return format("slot %s unsuitable for %s", slot_name(s, slot), id);
    if (s->fixed[c]) return format("duplicate fixed %s", id);
    Courses group = courses_at(s, s->fixed, slot);
    for (int i = 0; i < group.count; ++i)
        if (s->shared[c][group.items[i]]) return format("conflict %s %s", id, s->courses[group.items[i]].id);
    group.items[group.count++] = c;
    if (!pack(s, group, NULL)) return format("rooms full %s", slot_name(s, slot));
    s->fixed[c] = slot; return NULL;
}
static char *accept_after(Scheduler *s, const char *later, const char *earlier) {
    int a = find_course(s, later), b = find_course(s, earlier);
    if (a < 0) return format("unknown course %s", later);
    if (b < 0) return format("unknown course %s", earlier);
    if (!schedulable(s, a)) return format("course %s not schedulable", later);
    if (!schedulable(s, b)) return format("course %s not schedulable", earlier);
    if (a == b) return format("bad order %s %s", later, earlier);
    for (int i = 0; i < s->order_count; ++i)
        if (s->orders[i].later == a && s->orders[i].earlier == b) return format("duplicate order %s %s", later, earlier);
    if (reachable(s, b, a)) return format("cycle %s %s", later, earlier);
    if (s->fixed[a] && s->fixed[b] && s->fixed[a] <= s->fixed[b]) return format("fixed order %s %s", later, earlier);
    s->orders[s->order_count++] = (Order){a, b}; return NULL;
}
static void validate_calendar(Scheduler *s, const Lines *lines) {
    for (int i = 6; i < lines->count; ++i) {
        char kind[16], a[16], b[16], c[16];
        sscanf(lines->items[i], "%15s %15s %15s %15s", kind, a, b, c);
        char *message;
        if (!strcmp(kind, "closed")) message = accept_closed(s, a, b);
        else if (!strcmp(kind, "unavailable")) message = accept_unavailable(s, a, b, c);
        else if (!strcmp(kind, "fixed")) message = accept_fixed(s, a, b, c);
        else message = accept_after(s, a, b);
        if (message) add_line(&s->errors, "calendar.txt line %d: %s", i + 1, message);
    }
    for (int c = 0; c < s->course_count; ++c) if (s->fixed[c]) s->fixed_slots[s->fixed[c]] = true;
}
static void build_timetable(Scheduler *s) {
    for (;;) {
        Attempt attempt = { .scheduler = s, .dead_end_course = -1 };
        memcpy(s->assignment, s->fixed, sizeof s->assignment);
        for (int i = 0; i < s->schedulable.count; ++i) {
            int c = s->schedulable.items[i];
            if (!s->fixed[c] && !s->excluded[c]) attempt.pending.items[attempt.pending.count++] = c;
        }
        bool success = search_attempt(&attempt);
        s->attempts[s->attempt_count++] = (AttemptRecord){attempt.pending.count, attempt.dead_ends, success ? -1 : attempt.dead_end_course};
        if (success) {
            s->choice_count = attempt.choice_count;
            memcpy(s->choices, attempt.choices, (size_t)s->choice_count * sizeof(Choice)); return;
        }
        s->excluded[attempt.dead_end_course] = true;
    }
}
static int relation(const Scheduler *s, int a, int b) {
    int low = minimum(a, b), high = a > b ? a : b;
    if (day_of(s, low) == day_of(s, high)) {
        if (high - low == 1) return 0;
        if (high - low >= 2) return 1;
    } else if (high - low == 1) return 2;
    return -1;
}
static Breakdown breakdown(const Scheduler *s, const int *assignment) {
    Breakdown result = {0};
    for (int a = 0; a < s->course_count; ++a) if (assignment[a])
        for (int b = a + 1; b < s->course_count; ++b) if (assignment[b] && s->shared[a][b]) {
            int kind = relation(s, assignment[a], assignment[b]);
            if (kind >= 0) result.counts[kind] += s->shared[a][b];
        }
    for (int i = 0; i < s->front_load.count; ++i) if (assignment[s->front_load.items[i]] > s->deadline) ++result.late;
    result.total = result.late * s->weights[3];
    for (int k = 0; k < 3; ++k) result.total += result.counts[k] * s->weights[k];
    return result;
}
static char *breakdown_text(Breakdown b) {
    return format("back_to_back %d same_day %d overnight %d front_load %d penalty %d", b.counts[0], b.counts[1], b.counts[2], b.late, b.total);
}
static char *blocking_reason(const Scheduler *s, int c, int slot) {
    if (s->closed[slot]) return format("closed");
    if (slot_length(s, slot) < s->courses[c].duration) return format("too_short");
    int student = blocked_student(s, c, slot);
    if (student >= 0) return format("unavailable %s", s->students[student].id);
    int clash = -1;
    for (int n = 0; n < s->course_count; ++n)
        if (s->assignment[n] == slot && s->shared[c][n] && (clash < 0 || s->shared[c][n] > s->shared[c][clash])) clash = n;
    if (clash >= 0) return format("conflict %s shared %d", s->courses[clash].id, s->shared[c][clash]);
    int other = order_conflict(s, c, slot, s->assignment);
    if (other >= 0) return format("order %s", s->courses[other].id);
    return format("rooms");
}
static void insert_excluded(Scheduler *s) {
    for (int c = 0; c < s->course_count; ++c) if (s->excluded[c]) {
        Courses slots = candidate_slots(s, c, s->assignment);
        if (!slots.count) {
            for (int slot = 1; slot <= s->slots; ++slot) s->reasons[c][slot] = blocking_reason(s, c, slot);
            continue;
        }
        int before = breakdown(s, s->assignment).total, best_slot = 0, best_total = 0;
        for (int i = 0; i < slots.count; ++i) {
            int slot = slots.items[i]; s->assignment[c] = slot;
            int total = breakdown(s, s->assignment).total;
            if (!best_slot || total < best_total) { best_slot = slot; best_total = total; }
        }
        s->assignment[c] = best_slot;
        s->insertions[s->insertion_count++] = (Insertion){c, best_slot, best_total - before};
    }
    s->initial = breakdown(s, s->assignment); s->penalty = s->initial.total;
}
static bool valid_trial(const Scheduler *s, const int *trial) {
    for (int c = 0; c < s->course_count; ++c)
        if (trial[c] != s->assignment[c] && !suitable(s, c, trial[c])) return false;
    return orders_satisfied(s, trial);
}
static void exchange_slots(Scheduler *s) {
    int round = 0, serial = 0;
    for (;;) {
        int tally[4] = {0}, pairs = 0; Lines records = {0}; ++round;
        for (int home = 1; home <= s->slots; ++home) if (!s->closed[home])
            for (int target = home + 1; target <= s->slots; ++target) if (!s->closed[target]) {
                ++pairs;
                if (s->fixed_slots[home] || s->fixed_slots[target]) { ++tally[0]; continue; }
                int trial[MAX_COURSES]; memcpy(trial, s->assignment, sizeof trial);
                for (int c = 0; c < s->course_count; ++c) {
                    if (trial[c] == home) trial[c] = target;
                    else if (trial[c] == target) trial[c] = home;
                }
                if (!valid_trial(s, trial)) { ++tally[1]; continue; }
                int total = breakdown(s, trial).total;
                if (total >= s->penalty) { ++tally[2]; continue; }
                ++tally[3]; ++serial;
                add_line(&records, "EXCHANGE %d %s %s penalty %d -> %d", serial, slot_name(s, home), slot_name(s, target), s->penalty, total);
                memcpy(s->assignment, trial, sizeof trial); s->penalty = total;
            }
        add_line(&s->exchange_log, "ROUND %d pairs %d fixed %d invalid %d worse %d applied %d", round, pairs, tally[0], tally[1], tally[2], tally[3]);
        append_lines(&s->exchange_log, &records);
        if (!tally[3]) break;
    }
    s->exchanged = breakdown(s, s->assignment);
}
static void swap_chains(Scheduler *s) {
    int pass = 0, serial = 0;
    for (;;) {
        int tally[5] = {0}, candidates = 0; Lines records = {0}; ++pass;
        for (int c = 0; c < s->course_count; ++c) if (s->assignment[c] && !s->fixed[c]) {
            int home = s->assignment[c];
            for (int target = 1; target <= s->slots; ++target) {
                if (s->closed[target] || target == home) continue;
                ++candidates; Courses chain = kempe_chain(s, c, home, target); bool fixed = false;
                for (int i = 0; i < chain.count; ++i) if (s->fixed[chain.items[i]]) fixed = true;
                if (fixed) { ++tally[0]; continue; }
                int trial[MAX_COURSES]; memcpy(trial, s->assignment, sizeof trial);
                for (int i = 0; i < chain.count; ++i) {
                    int member = chain.items[i]; trial[member] = s->assignment[member] == home ? target : home;
                }
                if (!valid_trial(s, trial)) { ++tally[1]; continue; }
                if (!pack(s, courses_at(s, trial, home), NULL) || !pack(s, courses_at(s, trial, target), NULL)) { ++tally[2]; continue; }
                int total = breakdown(s, trial).total;
                if (total >= s->penalty) { ++tally[3]; continue; }
                ++tally[4]; ++serial;
                add_line(&records, "SWAP %d %s %s %s chain %d penalty %d -> %d", serial, s->courses[c].id, slot_name(s, home), slot_name(s, target), chain.count, s->penalty, total);
                for (int i = 0; i < chain.count; ++i) {
                    int member = chain.items[i];
                    add_line(&records, "  MOVE %s %s -> %s", s->courses[member].id, slot_name(s, s->assignment[member]), slot_name(s, trial[member]));
                }
                memcpy(s->assignment, trial, sizeof trial); s->penalty = total; break;
            }
        }
        add_line(&s->swap_log, "PASS %d candidates %d fixed %d invalid %d rooms %d worse %d applied %d", pass, candidates, tally[0], tally[1], tally[2], tally[3], tally[4]);
        append_lines(&s->swap_log, &records);
        if (!tally[4]) break;
    }
    s->final = breakdown(s, s->assignment);
}
static void assign_rooms(Scheduler *s) {
    for (int slot = 1; slot <= s->slots; ++slot) if (!s->closed[slot]) {
        Courses group = courses_at(s, s->assignment, slot); s->packed_count[slot] = group.count;
        if (!pack(s, group, s->packed[slot])) exit(EXIT_FAILURE);
        for (int i = 0; i < group.count; ++i) s->placements[s->packed[slot][i].course] = s->packed[slot][i];
    }
}
static void compute_statistics(Scheduler *s) {
    for (int a = 0; a < s->course_count; ++a) if (s->assignment[a])
        for (int b = a + 1; b < s->course_count; ++b) if (s->assignment[b] && s->shared[a][b]) {
            int kind = relation(s, s->assignment[a], s->assignment[b]);
            if (kind >= 0) { int value = s->weights[kind] * s->shared[a][b]; s->contributions[a] += value; s->contributions[b] += value; }
        }
    for (int i = 0; i < s->front_load.count; ++i) {
        int c = s->front_load.items[i]; if (s->assignment[c] > s->deadline) s->contributions[c] += s->weights[3];
    }
    for (int student = 0; student < s->student_count; ++student) {
        StudentStats *stats = &s->statistics[student]; const Student *record = &s->students[student];
        for (int i = 0; i < record->count; ++i) {
            int c = record->courses[i]; if (!s->assignment[c]) continue;
            int j = stats->assigned.count++;
            while (j > 0 && s->assignment[stats->assigned.items[j - 1]] > s->assignment[c]) { stats->assigned.items[j] = stats->assigned.items[j - 1]; --j; }
            stats->assigned.items[j] = c;
        }
        for (int i = 0; i < stats->assigned.count; ++i)
            for (int j = i + 1; j < stats->assigned.count; ++j) {
                int kind = relation(s, s->assignment[stats->assigned.items[i]], s->assignment[stats->assigned.items[j]]);
                if (kind >= 0) ++stats->counts[kind];
            }
        for (int k = 0; k < 3; ++k) stats->total += s->weights[k] * stats->counts[k];
    }
}
static int assigned_count(const Scheduler *s) { int count = 0; for (int c = 0; c < s->course_count; ++c) if (s->assignment[c]) ++count; return count; }
static bool unscheduled(const Scheduler *s, int c) { return s->courses[c].size && !s->assignment[c]; }
static int unscheduled_count(const Scheduler *s) { int count = 0; for (int c = 0; c < s->course_count; ++c) if (unscheduled(s, c)) ++count; return count; }
static int open_count(const Scheduler *s) { int count = 0; for (int slot = 1; slot <= s->slots; ++slot) if (!s->closed[slot]) ++count; return count; }
static void room_loads(const Scheduler *s, int slot, int *exams, int *students) {
    memset(exams, 0, MAX_ROOMS * sizeof(int)); memset(students, 0, MAX_ROOMS * sizeof(int));
    for (int i = 0; i < s->packed_count[slot]; ++i) { Placement p = s->packed[slot][i]; ++exams[p.room]; students[p.room] += s->courses[p.course].size; }
}
static Lines timetable_lines(const Scheduler *s) {
    Lines lines = {0}; int opened = open_count(s);
    add_line(&lines, "TIMETABLE days %d periods %d open %d courses %d scheduled %d unscheduled %d empty %d", s->days, s->periods, opened, s->course_count, assigned_count(s), unscheduled_count(s), s->empty.count);
    char *cells[6];
    for (int p = 1; p <= s->periods; ++p) cells[p - 1] = format("P%d", p);
    cells[s->periods] = "TOTAL"; add_line(&lines, "%s", fixed_width("DAY", cells, s->periods + 1, 4, 10));
    for (int day = 1; day <= s->days; ++day) {
        int exams = 0, students = 0;
        for (int p = 1; p <= s->periods; ++p) {
            int slot = (day - 1) * s->periods + p;
            if (s->closed[slot]) { cells[p - 1] = "closed"; continue; }
            int count = 0;
            for (int i = 0; i < s->packed_count[slot]; ++i) count += s->courses[s->packed[slot][i].course].size;
            cells[p - 1] = format("%d/%d", s->packed_count[slot], count); exams += s->packed_count[slot]; students += count;
        }
        cells[s->periods] = format("%d/%d", exams, students);
        add_line(&lines, "%s", fixed_width(format("D%d", day), cells, s->periods + 1, 4, 10));
    }
    int total_invigilators = 0;
    for (int slot = 1; slot <= s->slots; ++slot) {
        if (s->closed[slot]) { add_line(&lines, "SLOT %d %s minutes %d closed", slot, slot_name(s, slot), slot_length(s, slot)); continue; }
        int exams[MAX_ROOMS], students[MAX_ROOMS], count = 0, seats = 0, used = 0, invigilators = 0;
        room_loads(s, slot, exams, students);
        for (int r = 0; r < s->room_count; ++r) if (exams[r]) { count += students[r]; seats += s->rooms[r].capacity; ++used; invigilators += ceil_div(students[r], s->ratio); }
        total_invigilators += invigilators;
        add_line(&lines, "SLOT %d %s minutes %d exams %d students %d rooms %d seats %d invigilators %d", slot, slot_name(s, slot), slot_length(s, slot), s->packed_count[slot], count, used, seats, invigilators);
        for (int i = 0; i < s->packed_count[slot]; ++i) {
            Placement p = s->packed[slot][i]; const Course *course = &s->courses[p.course];
            add_line(&lines, "  %s %dmin students %d room %s seats %d-%d%s %s", course->id, course->duration, course->size, s->rooms[p.room].id, p.first, p.last, s->fixed[p.course] ? " fixed" : "", course->name);
        }
    }
    for (int r = 0; r < s->room_count; ++r) {
        int slots = 0, exams = 0, seated = 0;
        for (int slot = 1; slot <= s->slots; ++slot) {
            bool used = false;
            for (int i = 0; i < s->packed_count[slot]; ++i) if (s->packed[slot][i].room == r) { used = true; ++exams; seated += s->courses[s->packed[slot][i].course].size; }
            if (used) ++slots;
        }
        add_line(&lines, "ROOM %s capacity %d slots %d exams %d seated %d utilization %d", s->rooms[r].id, s->rooms[r].capacity, slots, exams, seated, rounded_percent(seated, s->rooms[r].capacity * opened));
    }
    add_line(&lines, "INVIGILATORS total %d ratio %d", total_invigilators, s->ratio); return lines;
}
static Lines room_lines(const Scheduler *s) {
    Lines lines = {0}; add_line(&lines, "slot,room,course,students,first_seat,last_seat");
    for (int slot = 1; slot <= s->slots; ++slot)
        for (int r = 0; r < s->room_count; ++r)
            for (int i = 0; i < s->packed_count[slot]; ++i) {
                Placement p = s->packed[slot][i]; if (p.room != r) continue;
                add_line(&lines, "%s,%s,%s,%d,%d,%d", slot_name(s, slot), s->rooms[r].id, s->courses[p.course].id, s->courses[p.course].size, p.first, p.last);
            }
    return lines;
}
static void student_statistics(const Scheduler *s, Lines *lines) {
    int sorted[MAX_STUDENTS], ranking[MAX_STUDENTS], gaps[MAX_SLOTS + 1] = {0}, dayloads[13] = {0};
    for (int student = 0; student < s->student_count; ++student) {
        int i = student;
        while (i > 0 && s->statistics[sorted[i - 1]].total > s->statistics[student].total) { sorted[i] = sorted[i - 1]; --i; }
        sorted[i] = student; i = student;
        while (i > 0 && s->statistics[ranking[i - 1]].total < s->statistics[student].total) { ranking[i] = ranking[i - 1]; --i; }
        ranking[i] = student;
        Courses assigned = s->statistics[student].assigned; int days[8] = {0}, maximum = 0;
        for (int j = 0; j < assigned.count; ++j) {
            int slot = s->assignment[assigned.items[j]], value = ++days[day_of(s, slot)]; if (value > maximum) maximum = value;
            if (j) ++gaps[slot - s->assignment[assigned.items[j - 1]]];
        }
        if (maximum) ++dayloads[maximum];
    }
    for (int i = 0; i < s->student_count;) {
        int value = s->statistics[sorted[i]].total, j = i + 1;
        while (j < s->student_count && s->statistics[sorted[j]].total == value) ++j;
        add_line(lines, "HISTOGRAM %d %d", value, j - i); i = j;
    }
    for (int gap = 1; gap <= s->slots; ++gap) if (gaps[gap]) add_line(lines, "GAP %d %d", gap, gaps[gap]);
    for (int load = 1; load <= 12; ++load) if (dayloads[load]) add_line(lines, "DAYLOAD %d %d", load, dayloads[load]);
    for (int i = 0; i < minimum(5, s->student_count); ++i) {
        int student = ranking[i]; const StudentStats *stats = &s->statistics[student];
        if (stats->total) add_line(lines, "WORST %s penalty %d back_to_back %d same_day %d overnight %d", s->students[student].id, stats->total, stats->counts[0], stats->counts[1], stats->counts[2]);
    }
}
static Lines penalty_lines(const Scheduler *s) {
    Lines lines = {0};
    add_line(&lines, "WEIGHTS back_to_back %d same_day %d overnight %d front_load %d", s->weights[0], s->weights[1], s->weights[2], s->weights[3]);
    add_line(&lines, "FRONT_LOAD courses %d last_slot %s", s->front_load.count, slot_name(s, s->deadline));
    add_line(&lines, "INITIAL %s", breakdown_text(s->initial)); append_lines(&lines, &s->exchange_log);
    add_line(&lines, "EXCHANGED %s", breakdown_text(s->exchanged)); append_lines(&lines, &s->swap_log);
    add_line(&lines, "FINAL %s", breakdown_text(s->final)); add_line(&lines, "SAVED %d", s->initial.total - s->final.total);
    int daily[8][3] = {{0}};
    for (int a = 0; a < s->course_count; ++a) if (s->assignment[a])
        for (int b = a + 1; b < s->course_count; ++b) if (s->assignment[b] && s->shared[a][b]) {
            int kind = relation(s, s->assignment[a], s->assignment[b]);
            if (kind >= 0) daily[day_of(s, minimum(s->assignment[a], s->assignment[b]))][kind] += s->shared[a][b];
        }
    for (int day = 1; day <= s->days; ++day) add_line(&lines, "DAY D%d back_to_back %d same_day %d overnight %d", day, daily[day][0], daily[day][1], daily[day][2]);
    for (int i = 0; i < s->front_load.count; ++i) {
        int c = s->front_load.items[i]; if (s->assignment[c] > s->deadline) add_line(&lines, "LATE %s %s students %d", s->courses[c].id, slot_name(s, s->assignment[c]), s->courses[c].size);
    }
    Courses ranked = {0}; for (int c = 0; c < s->course_count; ++c) if (s->assignment[c]) ranked.items[ranked.count++] = c;
    sort_courses(s, &ranked, s->contributions);
    for (int i = 0; i < minimum(10, ranked.count); ++i) { int c = ranked.items[i]; if (s->contributions[c]) add_line(&lines, "COURSE %s %s penalty %d", s->courses[c].id, slot_name(s, s->assignment[c]), s->contributions[c]); }
    student_statistics(s, &lines); return lines;
}
static Lines schedule_lines(const Scheduler *s, const Lines *queries) {
    static const char *classes[] = {"BACK_TO_BACK", "SAME_DAY", "OVERNIGHT"}; Lines lines = {0};
    for (int q = 0; q < queries->count; ++q) {
        int student = find_student(s, queries->items[q]);
        if (student < 0) { add_line(&lines, "STUDENT %s not found", queries->items[q]); continue; }
        const Student *record = &s->students[student]; const StudentStats *stats = &s->statistics[student];
        add_line(&lines, "STUDENT %s exams %d scheduled %d penalty %d", record->id, record->count, stats->assigned.count, stats->total);
        for (int i = 0; i < stats->assigned.count; ++i) {
            int c = stats->assigned.items[i], offset = 0; const Course *course = &s->courses[c]; Placement p = s->placements[c];
            while (course->students[offset] != student) ++offset;
            add_line(&lines, "  %s %s room %s seat %d %s", slot_name(s, s->assignment[c]), course->id, s->rooms[p.room].id, p.first + offset, course->name);
        }
        for (int i = 0; i < record->count; ++i) { int c = record->courses[i]; if (!s->assignment[c]) add_line(&lines, "  UNSCHEDULED %s %s", s->courses[c].id, s->courses[c].name); }
        for (int i = 0; i < stats->assigned.count; ++i)
            for (int j = i + 1; j < stats->assigned.count; ++j) {
                int a = stats->assigned.items[i], b = stats->assigned.items[j], kind = relation(s, s->assignment[a], s->assignment[b]);
                if (kind >= 0) add_line(&lines, "  %s %s %s %s %s", classes[kind], slot_name(s, s->assignment[a]), s->courses[a].id, slot_name(s, s->assignment[b]), s->courses[b].id);
            }
        for (int slot = 1; slot <= s->slots; ++slot) if (record->unavailable[slot]) add_line(&lines, "  UNAVAILABLE %s", slot_name(s, slot));
    }
    return lines;
}
static Lines status_lines(const Scheduler *s) {
    Lines lines = {0}; add_line(&lines, "course,status,slot,students,minutes,degree,penalty");
    for (int c = 0; c < s->course_count; ++c) {
        const Course *course = &s->courses[c];
        const char *status = s->fixed[c] ? "fixed" : s->assignment[c] ? "scheduled" : course->size > s->largest_room ? "too_large" : !course->size ? "empty" : "no_slot";
        add_line(&lines, "%s,%s,%s,%d,%d,%d,%d", course->id, status, s->assignment[c] ? slot_name(s, s->assignment[c]) : "-", course->size, course->duration, s->degree[c], s->contributions[c]);
    }
    return lines;
}
static Lines report_lines(const Scheduler *s) {
    Lines lines = {0};
    add_line(&lines, "INPUT courses %d enrolments %d rooms %d students %d errors %d", s->course_count, s->enrolment_count, s->room_count, s->student_count, s->errors.count);
    for (int i = 0; i < s->errors.count; ++i) add_line(&lines, "ERROR %s", s->errors.items[i]);
    int edges = 0, shared = 0;
    for (int a = 0; a < s->course_count; ++a) for (int b = a + 1; b < s->course_count; ++b) if (s->shared[a][b]) { ++edges; shared += s->shared[a][b]; }
    int vertices = s->vertices.count, density = vertices >= 2 ? 2000 * edges / (vertices * (vertices - 1)) : 0;
    add_line(&lines, "GRAPH courses %d edges %d shared %d density %d", vertices, edges, shared, density);
    Courses ranked = s->vertices; sort_courses(s, &ranked, s->degree);
    for (int i = 0; i < minimum(5, ranked.count); ++i) {
        int c = ranked.items[i], total = 0; for (int n = 0; n < s->course_count; ++n) total += s->shared[c][n];
        add_line(&lines, "DEGREE %s neighbours %d shared %d students %d", s->courses[c].id, s->degree[c], total, s->courses[c].size);
    }
    Component groups[MAX_COURSES]; int count = components(s, groups); add_line(&lines, "COMPONENTS %d", count);
    for (int i = 0; i < count; ++i) add_line(&lines, "COMPONENT %d size %d first %s", i + 1, groups[i].members.count, s->courses[groups[i].members.items[0]].id);
    Courses clique = greedy_clique(s); char clique_text[1000]; int offset = sprintf(clique_text, "CLIQUE size %d", clique.count);
    for (int i = 0; i < clique.count; ++i) offset += sprintf(clique_text + offset, " %s", s->courses[clique.items[i]].id);
    add_line(&lines, "%s", clique_text);
    int most = 0, attaining = 0, demand = 0, capacity = 0;
    for (int i = 0; i < s->student_count; ++i) {
        int load = s->students[i].count; if (load > most) { most = load; attaining = 0; } if (load == most) ++attaining;
    }
    for (int i = 0; i < s->schedulable.count; ++i) demand += s->courses[s->schedulable.items[i]].size;
    for (int r = 0; r < s->room_count; ++r) capacity += s->rooms[r].capacity;
    add_line(&lines, "LOAD max_exams %d students %d", most, attaining);
    add_line(&lines, "SEATS demand %d capacity %d min_slots %d", demand, capacity, ceil_div(demand, capacity));
    ranked = s->schedulable; sort_courses(s, &ranked, s->degree); add_line(&lines, "HEURISTIC largest_degree slots %d", greedy_numbering(s, ranked));
    sort_courses(s, &ranked, NULL); add_line(&lines, "HEURISTIC largest_enrolment slots %d", greedy_numbering(s, ranked));
    ranked = s->vertices; sort_courses(s, &ranked, NULL); ranked.count = minimum(8, ranked.count); char *cells[8];
    for (int i = 0; i < ranked.count; ++i) cells[i] = (char *)s->courses[ranked.items[i]].id;
    add_line(&lines, "%s", fixed_width("MATRIX", cells, ranked.count, 9, 9));
    for (int i = 0; i < ranked.count; ++i) {
        int row = ranked.items[i];
        for (int j = 0; j < ranked.count; ++j) cells[j] = i == j ? "-" : format("%d", s->shared[row][ranked.items[j]]);
        add_line(&lines, "%s", fixed_width(s->courses[row].id, cells, ranked.count, 9, 9));
    }
    for (int i = 0; i < s->empty.count; ++i) add_line(&lines, "EMPTY %s", s->courses[s->empty.items[i]].id);
    for (int i = 0; i < s->oversized.count; ++i) { int c = s->oversized.items[i]; add_line(&lines, "TOO_LARGE %s students %d largest_room %d", s->courses[c].id, s->courses[c].size, s->largest_room); }
    for (int slot = 1; slot <= s->slots; ++slot) if (s->closed[slot]) add_line(&lines, "CLOSED %s", slot_name(s, slot));
    for (int c = 0; c < s->course_count; ++c) if (s->fixed[c]) add_line(&lines, "FIXED %s %s", s->courses[c].id, slot_name(s, s->fixed[c]));
    for (int i = 0; i < s->order_count; ++i) add_line(&lines, "AFTER %s %s", s->courses[s->orders[i].later].id, s->courses[s->orders[i].earlier].id);
    for (int i = 0; i < s->attempt_count; ++i) {
        AttemptRecord a = s->attempts[i]; char *result = a.failed_course < 0 ? "success" : format("failed %s", s->courses[a.failed_course].id);
        add_line(&lines, "ATTEMPT %d courses %d backtracks %d %s", i + 1, a.size, a.dead_ends, result);
    }
    for (int i = 0; i < s->choice_count; ++i) { Choice c = s->choices[i]; add_line(&lines, "ORDER %d %s %s saturation %d degree %d", i + 1, s->courses[c.course].id, slot_name(s, c.slot), c.saturation, s->degree[c.course]); }
    for (int i = 0; i < s->insertion_count; ++i) { Insertion in = s->insertions[i]; add_line(&lines, "INSERTED %s %s penalty %d", s->courses[in.course].id, slot_name(s, in.slot), in.increase); }
    for (int c = 0; c < s->course_count; ++c) if (unscheduled(s, c)) {
        add_line(&lines, "UNSCHEDULED %s reason %s students %d", s->courses[c].id, s->courses[c].size > s->largest_room ? "too_large" : "no_slot", s->courses[c].size);
        for (int slot = 1; slot <= s->slots; ++slot) if (s->reasons[c][slot]) add_line(&lines, "  %s %s", slot_name(s, slot), s->reasons[c][slot]);
    }
    int slots_used = 0; for (int slot = 1; slot <= s->slots; ++slot) if (s->packed_count[slot]) ++slots_used;
    add_line(&lines, "SUMMARY scheduled %d unscheduled %d slots_used %d penalty %d", assigned_count(s), unscheduled_count(s), slots_used, s->penalty); return lines;
}
int main(void) {
    static Scheduler scheduler; Scheduler *s = &scheduler;
    load_courses(s); load_enrolments(s); load_rooms(s);
    Lines calendar = read_lines("input/calendar.txt"); read_settings(s, &calendar); classify(s); validate_calendar(s, &calendar);
    build_timetable(s); insert_excluded(s); exchange_slots(s); swap_chains(s); assign_rooms(s); compute_statistics(s);
    Lines queries = read_lines("input/queries.txt");
    Lines files[] = {timetable_lines(s), room_lines(s), penalty_lines(s), schedule_lines(s, &queries), status_lines(s), report_lines(s)};
    const char *names[] = {"timetable.txt", "rooms.csv", "penalties.txt", "student_schedules.txt", "course_status.csv", "report.txt"};
    for (int i = 0; i < 6; ++i) write_lines(names[i], &files[i]);
    return 0;
}
