#include "tracker.h"
typedef struct Allocation {
    void *pointer;
    struct Allocation *next;
} Allocation;
static Allocation *allocations;
static void release(void) {
    while (allocations) {
        Allocation *next = allocations->next;
        free(allocations->pointer);
        free(allocations);
        allocations = next;
    }
}
void *allocate(size_t count, size_t size) {
    void *pointer = calloc(count ? count : 1, size);
    Allocation *item = malloc(sizeof(*item));
    if (!pointer || !item)
        exit(EXIT_FAILURE);
    if (!allocations)
        atexit(release);
    item->pointer = pointer;
    item->next = allocations;
    allocations = item;
    return pointer;
}
static char *formatted(const char *pattern, va_list args) {
    va_list copy;
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *out = allocate((size_t)length + 1, 1);
    vsnprintf(out, (size_t)length + 1, pattern, args);
    return out;
}
char *format(const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    char *out = formatted(pattern, args);
    va_end(args);
    return out;
}
char *joined(const char *first, const char *second) { return format("%s%s", first, second); }
void line(Lines *lines, const char *pattern, ...) {
    if (lines->count == lines->capacity) {
        int next = lines->capacity ? 2 * lines->capacity : 16;
        char **data = allocate((size_t)next, sizeof(char *));
        if (lines->count)
            memcpy(data, lines->data, (size_t)lines->count * sizeof(char *));
        lines->data = data;
        lines->capacity = next;
    }
    va_list args;
    va_start(args, pattern);
    lines->data[lines->count++] = formatted(pattern, args);
    va_end(args);
}
Lines read_lines(const char *path) {
    FILE *input = fopen(path, "rb");
    fseek(input, 0, SEEK_END);
    long size = ftell(input);
    rewind(input);
    char *text = allocate((size_t)size + 1, 1);
    fread(text, 1, (size_t)size, input);
    fclose(input);
    Lines out = {0};
    char *start = text;
    for (long i = 0; i < size; ++i)
        if (text[i] == '\n') {
            text[i] = '\0';
            line(&out, "%s", start);
            start = text + i + 1;
        }
    return out;
}
typedef struct {
    int number, first, last;
    Position positions[101];
    bool exists[101];
} Target;
typedef struct {
    Params params;
    Position measurements[101][20];
    int measurement_count[101], scans, target_count;
    double times[101];
    Target targets[10];
} Input;
static Input *read_inputs(void) {
    Input *out = allocate(1, sizeof(Input));
    Lines measurements = read_lines("input/measurements.csv");
    for (int i = 1; i < measurements.count; ++i) {
        int scan;
        double time, x, y;
        sscanf(measurements.data[i], "%d,%lf,%lf,%lf", &scan, &time, &x, &y);
        out->scans = scan;
        out->times[scan] = time;
        out->measurements[scan][out->measurement_count[scan]++] = (Position){x, y};
    }
    Lines truth = read_lines("input/truth.csv");
    for (int i = 1; i < truth.count; ++i) {
        int number, scan;
        double x, y;
        sscanf(truth.data[i], "%d,%d,%lf,%lf", &number, &scan, &x, &y);
        if (!out->target_count || out->targets[out->target_count - 1].number != number) {
            Target *target = &out->targets[out->target_count++];
            target->number = number;
            target->first = scan;
        }
        Target *target = &out->targets[out->target_count - 1];
        target->last = scan;
        target->positions[scan] = (Position){x, y};
        target->exists[scan] = true;
    }
    Params *p = &out->params;
    Lines settings = read_lines("input/params.txt");
    for (int i = 0; i < settings.count; ++i) {
        char key[40];
        sscanf(settings.data[i], "%39s", key);
        const char *value = settings.data[i] + strlen(key) + 1;
        if (strcmp(key, "MODEL") == 0)
            p->ca = strcmp(value, "CA") == 0;
        else if (strcmp(key, "Q_CV") == 0)
            sscanf(value, "%lf", &p->q_cv);
        else if (strcmp(key, "Q_CA") == 0)
            sscanf(value, "%lf", &p->q_ca);
        else if (strcmp(key, "SIGMA") == 0)
            sscanf(value, "%lf", &p->sigma);
        else if (strcmp(key, "INIT_VELOCITY_VARIANCE") == 0)
            sscanf(value, "%lf", &p->velocity);
        else if (strcmp(key, "INIT_ACCELERATION_VARIANCE") == 0)
            sscanf(value, "%lf", &p->acceleration);
        else if (strcmp(key, "GATE") == 0)
            sscanf(value, "%lf", &p->gate);
        else if (strcmp(key, "CONFIRM") == 0)
            sscanf(value, "%d %d", &p->confirm, &p->window);
        else if (strcmp(key, "DELETE") == 0)
            sscanf(value, "%d", &p->deletion);
        else if (strcmp(key, "ABG") == 0)
            sscanf(value, "%lf %lf %lf", &p->abg[0], &p->abg[1], &p->abg[2]);
        else if (strcmp(key, "IMM_Q") == 0)
            sscanf(value, "%lf %lf", &p->imm_q[0], &p->imm_q[1]);
        else if (strcmp(key, "IMM_TRANSITION") == 0)
            sscanf(value, "%lf %lf %lf %lf", &p->transition[0][0], &p->transition[0][1],
                   &p->transition[1][0], &p->transition[1][1]);
        else if (strcmp(key, "IMM_INITIAL") == 0)
            sscanf(value, "%lf %lf", &p->imm_initial[0], &p->imm_initial[1]);
        else if (strcmp(key, "MATCH_DISTANCE") == 0)
            sscanf(value, "%lf", &p->delta);
        else if (strcmp(key, "OSPA_CUTOFF") == 0)
            sscanf(value, "%lf", &p->cutoff);
        else if (strcmp(key, "CONSISTENCY_BOUND") == 0)
            sscanf(value, "%lf", &p->bound);
        else if (strcmp(key, "NIS_EDGES") == 0) {
            int offset = 0, used;
            double edge;
            while (sscanf(value + offset, "%lf %n", &edge, &used) == 1) {
                p->edges[p->edge_count++] = edge;
                offset += used;
            }
        } else if (strcmp(key, "PLOT_X") == 0)
            sscanf(value, "%lf %lf", &p->xmin, &p->xmax);
        else if (strcmp(key, "PLOT_Y") == 0)
            sscanf(value, "%lf %lf", &p->ymin, &p->ymax);
        else if (strcmp(key, "PLOT_SIZE") == 0)
            sscanf(value, "%d %d", &p->width, &p->height);
    }
    return out;
}
typedef struct {
    Vector estimates[5][101];
    Matrix covariances[101];
    double high[101], logs[2], path, mean_distance;
    int longest_gap, common, target, primary_matches[101];
} TrackAnalysis;
typedef struct {
    int number, birth, last_hit, confirmed, deleted, hits, misses, status;
    Kalman filter;
    Position observations[101];
    bool observed[101], has_nis[101];
    double nis[101];
    TrackAnalysis *analysis;
} Track;
typedef struct {
    int track, common, velocity_count, inside;
    double position[5], velocity[5], nees;
} Result;
typedef struct {
    const Input *input;
    const Params *p;
    int scans, primary, track_count, evaluated[52], evaluated_count, conflict_m, conflict_t,
        greedy_differences;
    Track *tracks;
    Lines track_rows, log;
    int labels[5][10][101], sizes[100][2], matched_tracks[10];
    double ospa_values[5][100], overall_position[5], overall_velocity[5];
    Continuity continuities[5][10];
    Result results[10];
} Analysis;
static Position position(Vector vector) { return (Position){vector.values[0], vector.values[1]}; }
static char *optional(int value) { return value < 0 ? "-" : format("%d", value); }
static const char *filters[5] = {"cv", "ca", "abg", "imm", "rts"};
static char *listed(const char *key, Lines values) {
    char *out = format("%s", key);
    for (int i = 0; i < values.count; ++i)
        out = joined(out, format(" %s", values.data[i]));
    return values.count ? out : joined(out, " none");
}
static char *scores(const double values[5]) {
    char *out = "";
    int best = 0;
    for (int i = 0; i < 5; ++i) {
        out = joined(out, format("%s%s %s", i ? " " : "", filters[i], real(values[i])));
        if (strtod(real(values[i]), NULL) < strtod(real(values[best]), NULL))
            best = i;
    }
    return joined(out, format(" best %s", filters[best]));
}
static void frame(Lines *out, const Lines *grid) {
    int width = (int)strlen(grid->data[0]);
    char *border = allocate((size_t)width + 3, 1);
    border[0] = border[width + 1] = '+';
    memset(border + 1, '-', (size_t)width);
    line(out, "%s", border);
    for (int i = 0; i < grid->count; ++i)
        line(out, "|%s|", grid->data[i]);
    line(out, "%s", border);
}
typedef struct {
    int row, column;
    double cost;
} Candidate;
static int candidate_order(const void *a, const void *b) {
    const Candidate *x = a, *y = b;
    return x->cost != y->cost ? (x->cost < y->cost ? -1 : 1)
           : x->row != y->row ? x->row - y->row
                              : x->column - y->column;
}
static int pair_order(const void *a, const void *b) {
    const Pair *x = a, *y = b;
    return x->row != y->row ? x->row - y->row : x->column - y->column;
}
static void tracking(Analysis *a) {
    const Input *input = a->input;
    const Params *p = a->p;
    line(&a->track_rows, "track,scan,x,y,vx,vy,status");
    for (int scan = 1; scan <= a->scans; ++scan) {
        int live[1000], rows = 0, columns = input->measurement_count[scan];
        for (int i = 0; i < a->track_count; ++i)
            if (a->tracks[i].status != 2)
                live[rows++] = i;
        for (int i = 0; scan > 1 && i < rows; ++i)
            predict(&a->tracks[live[i]].filter, input->times[scan] - input->times[scan - 1]);
        double *costs = allocate((size_t)(rows * columns), sizeof(double));
        bool *usable = allocate((size_t)(rows * columns), sizeof(bool));
        int *row_gates = allocate((size_t)rows, sizeof(int)), column_gates[20] = {0};
        Candidate *candidates = allocate((size_t)(rows * columns), sizeof(Candidate));
        int candidate_count = 0;
        Lines gates = {0};
        for (int i = 0; i < rows; ++i)
            for (int j = 0; j < columns; ++j) {
                Innovation observation =
                    innovation(&a->tracks[live[i]].filter, input->measurements[scan][j]);
                if (observation.distance <= p->gate) {
                    int offset = i * columns + j;
                    costs[offset] = observation.distance;
                    usable[offset] = true;
                    ++row_gates[i];
                    ++column_gates[j];
                    candidates[candidate_count++] = (Candidate){i, j, observation.distance};
                    line(&gates, "%d:%d=%s", a->tracks[live[i]].number, j + 1,
                         real(observation.distance));
                }
            }
        Pairs assigned = optimal_assignment(costs, usable, rows, columns);
        qsort(candidates, (size_t)candidate_count, sizeof(Candidate), candidate_order);
        bool used_rows[1000] = {false}, used_columns[20] = {false};
        Pair greedy[20];
        int greedy_count = 0;
        for (int i = 0; i < candidate_count; ++i) {
            Candidate candidate = candidates[i];
            if (!used_rows[candidate.row] && !used_columns[candidate.column]) {
                greedy[greedy_count++] = (Pair){candidate.row, candidate.column};
                used_rows[candidate.row] = true;
                used_columns[candidate.column] = true;
            }
        }
        qsort(greedy, (size_t)greedy_count, sizeof(Pair), pair_order);
        bool different = assigned.count != greedy_count;
        for (int i = 0; !different && i < assigned.count; ++i)
            different = assigned.data[i].row != greedy[i].row ||
                        assigned.data[i].column != greedy[i].column;
        a->greedy_differences += different;
        int matches[1000];
        for (int i = 0; i < rows; ++i)
            matches[i] = -1;
        memset(used_columns, 0, sizeof(used_columns));
        Lines assignment_items = {0}, greedy_items = {0}, missed = {0}, confirmed = {0},
              deleted = {0}, new_items = {0};
        for (int i = 0; i < assigned.count; ++i) {
            Pair pair = assigned.data[i];
            matches[pair.row] = pair.column;
            used_columns[pair.column] = true;
            line(&assignment_items, "%d:%d", a->tracks[live[pair.row]].number, pair.column + 1);
        }
        for (int i = 0; i < greedy_count; ++i)
            line(&greedy_items, "%d:%d", a->tracks[live[greedy[i].row]].number,
                 greedy[i].column + 1);
        for (int row = 0; row < rows; ++row) {
            Track *track = &a->tracks[live[row]];
            int column = matches[row];
            if (column >= 0) {
                update(&track->filter,
                       innovation(&track->filter, input->measurements[scan][column]));
                track->observations[scan] = input->measurements[scan][column];
                track->observed[scan] = true;
                track->nis[scan] = costs[row * columns + column];
                track->has_nis[scan] = true;
                track->last_hit = scan;
                ++track->hits;
                track->misses = 0;
            } else {
                ++track->misses;
                line(&missed, "%d", track->number);
            }
            if (track->status == 1) {
                if (track->misses >= p->deletion) {
                    track->status = 2;
                    track->deleted = scan;
                    line(&deleted, "%d", track->number);
                }
            } else if (track->hits >= p->confirm) {
                track->status = 1;
                track->confirmed = scan;
                line(&confirmed, "%d", track->number);
            } else if (scan - track->birth + 1 >= p->window) {
                track->status = 2;
                track->deleted = scan;
                line(&deleted, "%d", track->number);
            }
        }
        int processed[1000], processed_count = rows;
        memcpy(processed, live, (size_t)rows * sizeof(int));
        for (int j = 0; j < columns; ++j)
            if (!used_columns[j]) {
                int index = a->track_count++;
                Track *track = &a->tracks[index];
                track->number = index + 1;
                track->birth = track->last_hit = scan;
                track->confirmed = track->deleted = -1;
                track->hits = 1;
                track->filter =
                    kalman(p->ca, p->ca ? p->q_ca : p->q_cv, p, input->measurements[scan][j]);
                track->observations[scan] = input->measurements[scan][j];
                track->observed[scan] = true;
                processed[processed_count++] = index;
                line(&new_items, "%d:%d", index + 1, j + 1);
            }
        int cm = 0, ct = 0, tentative = 0, confirmed_count = 0;
        for (int j = 0; j < columns; ++j)
            cm += column_gates[j] >= 2;
        for (int i = 0; i < rows; ++i)
            ct += row_gates[i] >= 2;
        a->conflict_m += cm;
        a->conflict_t += ct;
        for (int i = 0; i < a->track_count; ++i) {
            tentative += a->tracks[i].status == 0;
            confirmed_count += a->tracks[i].status == 1;
        }
        line(&a->log, "scan %d tracks %d measurements %d", scan, rows, columns);
        line(&a->log, "%s", listed("gate", gates));
        line(&a->log, "%s", listed("assign", assignment_items));
        line(&a->log, "%s", listed("greedy", greedy_items));
        line(&a->log, "%s", listed("missed", missed));
        line(&a->log, "%s", listed("new", new_items));
        line(&a->log, "%s", listed("confirmed", confirmed));
        line(&a->log, "%s", listed("deleted", deleted));
        line(&a->log, "status tentative %d confirmed %d", tentative, confirmed_count);
        line(&a->log, "conflicts measurements %d tracks %d", cm, ct);
        for (int i = 0; i < processed_count; ++i) {
            Track *track = &a->tracks[processed[i]];
            line(&a->track_rows, "%d,%d,%s,%s,%s,%s,%s", track->number, scan,
                 real(track->filter.x.values[0]), real(track->filter.x.values[1]),
                 real(track->filter.x.values[2]), real(track->filter.x.values[3]),
                 track->status == 0   ? "tentative"
                 : track->status == 1 ? "confirmed"
                                      : "deleted");
        }
    }
    for (int i = 0; i < a->track_count; ++i)
        if (a->tracks[i].confirmed >= 0)
            a->evaluated[a->evaluated_count++] = i;
}
static void compared_filters(Analysis *a) {
    const Input *input = a->input;
    const Params *p = a->p;
    for (int i = 0; i < a->evaluated_count; ++i) {
        Track *track = &a->tracks[a->evaluated[i]];
        TrackAnalysis *analysis = track->analysis = allocate(1, sizeof(TrackAnalysis));
        analysis->target = -1;
        for (int scan = 0; scan <= a->scans; ++scan)
            analysis->primary_matches[scan] = -1;
        History history[100];
        int count = track->last_hit - track->birth + 1;
        for (int kind = 0; kind < 2; ++kind) {
            Kalman filter = kalman(kind == 1, kind == 1 ? p->q_ca : p->q_cv, p,
                                   track->observations[track->birth]);
            for (int scan = track->birth; scan <= track->last_hit; ++scan) {
                if (scan > track->birth) {
                    predict(&filter, input->times[scan] - input->times[scan - 1]);
                    if (track->observed[scan])
                        analysis->logs[kind] +=
                            update(&filter, innovation(&filter, track->observations[scan]));
                }
                analysis->estimates[kind][scan] = filter.x;
                if (kind == a->primary) {
                    history[scan - track->birth] =
                        (History){filter.x, filter.xp, filter.P, filter.Pp, filter.F};
                    analysis->covariances[scan] = filter.P;
                }
            }
        }
        Vector *smoothed = smooth(history, count);
        for (int scan = track->birth; scan <= track->last_hit; ++scan)
            analysis->estimates[4][scan] = smoothed[scan - track->birth];
        Vector abg = {
            6,
            {track->observations[track->birth].x, track->observations[track->birth].y, 0, 0, 0, 0}};
        IMM mixed = imm(p, track->observations[track->birth]);
        int gap = 0;
        for (int scan = track->birth; scan <= track->last_hit; ++scan) {
            if (scan > track->birth) {
                double t = input->times[scan] - input->times[scan - 1];
                for (int axis = 0; axis < 2; ++axis) {
                    double position = abg.values[axis], velocity = abg.values[axis + 2],
                           acceleration = abg.values[axis + 4];
                    position = position + t * velocity + t * t * acceleration / 2;
                    velocity = velocity + t * acceleration;
                    if (track->observed[scan]) {
                        double coordinate =
                                   axis ? track->observations[scan].y : track->observations[scan].x,
                               residual = coordinate - position;
                        position = position + p->abg[0] * residual;
                        velocity = velocity + p->abg[1] * residual / t;
                        acceleration = acceleration + 2 * p->abg[2] * residual / (t * t);
                    }
                    abg.values[axis] = position;
                    abg.values[axis + 2] = velocity;
                    abg.values[axis + 4] = acceleration;
                }
                imm_step(&mixed, t, track->observed[scan] ? &track->observations[scan] : NULL);
            }
            analysis->estimates[2][scan] = abg;
            analysis->estimates[3][scan] = imm_estimate(&mixed);
            analysis->high[scan] = mixed.probabilities[1];
            gap = track->observed[scan] ? 0 : gap + 1;
            if (gap > analysis->longest_gap)
                analysis->longest_gap = gap;
            if (scan > track->birth)
                analysis->path += distance(position(analysis->estimates[4][scan - 1]),
                                           position(analysis->estimates[4][scan]));
        }
    }
}
static void scan_evaluation(Analysis *a) {
    const Input *input = a->input;
    const Params *p = a->p;
    for (int kind = 0; kind < 5; ++kind)
        for (int b = 0; b < input->target_count; ++b)
            for (int scan = 0; scan <= a->scans; ++scan)
                a->labels[kind][b][scan] = -1;
    for (int scan = 1; scan <= a->scans; ++scan) {
        int active[52], targets[10], rows = 0, columns = 0;
        for (int i = 0; i < a->evaluated_count; ++i) {
            int index = a->evaluated[i];
            if (a->tracks[index].birth <= scan && scan <= a->tracks[index].last_hit)
                active[rows++] = index;
        }
        Position truth[10];
        for (int b = 0; b < input->target_count; ++b)
            if (input->targets[b].exists[scan]) {
                targets[columns] = b;
                truth[columns++] = input->targets[b].positions[scan];
            }
        a->sizes[scan - 1][0] = columns;
        a->sizes[scan - 1][1] = rows;
        for (int kind = 0; kind < 5; ++kind) {
            double costs[520] = {0};
            bool usable[520] = {false};
            Position estimates[52];
            for (int i = 0; i < rows; ++i) {
                estimates[i] = position(a->tracks[active[i]].analysis->estimates[kind][scan]);
                for (int j = 0; j < columns; ++j) {
                    double value = distance(estimates[i], truth[j]);
                    if (value <= p->delta) {
                        costs[i * columns + j] = value;
                        usable[i * columns + j] = true;
                    }
                }
            }
            Pairs matching = optimal_assignment(costs, usable, rows, columns);
            for (int i = 0; i < matching.count; ++i) {
                Pair pair = matching.data[i];
                int index = active[pair.row], target = targets[pair.column];
                a->labels[kind][target][scan] = a->tracks[index].number;
                if (kind == a->primary)
                    a->tracks[index].analysis->primary_matches[scan] = target;
            }
            a->ospa_values[kind][scan - 1] = ospa(estimates, rows, truth, columns, p->cutoff);
        }
    }
    for (int kind = 0; kind < 5; ++kind)
        for (int b = 0; b < input->target_count; ++b) {
            Target target = input->targets[b];
            a->continuities[kind][b] =
                continuity(a->labels[kind][b] + target.first, target.last - target.first + 1);
        }
}
static void match_tracks(Analysis *a) {
    const Input *input = a->input;
    int rows = a->evaluated_count, columns = input->target_count;
    double costs[520] = {0};
    bool usable[520] = {false};
    for (int i = 0; i < rows; ++i) {
        Track *track = &a->tracks[a->evaluated[i]];
        for (int b = 0; b < columns; ++b) {
            const Target *target = &input->targets[b];
            double sum = 0;
            int count = 0;
            bool close = false;
            for (int scan = 1; scan <= a->scans; ++scan) {
                bool in_track = track->birth <= scan && scan <= track->last_hit,
                     in_target = target->exists[scan];
                if (!in_track && !in_target)
                    continue;
                ++count;
                if (in_track && in_target) {
                    double value = distance(position(track->analysis->estimates[a->primary][scan]),
                                            target->positions[scan]);
                    sum += fmin(a->p->cutoff, value);
                    close = close || value < a->p->cutoff;
                } else
                    sum += a->p->cutoff;
            }
            if (close) {
                usable[i * columns + b] = true;
                costs[i * columns + b] = sum / count;
            }
        }
    }
    for (int b = 0; b < columns; ++b)
        a->matched_tracks[b] = -1;
    Pairs matching = optimal_assignment(costs, usable, rows, columns);
    for (int i = 0; i < matching.count; ++i) {
        Pair pair = matching.data[i];
        int index = a->evaluated[pair.row];
        Track *track = &a->tracks[index];
        track->analysis->target = pair.column;
        track->analysis->mean_distance = costs[pair.row * columns + pair.column];
        a->matched_tracks[pair.column] = index;
        for (int scan = track->birth; scan <= track->last_hit; ++scan)
            track->analysis->common += input->targets[pair.column].exists[scan];
    }
}
static void evaluate_errors(Analysis *a) {
    const Input *input = a->input;
    double position_sum[5] = {0}, velocity_sum[5] = {0};
    int position_count = 0, velocity_count = 0;
    for (int b = 0; b < input->target_count; ++b) {
        Result *result = &a->results[b];
        result->track = a->matched_tracks[b];
        if (result->track < 0)
            continue;
        Track *track = &a->tracks[result->track];
        const Target *target = &input->targets[b];
        double ps[5] = {0}, vs[5] = {0}, nees_sum = 0;
        for (int scan = target->first; scan <= target->last; ++scan) {
            if (scan < track->birth || scan > track->last_hit)
                continue;
            ++result->common;
            ++position_count;
            bool has_velocity = scan > target->first && scan < target->last;
            Position velocity = {0};
            if (has_velocity) {
                double interval = input->times[scan + 1] - input->times[scan - 1];
                velocity = (Position){
                    (target->positions[scan + 1].x - target->positions[scan - 1].x) / interval,
                    (target->positions[scan + 1].y - target->positions[scan - 1].y) / interval};
                ++result->velocity_count;
                ++velocity_count;
            }
            for (int kind = 0; kind < 5; ++kind) {
                Vector x = track->analysis->estimates[kind][scan];
                double pe = squared_distance(position(x), target->positions[scan]);
                ps[kind] += pe;
                position_sum[kind] += pe;
                if (has_velocity) {
                    double ve = squared_distance((Position){x.values[2], x.values[3]}, velocity);
                    vs[kind] += ve;
                    velocity_sum[kind] += ve;
                }
            }
            Vector x = track->analysis->estimates[a->primary][scan];
            Matrix covariance = zeros(2, 2);
            for (int i = 0; i < 2; ++i)
                for (int j = 0; j < 2; ++j)
                    covariance.values[i][j] = track->analysis->covariances[scan].values[i][j];
            double nees = quadratic2((Position){x.values[0] - target->positions[scan].x,
                                                x.values[1] - target->positions[scan].y},
                                     inverse(covariance));
            nees_sum += nees;
            result->inside += nees <= a->p->bound;
        }
        for (int kind = 0; kind < 5; ++kind) {
            result->position[kind] = sqrt(ps[kind] / result->common);
            result->velocity[kind] = sqrt(vs[kind] / result->velocity_count);
        }
        result->nees = nees_sum / result->common;
    }
    for (int kind = 0; kind < 5; ++kind) {
        a->overall_position[kind] = sqrt(position_sum[kind] / position_count);
        a->overall_velocity[kind] = sqrt(velocity_sum[kind] / velocity_count);
    }
}
static Lines evaluation_report(const Analysis *a) {
    const Input *input = a->input;
    const Params *p = a->p;
    Lines out = {0};
    int measurements = 0, false_tracks = 0, used = 0, lost = 0;
    for (int scan = 1; scan <= a->scans; ++scan)
        measurements += input->measurement_count[scan];
    for (int i = 0; i < a->evaluated_count; ++i) {
        const Track *track = &a->tracks[a->evaluated[i]];
        bool matched = false;
        for (int scan = track->birth; scan <= track->last_hit; ++scan)
            matched = matched || track->analysis->primary_matches[scan] >= 0;
        false_tracks += !matched;
        used += track->hits;
    }
    for (int b = 0; b < input->target_count; ++b)
        lost += a->matched_tracks[b] < 0;
    line(&out, "summary");
    line(&out, "scans %d", a->scans);
    line(&out, "measurements %d", measurements);
    line(&out, "targets %d", input->target_count);
    line(&out, "tracks_created %d", a->track_count);
    line(&out, "tracks_confirmed %d", a->evaluated_count);
    line(&out, "false_tracks %d", false_tracks);
    line(&out, "missed_targets %d", lost);
    line(&out, "measurements_used %d", used);
    line(&out, "conflict_measurements %d", a->conflict_m);
    line(&out, "conflict_tracks %d", a->conflict_t);
    line(&out, "greedy_differences %d", a->greedy_differences);
    line(&out, "");
    line(&out, "targets");
    for (int b = 0; b < input->target_count; ++b) {
        const Target *target = &input->targets[b];
        double path = 0;
        for (int scan = target->first + 1; scan <= target->last; ++scan)
            path += distance(target->positions[scan - 1], target->positions[scan]);
        line(&out, "target %d first %d last %d scans %d path %s mean_speed %s", target->number,
             target->first, target->last, target->last - target->first + 1, real(path),
             real(path / (input->times[target->last] - input->times[target->first])));
    }
    line(&out, "");
    line(&out, "tracks");
    for (int i = 0; i < a->evaluated_count; ++i) {
        const Track *track = &a->tracks[a->evaluated[i]];
        double sum = 0;
        int inside = 0, count = 0;
        for (int scan = track->birth; scan <= track->last_hit; ++scan)
            if (track->has_nis[scan]) {
                sum += track->nis[scan];
                inside += track->nis[scan] <= p->bound;
                ++count;
            }
        line(
            &out,
            "track %d birth %d confirmed %d end %d deleted %s hits %d misses %d longest_gap %d path %s nis %s nis_inside %d/%d",
            track->number, track->birth, track->confirmed, track->last_hit,
            optional(track->deleted), track->hits, track->last_hit - track->birth + 1 - track->hits,
            track->analysis->longest_gap, real(track->analysis->path), real(sum / count), inside,
            count);
    }
    line(&out, "");
    line(&out, "matching");
    for (int i = 0; i < a->evaluated_count; ++i) {
        const Track *track = &a->tracks[a->evaluated[i]];
        const TrackAnalysis *analysis = track->analysis;
        char *row = format(
            "track %d target %s", track->number,
            analysis->target < 0 ? "-" : format("%d", input->targets[analysis->target].number));
        if (analysis->target >= 0)
            row = joined(row, format(" common %d mean_distance %s", analysis->common,
                                     real(analysis->mean_distance)));
        int count = 0;
        Lines segments = {0};
        for (int scan = track->birth; scan <= track->last_hit; ++scan) {
            int target = analysis->primary_matches[scan];
            if (target < 0)
                continue;
            int first = scan;
            while (scan < track->last_hit && analysis->primary_matches[scan + 1] == target)
                ++scan;
            count += scan - first + 1;
            line(&segments, "%d-%d:%d", first, scan, input->targets[target].number);
        }
        line(&out, "%s matched_scans %d %s", row, count, listed("segments", segments));
    }
    line(&out, "");
    line(&out, "rmse");
    for (int b = 0; b < input->target_count; ++b) {
        const Result *result = &a->results[b];
        if (result->track < 0) {
            line(&out, "target %d track -", input->targets[b].number);
            continue;
        }
        line(&out, "target %d track %d common %d %s", input->targets[b].number,
             a->tracks[result->track].number, result->common, scores(result->position));
        line(&out, "target %d velocity %d %s", input->targets[b].number, result->velocity_count,
             scores(result->velocity));
    }
    line(&out, "overall position %s", scores(a->overall_position));
    line(&out, "overall velocity %s", scores(a->overall_velocity));
    line(&out, "");
    line(&out, "consistency");
    for (int b = 0; b < input->target_count; ++b) {
        const Result *result = &a->results[b];
        if (result->track < 0)
            line(&out, "target %d track -", input->targets[b].number);
        else
            line(&out, "target %d track %d nees %s inside %d/%d", input->targets[b].number,
                 a->tracks[result->track].number, real(result->nees), result->inside,
                 result->common);
    }
    int observed[11] = {0}, nis_count = 0;
    for (int i = 0; i < a->evaluated_count; ++i) {
        const Track *track = &a->tracks[a->evaluated[i]];
        for (int scan = track->birth; scan <= track->last_hit; ++scan)
            if (track->has_nis[scan]) {
                ++nis_count;
                int bin = 0;
                while (bin < p->edge_count && p->edges[bin] <= track->nis[scan])
                    ++bin;
                ++observed[bin];
            }
    }
    char *histogram = format("nis_histogram total %d observed", nis_count);
    for (int bin = 0; bin <= p->edge_count; ++bin)
        histogram = joined(histogram, format(" %d", observed[bin]));
    histogram = joined(histogram, " expected");
    double lower = 0;
    for (int bin = 0; bin <= p->edge_count; ++bin) {
        double upper_probability = bin == p->edge_count ? 0 : exp(-p->edges[bin] / 2);
        histogram = joined(histogram,
                           format(" %s", real(nis_count * (exp(-lower / 2) - upper_probability))));
        if (bin < p->edge_count)
            lower = p->edges[bin];
    }
    line(&out, "%s", histogram);
    line(&out, "");
    line(&out, "models");
    for (int i = 0; i < a->evaluated_count; ++i) {
        const Track *track = &a->tracks[a->evaluated[i]];
        line(&out, "track %d updates %d cv %s ca %s better %s", track->number, track->hits - 1,
             real(track->analysis->logs[0]), real(track->analysis->logs[1]),
             track->analysis->logs[0] >= track->analysis->logs[1] ? "cv" : "ca");
    }
    line(&out, "");
    line(&out, "ospa cutoff %s order 2", real(p->cutoff));
    line(&out, "scan targets tracks cv ca abg imm rts");
    for (int scan = 1; scan <= a->scans; ++scan) {
        char *row = format("%d %d %d", scan, a->sizes[scan - 1][0], a->sizes[scan - 1][1]);
        for (int kind = 0; kind < 5; ++kind)
            row = joined(row, format(" %s", real(a->ospa_values[kind][scan - 1])));
        line(&out, "%s", row);
    }
    char *means = "mean";
    for (int kind = 0; kind < 5; ++kind) {
        double sum = 0;
        for (int scan = 0; scan < a->scans; ++scan)
            sum += a->ospa_values[kind][scan];
        means = joined(means, format(" %s", real(sum / a->scans)));
    }
    line(&out, "%s", means);
    line(&out, "");
    line(&out, "continuity");
    for (int kind = 0; kind < 5; ++kind) {
        int covered = 0, breaks = 0, swaps = 0;
        for (int b = 0; b < input->target_count; ++b) {
            Continuity value = a->continuities[kind][b];
            covered += value.covered;
            breaks += value.breaks;
            swaps += value.swaps;
        }
        line(&out, "%s covered %d breaks %d swaps %d", filters[kind], covered, breaks, swaps);
        for (int b = 0; b < input->target_count; ++b) {
            Continuity value = a->continuities[kind][b];
            line(&out, "  target %d scans %d covered %d breaks %d swaps %d delay %s",
                 input->targets[b].number, input->targets[b].last - input->targets[b].first + 1,
                 value.covered, value.breaks, value.swaps, optional(value.delay));
        }
    }
    line(&out, "");
    line(&out, "imm");
    for (int i = 0; i < a->evaluated_count; ++i) {
        const Track *track = &a->tracks[a->evaluated[i]];
        const TrackAnalysis *analysis = track->analysis;
        double sum = 0;
        int maximum = track->birth, count = 0;
        Lines segments = {0};
        for (int scan = track->birth; scan <= track->last_hit; ++scan) {
            sum += analysis->high[scan];
            if (analysis->high[scan] > analysis->high[maximum])
                maximum = scan;
            count += analysis->high[scan] > 0.5;
        }
        for (int scan = track->birth; scan <= track->last_hit; ++scan)
            if (analysis->high[scan] > 0.5) {
                int first = scan;
                while (scan < track->last_hit && analysis->high[scan + 1] > 0.5)
                    ++scan;
                line(&segments, "%d-%d", first, scan);
            }
        line(&out, "track %d mean_high %s max_high %s at %d high_scans %d %s", track->number,
             real(sum / (track->last_hit - track->birth + 1)), real(analysis->high[maximum]),
             maximum, count, listed("segments", segments));
    }
    return out;
}
static char character(int index) { return (char)(index < 26 ? 'A' + index : 'a' + index - 26); }
static bool cell(const Params *p, Position point, Pair *location) {
    double dx = (p->xmax - p->xmin) / p->width, dy = (p->ymax - p->ymin) / p->height;
    int column = (int)floor((point.x - p->xmin) / dx), row = (int)floor((p->ymax - point.y) / dy);
    if (column < 0 || column >= p->width || row < 0 || row >= p->height)
        return false;
    *location = (Pair){row, column};
    return true;
}
static Lines blank_grid(int width, int height) {
    Lines grid = {0};
    for (int row = 0; row < height; ++row) {
        char *text = allocate((size_t)width + 1, 1);
        memset(text, ' ', (size_t)width);
        line(&grid, "%s", text);
    }
    return grid;
}
static Lines plots(const Analysis *a) {
    const Input *input = a->input;
    const Params *p = a->p;
    Lines out = {0};
    line(&out, "tracks x %s %s y %s %s size %d %d", real(p->xmin), real(p->xmax), real(p->ymin),
         real(p->ymax), p->width, p->height);
    Lines grid = blank_grid(p->width, p->height);
    Pair location;
    for (int b = 0; b < input->target_count; ++b) {
        const Target *target = &input->targets[b];
        for (int scan = target->first; scan <= target->last; ++scan)
            if (cell(p, target->positions[scan], &location))
                grid.data[location.row][location.column] = '.';
    }
    for (int i = 0; i < a->evaluated_count; ++i) {
        const Track *track = &a->tracks[a->evaluated[i]];
        for (int scan = track->birth; scan <= track->last_hit; ++scan)
            if (cell(p, position(track->analysis->estimates[4][scan]), &location))
                grid.data[location.row][location.column] = character(i);
    }
    frame(&out, &grid);
    for (int i = 0; i < a->evaluated_count; ++i) {
        const Track *track = &a->tracks[a->evaluated[i]];
        line(&out, "%c track %d target %s", character(i), track->number,
             track->analysis->target < 0
                 ? "-"
                 : format("%d", input->targets[track->analysis->target].number));
    }
    line(&out, "");
    line(&out, "measurements");
    int counts[50][100] = {0};
    for (int scan = 1; scan <= a->scans; ++scan)
        for (int j = 0; j < input->measurement_count[scan]; ++j)
            if (cell(p, input->measurements[scan][j], &location))
                ++counts[location.row][location.column];
    for (int row = 0; row < p->height; ++row)
        for (int column = 0; column < p->width; ++column) {
            int count = counts[row][column];
            grid.data[row][column] = count == 0 ? ' ' : count >= 10 ? '#' : (char)('0' + count);
        }
    frame(&out, &grid);
    line(&out, "");
    line(&out, "timeline");
    char characters[1001] = {0};
    for (int i = 0; i < a->evaluated_count; ++i)
        characters[a->tracks[a->evaluated[i]].number] = character(i);
    for (int b = 0; b < input->target_count; ++b) {
        char timeline[101];
        memset(timeline, ' ', (size_t)a->scans);
        timeline[a->scans] = '\0';
        const Target *target = &input->targets[b];
        for (int scan = target->first; scan <= target->last; ++scan) {
            int label = a->labels[a->primary][b][scan];
            timeline[scan - 1] = label < 0 ? '.' : characters[label];
        }
        line(&out, "%d |%s|", target->number, timeline);
    }
    line(&out, "");
    line(&out, "ospa %s", filters[a->primary]);
    Lines ospa_grid = blank_grid(a->scans, 10);
    for (int scan = 0; scan < a->scans; ++scan) {
        int height = (int)floor(10 * a->ospa_values[a->primary][scan] / p->cutoff);
        for (int row = 0; row < 10; ++row)
            if (height >= 10 - row)
                ospa_grid.data[row][scan] = '#';
    }
    frame(&out, &ospa_grid);
    return out;
}
static void save(const char *name, Lines lines) {
    FILE *output = fopen(format("output/%s", name), "wb");
    for (int i = 0; i < lines.count; ++i)
        fprintf(output, "%s\n", lines.data[i]);
    fclose(output);
}
int main(void) {
    const Input *input = read_inputs();
    Analysis *a = allocate(1, sizeof(Analysis));
    a->input = input;
    a->p = &input->params;
    a->scans = input->scans;
    a->primary = input->params.ca ? 1 : 0;
    a->tracks = allocate(1000, sizeof(Track));
    tracking(a);
    compared_filters(a);
    scan_evaluation(a);
    match_tracks(a);
    evaluate_errors(a);
    mkdir("output", 0777);
    save("tracks.csv", a->track_rows);
    save("association_log.txt", a->log);
    Lines smoothed = {0};
    line(&smoothed, "track,scan,x,y,vx,vy");
    for (int i = 0; i < a->evaluated_count; ++i) {
        const Track *track = &a->tracks[a->evaluated[i]];
        for (int scan = track->birth; scan <= track->last_hit; ++scan) {
            Vector x = track->analysis->estimates[4][scan];
            line(&smoothed, "%d,%d,%s,%s,%s,%s", track->number, scan, real(x.values[0]),
                 real(x.values[1]), real(x.values[2]), real(x.values[3]));
        }
    }
    save("smoothed.csv", smoothed);
    save("evaluation.txt", evaluation_report(a));
    save("track_plot.txt", plots(a));
    return 0;
}
