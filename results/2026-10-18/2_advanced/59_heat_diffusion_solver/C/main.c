#include "heat.h"
static void boundary(System *system) {
    Lines rows = read_lines("input/boundary.txt");
    for (int i = 0; i < rows.count; ++i) {
        if (strncmp(rows.data[i], "segment ", 8) == 0) {
            Segment *segment = &system->segments[system->segment_count++];
            int start, end;
            sscanf(rows.data[i], "segment %12s %6s %d %d %10s", segment->name, segment->edge,
                   &start, &end, segment->kind);
            if (strcmp(segment->kind, "fixed") == 0)
                sscanf(rows.data[i], "%*s %*s %*s %*d %*d %*s %lf", &segment->theta);
            else if (strcmp(segment->kind, "convective") == 0)
                sscanf(rows.data[i], "%*s %*s %*s %*d %*d %*s %lf %lf", &segment->coefficient,
                       &segment->theta);
            segment_faces(&system->mesh, segment, start, end);
        } else {
            Source *source = &system->sources[system->source_count++];
            int r1, c1, r2, c2, offset = 0;
            sscanf(rows.data[i], "source %12s %d %d %d %d %lf %n", source->name, &r1, &c1, &r2, &c2,
                   &source->power, &offset);
            source_cells(&system->mesh, source, r1, c1, r2, c2);
            while (source->interval_count < 10) {
                int used = 0, index = source->interval_count;
                if (sscanf(rows.data[i] + offset, "%d %d %n", &source->on[index],
                           &source->off[index], &used) != 2)
                    break;
                ++source->interval_count;
                offset += used;
            }
        }
    }
}
static Params parameters(const Mesh *mesh) {
    Params out = {0};
    Lines rows = read_lines("input/params.txt");
    for (int i = 0; i < rows.count; ++i) {
        char key[20];
        sscanf(rows.data[i], "%19s", key);
        const char *value = rows.data[i] + strlen(key) + 1;
        if (strcmp(key, "initial") == 0)
            sscanf(value, "%lf", &out.initial);
        else if (strcmp(key, "end_time") == 0)
            sscanf(value, "%d", &out.end);
        else if (strcmp(key, "probe_every") == 0)
            sscanf(value, "%d", &out.probe_every);
        else if (strcmp(key, "tolerance") == 0)
            sscanf(value, "%lf", &out.tolerance);
        else if (strcmp(key, "max_iterations") == 0)
            sscanf(value, "%d", &out.max_iterations);
        else if (strcmp(key, "omega") == 0)
            sscanf(value, "%lf", &out.omega);
        else if (strcmp(key, "alarm") == 0)
            sscanf(value, "%lf", &out.alarm);
        else if (strcmp(key, "limit") == 0)
            sscanf(value, "%lf", &out.limit);
        else if (strcmp(key, "reference") == 0)
            sscanf(value, "%12s", out.reference);
        else if (strcmp(key, "snapshots") == 0) {
            int offset = 0, used = 0, time;
            while (sscanf(value + offset, "%d %n", &time, &used) == 1) {
                out.snapshots[out.snapshot_count++] = time;
                offset += used;
            }
        } else if (strcmp(key, "bands") == 0) {
            int offset = 0, used = 0;
            double band;
            while (sscanf(value + offset, "%lf %n", &band, &used) == 1) {
                out.bands[out.band_count++] = band;
                offset += used;
            }
        } else if (strcmp(key, "probe") == 0) {
            Probe *probe = &out.probes[out.probe_count++];
            int r, c;
            sscanf(value, "%12s %d %d", probe->name, &r, &c);
            probe->point = cell(mesh, r, c);
        } else if (strcmp(key, "run") == 0) {
            Run *run = &out.runs[out.run_count++];
            sscanf(value, "%12s %15s %d", run->name, run->method, &run->step);
        }
    }
    return out;
}
static bool operating(const Source *source, int time) {
    for (int i = 0; i < source->interval_count; ++i)
        if (source->on[i] <= time && time < source->off[i])
            return true;
    return false;
}
static double duty(const Source *source, int end) {
    int duration = 0;
    for (int i = 0; i < source->interval_count; ++i)
        duration += (source->off[i] < end ? source->off[i] : end) -
                    (source->on[i] < end ? source->on[i] : end);
    return (double)duration / end;
}
static double source_terms(const System *system, int time, double *field) {
    memset(field, 0, (size_t)system->mesh.count * sizeof(double));
    double power = 0;
    for (int i = 0; i < system->source_count; ++i) {
        const Source *source = &system->sources[i];
        if (time >= 0 && !operating(source, time))
            continue;
        power += source->power;
        double weight = source->power / source->count;
        for (int j = 0; j < source->count; ++j)
            field[source->cells[j]] += weight;
    }
    return power;
}
static System *load_system(void) {
    System *out = allocate(1, sizeof(System));
    out->mesh = read_mesh();
    out->material_count = read_materials(out->materials);
    boundary(out);
    const Mesh *mesh = &out->mesh;
    for (int p = 0; p < mesh->count; ++p) {
        int m = 0;
        while (out->materials[m].code != mesh->codes[p])
            ++m;
        out->cell_material[p] = m;
        out->capacity[p] = capacity(out->materials[m], mesh->dx, mesh->thickness);
    }
    for (int p = 0; p < mesh->count; ++p)
        for (int direction = 0; direction < 4; ++direction) {
            Face *face = &out->faces[p][direction];
            face->neighbor = mesh->neighbors[p][direction];
            if (face->neighbor >= 0)
                face->g =
                    interior(out->materials[out->cell_material[p]].k,
                             out->materials[out->cell_material[face->neighbor]].k, mesh->thickness);
        }
    for (int i = 0; i < out->segment_count; ++i) {
        Segment *segment = &out->segments[i];
        for (int j = 0; j < segment->count; ++j) {
            CellFace item = segment->faces[j];
            Face *face = &out->faces[item.point][item.direction];
            double k = out->materials[out->cell_material[item.point]].k;
            if (strcmp(segment->kind, "fixed") == 0) {
                face->g = fixed(k, mesh->thickness);
                face->theta = segment->theta;
                face->boundary = true;
            } else if (strcmp(segment->kind, "convective") == 0) {
                face->g = convective(k, segment->coefficient, mesh->dx, mesh->thickness);
                face->theta = segment->theta;
                face->boundary = true;
            }
        }
    }
    out->dt_max = DBL_MAX;
    for (int p = 0; p < mesh->count; ++p) {
        for (int direction = 0; direction < 4; ++direction) {
            Face face = out->faces[p][direction];
            out->diagonal[p] += face.g;
            if (face.boundary)
                out->beta[p] += face.g * face.theta;
        }
        double maximum = out->capacity[p] / out->diagonal[p];
        if (maximum < out->dt_max)
            out->dt_max = maximum;
    }
    out->total_power = source_terms(out, -1, out->source_all);
    return out;
}
static const char *status(const System *system, const Params *params, Run run) {
    if (params->end % run.step || params->probe_every % run.step)
        return "step";
    for (int i = 0; i < params->snapshot_count; ++i)
        if (params->snapshots[i] % run.step)
            return "step";
    for (int s = 0; s < system->source_count; ++s) {
        const Source *source = &system->sources[s];
        for (int i = 0; i < source->interval_count; ++i)
            if (source->on[i] % run.step || source->off[i] % run.step)
                return "step";
    }
    return strcmp(run.method, "ftcs") == 0 && (double)run.step / 1000 > system->dt_max ? "unstable"
                                                                                       : "accepted";
}
static double stored(const System *system, const double *field, double initial, int material) {
    double out = 0;
    for (int p = 0; p < system->mesh.count; ++p)
        if (material < 0 || system->cell_material[p] == material)
            out += system->capacity[p] * (field[p] - initial);
    return out;
}
static double segment_flow(const System *system, const Segment *segment, const double *field) {
    double out = 0;
    if (strcmp(segment->kind, "insulated") == 0)
        return out;
    for (int i = 0; i < segment->count; ++i) {
        CellFace item = segment->faces[i];
        Face face = system->faces[item.point][item.direction];
        out += face.g * (face.theta - field[item.point]);
    }
    return out;
}
static double maximum_difference(const double *first, const double *second, int count) {
    double out = 0;
    for (int p = 0; p < count; ++p)
        if (fabs(first[p] - second[p]) > out)
            out = fabs(first[p] - second[p]);
    return out;
}
static const char *balance_verdict(double u, double b, double q) {
    return fabs(u - b - q) <= 0.000001 * (fabs(u) + fabs(b) + fabs(q)) ? "ok" : "failed";
}
typedef struct {
    int time;
    double *field, u, b, q;
} Snapshot;
typedef struct {
    int time;
    double values[8];
} ProbeRow;
typedef struct {
    Run run;
    const char *status;
    double *field, boundaries[20], source_energy, stored, boundary_energy, peak;
    int peak_time, peak_cell, above;
    bool has_alarm;
    int alarm_time, alarm_cell;
    Snapshot snapshots[5];
    int snapshot_count;
    ProbeRow probes[501];
    int probe_count;
} Result;
static void observe(const System *system, const Params *params, Result *out, int time) {
    int hot = hottest(out->field, system->mesh.count);
    double maximum = out->field[hot];
    if (maximum > out->peak) {
        out->peak = maximum;
        out->peak_time = time;
        out->peak_cell = hot;
    }
    if (maximum >= params->alarm) {
        if (!out->has_alarm) {
            out->has_alarm = true;
            out->alarm_time = time;
            out->alarm_cell = hot;
        }
        if (time > 0)
            out->above += out->run.step;
    }
    if (time % params->probe_every == 0) {
        ProbeRow *row = &out->probes[out->probe_count++];
        row->time = time;
        for (int i = 0; i < params->probe_count; ++i)
            row->values[i] = out->field[params->probes[i].point];
    }
    for (int i = 0; i < params->snapshot_count; ++i)
        if (params->snapshots[i] == time) {
            Snapshot *snapshot = &out->snapshots[out->snapshot_count++];
            snapshot->time = time;
            snapshot->field = allocate((size_t)system->mesh.count, sizeof(double));
            memcpy(snapshot->field, out->field, (size_t)system->mesh.count * sizeof(double));
            snapshot->u = stored(system, out->field, params->initial, -1);
            snapshot->b = 0;
            for (int j = 0; j < system->segment_count; ++j)
                snapshot->b += out->boundaries[j];
            snapshot->q = out->source_energy;
        }
}
static void transient_run(const System *system, const Params *params, Run definition, Result *out) {
    out->run = definition;
    out->status = status(system, params, definition);
    if (strcmp(out->status, "accepted"))
        return;
    int n = system->mesh.count;
    out->field = allocate((size_t)n, sizeof(double));
    for (int p = 0; p < n; ++p)
        out->field[p] = params->initial;
    out->peak = params->initial;
    double updated[1000], intermediate[1000], source[1000], average[1000];
    double dt = (double)definition.step / 1000;
    observe(system, params, out, 0);
    for (int time = 0; time < params->end; time += definition.step) {
        double power = source_terms(system, time, source);
        advance(system, out->field, source, dt, definition.method, updated, intermediate);
        bool crank = strcmp(definition.method, "crank_nicolson") == 0;
        if (crank)
            for (int p = 0; p < n; ++p)
                average[p] = (out->field[p] + updated[p]) / 2;
        for (int j = 0; j < system->segment_count; ++j) {
            const Segment *segment = &system->segments[j];
            bool horizontal =
                strcmp(segment->edge, "left") == 0 || strcmp(segment->edge, "right") == 0;
            const double *field = strcmp(definition.method, "ftcs") == 0 ? out->field
                                  : horizontal                           ? intermediate
                                  : crank                                ? average
                                                                         : updated;
            out->boundaries[j] += dt * segment_flow(system, segment, field);
        }
        out->source_energy += dt * power;
        memcpy(out->field, updated, (size_t)n * sizeof(double));
        observe(system, params, out, time + definition.step);
    }
    out->stored = stored(system, out->field, params->initial, -1);
    for (int j = 0; j < system->segment_count; ++j)
        out->boundary_energy += out->boundaries[j];
}
static double rate(const Iteration *solver) {
    return sqrt(solver->changes[solver->count - 1] / solver->changes[solver->count - 3]);
}
static char *milestones(const Iteration *solver, double tolerance) {
    static const int factors[4] = {1000, 100, 10, 1};
    char *out = "";
    for (int f = 0; f < 4; ++f) {
        int found = 0;
        for (int i = 0; i < solver->count; ++i)
            if (solver->changes[i] < tolerance * factors[f]) {
                found = i + 1;
                break;
            }
        out = joined(out, format(" %s", found ? format("%d", found) : "never"));
    }
    return out;
}
int main(void) {
    const System *system = load_system();
    const Mesh *mesh = &system->mesh;
    Params params = parameters(mesh);
    int n = mesh->count;
    double **rhs = allocate((size_t)system->source_count + 2, sizeof(double *));
    rhs[0] = allocate((size_t)n, sizeof(double));
    rhs[1] = allocate((size_t)n, sizeof(double));
    for (int p = 0; p < n; ++p) {
        rhs[0][p] = system->beta[p] + system->source_all[p];
        rhs[1][p] = system->beta[p];
    }
    for (int s = 0; s < system->source_count; ++s) {
        rhs[s + 2] = allocate((size_t)n, sizeof(double));
        const Source *source = &system->sources[s];
        for (int i = 0; i < source->count; ++i)
            rhs[s + 2][source->cells[i]] = 1.0 / source->count;
    }
    double **solutions = direct(system, rhs, system->source_count + 2);
    const double *steady = solutions[0], *base = solutions[1];
    Iteration solvers[4];
    solvers[0] = iterate(system, &params, "jacobi", 1);
    double rho = rate(&solvers[0]), omega_opt = 2 / (1 + sqrt(1 - rho * rho));
    solvers[1] = iterate(system, &params, "gauss_seidel", 1);
    solvers[2] = iterate(system, &params, "sor", params.omega);
    solvers[3] = iterate(system, &params, "sor_estimated", omega_opt);
    Result *results = allocate((size_t)params.run_count, sizeof(Result));
    int reference = 0;
    for (int i = 0; i < params.run_count; ++i) {
        if (strcmp(params.runs[i].name, params.reference) == 0)
            reference = i;
        transient_run(system, &params, params.runs[i], &results[i]);
    }
    Lines snapshots = {0}, probes = {0}, comparison = {0};
    line(&probes, "run,time,probe,temperature");
    line(&comparison, "ftcs_max_dt %s", real(system->dt_max, 4));
    for (int index = 0; index < params.run_count; ++index) {
        Result *result = &results[index];
        Run run = result->run;
        char *prefix = format("run %s %s dt %s", run.name, run.method, time_text(run.step));
        if (strcmp(result->status, "accepted")) {
            line(&snapshots, "%s rejected %s%s", prefix, result->status,
                 strcmp(result->status, "unstable") == 0
                     ? format(" max_dt %s", real(system->dt_max, 4))
                     : "");
            line(&comparison, "%s rejected %s", prefix, result->status);
            continue;
        }
        for (int i = 0; i < result->snapshot_count; ++i) {
            Snapshot snapshot = result->snapshots[i];
            line(&snapshots, "%s",
                 summary(format("%s time %s", prefix, time_text(snapshot.time)), mesh,
                         snapshot.field));
            field_lines(&snapshots, mesh, snapshot.field);
        }
        for (int i = 0; i < result->probe_count; ++i)
            for (int j = 0; j < params.probe_count; ++j)
                line(&probes, "%s,%s,%s,%s", run.name, time_text(result->probes[i].time),
                     params.probes[j].name, real(result->probes[i].values[j], 3));
        char *alarm = result->has_alarm ? format("%s at %s", time_text(result->alarm_time),
                                                 coordinates(mesh, result->alarm_cell))
                                        : "never";
        line(&comparison, "%s steps %d peak %s time %s at %s alarm %s above %s", prefix,
             params.end / run.step, real(result->peak, 2), time_text(result->peak_time),
             coordinates(mesh, result->peak_cell), alarm, time_text(result->above));
        line(&comparison, "energy %s stored %s boundary %s source %s balance %s", run.name,
             real(result->stored, 2), real(result->boundary_energy, 2),
             real(result->source_energy, 2),
             balance_verdict(result->stored, result->boundary_energy, result->source_energy));
        for (int i = 0; i < result->snapshot_count; ++i) {
            Snapshot snapshot = result->snapshots[i];
            line(&comparison, "energy_at %s time %s stored %s boundary %s source %s", run.name,
                 time_text(snapshot.time), real(snapshot.u, 2), real(snapshot.b, 2),
                 real(snapshot.q, 2));
        }
        for (int m = 0; m < system->material_count; ++m)
            line(&comparison, "energy_material %s %c %s", run.name, system->materials[m].code,
                 real(stored(system, result->field, params.initial, m), 2));
        for (int j = 0; j < system->segment_count; ++j)
            line(&comparison, "energy_segment %s %s %s", run.name, system->segments[j].name,
                 real(result->boundaries[j], 2));
        for (int probe = 0; probe < params.probe_count; ++probe) {
            double maximum = result->probes[0].values[probe], minimum = maximum;
            int max_time = 0, min_time = 0;
            for (int i = 0; i < result->probe_count; ++i) {
                ProbeRow *row = &result->probes[i];
                if (row->values[probe] > maximum) {
                    maximum = row->values[probe];
                    max_time = row->time;
                }
                if (row->values[probe] < minimum) {
                    minimum = row->values[probe];
                    min_time = row->time;
                }
            }
            line(&comparison, "probe_summary %s %s max %s time %s min %s time %s", run.name,
                 params.probes[probe].name, real(maximum, 3), time_text(max_time), real(minimum, 3),
                 time_text(min_time));
        }
        if (index != reference)
            for (int i = 0; i < result->snapshot_count; ++i) {
                const double *field = result->snapshots[i].field,
                             *other = results[reference].snapshots[i].field;
                double squared = 0;
                for (int p = 0; p < n; ++p) {
                    double difference = fabs(field[p] - other[p]);
                    squared += difference * difference;
                }
                line(&comparison, "compare %s %s time %s max_diff %s rms_diff %s", run.name,
                     params.reference, time_text(result->snapshots[i].time),
                     real(maximum_difference(field, other, n), 6), real(sqrt(squared / n), 6));
            }
        line(&comparison, "final %s steady_max_diff %s", run.name,
             real(maximum_difference(result->field, steady, n), 6));
    }
    line(&comparison, "steady direct max_residual %s", real(residual(system, steady, rhs[0]), 6));
    for (int i = 0; i < 4; ++i)
        line(&comparison, "steady %s iterations %d max_diff %s max_residual %s", solvers[i].method,
             solvers[i].count, real(maximum_difference(solvers[i].field, steady, n), 6),
             real(residual(system, solvers[i].field, rhs[0]), 6));
    line(&comparison, "jacobi_spectral_radius %s squared %s", real(rho, 6), real(rho * rho, 6));
    line(&comparison, "omega_estimated %s", real(omega_opt, 4));
    Lines report = {0};
    line(&report, "%s", summary("steady", mesh, steady));
    field_lines(&report, mesh, steady);
    for (int m = 0; m < system->material_count; ++m) {
        double minimum = DBL_MAX, maximum = -DBL_MAX, total = 0;
        int count = 0;
        for (int p = 0; p < n; ++p)
            if (system->cell_material[p] == m) {
                ++count;
                if (steady[p] < minimum)
                    minimum = steady[p];
                if (steady[p] > maximum)
                    maximum = steady[p];
                total += steady[p];
            }
        line(&report, "material %c %s cells %d min %s max %s mean %s", system->materials[m].code,
             system->materials[m].name, count, real(minimum, 2), real(maximum, 2),
             real(total / count, 2));
    }
    for (int s = 0; s < system->source_count; ++s) {
        const Source *source = &system->sources[s];
        double total = 0, maximum = steady[source->cells[0]];
        for (int i = 0; i < source->count; ++i) {
            double value = steady[source->cells[i]];
            total += value;
            if (value > maximum)
                maximum = value;
        }
        line(&report, "source %s power %s duty %s mean %s max %s", source->name,
             real(source->power, 4), real(duty(source, params.end), 4),
             real(total / source->count, 2), real(maximum, 2));
    }
    for (int s = 0; s < system->source_count; ++s)
        for (int t = 0; t < system->source_count; ++t) {
            const Source *source = &system->sources[s];
            double total = 0;
            for (int i = 0; i < source->count; ++i)
                total += solutions[t + 2][source->cells[i]];
            line(&report, "influence %s %s %s", source->name, system->sources[t].name,
                 real(total / source->count, 4));
        }
    double *superposition = allocate((size_t)n, sizeof(double)),
           *duty_field = allocate((size_t)n, sizeof(double));
    for (int p = 0; p < n; ++p) {
        superposition[p] = duty_field[p] = base[p];
        for (int s = 0; s < system->source_count; ++s) {
            const Source *source = &system->sources[s];
            superposition[p] += source->power * solutions[s + 2][p];
            duty_field[p] += (duty(source, params.end) * source->power) * solutions[s + 2][p];
        }
    }
    line(&report, "superposition %s",
         maximum_difference(superposition, steady, n) <= 0.000001 ? "ok" : "failed");
    for (int s = 0; s < system->source_count; ++s)
        for (int j = 0; j < system->segment_count; ++j) {
            const Segment *segment = &system->segments[j];
            double value = 0;
            if (strcmp(segment->kind, "insulated"))
                for (int i = 0; i < segment->count; ++i) {
                    CellFace item = segment->faces[i];
                    value +=
                        system->faces[item.point][item.direction].g * solutions[s + 2][item.point];
                }
            line(&report, "path %s %s %s", system->sources[s].name, segment->name, real(value, 4));
        }
    line(&report, "%s", summary("duty_steady", mesh, duty_field));
    for (int s = 0; s < system->source_count; ++s) {
        double minimum = DBL_MAX;
        int point = 0;
        for (int p = 0; p < n; ++p) {
            double value =
                (params.limit - (steady[p] - system->sources[s].power * solutions[s + 2][p])) /
                solutions[s + 2][p];
            if (value < minimum) {
                minimum = value;
                point = p;
            }
        }
        line(&report, "headroom %s max_power %s at %s", system->sources[s].name, real(minimum, 4),
             coordinates(mesh, point));
    }
    typedef struct {
        int faces;
        double forward, backward;
    } Interface;
    Interface interfaces[9][9] = {0};
    double gradient = -1;
    int gradient_first = 0, gradient_second = 0;
    for (int p = 0; p < n; ++p)
        for (int direction = 1; direction <= 3; direction += 2) {
            Face face = system->faces[p][direction];
            int q = face.neighbor;
            if (q < 0)
                continue;
            double value = fabs(steady[p] - steady[q]) / mesh->dx;
            if (value > gradient) {
                gradient = value;
                gradient_first = p;
                gradient_second = q;
            }
            int a = system->cell_material[p], b = system->cell_material[q];
            if (a == b)
                continue;
            double flow = face.g * (steady[p] - steady[q]), oriented = a < b ? flow : -flow;
            Interface *entry = &interfaces[a < b ? a : b][a > b ? a : b];
            ++entry->faces;
            if (oriented > 0)
                entry->forward += oriented;
            else if (oriented < 0)
                entry->backward += -oriented;
        }
    for (int a = 0; a < system->material_count; ++a)
        for (int b = a + 1; b < system->material_count; ++b) {
            Interface entry = interfaces[a][b];
            if (entry.faces)
                line(&report, "interface %c %c faces %d forward %s backward %s",
                     system->materials[a].code, system->materials[b].code, entry.faces,
                     real(entry.forward, 4), real(entry.backward, 4));
        }
    double total_flow = 0, absolute_flow = 0;
    for (int j = 0; j < system->segment_count; ++j) {
        const Segment *segment = &system->segments[j];
        double flow = segment_flow(system, segment, steady);
        total_flow += flow;
        absolute_flow += fabs(flow);
        line(&report, "segment %s %s %s flow %s", segment->name, segment->edge, segment->kind,
             real(flow, 4));
    }
    line(&report, "sources %s", real(system->total_power, 4));
    line(&report, "balance %s",
         fabs(total_flow + system->total_power) <= 0.000001 * (absolute_flow + system->total_power)
             ? "ok"
             : "failed");
    line(&report, "max_gradient %s between %s and %s", real(gradient, 2),
         coordinates(mesh, gradient_first), coordinates(mesh, gradient_second));
    for (int i = 0; i < 4; ++i) {
        const Iteration *solver = &solvers[i];
        line(&report, "solver %s%s iterations %d converged %s rate %s milestones%s", solver->method,
             i >= 2 ? format(" omega %s", real(solver->omega, 4)) : "", solver->count,
             solver->converged ? "yes" : "no", real(rate(solver), 6),
             milestones(solver, params.tolerance));
    }
    Lines maps = {0};
    isotherms(&maps, "isotherms steady", mesh, steady, &params);
    for (int i = 0; i < results[reference].snapshot_count; ++i) {
        Snapshot snapshot = results[reference].snapshots[i];
        isotherms(&maps, format("isotherms %s time %s", params.reference, time_text(snapshot.time)),
                  mesh, snapshot.field, &params);
    }
    save("snapshots.txt", snapshots);
    save("probes.csv", probes);
    save("steady_state.txt", report);
    save("solver_comparison.txt", comparison);
    save("isotherms.txt", maps);
    return 0;
}
