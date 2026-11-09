#include "seismic.h"
typedef struct {
    int station;
    double dx, dy, dz, shift;
} Jack;
typedef struct {
    Ids used;
    Run first, final;
    Observations observations;
    Ellipse error;
    double start_rms, gap, dmin, dh, dz;
    char quality;
    Jack jack[12];
    int max_jack, cluster;
    PickMagnitude magnitudes[12];
    bool has_ml;
    double ml, mlc, md;
} Event;
typedef struct {
    I column, row;
    bool valid;
} Position;
typedef struct {
    char **rows;
    I width, height;
} Grid;
static char *decimal(double value, int digits) {
    I amount = scaled(value, digits), absolute = amount < 0 ? -amount : amount, factor = 1;
    for (int i = 0; i < digits; ++i)
        factor *= 10;
    return digits ? format("%s%" PRId64 ".%0*" PRId64, amount < 0 ? "-" : "", absolute / factor, digits,
                           absolute % factor)
                  : format("%" PRId64, amount);
}
static char *time_text(I value) {
    return format("%" PRId64 ".%02" PRId64, value / 100, value % 100);
}
static const char *state_text(State state) {
    static const char *names[] = {"used", "dropped", "added", "rejected", "unassociated"};
    return names[state];
}
static Observations observations(Ids ids, const Pick *picks, const Station *stations, bool corrected) {
    Observations out = {0};
    for (int i = 0; i < ids.count; ++i) {
        Pick pick = picks[ids.data[i]];
        out.data[out.count++] = (Observation){
            pick.station, pick.sample / 100.0 - (corrected ? stations[pick.station].correction : 0)};
    }
    return out;
}
static void solution_line(FILE *out, const char *label, Solution q, double error) {
    fprintf(out, "%s x=%s y=%s z=%s t0=%s rms=%s\n", label, decimal(q.data[0], 1), decimal(q.data[1], 1),
            decimal(q.data[2], 1), decimal(q.data[3], 3), decimal(error, 4));
}
static void trace_lines(FILE *out, Run run) {
    for (int i = 0; i < 8; ++i)
        solution_line(out, format("ITER %d", i + 1), run.trace[i].solution, run.trace[i].rms);
}
static void pass_lines(FILE *out, int pass, Ids ids, Run run, const Pick *picks, const Station *stations,
                       const Params *p) {
    fprintf(out, "PASS %d stations=", pass);
    for (int i = 0; i < ids.count; ++i)
        fprintf(out, "%s%s", i ? "," : "", stations[picks[ids.data[i]].station].code);
    fputc('\n', out);
    solution_line(out, "GRID", run.grid, run.grid_rms);
    fputs("PROFILE", out);
    for (int i = 0; i < run.depths; ++i)
        fprintf(out, " %s", decimal(run.profile[i], 4));
    fputc('\n', out);
    trace_lines(out, run);
    for (int i = 0; i < ids.count; ++i) {
        Pick pick = picks[ids.data[i]];
        const Station *s = &stations[pick.station];
        double d = distance(run.solution, s);
        fprintf(out, "RES %s dist=%s tt=%s obs=%s res=%s\n", s->code, decimal(d, 1),
                decimal(d / p->velocity, 4), time_text(pick.sample), decimal(run.residual[i], 4));
    }
}
static char *position_text(Position p) {
    return p.valid ? format("%" PRId64 ",%" PRId64, p.column, p.row) : "outside";
}
static Position map_position(I x, I y, const Params *p) {
    if (x < 10 * p->area[0] || x >= 10 * p->area[1] || y < 10 * p->area[2] || y >= 10 * p->area[3])
        return (Position){0};
    return (Position){floor_div((x - 10 * p->area[0]) * p->map_size[0], 10 * (p->area[1] - p->area[0])),
                      p->map_size[1] - 1 -
                          floor_div((y - 10 * p->area[2]) * p->map_size[1], 10 * (p->area[3] - p->area[2])),
                      true};
}
static Position section_position(I coordinate, I z, I low, I high, const Params *p) {
    if (coordinate < 10 * low || coordinate >= 10 * high || z >= 10 * p->section[0])
        return (Position){0};
    return (Position){floor_div((coordinate - 10 * low) * p->map_size[0], 10 * (high - low)),
                      floor_div(z * p->section[1], 10 * p->section[0]), true};
}
static char symbol(const Event *event) {
    if (!event->has_ml)
        return '?';
    I h = scaled(event->ml, 2);
    return h < 100 ? '.' : h < 200 ? 'o' : h < 300 ? 'O' : '@';
}
static Grid grid(I width, I height) {
    Grid out = {.rows = allocate(height, sizeof(char *)), .width = width, .height = height};
    for (I i = 0; i < height; ++i) {
        out.rows[i] = allocate(width + 1, 1);
        memset(out.rows[i], ' ', width);
    }
    return out;
}
static void place(Grid grid, Position p, char value) {
    if (!p.valid)
        return;
    const char *priority = " ?.oO@^";
    char *current = &grid.rows[p.row][p.column];
    if (strchr(priority, value) > strchr(priority, *current))
        *current = value;
}
static void draw(FILE *out, Grid grid) {
    char *frame = allocate(grid.width + 1, 1);
    memset(frame, '-', grid.width);
    fprintf(out, "+%s+\n", frame);
    for (I i = 0; i < grid.height; ++i)
        fprintf(out, "|%s|\n", grid.rows[i]);
    fprintf(out, "+%s+\n", frame);
}
static int pick_compare(const void *left, const void *right) {
    const Pick *a = left;
    const Pick *b = right;
    if (a->sample != b->sample)
        return (a->sample > b->sample) - (a->sample < b->sample);
    return (a->station > b->station) - (a->station < b->station);
}
static void station_sort(Ids *ids, const Pick *picks) {
    for (int i = 1; i < ids->count; ++i) {
        int value = ids->data[i], j = i;
        while (j > 0 && picks[ids->data[j - 1]].station > picks[value].station) {
            ids->data[j] = ids->data[j - 1];
            --j;
        }
        ids->data[j] = value;
    }
}
static int integer_compare(const void *left, const void *right) {
    int a = *(const int *)left, b = *(const int *)right;
    return (a > b) - (a < b);
}
static bool fits(const Event *event, const double *bounds) {
    return event->gap <= bounds[0] && event->final.rms <= bounds[1] && event->error.smaj <= bounds[2];
}
int main(void) {
    mkdir("output", 0777);
    Params p = {0};
    Station stations[12] = {0};
    int station_count = 0;
    load(stations, &station_count, &p);
    Picks all = {0};
    for (int s = 0; s < station_count; ++s)
        detect_station(&stations[s], s, &p, &all);
    if (all.count > 1)
        qsort(all.data, all.count, sizeof(Pick), pick_compare);
    Pick *picks = all.data;
    int candidate_count = 0;
    Candidate *candidates = associate(&all, &p, &candidate_count);
    Event *events = allocate(candidate_count, sizeof(Event));
    int event_count = 0, rejected = 0;
    FILE *locations = fopen("output/locations.txt", "w");
    for (int ci = 0; ci < candidate_count; ++ci) {
        Candidate *candidate = &candidates[ci];
        station_sort(&candidate->picks, picks);
        Run first = locate(observations(candidate->picks, picks, stations, false), stations, &p);
        candidate->first_run = first;
        for (int i = 0; i < candidate->picks.count; ++i) {
            if (fabs(first.residual[i]) > p.limit) {
                candidate->drop_residual[candidate->dropped.count] = first.residual[i];
                candidate->dropped.data[candidate->dropped.count++] = candidate->picks.data[i];
            } else
                candidate->retained.data[candidate->retained.count++] = candidate->picks.data[i];
        }
        fprintf(locations, "CANDIDATE %d picks=%d first=%s\n", ci + 1, candidate->picks.count,
                time_text(picks[candidate->first].sample));
        pass_lines(locations, 1, candidate->picks, first, picks, stations, &p);
        for (int i = 0; i < candidate->dropped.count; ++i)
            fprintf(locations, "DROP %s res=%s\n", stations[picks[candidate->dropped.data[i]].station].code,
                    decimal(candidate->drop_residual[i], 4));
        if (candidate->dropped.count && candidate->retained.count < p.minimum) {
            candidate->rejected = true;
            ++rejected;
            for (int i = 0; i < candidate->picks.count; ++i)
                picks[candidate->picks.data[i]].state = REJECTED;
            fprintf(locations, "RESULT REJECTED stations=%d\n", candidate->retained.count);
            continue;
        }
        Run adopted = first;
        if (candidate->dropped.count) {
            adopted = locate(observations(candidate->retained, picks, stations, false), stations, &p);
            candidate->second_run = adopted;
            pass_lines(locations, 2, candidate->retained, adopted, picks, stations, &p);
        }
        candidate->event = event_count + 1;
        for (int i = 0; i < candidate->retained.count; ++i) {
            Pick *pick = &picks[candidate->retained.data[i]];
            pick->state = USED;
            pick->event = candidate->event;
            pick->first_residual = adopted.residual[i];
            Station *s = &stations[pick->station];
            ++s->used;
            s->correction += pick->first_residual;
            s->first_square += pick->first_residual * pick->first_residual;
        }
        for (int i = 0; i < candidate->dropped.count; ++i) {
            Pick *pick = &picks[candidate->dropped.data[i]];
            pick->state = DROPPED;
            pick->event = candidate->event;
        }
        events[event_count++] = (Event){.used = candidate->retained, .first = adopted};
        fprintf(locations, "RESULT EVENT %d\n", candidate->event);
    }
    fputs("CORRECTIONS\n", locations);
    for (int i = 0; i < station_count; ++i) {
        Station *s = &stations[i];
        if (s->used)
            s->correction /= s->used;
        fprintf(locations, "%s n=%d correction=%s\n", s->code, s->used, decimal(s->correction, 4));
    }
    for (int ei = 0; ei < event_count; ++ei) {
        Event *event = &events[ei];
        event->observations = observations(event->used, picks, stations, true);
        event->start_rms = rms(event->first.solution, event->observations, stations, p.velocity);
        event->final = geiger(event->first.solution, event->observations, stations, p.velocity);
        Solution q = event->final.solution;
        event->error = ellipse(q, event->observations, stations, p.velocity);
        double angles[12];
        event->dmin = INFINITY;
        for (int i = 0; i < event->used.count; ++i) {
            Pick *pick = &picks[event->used.data[i]];
            Station *s = &stations[pick->station];
            pick->residual = event->final.residual[i];
            s->final_square += pick->residual * pick->residual;
            double angle = atan2(s->x - q.data[0], s->y - q.data[1]) * 180 / 3.141592653589793;
            if (angle < 0)
                angle += 360;
            angles[i] = angle;
            double dx = s->x - q.data[0], dy = s->y - q.data[1], d = sqrt(dx * dx + dy * dy);
            if (d < event->dmin)
                event->dmin = d;
        }
        for (int i = 1; i < event->used.count; ++i) {
            double value = angles[i];
            int j = i;
            while (j > 0 && angles[j - 1] > value) {
                angles[j] = angles[j - 1];
                --j;
            }
            angles[j] = value;
        }
        event->gap = angles[0] + 360 - angles[event->used.count - 1];
        for (int i = 1; i < event->used.count; ++i)
            if (angles[i] - angles[i - 1] > event->gap)
                event->gap = angles[i] - angles[i - 1];
        event->quality = fits(event, p.qa) ? 'A' : fits(event, p.qb) ? 'B' : 'C';
        double dx = q.data[0] - event->first.solution.data[0], dy = q.data[1] - event->first.solution.data[1];
        event->dh = sqrt(dx * dx + dy * dy);
        event->dz = q.data[2] - event->first.solution.data[2];
        for (int omitted = 0; omitted < event->used.count; ++omitted) {
            Observations remaining = {0};
            for (int j = 0; j < event->used.count; ++j)
                if (j != omitted)
                    remaining.data[remaining.count++] = event->observations.data[j];
            Solution alternative = geiger(q, remaining, stations, p.velocity).solution;
            double x = alternative.data[0] - q.data[0], y = alternative.data[1] - q.data[1],
                   z = alternative.data[2] - q.data[2];
            event->jack[omitted] =
                (Jack){picks[event->used.data[omitted]].station, x, y, z, sqrt(x * x + y * y)};
            if (event->jack[omitted].shift > event->jack[event->max_jack].shift)
                event->max_jack = omitted;
        }
        fprintf(locations, "EVENT %d\n", ei + 1);
        solution_line(locations, "START", event->first.solution, event->start_rms);
        trace_lines(locations, event->final);
        for (int i = 0; i < event->used.count; ++i) {
            Pick pick = picks[event->used.data[i]];
            Station *s = &stations[pick.station];
            double d = distance(q, s);
            fprintf(locations, "RES %s dist=%s tt=%s obs=%s corr=%s res=%s\n", s->code, decimal(d, 1),
                    decimal(d / p.velocity, 4), time_text(pick.sample), decimal(s->correction, 4),
                    decimal(pick.residual, 4));
        }
        Ellipse e = event->error;
        fprintf(locations, "ELLIPSE smaj=%s smin=%s az=%s erz=%s ert=%s\n", decimal(e.smaj, 1),
                decimal(e.smin, 1), decimal(e.az, 1), decimal(e.erz, 1), decimal(e.ert, 4));
        fprintf(locations, "SHIFT dh=%s dz=%s\n", decimal(event->dh, 1), decimal(event->dz, 1));
        fprintf(locations, "GAP %s DMIN %s QUALITY %c\n", decimal(event->gap, 1), decimal(event->dmin, 1),
                event->quality);
        for (int i = 0; i < event->used.count; ++i) {
            Jack jack = event->jack[i];
            fprintf(locations, "JACK %s dx=%s dy=%s dz=%s shift=%s\n", stations[jack.station].code,
                    decimal(jack.dx, 1), decimal(jack.dy, 1), decimal(jack.dz, 1), decimal(jack.shift, 1));
        }
        Jack maximum = event->jack[event->max_jack];
        fprintf(locations, "JACKKNIFE max=%s station=%s\n", decimal(maximum.shift, 1),
                stations[maximum.station].code);
    }
    for (int ei = 0; ei < event_count; ++ei) {
        Event *event = &events[ei];
        double local[12], duration[12];
        int count = 0;
        for (int i = 0; i < event->used.count; ++i) {
            Pick pick = picks[event->used.data[i]];
            PickMagnitude value =
                magnitude(pick, distance(event->final.solution, &stations[pick.station]) / 1000, &p);
            event->magnitudes[i] = value;
            duration[i] = value.md;
            if (value.has_ml)
                local[count++] = value.ml;
        }
        event->has_ml = count > 0;
        if (count)
            event->ml = median(local, count);
        event->md = median(duration, event->used.count);
        for (int i = 0; i < event->used.count; ++i)
            if (event->magnitudes[i].has_ml) {
                Station *s = &stations[picks[event->used.data[i]].station];
                s->mag_correction += event->magnitudes[i].ml - event->ml;
                ++s->mag_count;
            }
    }
    for (int i = 0; i < station_count; ++i)
        if (stations[i].mag_count)
            stations[i].mag_correction /= stations[i].mag_count;
    for (int ei = 0; ei < event_count; ++ei) {
        Event *event = &events[ei];
        double corrected[12];
        int count = 0;
        for (int i = 0; i < event->used.count; ++i)
            if (event->magnitudes[i].has_ml)
                corrected[count++] =
                    event->magnitudes[i].ml - stations[picks[event->used.data[i]].station].mag_correction;
        if (count)
            event->mlc = median(corrected, count);
    }
    int point_count = 0;
    double sd = 0, st = 0, sdd = 0, sdt = 0;
    for (int ei = 0; ei < event_count; ++ei) {
        Event *event = &events[ei];
        for (int i = 0; i < event->used.count; ++i) {
            Pick pick = picks[event->used.data[i]];
            double d = distance(event->final.solution, &stations[pick.station]) / 1000,
                   t = pick.sample / 100.0 - event->final.solution.data[3];
            ++point_count;
            sd += d;
            st += t;
            sdd += d * d;
            sdt += d * t;
        }
    }
    double n = point_count, slope = (n * sdt - sd * st) / (n * sdd - sd * sd),
           intercept = (st - slope * sd) / n, ss = 0;
    for (int ei = 0; ei < event_count; ++ei) {
        Event *event = &events[ei];
        for (int i = 0; i < event->used.count; ++i) {
            Pick pick = picks[event->used.data[i]];
            double d = distance(event->final.solution, &stations[pick.station]) / 1000,
                   t = pick.sample / 100.0 - event->final.solution.data[3], r = t - intercept - slope * d;
            ss += r * r;
        }
    }
    fprintf(locations, "FIT n=%d velocity=%s intercept=%s rms=%s\n", point_count, decimal(1000 / slope, 1),
            decimal(intercept, 4), decimal(sqrt(ss / n), 4));
    int cluster_count = 0;
    int *members = allocate(event_count, sizeof(int));
    for (int first = 0; first < event_count; ++first) {
        if (events[first].cluster)
            continue;
        ++cluster_count;
        int member_count = 1;
        members[0] = first;
        events[first].cluster = cluster_count;
        for (int head = 0; head < member_count; ++head) {
            Solution a = events[members[head]].final.solution;
            for (int j = 0; j < event_count; ++j) {
                if (events[j].cluster)
                    continue;
                Solution b = events[j].final.solution;
                double d2 = 0;
                for (int axis = 0; axis < 3; ++axis)
                    d2 += (a.data[axis] - b.data[axis]) * (a.data[axis] - b.data[axis]);
                if (fabs(a.data[3] - b.data[3]) <= p.cluster[1] && sqrt(d2) <= p.cluster[0]) {
                    events[j].cluster = cluster_count;
                    members[member_count++] = j;
                }
            }
        }
        qsort(members, member_count, sizeof(int), integer_compare);
        if (member_count > 1) {
            Solution center = {0};
            double low = events[members[0]].final.solution.data[3], high = low;
            fprintf(locations, "CLUSTER %d events=", cluster_count);
            for (int i = 0; i < member_count; ++i) {
                fprintf(locations, "%s%d", i ? "," : "", members[i] + 1);
                Solution q = events[members[i]].final.solution;
                for (int axis = 0; axis < 3; ++axis)
                    center.data[axis] += q.data[axis];
                if (q.data[3] < low)
                    low = q.data[3];
                if (q.data[3] > high)
                    high = q.data[3];
            }
            fprintf(locations, " x=%s y=%s z=%s span=%s\n", decimal(center.data[0] / member_count, 1),
                    decimal(center.data[1] / member_count, 1), decimal(center.data[2] / member_count, 1),
                    decimal(high - low, 3));
        }
    }
    bool (*station_sets)[12] = allocate(event_count, sizeof(*station_sets));
    for (int ei = 0; ei < event_count; ++ei)
        for (int i = 0; i < events[ei].used.count; ++i)
            station_sets[ei][picks[events[ei].used.data[i]].station] = true;
    fputs("ADDED\n", locations);
    for (int i = 0; i < all.count; ++i) {
        Pick *pick = &picks[i];
        if (pick->state != UNASSOCIATED)
            continue;
        int selected = -1;
        double best = INFINITY, residual = 0;
        for (int ei = 0; ei < event_count; ++ei) {
            if (station_sets[ei][pick->station])
                continue;
            Solution q = events[ei].final.solution;
            double rho = pick->sample / 100.0 - q.data[3] -
                         distance(q, &stations[pick->station]) / p.velocity -
                         stations[pick->station].correction;
            if (fabs(rho) <= p.limit && fabs(rho) < best) {
                best = fabs(rho);
                selected = ei;
                residual = rho;
            }
        }
        if (selected >= 0) {
            pick->state = ADDED;
            pick->event = selected + 1;
            pick->residual = residual;
            station_sets[selected][pick->station] = true;
            fprintf(locations, "%s sample=%" PRId64 " event=%d res=%s\n", stations[pick->station].code,
                    pick->sample, pick->event, decimal(pick->residual, 4));
        }
    }
    int unassociated = 0;
    for (int i = 0; i < all.count; ++i)
        unassociated += picks[i].state == UNASSOCIATED;
    double *depths = allocate(event_count, sizeof(double));
    int quality[3] = {0};
    double total_rms = 0, min_depth = INFINITY, max_depth = -INFINITY;
    for (int ei = 0; ei < event_count; ++ei) {
        Event *event = &events[ei];
        depths[ei] = event->final.solution.data[2];
        if (depths[ei] < min_depth)
            min_depth = depths[ei];
        if (depths[ei] > max_depth)
            max_depth = depths[ei];
        ++quality[event->quality - 'A'];
        total_rms += event->final.rms;
    }
    fprintf(locations, "SUMMARY picks=%d candidates=%d events=%d rejected=%d unassociated=%d\n", all.count,
            candidate_count, event_count, rejected, unassociated);
    fprintf(locations, "DEPTH min=%s median=%s max=%s\n", decimal(min_depth, 1),
            decimal(median(depths, event_count), 1), decimal(max_depth, 1));
    fprintf(locations, "QUALITY A=%d B=%d C=%d mean_rms=%s\n", quality[0], quality[1], quality[2],
            decimal(total_rms / event_count, 4));
    fclose(locations);
    FILE *pick_file = fopen("output/picks.csv", "w");
    FILE *catalog = fopen("output/catalog.csv", "w");
    FILE *mag = fopen("output/magnitudes.txt", "w");
    FILE *station_file = fopen("output/stations.txt", "w");
    FILE *map_file = fopen("output/map.txt", "w");
    fputs("station,sample,time_s,duration,snr,amplitude,clipped,event,status,residual\n", pick_file);
    for (int i = 0; i < all.count; ++i) {
        Pick pick = picks[i];
        fprintf(pick_file, "%s,%" PRId64 ",%s,%" PRId64 ",%s,%" PRId64 ",%s,%d,%s,%s\n",
                stations[pick.station].code, pick.sample, time_text(pick.sample), pick.duration,
                decimal(pick.ratio, 2), pick.amplitude, pick.clipped ? "yes" : "no", pick.event,
                state_text(pick.state),
                (pick.state == USED || pick.state == ADDED) ? decimal(pick.residual, 4) : "-");
    }
    fputs("event,origin_time,x,y,depth,rms,stations,gap,dmin,smaj,smin,azimuth,erz,ml,md,quality,cluster\n",
          catalog);
    double *local = allocate(event_count, sizeof(double));
    double *duration = allocate(event_count, sizeof(double));
    int magnitude_count = 0;
    for (int ei = 0; ei < event_count; ++ei) {
        Event *event = &events[ei];
        Solution q = event->final.solution;
        Ellipse e = event->error;
        fprintf(catalog, "%d,%s,%s,%s,%s,%s,%d,%s,%s,%s,%s,%s,%s,%s,%s,%c,%d\n", ei + 1,
                decimal(q.data[3], 3), decimal(q.data[0], 1), decimal(q.data[1], 1), decimal(q.data[2], 1),
                decimal(event->final.rms, 4), event->used.count, decimal(event->gap, 1),
                decimal(event->dmin, 1), decimal(e.smaj, 1), decimal(e.smin, 1), decimal(e.az, 1),
                decimal(e.erz, 1), event->has_ml ? decimal(event->ml, 2) : "-", decimal(event->md, 2),
                event->quality, event->cluster);
        int available = 0;
        for (int i = 0; i < event->used.count; ++i)
            available += event->magnitudes[i].has_ml;
        fprintf(mag, "EVENT %d ML=%s n=%d MD=%s\n", ei + 1, event->has_ml ? decimal(event->ml, 2) : "-",
                available, decimal(event->md, 2));
        for (int i = 0; i < event->used.count; ++i) {
            PickMagnitude value = event->magnitudes[i];
            Pick pick = picks[event->used.data[i]];
            fprintf(mag, "%s r=%s amp=%" PRId64, stations[pick.station].code, decimal(value.radius, 3),
                    pick.amplitude);
            if (value.has_ml)
                fprintf(mag, " ml=%s res=%s", decimal(value.ml, 2), decimal(value.ml - event->ml, 2));
            else
                fputs(" clipped", mag);
            fprintf(mag, " dur=%" PRId64 " md=%s\n", pick.duration, decimal(value.md, 2));
        }
        if (event->has_ml) {
            local[magnitude_count] = event->ml;
            duration[magnitude_count++] = event->md;
        }
    }
    fputs("CORRECTED\n", mag);
    for (int ei = 0; ei < event_count; ++ei)
        fprintf(mag, "EVENT %d MLC=%s\n", ei + 1, events[ei].has_ml ? decimal(events[ei].mlc, 2) : "-");
    Frequency f = frequency(local, duration, magnitude_count);
    fputs("FMD\n", mag);
    for (I t = f.counts[0].value; t <= f.counts[f.count - 1].value; ++t) {
        int count = 0, cumulative = 0;
        for (int i = 0; i < f.count; ++i) {
            if (f.counts[i].value == t)
                count = f.counts[i].count;
            if (f.counts[i].value >= t)
                cumulative += f.counts[i].count;
        }
        fprintf(mag, "M=%s N=%d CUM=%d\n", class_text(t), count, cumulative);
    }
    fprintf(mag, "MC %s\nBVALUE %s SIGMA %s N %d\nAVALUE %s\n", class_text(f.completeness), decimal(f.b, 3),
            decimal(f.sigma, 3), f.nb, decimal(f.a, 3));
    fprintf(mag, "MLMD n=%d slope=%s intercept=%s r=%s mean_diff=%s\n", f.n, decimal(f.slope, 3),
            decimal(f.intercept, 3), decimal(f.r, 3), decimal(f.mean_diff, 3));
    I *t = p.timeline;
    Grid timeline = grid(t[1], t[4]);
    for (int ei = 0; ei < event_count; ++ei) {
        Event *event = &events[ei];
        if (!event->has_ml)
            continue;
        I time = scaled(event->final.solution.data[3], 3), h = scaled(event->ml, 2);
        if (time < 0 || time >= 1000 * t[0] || h < 100 * t[2])
            continue;
        I col = floor_div(time * t[1], 1000 * t[0]),
          level = floor_div((h - 100 * t[2]) * t[4], 100 * (t[3] - t[2]));
        if (level > t[4] - 1)
            level = t[4] - 1;
        for (I k = 0; k <= level; ++k) {
            char *cell = &timeline.rows[t[4] - 1 - k][col];
            if (k == level)
                *cell = 'o';
            else if (*cell == ' ')
                *cell = '|';
        }
    }
    fprintf(mag, "TIMELINE t=0..%" PRId64 " ML=%" PRId64 "..%" PRId64 "\n", t[0], t[2], t[3]);
    draw(mag, timeline);
    for (int si = 0; si < station_count; ++si) {
        Station *s = &stations[si];
        int states[5] = {0}, count = 0;
        for (int i = 0; i < all.count; ++i)
            if (picks[i].station == si) {
                ++states[picks[i].state];
                ++count;
            }
        fprintf(station_file, "STATION %s x=%" PRId64 " y=%" PRId64 " elevation=%" PRId64 "\n", s->code, s->x,
                s->y, s->elevation);
        fprintf(station_file,
                "SAMPLES start=%" PRId64 " count=%d mean=%" PRId64 " noise=%s peak=%" PRId64
                " clipped=%" PRId64 "\n",
                s->start, s->count, s->mean, decimal(s->noise, 1), s->peak, s->clipped);
        fprintf(station_file, "TRIGGERS total=%d short=%d picks=%d\n", s->triggers, s->short_triggers, count);
        fprintf(station_file, "PICKS used=%d dropped=%d added=%d rejected=%d unassociated=%d\n", states[0],
                states[1], states[2], states[3], states[4]);
        fprintf(station_file, "RESIDUALS n=%d rms=%s correction=%s after=%s\n", s->used,
                s->used ? decimal(sqrt(s->first_square / s->used), 4) : "-", decimal(s->correction, 4),
                s->used ? decimal(sqrt(s->final_square / s->used), 4) : "-");
        fprintf(station_file, "MAGNITUDES n=%d correction=%s\n", s->mag_count, decimal(s->mag_correction, 2));
    }
    Grid map = grid(p.map_size[0], p.map_size[1]), ew = grid(p.map_size[0], p.section[1]),
         ns = grid(p.map_size[0], p.section[1]);
    Position(*positions)[3] = allocate(event_count, sizeof(*positions));
    for (int ei = 0; ei < event_count; ++ei) {
        Event *event = &events[ei];
        I x = scaled(event->final.solution.data[0], 1), y = scaled(event->final.solution.data[1], 1),
          z = scaled(event->final.solution.data[2], 1);
        positions[ei][0] = map_position(x, y, &p);
        positions[ei][1] = section_position(x, z, p.area[0], p.area[1], &p);
        positions[ei][2] = section_position(y, z, p.area[2], p.area[3], &p);
        place(map, positions[ei][0], symbol(event));
        place(ew, positions[ei][1], symbol(event));
        place(ns, positions[ei][2], symbol(event));
    }
    Position station_positions[12];
    for (int si = 0; si < station_count; ++si) {
        station_positions[si] = map_position(10 * stations[si].x, 10 * stations[si].y, &p);
        place(map, station_positions[si], '^');
    }
    fprintf(map_file, "MAP x=%" PRId64 "..%" PRId64 " y=%" PRId64 "..%" PRId64 "\n", p.area[0], p.area[1],
            p.area[2], p.area[3]);
    draw(map_file, map);
    fprintf(map_file, "SECTION EW x=%" PRId64 "..%" PRId64 " z=0..%" PRId64 "\n", p.area[0], p.area[1],
            p.section[0]);
    draw(map_file, ew);
    fprintf(map_file, "SECTION NS y=%" PRId64 "..%" PRId64 " z=0..%" PRId64 "\n", p.area[2], p.area[3],
            p.section[0]);
    draw(map_file, ns);
    fputs("LEGEND ^ station . ML<1 o ML<2 O ML<3 @ ML>=3 ? no ML\n", map_file);
    for (int si = 0; si < station_count; ++si)
        fprintf(map_file, "STATION %s map=%s\n", stations[si].code, position_text(station_positions[si]));
    for (int ei = 0; ei < event_count; ++ei)
        fprintf(map_file, "EVENT %d %c map=%s ew=%s ns=%s\n", ei + 1, symbol(&events[ei]),
                position_text(positions[ei][0]), position_text(positions[ei][1]),
                position_text(positions[ei][2]));
    fclose(pick_file);
    fclose(catalog);
    fclose(mag);
    fclose(station_file);
    fclose(map_file);
    release_all();
    return 0;
}
