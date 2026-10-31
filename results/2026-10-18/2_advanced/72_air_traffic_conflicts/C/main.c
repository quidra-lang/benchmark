#include "airspace.h"

#define PI 3.141592653589793
static const char *geometry_names[3] = {"head_on", "crossing", "trailing"};
static const char *severity_names[3] = {"HIGH", "MEDIUM", "LOW"};
static const char *outcomes[3] = {"remaining", "resolved", "indirect"};
typedef struct {
    Pair pair;
    double start, end, distance;
} Summary;
typedef enum { INFEASIBLE, BLOCKED, ACCEPTED } TrialStatus;
typedef struct {
    int flight;
    Name name;
    TrialStatus status;
    Summary blocker;
} Trial;
DEFINE_VECTOR(Trials, Trial)
typedef struct {
    Summary target;
    Trials trials;
    bool accepted;
    Trial chosen;
} Round;
DEFINE_VECTOR(Rounds, Round)
DEFINE_VECTOR(Summaries, Summary)
typedef struct {
    int flight, sector;
    double entry, exit;
    int previous, next;
} Transit;
DEFINE_VECTOR(Transits, Transit)
typedef struct {
    int sector;
    size_t number;
    Integer start, end;
    int entries[2], peak[2];
    double mean;
    int status;
} Period;
DEFINE_VECTOR(Periods, Period)
typedef struct {
    Pair pair;
    Integer first, last, samples;
    double predicted, distance;
    bool matched;
    double lead;
} Alert;
DEFINE_VECTOR(Alerts, Alert)
typedef struct {
    Integer level;
    bool flights[2][100];
    double time[2];
} LevelUsage;
DEFINE_VECTOR(Levels, LevelUsage)
typedef struct {
    Input input;
    Plan plans[2][100];
    Trajectory trajectories[2][100];
    Conflicts conflicts[2];
    bool unresolved[100][100], resolved[100][100], final_pairs[100][100];
    Rounds rounds;
    Summaries unresolved_conflicts;
    Transits transits[2];
    int *occupancy[2][20];
    Periods periods;
    Integers samples;
} Traffic;
static Summary summary(const Conflict *c) {
    return (Summary){c->pair, c->start, c->end, c->closest.loss.distance};
}
static bool pair_equal(Pair a, Pair b) { return a.first == b.first && a.second == b.second; }
static bool summary_before(Summary a, Summary b) {
    return a.start < b.start ||
           (a.start == b.start && (a.pair.first < b.pair.first || (a.pair.first == b.pair.first &&
                                                                   a.pair.second < b.pair.second)));
}
static const char *callsign(const Traffic *t, int flight) {
    return t->input.plans[flight].callsign;
}
static const char *pair_name(const Traffic *t, Pair pair) {
    static char names[32][20];
    static unsigned index;
    char *out = names[index++ % 32];
    snprintf(out, 20, "%s-%s", callsign(t, pair.first), callsign(t, pair.second));
    return out;
}
static const char *sector_name(const Traffic *t, int sector) {
    return sector < 0 ? "-" : t->input.sectors[sector].name;
}
static bool active(const Conflict *c, double time) { return c->start <= time && time < c->end; }
static double track(const Segment *s) {
    double angle = atan2(s->velocity.v[0], s->velocity.v[1]) * 180 / PI;
    return angle < 0 ? angle + 360 : angle;
}
static bool contains(const Sector *s, Point p) {
    return (double)s->x1 / 10 <= p.v[0] && p.v[0] < (double)s->x2 / 10 &&
           (double)s->y1 / 10 <= p.v[1] && p.v[1] < (double)s->y2 / 10 &&
           (double)s->lower * 100 <= p.v[2] && p.v[2] < (double)s->upper * 100;
}
static bool inside(const Segment *s, const Sector *sector, double *first, double *last) {
    double low[3] = {(double)sector->x1 / 10, (double)sector->y1 / 10, (double)sector->lower * 100};
    double high[3] = {(double)sector->x2 / 10, (double)sector->y2 / 10,
                      (double)sector->upper * 100};
    *first = s->start_time;
    *last = s->end_time;
    for (int a = 0; a < 3; ++a) {
        double p = s->start.v[a], v = s->velocity.v[a];
        if (v == 0) {
            if (!(low[a] <= p && p < high[a]))
                return false;
        } else {
            double r1 = (low[a] - p) / v, r2 = (high[a] - p) / v;
            *first = fmax(*first, s->start_time + fmin(r1, r2));
            *last = fmin(*last, s->start_time + fmax(r1, r2));
        }
    }
    return *last - *first > 1e-6;
}
static bool find_blocker(const Traffic *t, int changed, const Trajectory *candidate, int partner,
                         double start, Summary *out) {
    bool found = false;
    for (int other = 0; other < t->input.plan_count; ++other) {
        if (other == changed)
            continue;
        Pair pair = changed < other ? (Pair){changed, other} : (Pair){other, changed};
        if (t->unresolved[pair.first][pair.second])
            continue;
        const Trajectory *a = pair.first == changed ? candidate : &t->trajectories[1][pair.first];
        const Trajectory *b = pair.second == changed ? candidate : &t->trajectories[1][pair.second];
        Conflicts list = pair_conflicts(pair.first, a, pair.second, b, &t->input.params);
        for (size_t i = 0; i < list.count; ++i) {
            Summary item = summary(&list.items[i]);
            if ((other == partner || item.start < start + (double)t->input.params.lookahead) &&
                (!found || summary_before(item, *out))) {
                *out = item;
                found = true;
            }
        }
        free_conflicts(&list);
    }
    return found;
}
static void resolve(Traffic *t) {
    Manoeuvres choices = manoeuvres(t->input.params.max_delay);
    for (;;) {
        Conflicts current =
            all_conflicts(t->trajectories[1], t->input.plan_count, &t->input.params);
        const Conflict *target = NULL;
        for (size_t i = 0; i < current.count; ++i)
            if (!t->unresolved[current.items[i].pair.first][current.items[i].pair.second]) {
                target = &current.items[i];
                break;
            }
        if (!target) {
            free_conflicts(&current);
            break;
        }
        Round record = {0};
        record.target = summary(target);
        int priority[2];
        priority_order(target->pair.first, target->pair.second, t->plans[1], priority);
        for (int index = 0; index < 2 && !record.accepted; ++index) {
            int flight = priority[index], partner = priority[1 - index];
            for (size_t i = 0; i < choices.count; ++i) {
                const Manoeuvre *choice = &choices.items[i];
                Trial trial = {0};
                trial.flight = flight;
                trial.name = choice->name;
                trial.status = INFEASIBLE;
                Plan proposal;
                if (propose(&t->plans[1][flight], choice, t->input.types, &t->input.params,
                            &proposal)) {
                    Trajectory candidate;
                    build_trajectory(&proposal, t->input.types, &candidate);
                    if (find_blocker(t, flight, &candidate, partner, target->start, &trial.blocker))
                        trial.status = BLOCKED;
                    else {
                        trial.status = ACCEPTED;
                        Names_append(&proposal.history, choice->name);
                        t->plans[1][flight] = proposal;
                        t->trajectories[1][flight] = candidate;
                        record.accepted = true;
                        record.chosen = trial;
                    }
                }
                Trials_append(&record.trials, trial);
                if (record.accepted)
                    break;
            }
        }
        if (record.accepted)
            t->resolved[target->pair.first][target->pair.second] = true;
        else {
            t->unresolved[target->pair.first][target->pair.second] = true;
            Summaries_append(&t->unresolved_conflicts, record.target);
        }
        Rounds_append(&t->rounds, record);
        free_conflicts(&current);
    }
    free(choices.items);
}
static void classify(Traffic *t, int state) {
    for (size_t i = 0; i < t->conflicts[state].count; ++i) {
        Conflict *c = &t->conflicts[state].items[i];
        Piece *piece = &c->closest;
        const Segment *a = &t->trajectories[state][c->pair.first].segments[piece->first_segment],
                      *b = &t->trajectories[state][c->pair.second].segments[piece->second_segment];
        Point pa = position(a, piece->loss.time), pb = position(b, piece->loss.time), middle;
        c->first_level = pa.v[2] / 100;
        c->second_level = pb.v[2] / 100;
        c->first_track = track(a);
        c->second_track = track(b);
        double gap = fabs(c->first_track - c->second_track);
        c->angle = gap > 180 ? 360 - gap : gap;
        double dot = a->velocity.v[0] * b->velocity.v[0] + a->velocity.v[1] * b->velocity.v[1],
               cross = a->velocity.v[0] * b->velocity.v[1] - a->velocity.v[1] * b->velocity.v[0];
        c->geometry = dot * dot > cross * cross ? (dot < 0 ? 0 : 2) : 1;
        c->severity = 10 * piece->loss.distance < 4 * (double)t->input.params.horizontal   ? 0
                      : 10 * piece->loss.distance < 7 * (double)t->input.params.horizontal ? 1
                                                                                           : 2;
        for (int axis = 0; axis < 3; ++axis)
            middle.v[axis] = (pa.v[axis] + pb.v[axis]) / 2;
        c->sector = -1;
        for (int s = 0; s < t->input.sector_count; ++s)
            if (contains(&t->input.sectors[s], middle)) {
                c->sector = s;
                break;
            }
        c->outcome = state == 1 || t->final_pairs[c->pair.first][c->pair.second] ? 0
                     : t->resolved[c->pair.first][c->pair.second]                ? 1
                                                                                 : 2;
    }
}
static void trajectory_report(const Traffic *t, FILE *out) {
    fputs("callsign,segment,leg,phase,t_start,t_end,x_start,y_start,fl_start,x_end,y_end,fl_end\n",
          out);
    for (int flight = 0; flight < t->input.plan_count; ++flight)
        for (int i = 0; i < t->trajectories[1][flight].count; ++i) {
            const Segment *s = &t->trajectories[1][flight].segments[i];
            fprintf(out, "%s,%d,%d,%s,%s,%s,%s,%s,%lld,%s,%s,%lld\n", callsign(t, flight),
                    s->number, s->leg, phase_name(s->phase), decimal(s->start_time, 3),
                    decimal(s->end_time, 3), decimal(s->start.v[0], 3), decimal(s->start.v[1], 3),
                    (long long)(s->start.v[2] / 100), decimal(s->end.v[0], 3),
                    decimal(s->end.v[1], 3), (long long)(s->end.v[2] / 100));
        }
}
static void conflict_counts(const Traffic *t, int state, size_t counts[100]) {
    memset(counts, 0, 100 * sizeof *counts);
    for (size_t i = 0; i < t->conflicts[state].count; ++i) {
        Pair p = t->conflicts[state].items[i].pair;
        ++counts[p.first];
        ++counts[p.second];
    }
}
static void conflict_report(const Traffic *t, int state, FILE *out) {
    const Conflicts *list = &t->conflicts[state];
    fprintf(out, "CONFLICTS plan=%s count=%zu\n", state ? "final" : "initial", list->count);
    double total = 0, minimum = 0;
    size_t geometries[3] = {0}, severities[3] = {0};
    for (size_t i = 0; i < list->count; ++i) {
        const Conflict *c = &list->items[i];
        const Piece *piece = &c->closest;
        const Segment *a = &t->trajectories[state][c->pair.first].segments[piece->first_segment],
                      *b = &t->trajectories[state][c->pair.second].segments[piece->second_segment];
        fprintf(out, "CONFLICT %zu %s start=%s end=%s duration=%s outcome=%s\n", i + 1,
                pair_name(t, c->pair), decimal(c->start, 3), decimal(c->end, 3),
                decimal(c->end - c->start, 3), outcomes[c->outcome]);
        fprintf(out, "  CPA t=%s dist=%s vert=%s levels=%s/%s tracks=%s/%s angle=%s\n",
                decimal(piece->loss.time, 3), decimal(piece->loss.distance, 3),
                decimal(piece->loss.vertical, 1), decimal(c->first_level, 2),
                decimal(c->second_level, 2), decimal(c->first_track, 1),
                decimal(c->second_track, 1), decimal(c->angle, 1));
        fprintf(out, "  TYPE geometry=%s phases=%s/%s segments=%d/%d sector=%s severity=%s\n",
                geometry_names[c->geometry], phase_name(a->phase), phase_name(b->phase), a->number,
                b->number, sector_name(t, c->sector), severity_names[c->severity]);
        for (size_t k = 0; k < c->pieces.count; ++k) {
            const Piece *p = &c->pieces.items[k];
            fprintf(out, "  PIECE %d/%d %s %s\n", p->first_segment + 1, p->second_segment + 1,
                    decimal(p->loss.low, 3), decimal(p->loss.high, 3));
        }
        total += c->end - c->start;
        if (i == 0 || piece->loss.distance < minimum)
            minimum = piece->loss.distance;
        ++geometries[c->geometry];
        ++severities[c->severity];
    }
    fprintf(
        out,
        "SUMMARY count=%zu total=%s min_dist=%s head_on=%zu crossing=%zu trailing=%zu high=%zu medium=%zu low=%zu\n",
        list->count, decimal(total, 3), list->count ? decimal(minimum, 3) : "-", geometries[0],
        geometries[1], geometries[2], severities[0], severities[1], severities[2]);
    size_t counts[100];
    conflict_counts(t, state, counts);
    for (int flight = 0; flight < t->input.plan_count; ++flight)
        if (counts[flight]) {
            bool partners[100] = {false};
            double first = 0;
            bool found = false;
            for (size_t i = 0; i < list->count; ++i) {
                const Conflict *c = &list->items[i];
                if (c->pair.first == flight || c->pair.second == flight) {
                    partners[c->pair.first == flight ? c->pair.second : c->pair.first] = true;
                    if (!found) {
                        first = c->start;
                        found = true;
                    }
                }
            }
            fprintf(out, "FLIGHT %s conflicts=%zu first=%s partners=", callsign(t, flight),
                    counts[flight], decimal(first, 3));
            bool separator = false;
            for (int other = 0; other < t->input.plan_count; ++other)
                if (partners[other]) {
                    if (separator)
                        fputc(',', out);
                    fputs(callsign(t, other), out);
                    separator = true;
                }
            fputc('\n', out);
        }
    fprintf(out, "TIMELINE from=%lld to=%lld step=60\n", (long long)t->input.params.sample_start,
            (long long)t->input.params.sample_end);
    for (int flight = 0; flight < t->input.plan_count; ++flight)
        if (counts[flight]) {
            fprintf(out, "%s ", callsign(t, flight));
            for (size_t j = 0; j < t->samples.count; ++j) {
                double time = (double)t->samples.items[j];
                char ch = active_segment(&t->trajectories[state][flight], time) ? '-' : '.';
                if (ch == '-')
                    for (size_t i = 0; i < list->count; ++i) {
                        const Conflict *c = &list->items[i];
                        if ((c->pair.first == flight || c->pair.second == flight) &&
                            active(c, time)) {
                            ch = 'X';
                            break;
                        }
                    }
                fputc(ch, out);
            }
            fputc('\n', out);
        }
}
static void resolution_report(const Traffic *t, FILE *out) {
    size_t accepted = 0, level = 0, speed = 0, delay = 0, trials = 0, infeasible = 0, blocked = 0;
    const char *statuses[3] = {"infeasible", "blocked", "accepted"};
    for (size_t i = 0; i < t->rounds.count; ++i) {
        const Round *r = &t->rounds.items[i];
        fprintf(out, "ROUND %zu %s start=%s end=%s dist=%s\n", i + 1, pair_name(t, r->target.pair),
                decimal(r->target.start, 3), decimal(r->target.end, 3),
                decimal(r->target.distance, 3));
        for (size_t j = 0; j < r->trials.count; ++j) {
            const Trial *trial = &r->trials.items[j];
            fprintf(out, "  TRY %s %s %s", callsign(t, trial->flight), trial->name.text,
                    statuses[trial->status]);
            if (trial->status == BLOCKED)
                fprintf(out, " %s start=%s", pair_name(t, trial->blocker.pair),
                        decimal(trial->blocker.start, 3));
            fputc('\n', out);
            ++trials;
            infeasible += trial->status == INFEASIBLE;
            blocked += trial->status == BLOCKED;
        }
        if (r->accepted) {
            const Trial *trial = &r->chosen;
            fprintf(out, "  RESULT resolved %s %s\n", callsign(t, trial->flight), trial->name.text);
            ++accepted;
            level +=
                !strcmp(trial->name.text, "level_up") || !strcmp(trial->name.text, "level_down");
            speed += !strcmp(trial->name.text, "speed_down");
            delay += !strncmp(trial->name.text, "delay_", 6);
        } else
            fputs("  RESULT unresolved\n", out);
    }
    size_t initial[100], final[100];
    conflict_counts(t, 0, initial);
    conflict_counts(t, 1, final);
    double total_extra = 0;
    Integer total_delay = 0;
    for (int flight = 0; flight < t->input.plan_count; ++flight) {
        const Plan *old = &t->plans[0][flight], *p = &t->plans[1][flight];
        double before = t->trajectories[0][flight].arrival,
               after = t->trajectories[1][flight].arrival, extra = after - before;
        total_extra += extra;
        total_delay += p->delay;
        char *history = joined(&p->history);
        fprintf(
            out,
            "FLIGHT %s departure=%lld delay=%lld level=%s speed=%d->%d arrival=%s->%s extra=%s length=%s conflicts=%zu->%zu manoeuvres=%s\n",
            callsign(t, flight), (long long)(p->departure + p->delay), (long long)p->delay,
            signed_integer(p->offset), old->speed, p->speed, decimal(before, 3), decimal(after, 3),
            decimal(extra, 3), decimal(t->trajectories[1][flight].length, 3), initial[flight],
            final[flight], p->history.count ? history : "-");
        free(history);
    }
    for (size_t i = 0; i < t->unresolved_conflicts.count; ++i) {
        Summary c = t->unresolved_conflicts.items[i];
        fprintf(out, "UNRESOLVED %s start=%s dist=%s\n", pair_name(t, c.pair), decimal(c.start, 3),
                decimal(c.distance, 3));
    }
    fprintf(
        out,
        "TOTAL rounds=%zu resolved=%zu unresolved=%zu level=%zu speed=%zu delay=%zu total_delay=%lld total_extra=%s trials=%zu infeasible=%zu blocked=%zu\n",
        t->rounds.count, accepted, t->unresolved_conflicts.count, level, speed, delay,
        (long long)total_delay, decimal(total_extra, 3), trials, infeasible, blocked);
}
static int transit_compare(const void *left, const void *right) {
    const Transit *a = left, *b = right;
    if (a->entry != b->entry)
        return a->entry < b->entry ? -1 : 1;
    return (a->sector > b->sector) - (a->sector < b->sector);
}
static void compute_transits(Traffic *t, int state) {
    for (int flight = 0; flight < t->input.plan_count; ++flight) {
        Transits list = {0};
        for (int sector = 0; sector < t->input.sector_count; ++sector) {
            double firsts[14], lasts[14];
            int count = 0;
            for (int i = 0; i < t->trajectories[state][flight].count; ++i) {
                double first, last;
                if (!inside(&t->trajectories[state][flight].segments[i], &t->input.sectors[sector],
                            &first, &last))
                    continue;
                if (count && first - lasts[count - 1] <= 1e-6)
                    lasts[count - 1] = last;
                else {
                    firsts[count] = first;
                    lasts[count++] = last;
                }
            }
            for (int i = 0; i < count; ++i)
                Transits_append(&list, (Transit){flight, sector, firsts[i], lasts[i], -1, -1});
        }
        if (list.count > 1)
            qsort(list.items, list.count, sizeof *list.items, transit_compare);
        for (size_t i = 1; i < list.count; ++i)
            if (fabs(list.items[i].entry - list.items[i - 1].exit) <= 1e-6) {
                list.items[i - 1].next = list.items[i].sector;
                list.items[i].previous = list.items[i - 1].sector;
            }
        for (size_t i = 0; i < list.count; ++i)
            Transits_append(&t->transits[state], list.items[i]);
        free(list.items);
    }
}
static void transit_report(const Traffic *t, FILE *out) {
    fputs("callsign,sector,entry,exit,duration,from,to\n", out);
    for (size_t i = 0; i < t->transits[1].count; ++i) {
        const Transit *r = &t->transits[1].items[i];
        fprintf(out, "%s,%s,%s,%s,%s,%s,%s\n", callsign(t, r->flight), sector_name(t, r->sector),
                decimal(r->entry, 3), decimal(r->exit, 3), decimal(r->exit - r->entry, 3),
                sector_name(t, r->previous), sector_name(t, r->next));
    }
}
static void compute_occupancy(Traffic *t, int state) {
    for (int s = 0; s < t->input.sector_count; ++s)
        t->occupancy[state][s] = calloc(t->samples.count, sizeof(int));
    for (size_t i = 0; i < t->samples.count; ++i)
        for (int flight = 0; flight < t->input.plan_count; ++flight) {
            double time = (double)t->samples.items[i];
            const Segment *segment = active_segment(&t->trajectories[state][flight], time);
            if (!segment)
                continue;
            Point point = position(segment, time);
            for (int s = 0; s < t->input.sector_count; ++s)
                if (contains(&t->input.sectors[s], point))
                    ++t->occupancy[state][s][i];
        }
}
static void compute_periods(Traffic *t) {
    for (int s = 0; s < t->input.sector_count; ++s)
        for (size_t i = 0; i < t->samples.count; i += 5) {
            Period p = {0};
            p.sector = s;
            p.number = i / 5 + 1;
            p.start = t->samples.items[i];
            p.end = p.start + 300;
            int sum = 0;
            for (int state = 0; state < 2; ++state) {
                for (size_t j = i; j < i + 5; ++j) {
                    int value = t->occupancy[state][s][j];
                    if (value > p.peak[state])
                        p.peak[state] = value;
                    if (state == 1)
                        sum += value;
                }
                for (size_t j = 0; j < t->transits[state].count; ++j) {
                    const Transit *r = &t->transits[state].items[j];
                    if (r->sector == s && (double)p.start <= r->entry && r->entry < (double)p.end)
                        ++p.entries[state];
                }
            }
            p.mean = (double)sum / 5;
            p.status = p.peak[1] > t->input.sectors[s].capacity   ? 0
                       : p.peak[0] > t->input.sectors[s].capacity ? 1
                                                                  : 2;
            Periods_append(&t->periods, p);
        }
}
static void sector_load_report(const Traffic *t, FILE *out) {
    const char *status[3] = {"OVER", "RELIEVED", "OK"};
    fputs(
        "sector,period,start,end,entries_initial,entries_final,peak_initial,peak_final,mean_final,capacity,status\n",
        out);
    for (size_t i = 0; i < t->periods.count; ++i) {
        const Period *p = &t->periods.items[i];
        fprintf(out, "%s,%zu,%lld,%lld,%d,%d,%d,%d,%s,%lld,%s\n", sector_name(t, p->sector),
                p->number, (long long)p->start, (long long)p->end, p->entries[0], p->entries[1],
                p->peak[0], p->peak[1], decimal(p->mean, 1),
                (long long)t->input.sectors[p->sector].capacity, status[p->status]);
    }
}
static char **make_grid(size_t width, size_t height, char character) {
    char **grid = malloc(height * sizeof *grid);
    for (size_t i = 0; i < height; ++i) {
        grid[i] = malloc(width);
        memset(grid[i], character, width);
    }
    return grid;
}
static void free_grid(char **grid, size_t height) {
    for (size_t i = 0; i < height; ++i)
        free(grid[i]);
    free(grid);
}
static int level_compare(const void *left, const void *right) {
    Integer a = ((const LevelUsage *)left)->level, b = ((const LevelUsage *)right)->level;
    return (b > a) - (b < a);
}
static void sector_report(const Traffic *t, FILE *out) {
    for (int sector = 0; sector < t->input.sector_count; ++sector) {
        const Sector *s = &t->input.sectors[sector];
        fprintf(out, "SECTOR %s x=%d..%d y=%d..%d fl=%lld..%lld capacity=%lld\n", s->name, s->x1,
                s->x2, s->y1, s->y2, (long long)s->lower, (long long)s->upper,
                (long long)s->capacity);
        Integer height = s->capacity + 1;
        for (int state = 0; state < 2; ++state) {
            size_t entries = 0, conflict_count = 0, over = 0;
            double dwell = 0;
            int peak = 0;
            for (size_t i = 0; i < t->transits[state].count; ++i) {
                const Transit *r = &t->transits[state].items[i];
                if (r->sector == sector) {
                    ++entries;
                    dwell += r->exit - r->entry;
                }
            }
            for (size_t i = 0; i < t->samples.count; ++i)
                if (t->occupancy[state][sector][i] > peak)
                    peak = t->occupancy[state][sector][i];
            for (size_t i = 0; i < t->periods.count; ++i)
                if (t->periods.items[i].sector == sector &&
                    t->periods.items[i].peak[state] > s->capacity)
                    ++over;
            for (size_t i = 0; i < t->conflicts[state].count; ++i)
                conflict_count += t->conflicts[state].items[i].sector == sector;
            fprintf(out, "%s entries=%zu time=%s mean=%s peak=%d over=%zu conflicts=%zu\n",
                    state ? "FINAL" : "INITIAL", entries, decimal(dwell, 3),
                    entries ? decimal(dwell / (double)entries, 3) : "-", peak, over,
                    conflict_count);
            if (state == 1 && peak > height)
                height = peak;
        }
        char **grid = make_grid(t->samples.count, (size_t)height, '.');
        for (Integer row = 0; row < height; ++row) {
            Integer k = height - row;
            for (size_t j = 0; j < t->samples.count; ++j)
                grid[row][j] = t->occupancy[1][sector][j] >= k ? '#' : k == s->capacity ? '-' : '.';
        }
        frame(out, grid, t->samples.count, (size_t)height);
        free_grid(grid, (size_t)height);
    }
    Levels levels = {0};
    for (int state = 0; state < 2; ++state)
        for (int flight = 0; flight < t->input.plan_count; ++flight)
            for (int i = 0; i < t->trajectories[state][flight].count; ++i) {
                const Segment *s = &t->trajectories[state][flight].segments[i];
                if (s->phase != LEVEL)
                    continue;
                Integer level = (Integer)(s->start.v[2] / 100);
                size_t j = 0;
                while (j < levels.count && levels.items[j].level != level)
                    ++j;
                if (j == levels.count) {
                    LevelUsage usage = {0};
                    usage.level = level;
                    Levels_append(&levels, usage);
                }
                levels.items[j].flights[state][flight] = true;
                levels.items[j].time[state] += s->end_time - s->start_time;
            }
    qsort(levels.items, levels.count, sizeof *levels.items, level_compare);
    fputs("LEVELS\n", out);
    for (size_t i = 0; i < levels.count; ++i) {
        const LevelUsage *v = &levels.items[i];
        int counts[2] = {0};
        for (int state = 0; state < 2; ++state)
            for (int flight = 0; flight < t->input.plan_count; ++flight)
                counts[state] += v->flights[state][flight];
        fprintf(out, "LEVEL %lld flights=%d->%d time=%s->%s\n", (long long)v->level, counts[0],
                counts[1], decimal(v->time[0], 3), decimal(v->time[1], 3));
    }
    free(levels.items);
    size_t handoffs[20][20] = {{0}}, total = 0;
    for (size_t i = 0; i < t->transits[1].count; ++i) {
        const Transit *r = &t->transits[1].items[i];
        if (r->next >= 0) {
            ++handoffs[r->sector][r->next];
            ++total;
        }
    }
    fprintf(out, "HANDOFFS plan=final count=%zu\n", total);
    for (int a = 0; a < t->input.sector_count; ++a)
        for (int b = 0; b < t->input.sector_count; ++b)
            if (handoffs[a][b])
                fprintf(out, "HANDOFF %s %s %zu\n", sector_name(t, a), sector_name(t, b),
                        handoffs[a][b]);
}
static int alert_compare(const void *left, const void *right) {
    const Alert *a = left, *b = right;
    if (a->first != b->first)
        return a->first < b->first ? -1 : 1;
    if (a->pair.first != b->pair.first)
        return a->pair.first < b->pair.first ? -1 : 1;
    return (a->pair.second > b->pair.second) - (a->pair.second < b->pair.second);
}
static void alert_report(const Traffic *t, int state, FILE *out) {
    Alerts alerts = {0};
    for (int first = 0; first < t->input.plan_count; ++first)
        for (int second = first + 1; second < t->input.plan_count; ++second) {
            bool previous = false;
            for (size_t j = 0; j < t->samples.count; ++j) {
                Integer time = t->samples.items[j];
                const Segment *a = active_segment(&t->trajectories[state][first], (double)time),
                              *b = active_segment(&t->trajectories[state][second], (double)time);
                if (!a || !b)
                    continue;
                Point pa = position(a, (double)time), pb = position(b, (double)time), relative,
                      velocity;
                for (int k = 0; k < 3; ++k) {
                    relative.v[k] = pa.v[k] - pb.v[k];
                    velocity.v[k] = a->velocity.v[k] - b->velocity.v[k];
                }
                Loss loss;
                if (!loss_interval(relative, velocity, 0, (double)t->input.params.alert,
                                   (double)t->input.params.horizontal,
                                   (double)t->input.params.vertical, &loss))
                    continue;
                if (previous && time - alerts.items[alerts.count - 1].last == 60) {
                    Alert *v = &alerts.items[alerts.count - 1];
                    v->last = time;
                    ++v->samples;
                    v->distance = fmin(v->distance, loss.distance);
                } else {
                    Alert v = {{first, second},         time,          time,  1,
                               (double)time + loss.low, loss.distance, false, 0};
                    Alerts_append(&alerts, v);
                    previous = true;
                }
            }
        }
    if (alerts.count > 1)
        qsort(alerts.items, alerts.count, sizeof *alerts.items, alert_compare);
    bool *detected = calloc(t->conflicts[state].count, sizeof *detected);
    for (size_t i = 0; i < alerts.count; ++i) {
        Alert *a = &alerts.items[i];
        for (size_t j = 0; j < t->conflicts[state].count; ++j) {
            const Conflict *c = &t->conflicts[state].items[j];
            if (pair_equal(a->pair, c->pair) &&
                c->start < (double)(a->last + t->input.params.alert) && c->end > (double)a->first) {
                detected[j] = true;
                if (!a->matched) {
                    a->matched = true;
                    a->lead = c->start - (double)a->first;
                }
            }
        }
    }
    fprintf(out, "ALERTS plan=%s horizon=%lld count=%zu\n", state ? "final" : "initial",
            (long long)t->input.params.alert, alerts.count);
    double lead_sum = 0;
    size_t true_count = 0, missed = 0;
    for (size_t i = 0; i < alerts.count; ++i) {
        const Alert *a = &alerts.items[i];
        fprintf(
            out,
            "ALERT %zu %s first=%lld last=%lld samples=%lld predicted=%s min_dist=%s status=%s lead=%s\n",
            i + 1, pair_name(t, a->pair), (long long)a->first, (long long)a->last,
            (long long)a->samples, decimal(a->predicted, 3), decimal(a->distance, 3),
            a->matched ? "true" : "false", a->matched ? decimal(a->lead, 3) : "-");
        if (a->matched) {
            lead_sum += a->lead;
            ++true_count;
        }
    }
    for (size_t j = 0; j < t->conflicts[state].count; ++j)
        if (!detected[j]) {
            const Conflict *c = &t->conflicts[state].items[j];
            ++missed;
            fprintf(out, "MISSED %s start=%s end=%s\n", pair_name(t, c->pair), decimal(c->start, 3),
                    decimal(c->end, 3));
        }
    fprintf(out, "SUMMARY alerts=%zu true=%zu false=%zu missed=%zu mean_lead=%s\n", alerts.count,
            true_count, alerts.count - true_count, missed,
            true_count ? decimal(lead_sum / (double)true_count, 3) : "-");
    free(detected);
    free(alerts.items);
}
typedef struct {
    int column, row;
    bool inside;
} Cell;
static Cell cell(const Traffic *t, Point point) {
    const Integer *r = t->input.params.radar;
    Integer column = (Integer)floor((10 * point.v[0] - (double)r[0]) * (double)r[4] /
                                    (double)(r[2] - r[0])),
            bottom = (Integer)floor((10 * point.v[1] - (double)r[1]) * (double)r[5] /
                                    (double)(r[3] - r[1]));
    if (column >= 0 && column < r[4] && bottom >= 0 && bottom < r[5])
        return (Cell){(int)column, (int)(r[5] - 1 - bottom), true};
    return (Cell){0, 0, false};
}
static void radar_snapshot(const Traffic *t, int state, Integer time, FILE *out) {
    int width = (int)t->input.params.radar[4], height = (int)t->input.params.radar[5],
        counts[6400] = {0}, first_flight[6400];
    char **grid = make_grid((size_t)width, (size_t)height, '.');
    bool present[100] = {false}, conflicted[100] = {false};
    Point positions[100];
    const Segment *segments[100];
    size_t aircraft = 0, active_count = 0;
    for (size_t i = 0; i < t->conflicts[state].count; ++i) {
        const Conflict *c = &t->conflicts[state].items[i];
        if (active(c, (double)time)) {
            ++active_count;
            conflicted[c->pair.first] = true;
            conflicted[c->pair.second] = true;
        }
    }
    for (int flight = 0; flight < t->input.plan_count; ++flight) {
        const Segment *s = active_segment(&t->trajectories[state][flight], (double)time);
        if (!s)
            continue;
        ++aircraft;
        present[flight] = true;
        segments[flight] = s;
        positions[flight] = position(s, (double)time);
        Cell p = cell(t, positions[flight]);
        if (p.inside) {
            int i = p.row * width + p.column;
            ++counts[i];
            first_flight[i] = flight;
        }
    }
    for (int row = 0; row < height; ++row)
        for (int col = 0; col < width; ++col) {
            int i = row * width + col;
            if (counts[i] > 1)
                grid[row][col] = (char)('0' + counts[i]);
            else if (counts[i] == 1) {
                int flight = first_flight[i];
                char ch = callsign(t, flight)[0];
                grid[row][col] = conflicted[flight] ? (char)(ch - 'A' + 'a') : ch;
            }
        }
    for (int flight = 0; flight < t->input.plan_count; ++flight)
        if (present[flight]) {
            double future = (double)(time + t->input.params.leader);
            const Segment *s = active_segment(&t->trajectories[state][flight], future);
            if (s) {
                Cell p = cell(t, position(s, future));
                if (p.inside && grid[p.row][p.column] == '.')
                    grid[p.row][p.column] = '*';
            }
        }
    fprintf(out, "RADAR plan=%s t=%lld aircraft=%zu conflicts=%zu\n", state ? "final" : "initial",
            (long long)time, aircraft, active_count);
    frame(out, grid, (size_t)width, (size_t)height);
    free_grid(grid, (size_t)height);
    for (int flight = 0; flight < t->input.plan_count; ++flight)
        if (present[flight]) {
            Point p = positions[flight];
            Cell location = cell(t, p);
            fprintf(out, "%s x=%s y=%s fl=%s track=%s phase=%s cell=", callsign(t, flight),
                    decimal(p.v[0], 3), decimal(p.v[1], 3), decimal(p.v[2] / 100, 2),
                    decimal(track(segments[flight]), 1), phase_name(segments[flight]->phase));
            if (location.inside)
                fprintf(out, "%d,%d\n", location.column, location.row);
            else
                fputs("outside\n", out);
        }
    for (size_t i = 0; i < t->conflicts[state].count; ++i) {
        const Conflict *c = &t->conflicts[state].items[i];
        if (active(c, (double)time)) {
            Point a = positions[c->pair.first], b = positions[c->pair.second];
            double dx = a.v[0] - b.v[0], dy = a.v[1] - b.v[1];
            fprintf(out, "CONFLICT %s dist=%s vert=%s\n", pair_name(t, c->pair),
                    decimal(sqrt(dx * dx + dy * dy), 3), decimal(fabs(a.v[2] - b.v[2]), 1));
        }
    }
}
static void density_report(const Traffic *t, int state, FILE *out) {
    int width = (int)t->input.params.radar[4], height = (int)t->input.params.radar[5];
    Integer *counts = calloc((size_t)width * height, sizeof *counts), maximum = 0;
    for (size_t i = 0; i < t->samples.count; ++i)
        for (int flight = 0; flight < t->input.plan_count; ++flight) {
            double time = (double)t->samples.items[i];
            const Segment *s = active_segment(&t->trajectories[state][flight], time);
            if (!s)
                continue;
            Cell p = cell(t, position(s, time));
            if (p.inside)
                ++counts[p.row * width + p.column];
        }
    char **grid = make_grid((size_t)width, (size_t)height, '.');
    for (int row = 0; row < height; ++row)
        for (int col = 0; col < width; ++col) {
            Integer count = counts[row * width + col];
            if (count > maximum)
                maximum = count;
            grid[row][col] = count == 0 ? '.' : count < 10 ? (char)('0' + count) : '#';
        }
    fprintf(out, "DENSITY plan=%s from=%lld to=%lld step=60 max=%lld\n",
            state ? "final" : "initial", (long long)t->input.params.sample_start,
            (long long)t->input.params.sample_end, (long long)maximum);
    frame(out, grid, (size_t)width, (size_t)height);
    free_grid(grid, (size_t)height);
    free(counts);
}
static void strips_report(const Traffic *t, FILE *out) {
    for (int flight = 0; flight < t->input.plan_count; ++flight) {
        const Plan *p = &t->plans[1][flight];
        const Trajectory *before = &t->trajectories[0][flight],
                         *after = &t->trajectories[1][flight];
        char *history = joined(&p->history);
        fprintf(out, "STRIP %s type=%s waypoints=%d length=%s manoeuvres=%s\n", p->callsign,
                t->input.types[p->type].name, p->waypoint_count, decimal(after->length, 3),
                p->history.count ? history : "-");
        free(history);
        for (int k = 0; k < p->waypoint_count; ++k) {
            const Waypoint *w = &p->waypoints[k];
            fprintf(out, "WPT %d at=%d:%d eta=%s->%s fl=%lld->%lld\n", k, w->x, w->y,
                    decimal(before->passing[k].time, 3), decimal(after->passing[k].time, 3),
                    (long long)before->passing[k].level, (long long)after->passing[k].level);
        }
        fputs("SECTORS ", out);
        bool separator = false;
        for (size_t i = 0; i < t->transits[1].count; ++i) {
            const Transit *r = &t->transits[1].items[i];
            if (r->flight == flight) {
                if (separator)
                    fputc(',', out);
                fprintf(out, "%s@%s", sector_name(t, r->sector), decimal(r->entry, 3));
                separator = true;
            }
        }
        if (!separator)
            fputc('-', out);
        fputc('\n', out);
    }
}
int main(void) {
    Traffic *t = calloc(1, sizeof *t);
    read_inputs(&t->input);
    for (int state = 0; state < 2; ++state)
        for (int flight = 0; flight < t->input.plan_count; ++flight) {
            t->plans[state][flight] = t->input.plans[flight];
            build_trajectory(&t->plans[state][flight], t->input.types,
                             &t->trajectories[state][flight]);
        }
    for (Integer time = t->input.params.sample_start; time < t->input.params.sample_end; time += 60)
        Integers_append(&t->samples, time);
    t->conflicts[0] = all_conflicts(t->trajectories[0], t->input.plan_count, &t->input.params);
    resolve(t);
    t->conflicts[1] = all_conflicts(t->trajectories[1], t->input.plan_count, &t->input.params);
    for (size_t i = 0; i < t->conflicts[1].count; ++i) {
        Pair p = t->conflicts[1].items[i].pair;
        t->final_pairs[p.first][p.second] = true;
    }
    for (int state = 0; state < 2; ++state) {
        classify(t, state);
        compute_transits(t, state);
        compute_occupancy(t, state);
    }
    compute_periods(t);
    mkdir("output", 0777);
    FILE *file = open_output("trajectories.csv");
    trajectory_report(t, file);
    fclose(file);
    file = open_output("conflicts.txt");
    conflict_report(t, 0, file);
    conflict_report(t, 1, file);
    fclose(file);
    file = open_output("resolutions.txt");
    resolution_report(t, file);
    fclose(file);
    file = open_output("sector_transits.csv");
    transit_report(t, file);
    fclose(file);
    file = open_output("sector_load.csv");
    sector_load_report(t, file);
    fclose(file);
    file = open_output("sector_report.txt");
    sector_report(t, file);
    fclose(file);
    file = open_output("alerts.txt");
    alert_report(t, 0, file);
    alert_report(t, 1, file);
    fclose(file);
    file = open_output("radar.txt");
    for (size_t i = 0; i < t->input.params.snapshots.count; ++i) {
        radar_snapshot(t, 0, t->input.params.snapshots.items[i], file);
        radar_snapshot(t, 1, t->input.params.snapshots.items[i], file);
    }
    density_report(t, 0, file);
    density_report(t, 1, file);
    fclose(file);
    file = open_output("strips.txt");
    strips_report(t, file);
    fclose(file);
    for (int state = 0; state < 2; ++state) {
        free_conflicts(&t->conflicts[state]);
        free(t->transits[state].items);
        for (int s = 0; s < t->input.sector_count; ++s)
            free(t->occupancy[state][s]);
    }
    for (int flight = 0; flight < t->input.plan_count; ++flight)
        free(t->plans[1][flight].history.items);
    for (size_t i = 0; i < t->rounds.count; ++i)
        free(t->rounds.items[i].trials.items);
    free(t->rounds.items);
    free(t->unresolved_conflicts.items);
    free(t->periods.items);
    free(t->samples.items);
    free(t->input.params.snapshots.items);
    free(t);
    return 0;
}
